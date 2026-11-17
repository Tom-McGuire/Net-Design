import '../models/endpoint_node_instance.dart';
import '../models/endpoint_template.dart';
import '../models/enums.dart';
import '../models/network_link_edge.dart';
import '../models/switch_node_instance.dart';
import '../models/switch_port_config.dart';
import '../models/topology_project.dart';
import '../models/validation_issue.dart';
import 'multicast_stream_resolver.dart';

/// Selectable multicast trace target displayed in the Tier 3 "Trace Stream" bar.
class StreamTraceTarget {
  const StreamTraceTarget({
    required this.id,
    required this.label,
    required this.vlanId,
    required this.multicastIps,
    required this.protocol,
    this.sourceEndpointId,
  });

  final String id;
  final String label;
  final int vlanId;
  final Set<String> multicastIps;
  final TrafficProtocol protocol;
  final String? sourceEndpointId;
}

typedef EndpointPortAttachment = ({
  SwitchNodeInstance sw,
  SwitchPortConfig port,
  NetworkLinkEdge link,
  EndpointNodeInstance ep,
  int epPortNum,
});

/// Traces Layer 2 multicast stream paths, IGMP pruning, flooding, and
/// validates duplicate TX stream / orphan RX subscriptions.
class MulticastFlowTracer {
  const MulticastFlowTracer();

  /// Builds lookup keyed by `'${ep.id}:$epPortNumber'` for valid non-mismatched links.
  static Map<String, EndpointPortAttachment> buildEndpointAttachments({
    required Map<String, SwitchNodeInstance> switchesById,
    required Map<String, EndpointNodeInstance> endpointsById,
    required List<NetworkLinkEdge> links,
  }) {
    final result = <String, EndpointPortAttachment>{};
    for (final link in links) {
      if (link.hasMediaMismatch) continue;
      final epA = endpointsById[link.sourceNodeId];
      final epB = endpointsById[link.targetNodeId];
      final swA = switchesById[link.sourceNodeId];
      final swB = switchesById[link.targetNodeId];

      if (epA != null && swB != null) {
        final swPort = swB.portByNumber(link.targetPortNumber);
        if (swPort != null) {
          result['${epA.id}:${link.sourcePortNumber}'] = (
            sw: swB,
            port: swPort,
            link: link,
            ep: epA,
            epPortNum: link.sourcePortNumber,
          );
        }
      } else if (epB != null && swA != null) {
        final swPort = swA.portByNumber(link.sourcePortNumber);
        if (swPort != null) {
          result['${epB.id}:${link.targetPortNumber}'] = (
            sw: swA,
            port: swPort,
            link: link,
            ep: epB,
            epPortNum: link.targetPortNumber,
          );
        }
      }
    }
    return result;
  }

  /// Resolves the active VLAN ID for an endpoint traffic flow considering its attached port.
  static int effectiveVlanForFlow(
    TrafficRequirement flow,
    EndpointPortAttachment? att,
  ) {
    if (att == null || !att.sw.supportsVlans) {
      return flow.defaultVlanId;
    }
    if (att.port.portMode == SwitchPortMode.trunk &&
        att.port.allowedVlans.contains(flow.defaultVlanId)) {
      return flow.defaultVlanId;
    }
    return att.port.nativeVlan;
  }

  /// Emits validation findings for invalid stream syntax, duplicate TX sources,
  /// and orphan RX subscriptions.
  void validateStreams({
    required Map<String, SwitchNodeInstance> switchesById,
    required Map<String, EndpointNodeInstance> endpointsById,
    required List<NetworkLinkEdge> links,
    required List<ValidationIssue> issues,
  }) {
    final attachments = buildEndpointAttachments(
      switchesById: switchesById,
      endpointsById: endpointsById,
      links: links,
    );

    final forwardingLinks = links.where((l) {
      return switchesById.containsKey(l.sourceNodeId) &&
          switchesById.containsKey(l.targetNodeId) &&
          !l.hasMediaMismatch &&
          (l.stpState == LinkStpState.forwarding ||
              l.stpState == LinkStpState.loopUnprotected);
    }).toList();

    // Index TX streams by VLAN component (or switchless VLAN) -> IP -> publishers
    final txEntries = <({
      EndpointNodeInstance ep,
      TrafficRequirement flow,
      EndpointPortAttachment? att,
      int vlanId,
      ResolvedMulticastStream stream,
    })>[];

    for (final ep in endpointsById.values) {
      for (final flow in ep.activeTrafficFlows) {
        final specError = MulticastStreamResolver.validateFlowSpec(flow);
        if (specError != null) {
          issues.add(
            ValidationIssue(
              id: 'stream-spec-invalid-${ep.id}-${flow.id}',
              severity: IssueSeverity.warning,
              category: IssueCategory.igmp,
              title: 'Invalid Multicast Stream Spec',
              message: '${ep.userLabel}: $specError',
              recommendation:
                  'Correct the universe range (1–63999) or multicast IPv4 range (224.0.0.0–239.255.255.255).',
              nodeId: ep.id,
              vlanId: flow.defaultVlanId,
            ),
          );
          continue;
        }

        if (!flow.direction.isPublisher) continue;
        final att = attachments['${ep.id}:${flow.effectivePortNumber}'];
        final vlanId = effectiveVlanForFlow(flow, att);
        final resolved = MulticastStreamResolver.resolveFlowStreams(
          flow,
          effectiveVlanId: vlanId,
        );
        for (final s in resolved) {
          txEntries.add((
            ep: ep,
            flow: flow,
            att: att,
            vlanId: vlanId,
            stream: s,
          ));
        }
      }
    }

    // 1. Check Duplicate TX Stream Collision per (VLAN, Multicast IP)
    final txByVlanIp =
        <String, List<({EndpointNodeInstance ep, TrafficRequirement flow, ResolvedMulticastStream stream, EndpointPortAttachment? att})>>{};
    for (final item in txEntries) {
      txByVlanIp.putIfAbsent('${item.vlanId}:${item.stream.multicastIp}', () => []).add((
        ep: item.ep,
        flow: item.flow,
        stream: item.stream,
        att: item.att,
      ));
    }

    final reportedCollisionPairs = <String>{};
    for (final entry in txByVlanIp.entries) {
      final list = entry.value;
      if (list.length < 2) continue;

      // Flag collisions between distinct TX endpoints/ports on the same VLAN.
      for (var i = 0; i < list.length; i++) {
        for (var j = i + 1; j < list.length; j++) {
          final a = list[i];
          final b = list[j];
          final portKeyA = '${a.ep.id}:${a.flow.effectivePortNumber}';
          final portKeyB = '${b.ep.id}:${b.flow.effectivePortNumber}';
          if (portKeyA == portKeyB && a.flow.id == b.flow.id) continue;

          // If both attached to switches, check L2 VLAN reachability between them.
          if (a.att != null &&
              b.att != null &&
              a.att!.sw.id != b.att!.sw.id &&
              !_isVlanReachable(
                startSwId: a.att!.sw.id,
                targetSwId: b.att!.sw.id,
                vlanId: a.stream.vlanId,
                forwardingLinks: forwardingLinks,
              )) {
            continue;
          }

          final ids = [a.ep.id, b.ep.id]..sort();
          final pairKey = '${ids.join(':')}:V${a.stream.vlanId}:${a.stream.multicastIp}';
          if (!reportedCollisionPairs.add(pairKey)) continue;

          final streamDesc = a.stream.sacnUniverse != null
              ? 'sACN Universe ${a.stream.sacnUniverse} (${a.stream.multicastIp})'
              : 'multicast group ${a.stream.multicastIp}';
          issues.add(
            ValidationIssue(
              id: 'stream-dup-tx-$pairKey',
              severity: IssueSeverity.warning,
              category: IssueCategory.igmp,
              title: 'Duplicate TX Stream Collision',
              message:
                  '${a.ep.userLabel} and ${b.ep.userLabel} both transmit $streamDesc on VLAN ${a.stream.vlanId}, causing conflicting data on receivers.',
              recommendation:
                  'Assign distinct sACN universes or multicast group IPs, or separate the sources onto different VLANs.',
              nodeId: a.ep.id,
              vlanId: a.stream.vlanId,
            ),
          );
        }
      }
    }

    // 2. Check Orphan RX Subscriptions (RX requests specific streams with no reachable TX source)
    for (final ep in endpointsById.values) {
      for (final flow in ep.activeTrafficFlows) {
        if (!flow.direction.isSubscriber) continue;
        final att = attachments['${ep.id}:${flow.effectivePortNumber}'];
        final vlanId = effectiveVlanForFlow(flow, att);
        final rxStreams = MulticastStreamResolver.resolveFlowStreams(
          flow,
          effectiveVlanId: vlanId,
        );
        if (rxStreams.isEmpty) continue;

        final missing = <ResolvedMulticastStream>[];
        for (final rxStream in rxStreams) {
          final candidates = txByVlanIp['$vlanId:${rxStream.multicastIp}'];
          if (candidates == null || candidates.isEmpty) {
            missing.add(rxStream);
            continue;
          }

          final hasReachableTx = candidates.any((tx) {
            if (tx.ep.id == ep.id && tx.flow.id == flow.id) return false;
            if (att == null || tx.att == null) {
              // Unwired check: consider same-VLAN TX as matching until wired.
              return true;
            }
            if (!tx.att!.port.permitsVlan(
              vlanId,
              switchSupportsVlans: tx.att!.sw.supportsVlans,
            )) {
              return false;
            }
            if (att.sw.id == tx.att!.sw.id) return true;
            return _isVlanReachable(
              startSwId: tx.att!.sw.id,
              targetSwId: att.sw.id,
              vlanId: vlanId,
              forwardingLinks: forwardingLinks,
            );
          });

          if (!hasReachableTx) {
            missing.add(rxStream);
          }
        }

        if (missing.isNotEmpty) {
          final summary = missing.first.sacnUniverse != null
              ? 'sACN U${MulticastStreamResolver.formatUniverseRanges([
                  for (final m in missing)
                    if (m.sacnUniverse != null) m.sacnUniverse!,
                ])}'
              : missing.map((m) => m.multicastIp).join(', ');
          issues.add(
            ValidationIssue(
              id: 'stream-orphan-rx-${ep.id}-${flow.id}',
              severity: IssueSeverity.warning,
              category: IssueCategory.igmp,
              title: 'Orphan RX Stream Subscription',
              message:
                  '${ep.userLabel} subscribes to $summary on VLAN $vlanId, but no reachable TX publisher advertises those streams.',
              recommendation:
                  'Define or connect a TX publisher on VLAN $vlanId advertising $summary, or adjust the RX universe/multicast subscription.',
              nodeId: ep.id,
              vlanId: vlanId,
            ),
          );
        }
      }
    }
  }

  /// Collects selectable trace targets from TX and RX multicast stream specs in [project].
  static List<StreamTraceTarget> buildTraceTargets(TopologyProject project) {
    final switchesById = {for (final sw in project.switches) sw.id: sw};
    final endpointsById = {for (final ep in project.endpoints) ep.id: ep};
    final attachments = buildEndpointAttachments(
      switchesById: switchesById,
      endpointsById: endpointsById,
      links: project.links,
    );

    final targets = <StreamTraceTarget>[];
    final individualTargets = <StreamTraceTarget>[];
    final seenIds = <String>{};
    final vlanAllIps = <int, Set<String>>{};
    final vlanProtocol = <int, TrafficProtocol>{};

    for (final ep in project.endpoints) {
      for (final flow in ep.activeTrafficFlows) {
        if (!flow.direction.isPublisher) continue;
        final att = attachments['${ep.id}:${flow.effectivePortNumber}'];
        final vlanId = effectiveVlanForFlow(flow, att);
        final resolved = MulticastStreamResolver.resolveFlowStreams(
          flow,
          effectiveVlanId: vlanId,
        );
        if (resolved.isEmpty) continue;

        final ips = {for (final s in resolved) s.multicastIp};
        vlanAllIps.putIfAbsent(vlanId, () => <String>{}).addAll(ips);
        vlanProtocol.putIfAbsent(vlanId, () => flow.protocol);

        final specStr = flow.protocol == TrafficProtocol.sacn
            ? 'sACN U${MulticastStreamResolver.formatUniverseRanges([
                for (final s in resolved)
                  if (s.sacnUniverse != null) s.sacnUniverse!,
              ])}'
            : '${flow.protocol.label} (${flow.multicastGroupSpec?.trim()})';

        final flowTargetId = 'tx:${ep.id}:${flow.id}';
        if (seenIds.add(flowTargetId)) {
          targets.add(
            StreamTraceTarget(
              id: flowTargetId,
              label: '$specStr — ${ep.userLabel} (V$vlanId)',
              vlanId: vlanId,
              multicastIps: ips,
              protocol: flow.protocol,
              sourceEndpointId: ep.id,
            ),
          );
        }

        // Collect individual universe/group entries after TX/RX bundles (capped to 16 per flow)
        if (resolved.length > 1) {
          for (final s in resolved.take(16)) {
            final singleId = 'ip:V$vlanId:${s.multicastIp}';
            if (seenIds.add(singleId)) {
              individualTargets.add(
                StreamTraceTarget(
                  id: singleId,
                  label: '${s.displayLabel} (V$vlanId)',
                  vlanId: vlanId,
                  multicastIps: {s.multicastIp},
                  protocol: s.protocol,
                ),
              );
            }
          }
        }
      }
    }

    // Add RX subscription subset targets
    for (final ep in project.endpoints) {
      for (final flow in ep.activeTrafficFlows) {
        if (!flow.direction.isSubscriber) continue;
        final att = attachments['${ep.id}:${flow.effectivePortNumber}'];
        final vlanId = effectiveVlanForFlow(flow, att);
        final resolved = MulticastStreamResolver.resolveFlowStreams(
          flow,
          effectiveVlanId: vlanId,
        );
        if (resolved.isEmpty) continue;
        final ips = {for (final s in resolved) s.multicastIp};
        final specStr = flow.protocol == TrafficProtocol.sacn
            ? 'U${MulticastStreamResolver.formatUniverseRanges([
                for (final s in resolved)
                  if (s.sacnUniverse != null) s.sacnUniverse!,
              ])}'
            : '${flow.multicastGroupSpec?.trim()}';
        final rxTargetId = 'rx:${ep.id}:${flow.id}';
        if (seenIds.add(rxTargetId)) {
          targets.add(
            StreamTraceTarget(
              id: rxTargetId,
              label: 'RX $specStr -> ${ep.userLabel} (V$vlanId)',
              vlanId: vlanId,
              multicastIps: ips,
              protocol: flow.protocol,
            ),
          );
        }
      }
    }

    final sortedVlanIds = vlanAllIps.keys.toList()..sort();
    final vlanBundleTargets = <StreamTraceTarget>[
      for (final vId in sortedVlanIds)
        StreamTraceTarget(
          id: 'vlan:$vId',
          label: 'All VLAN $vId Streams',
          vlanId: vId,
          multicastIps: vlanAllIps[vId]!,
          protocol: vlanProtocol[vId] ?? TrafficProtocol.sacn,
        ),
    ];

    return [
      ...vlanBundleTargets,
      ...targets,
      ...individualTargets,
    ];
  }

  /// Applies static per-link multicast delivery / flooding / IGMP pruning state onto [project.links].
  static void applyTrace({
    required TopologyProject project,
    required StreamTraceTarget? target,
  }) {
    for (final link in project.links) {
      link.resetStreamTraceState();
    }
    if (target == null || target.multicastIps.isEmpty) return;

    final switchesById = {for (final sw in project.switches) sw.id: sw};
    final endpointsById = {for (final ep in project.endpoints) ep.id: ep};
    final attachments = buildEndpointAttachments(
      switchesById: switchesById,
      endpointsById: endpointsById,
      links: project.links,
    );

    final vlanId = target.vlanId;

    final forwardingVlanLinks = project.links.where((l) {
      return switchesById.containsKey(l.sourceNodeId) &&
          switchesById.containsKey(l.targetNodeId) &&
          !l.hasMediaMismatch &&
          !l.hasVlanMismatch &&
          l.activeVlans.contains(vlanId) &&
          (l.stpState == LinkStpState.forwarding ||
              l.stpState == LinkStpState.loopUnprotected);
    }).toList();

    // Collect TX publishers matching target
    final matchingTxSources = <({
      EndpointNodeInstance ep,
      TrafficRequirement flow,
      EndpointPortAttachment att,
      List<ResolvedMulticastStream> streams,
    })>[];

    for (final ep in project.endpoints) {
      if (target.sourceEndpointId != null && ep.id != target.sourceEndpointId) {
        continue;
      }
      for (final flow in ep.activeTrafficFlows) {
        if (!flow.direction.isPublisher) continue;
        final att = attachments['${ep.id}:${flow.effectivePortNumber}'];
        if (att == null) continue;
        final effVlan = effectiveVlanForFlow(flow, att);
        if (effVlan != vlanId) continue;
        if (!att.port.permitsVlan(
          vlanId,
          switchSupportsVlans: att.sw.supportsVlans,
        )) {
          continue;
        }
        final matched = MulticastStreamResolver.resolveFlowStreams(
          flow,
          effectiveVlanId: vlanId,
        ).where((s) => target.multicastIps.contains(s.multicastIp)).toList();
        if (matched.isNotEmpty) {
          matchingTxSources.add((
            ep: ep,
            flow: flow,
            att: att,
            streams: matched,
          ));
        }
      }
    }

    if (matchingTxSources.isEmpty) return;

    // Collect subscribed RX receivers on vlanId by multicastIp
    final rxByIp = <String, List<({EndpointNodeInstance ep, EndpointPortAttachment att})>>{};
    for (final ep in project.endpoints) {
      for (final flow in ep.activeTrafficFlows) {
        if (!flow.direction.isSubscriber) continue;
        final att = attachments['${ep.id}:${flow.effectivePortNumber}'];
        if (att == null) continue;
        final effVlan = effectiveVlanForFlow(flow, att);
        if (effVlan != vlanId) continue;
        if (!att.port.permitsVlan(
          vlanId,
          switchSupportsVlans: att.sw.supportsVlans,
        )) {
          continue;
        }
        final rxStreams = MulticastStreamResolver.resolveFlowStreams(
          flow,
          effectiveVlanId: vlanId,
        );
        for (final s in rxStreams) {
          if (target.multicastIps.contains(s.multicastIp)) {
            rxByIp.putIfAbsent(s.multicastIp, () => []).add((
              ep: ep,
              att: att,
            ));
          }
        }
      }
    }

    // Track per-link unique counted stream IPs so parallel merges don't double-count
    final linkDeliveredIps = <String, Map<String, double>>{};
    final linkFloodedIps = <String, Map<String, double>>{};
    final linkDirAwayFromTx = <String, bool>{};
    final candidatePrunedLinks = <NetworkLinkEdge>{};

    void recordDelivery(
      NetworkLinkEdge link,
      String ip,
      double mbps,
      bool srcToDst,
    ) {
      linkDeliveredIps.putIfAbsent(link.id, () => {})[ip] = mbps;
      linkDirAwayFromTx[link.id] = srcToDst;
    }

    void recordFlood(
      NetworkLinkEdge link,
      String ip,
      double mbps,
      bool srcToDst,
    ) {
      linkFloodedIps.putIfAbsent(link.id, () => {})[ip] = mbps;
      linkDirAwayFromTx.putIfAbsent(link.id, () => srcToDst);
    }

    for (final tx in matchingTxSources) {
      final txSw = tx.att.sw;
      final txLink = tx.att.link;
      final txSrcToDst = txLink.sourceNodeId == tx.ep.id;

      // Mark TX access link as Delivered (endpoint -> switch)
      for (final s in tx.streams) {
        recordDelivery(txLink, s.multicastIp, s.bandwidthMbps, txSrcToDst);
      }

      // Compute BFS tree from txSw across active forwarding VLAN links
      final bfs = _buildBfsTree(
        rootSwitchId: txSw.id,
        vlanLinks: forwardingVlanLinks,
      );

      final compSwitchIds = bfs.visited;
      final compLinks = forwardingVlanLinks
          .where(
            (l) =>
                compSwitchIds.contains(l.sourceNodeId) &&
                compSwitchIds.contains(l.targetNodeId),
          )
          .toList();

      // Identify Active IGMP Querier and IGMP Snooping capability in component
      String? activeQuerierSwId;
      for (final swId in compSwitchIds) {
        final sw = switchesById[swId];
        if (sw != null && sw.activeQuerierVlans.contains(vlanId)) {
          activeQuerierSwId = sw.id;
          break;
        }
      }

      bool isSnoopingActive(SwitchNodeInstance sw) {
        final cfg = sw.vlanConfigs[vlanId];
        return sw.supportsIgmpSnooping &&
            cfg != null &&
            cfg.igmpSnoopingEnabled;
      }

      final txSwitchSnooping = isSnoopingActive(txSw);

      if (!txSwitchSnooping || activeQuerierSwId == null) {
        // Without IGMP Snooping on TX switch OR without any Active Querier on the VLAN,
        // multicast floods across every reachable forwarding VLAN link and non-TX access port!
        for (final l in compLinks) {
          final parentOfSource = bfs.parentLink[l.sourceNodeId]?.id == l.id;
          final srcToDst = !parentOfSource;
          for (final s in tx.streams) {
            recordFlood(l, s.multicastIp, s.bandwidthMbps, srcToDst);
          }
        }
        for (final att in attachments.values) {
          if (att.link.id == txLink.id) continue;
          if (!compSwitchIds.contains(att.sw.id)) continue;
          if (!att.port.permitsVlan(
            vlanId,
            switchSupportsVlans: att.sw.supportsVlans,
          )) {
            continue;
          }
          if (att.port.portMode == SwitchPortMode.access &&
              att.port.nativeVlan != vlanId) {
            continue;
          }
          final swToEp = att.link.sourceNodeId == att.sw.id;
          for (final s in tx.streams) {
            recordFlood(att.link, s.multicastIp, s.bandwidthMbps, swToEp);
          }
        }
        continue;
      }

      // Snooping + Active Querier are active -> trace delivered & pruned branches!
      candidatePrunedLinks.addAll(compLinks);
      for (final att in attachments.values) {
        if (att.link.id == txLink.id) continue;
        if (!compSwitchIds.contains(att.sw.id)) continue;
        if (!att.port.permitsVlan(
          vlanId,
          switchSupportsVlans: att.sw.supportsVlans,
        )) {
          continue;
        }
        if (att.port.portMode == SwitchPortMode.access &&
            att.port.nativeVlan != vlanId) {
          continue;
        }
        candidatePrunedLinks.add(att.link);
      }

      for (final s in tx.streams) {
        // Every snooping switch forwards multicast toward the Active Querier router port.
        final targetSwitches = <String>{activeQuerierSwId};
        final subs = rxByIp[s.multicastIp] ?? const [];
        for (final sub in subs) {
          if (compSwitchIds.contains(sub.att.sw.id)) {
            targetSwitches.add(sub.att.sw.id);
            final swToEp = sub.att.link.sourceNodeId == sub.att.sw.id;
            recordDelivery(sub.att.link, s.multicastIp, s.bandwidthMbps, swToEp);
          }
        }

        // Also if any switch in compIds has IGMP snooping DISABLED, multicast
        // delivered into it floods to its local VLAN ports; trace path to it if flooded.
        for (final targetSwId in targetSwitches) {
          String? cursor = targetSwId;
          while (cursor != null && cursor != txSw.id) {
            final edge = bfs.parentLink[cursor];
            final prev = bfs.parentNode[cursor];
            if (edge == null || prev == null) break;
            final srcToDst = edge.sourceNodeId == prev;
            recordDelivery(edge, s.multicastIp, s.bandwidthMbps, srcToDst);

            // Check if intermediate/target switch lacks IGMP snooping
            final swNode = switchesById[cursor];
            if (swNode != null && !isSnoopingActive(swNode)) {
              for (final att in attachments.values) {
                if (att.sw.id != swNode.id || att.link.id == txLink.id) continue;
                final isSub = subs.any((sub) => sub.att.link.id == att.link.id);
                if (isSub) continue;
                if (!att.port.permitsVlan(
                  vlanId,
                  switchSupportsVlans: att.sw.supportsVlans,
                )) {
                  continue;
                }
                final swToEp = att.link.sourceNodeId == swNode.id;
                recordFlood(att.link, s.multicastIp, s.bandwidthMbps, swToEp);
              }
            }
            cursor = prev;
          }
        }
      }
    }

    // Apply computed trace states back onto project links
    for (final link in project.links) {
      final del = linkDeliveredIps[link.id];
      final fld = linkFloodedIps[link.id];

      if (del != null && del.isNotEmpty) {
        link.streamTraceState = LinkStreamTraceState.delivered;
        link.tracedStreamCount = del.length;
        link.tracedStreamMbps = del.values.fold(0.0, (a, b) => a + b);
        link.streamDirectionSourceToTarget = linkDirAwayFromTx[link.id] ?? true;
      } else if (fld != null && fld.isNotEmpty) {
        link.streamTraceState = LinkStreamTraceState.flooded;
        link.tracedStreamCount = fld.length;
        link.tracedStreamMbps = fld.values.fold(0.0, (a, b) => a + b);
        link.streamDirectionSourceToTarget = linkDirAwayFromTx[link.id] ?? true;
      } else if (candidatePrunedLinks.any((c) => c.id == link.id)) {
        link.streamTraceState = LinkStreamTraceState.igmpPruned;
        link.tracedStreamCount = 0;
        link.tracedStreamMbps = 0.0;
      }
    }
  }

  static bool _isVlanReachable({
    required String startSwId,
    required String targetSwId,
    required int vlanId,
    required List<NetworkLinkEdge> forwardingLinks,
  }) {
    if (startSwId == targetSwId) return true;
    final visited = <String>{startSwId};
    final queue = <String>[startSwId];
    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      for (final l in forwardingLinks) {
        if (!l.connectsNode(curr) || !l.activeVlans.contains(vlanId)) continue;
        final next = l.otherNodeId(curr);
        if (next == targetSwId) return true;
        if (visited.add(next)) {
          queue.add(next);
        }
      }
    }
    return false;
  }

  static ({
    Set<String> visited,
    Map<String, NetworkLinkEdge> parentLink,
    Map<String, String> parentNode,
  }) _buildBfsTree({
    required String rootSwitchId,
    required List<NetworkLinkEdge> vlanLinks,
  }) {
    final visited = <String>{rootSwitchId};
    final parentLink = <String, NetworkLinkEdge>{};
    final parentNode = <String, String>{};
    final queue = <String>[rootSwitchId];

    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      for (final l in vlanLinks) {
        if (!l.connectsNode(curr)) continue;
        final next = l.otherNodeId(curr);
        if (visited.add(next)) {
          parentLink[next] = l;
          parentNode[next] = curr;
          queue.add(next);
        }
      }
    }

    return (
      visited: visited,
      parentLink: parentLink,
      parentNode: parentNode,
    );
  }
}
