import '../models/endpoint_node_instance.dart';
import '../models/enums.dart';
import '../models/network_link_edge.dart';
import '../models/switch_node_instance.dart';
import '../models/validation_issue.dart';
import 'multicast_flow_tracer.dart';
import 'multicast_stream_resolver.dart';
import 'topology_graph_utils.dart';

/// Pass 4: Link Bandwidth Utilization, Media Compatibility, Speed Step-Down & PoE Budget Solver.
class ResourceBudgetSolver {
  const ResourceBudgetSolver();

  void solve({
    required Map<String, SwitchNodeInstance> switchesById,
    required Map<String, EndpointNodeInstance> endpointsById,
    required List<NetworkLinkEdge> links,
    required List<ValidationIssue> issues,
    Map<String, EndpointPortAttachment>? precomputedAttachments,
  }) {
    // Map (endpointId, epPortNumber) -> attached switch, port & link.
    final epAttachments = precomputedAttachments ??
        MulticastFlowTracer.buildEndpointAttachments(
          switchesById: switchesById,
          endpointsById: endpointsById,
          links: links,
        );

    for (final link in links) {
      link.estimatedLoadMbps = 0.0;
      final epA = endpointsById[link.sourceNodeId];
      final epB = endpointsById[link.targetNodeId];
      final swA = switchesById[link.sourceNodeId];
      final swB = switchesById[link.targetNodeId];

      final nameA = swA?.userLabel ?? epA?.userLabel ?? link.sourceNodeId;
      final nameB = swB?.userLabel ?? epB?.userLabel ?? link.targetNodeId;
      final speedA = swA?.portByNumber(link.sourcePortNumber)?.maxSpeed ??
          epA?.tryPortByNumber(link.sourcePortNumber)?.effectiveSpeed ??
          epA?.nicSpeed ??
          link.negotiatedSpeed;
      final speedB = swB?.portByNumber(link.targetPortNumber)?.maxSpeed ??
          epB?.tryPortByNumber(link.targetPortNumber)?.effectiveSpeed ??
          epB?.nicSpeed ??
          link.negotiatedSpeed;
      final mediaA = swA?.portByNumber(link.sourcePortNumber)?.mediaType ??
          epA?.tryPortByNumber(link.sourcePortNumber)?.mediaType ??
          PortMediaType.rj45;
      final mediaB = swB?.portByNumber(link.targetPortNumber)?.mediaType ??
          epB?.tryPortByNumber(link.targetPortNumber)?.mediaType ??
          PortMediaType.rj45;

      // Flag physical media mismatches (RJ45 <-> SFP/Fibre) as Critical.
      if (link.hasMediaMismatch) {
        issues.add(
          ValidationIssue(
            id: 'media-mismatch-${link.id}',
            severity: IssueSeverity.critical,
            category: IssueCategory.bandwidth,
            title: 'Incompatible Physical Media ($nameA <-> $nameB)',
            message:
                '$nameA Port ${link.sourcePortNumber} (${mediaA.label}) cannot connect directly to $nameB Port ${link.targetPortNumber} (${mediaB.label}).',
            recommendation:
                'Connect RJ45 to RJ45 and SFP/Fibre to SFP/Fibre.',
            nodeId: swA?.id ?? swB?.id,
            portNumber: swA != null
                ? link.sourcePortNumber
                : (swB != null ? link.targetPortNumber : null),
            linkId: link.id,
          ),
        );
        continue;
      }

      // Report speed step-downs: 1G SFP <-> 10G SFP+ is a Warning; RJ45 step-downs remain Info.
      if (link.hasSpeedStepDown) {
        if (link.isSfpStepDown) {
          issues.add(
            ValidationIssue(
              id: 'bw-stepdown-${link.id}',
              severity: IssueSeverity.warning,
              category: IssueCategory.bandwidth,
              title: 'SFP / SFP+ Speed Step-Down',
              message:
                  '10G SFP+ connected to 1G SFP between $nameA (${speedA.label}) and $nameB (${speedB.label}) — verify transceiver compatibility / speed step-down (negotiated at ${link.negotiatedSpeed.label}).',
              recommendation:
                  'Use matching 1G SFP or 10G SFP+ transceivers at both ends if full 10G throughput is needed.',
              nodeId: swA?.id ?? swB?.id,
              portNumber: swA != null
                  ? link.sourcePortNumber
                  : (swB != null ? link.targetPortNumber : null),
              linkId: link.id,
            ),
          );
        } else {
          issues.add(
            ValidationIssue(
              id: 'bw-stepdown-${link.id}',
              severity: IssueSeverity.info,
              category: IssueCategory.bandwidth,
              title: 'Link Speed Stepped Down',
              message:
                  '$nameA (${speedA.label}) <-> $nameB (${speedB.label}) negotiated at ${link.negotiatedSpeed.label}.',
              nodeId: swA?.id ?? swB?.id,
              portNumber: swA != null
                  ? link.sourcePortNumber
                  : (swB != null ? link.targetPortNumber : null),
              linkId: link.id,
            ),
          );
        }
      }
    }

    final forwardingInterSwitchLinks = links.where((l) {
      return switchesById.containsKey(l.sourceNodeId) &&
          switchesById.containsKey(l.targetNodeId) &&
          !l.hasMediaMismatch &&
          (l.stpState == LinkStpState.forwarding ||
              l.stpState == LinkStpState.loopUnprotected);
    }).toList();

    // 4.1 Accumulate bandwidth across bound NIC access links & inter-switch forwarding tree.
    for (final ep in endpointsById.values) {
      for (final flow in ep.activeTrafficFlows) {
        final att = epAttachments['${ep.id}:${flow.effectivePortNumber}'];
        if (att == null) continue;

        att.link.estimatedLoadMbps += flow.estimatedBandwidthMbps;

        if (!flow.direction.isPublisher) continue;
        final vlanId = MulticastFlowTracer.effectiveVlanForFlow(flow, att);

        final vlanForwardLinks = forwardingInterSwitchLinks
            .where((l) => l.activeVlans.contains(vlanId))
            .toList();

        final reachableVlanLinks = _collectReachableVlanLinks(
          startSwitchId: att.sw.id,
          vlanLinks: vlanForwardLinks,
        );

        // Identify reachable switches & whether an Active Querier exists on vlanId.
        final compSwitchIds = <String>{att.sw.id};
        for (final l in reachableVlanLinks) {
          compSwitchIds.add(l.sourceNodeId);
          compSwitchIds.add(l.targetNodeId);
        }
        String? activeQuerierSwId;
        for (final swId in compSwitchIds) {
          final sw = switchesById[swId];
          if (sw != null && sw.activeQuerierVlans.contains(vlanId)) {
            activeQuerierSwId = sw.id;
            break;
          }
        }

        bool isSnoopingActiveOnVlan(String swId) {
          final sw = switchesById[swId];
          if (sw == null) return false;
          return sw.supportsIgmpSnooping &&
              (sw.vlanConfigs[vlanId]?.igmpSnoopingEnabled ?? false);
        }

        final snoopingOnTxSwitch = isSnoopingActiveOnVlan(att.sw.id);

        // Broadcast or un-snooped/querierless multicast floods the reachable VLAN subgraph.
        final isBroadcast = flow.deliveryType == DeliveryType.broadcast;
        final isFloodedMulticast = flow.deliveryType == DeliveryType.multicast &&
            (!snoopingOnTxSwitch ||
                (activeQuerierSwId == null &&
                    compSwitchIds.length > 1));

        if (isBroadcast || isFloodedMulticast) {
          for (final l in reachableVlanLinks) {
            l.estimatedLoadMbps += flow.estimatedBandwidthMbps;
          }
          continue;
        }

        // Stream-level multicast pruning when resolved streams exist (e.g., sACN universes)
        final txStreams = MulticastStreamResolver.resolveFlowStreams(
          flow,
          effectiveVlanId: vlanId,
        );
        if (flow.deliveryType == DeliveryType.multicast && txStreams.isNotEmpty) {
          for (final stream in txStreams) {
            final targetSwitches = <String>{};
            if (activeQuerierSwId != null && activeQuerierSwId != att.sw.id) {
              targetSwitches.add(activeQuerierSwId);
            }
            var hasCompSubscriber = false;
            for (final otherEp in endpointsById.values) {
              if (otherEp.id == ep.id) continue;
              for (final otherFlow in otherEp.activeTrafficFlows) {
                if (!otherFlow.direction.isSubscriber ||
                    otherFlow.protocol != flow.protocol) {
                  continue;
                }
                final otherAtt =
                    epAttachments['${otherEp.id}:${otherFlow.effectivePortNumber}'];
                if (otherAtt == null ||
                    !compSwitchIds.contains(otherAtt.sw.id)) {
                  continue;
                }
                final otherVlan =
                    MulticastFlowTracer.effectiveVlanForFlow(otherFlow, otherAtt);
                if (otherVlan != vlanId) continue;

                final otherStreams = MulticastStreamResolver.resolveFlowStreams(
                  otherFlow,
                  effectiveVlanId: otherVlan,
                );
                final matchesStream = otherStreams.isEmpty ||
                    otherStreams
                        .any((os) => os.multicastIp == stream.multicastIp);
                if (matchesStream) {
                  hasCompSubscriber = true;
                  if (otherAtt.sw.id != att.sw.id) {
                    targetSwitches.add(otherAtt.sw.id);
                  }
                }
              }
            }

            if (!hasCompSubscriber &&
                att.sw.vlanConfigs[vlanId]?.dropUnregisteredMulticast == false) {
              for (final l in reachableVlanLinks) {
                l.estimatedLoadMbps += stream.bandwidthMbps;
              }
              continue;
            }

            final traversedLinks = targetSwitches.isNotEmpty
                ? _collectShortestPathUnion(
                    startSwitchId: att.sw.id,
                    targetSwitchIds: targetSwitches,
                    vlanLinks: vlanForwardLinks,
                  )
                : <NetworkLinkEdge>{};
            final floodedLinks = _collectSnoopingDisabledFloodLinks(
              startSwitchId: att.sw.id,
              deliveredLinks: traversedLinks,
              reachableVlanLinks: reachableVlanLinks,
              isSnoopingActive: isSnoopingActiveOnVlan,
            );
            for (final l in {...traversedLinks, ...floodedLinks}) {
              l.estimatedLoadMbps += stream.bandwidthMbps;
            }
          }
        } else {
          // Directed unicast or aggregate multicast flow without stream specs
          final targetSwitches = <String>{};
          if (flow.deliveryType == DeliveryType.multicast &&
              activeQuerierSwId != null &&
              activeQuerierSwId != att.sw.id) {
            targetSwitches.add(activeQuerierSwId);
          }
          var hasCompSubscriber = false;
          for (final otherEp in endpointsById.values) {
            if (otherEp.id == ep.id) continue;
            for (final otherFlow in otherEp.activeTrafficFlows) {
              if (!otherFlow.direction.isSubscriber ||
                  otherFlow.protocol != flow.protocol) {
                continue;
              }
              final otherAtt =
                  epAttachments['${otherEp.id}:${otherFlow.effectivePortNumber}'];
              if (otherAtt == null || !compSwitchIds.contains(otherAtt.sw.id)) {
                continue;
              }
              final otherVlan =
                  MulticastFlowTracer.effectiveVlanForFlow(otherFlow, otherAtt);
              if (otherVlan != vlanId) continue;
              hasCompSubscriber = true;
              if (otherAtt.sw.id != att.sw.id) {
                targetSwitches.add(otherAtt.sw.id);
              }
            }
          }

          if (flow.deliveryType == DeliveryType.multicast &&
              !hasCompSubscriber &&
              att.sw.vlanConfigs[vlanId]?.dropUnregisteredMulticast == false) {
            for (final l in reachableVlanLinks) {
              l.estimatedLoadMbps += flow.estimatedBandwidthMbps;
            }
            continue;
          }

          final traversedLinks = targetSwitches.isNotEmpty
              ? _collectShortestPathUnion(
                  startSwitchId: att.sw.id,
                  targetSwitchIds: targetSwitches,
                  vlanLinks: vlanForwardLinks,
                )
              : <NetworkLinkEdge>{};
          final floodedLinks = flow.deliveryType == DeliveryType.multicast
              ? _collectSnoopingDisabledFloodLinks(
                  startSwitchId: att.sw.id,
                  deliveredLinks: traversedLinks,
                  reachableVlanLinks: reachableVlanLinks,
                  isSnoopingActive: isSnoopingActiveOnVlan,
                )
              : const <NetworkLinkEdge>{};
          for (final l in {...traversedLinks, ...floodedLinks}) {
            l.estimatedLoadMbps += flow.estimatedBandwidthMbps;
          }
        }
      }
    }

    // Check link utilization thresholds (> 75% Warning, > 95% Critical).
    for (final link in links) {
      if (link.hasMediaMismatch) continue;
      final util = link.utilizationPercent;
      if (util <= 75.0) continue;

      final nameA = switchesById[link.sourceNodeId]?.userLabel ??
          endpointsById[link.sourceNodeId]?.userLabel ??
          link.sourceNodeId;
      final nameB = switchesById[link.targetNodeId]?.userLabel ??
          endpointsById[link.targetNodeId]?.userLabel ??
          link.targetNodeId;
      final isCritical = util > 95.0;

      issues.add(
        ValidationIssue(
          id: 'bw-util-${link.id}',
          severity: isCritical ? IssueSeverity.critical : IssueSeverity.warning,
          category: IssueCategory.bandwidth,
          title: isCritical
              ? 'Link Bandwidth Saturated (>95%)'
              : 'High Link Utilization (>75%)',
          message:
              'Link $nameA <-> $nameB (${link.negotiatedSpeed.label}) is carrying ${link.estimatedLoadMbps.toStringAsFixed(1)} Mbps (${util.toStringAsFixed(0)}% capacity).',
          recommendation:
              'Upgrade uplink port speed, enable IGMP Snooping to curb multicast flooding, or split high-bandwidth video/audio VLANs.',
          linkId: link.id,
        ),
      );
    }

    // 4.2 PoE port capability & switch budget aggregation (strictly RJ45 ports).
    for (final ep in endpointsById.values) {
      for (final epPort in ep.effectivePorts) {
        final drawWatts = epPort.effectivePoeDrawWatts;
        if (drawWatts <= 0) continue;
        final att = epAttachments['${ep.id}:${epPort.portNumber}'];
        if (att == null) continue;

        final suppliesPoe = att.port.mediaType == PortMediaType.rj45 &&
            att.sw.poeBudgetWatts > 0 &&
            att.port.poeCapable &&
            att.port.poeEnabled;
        if (!suppliesPoe) {
          final issueId = epPort.portNumber == 1
              ? 'poe-port-incapable-${ep.id}'
              : 'poe-port-incapable-${ep.id}-p${epPort.portNumber}';
          issues.add(
            ValidationIssue(
              id: issueId,
              severity: IssueSeverity.critical,
              category: IssueCategory.poe,
              title: 'PoE Power Missing on Port',
              message:
                  '${ep.userLabel} (${epPort.displayName}) requires ${drawWatts.toStringAsFixed(1)}W PoE, but ${att.sw.userLabel}: Port ${att.port.portNumber} does not supply PoE.',
              recommendation:
                  'Move ${ep.userLabel} to a PoE-enabled RJ45 port, enable PoE on Port ${att.port.portNumber}, or use a local power supply / PoE injector.',
              nodeId: att.sw.id,
              portNumber: att.port.portNumber,
              linkId: att.link.id,
            ),
          );
        } else {
          att.sw.totalPoeDrawWatts += drawWatts;
        }
      }
    }

    for (final sw in switchesById.values) {
      if (sw.poeBudgetWatts <= 0) continue;
      if (sw.totalPoeDrawWatts > sw.poeBudgetWatts) {
        issues.add(
          ValidationIssue(
            id: 'poe-budget-over-${sw.id}',
            severity: IssueSeverity.critical,
            category: IssueCategory.poe,
            title: 'Switch PoE Budget Exceeded',
            message:
                '${sw.userLabel} PoE draw is ${sw.totalPoeDrawWatts.toStringAsFixed(1)}W, exceeding its ${sw.poeBudgetWatts}W budget.',
            recommendation:
                'Redistribute PoE endpoints to another switch or use external power supplies.',
            nodeId: sw.id,
          ),
        );
      } else if (sw.totalPoeDrawWatts > sw.poeBudgetWatts * 0.8) {
        issues.add(
          ValidationIssue(
            id: 'poe-budget-high-${sw.id}',
            severity: IssueSeverity.warning,
            category: IssueCategory.poe,
            title: 'Switch PoE Budget Above 80%',
            message:
                '${sw.userLabel} PoE load is ${sw.totalPoeDrawWatts.toStringAsFixed(1)}W / ${sw.poeBudgetWatts}W (${((sw.totalPoeDrawWatts / sw.poeBudgetWatts) * 100).toStringAsFixed(0)}%).',
            recommendation:
                'Monitor PoE headroom before adding additional powered devices.',
            nodeId: sw.id,
          ),
        );
      }
    }
  }

  Set<NetworkLinkEdge> _collectReachableVlanLinks({
    required String startSwitchId,
    required List<NetworkLinkEdge> vlanLinks,
  }) {
    final visitedNodes = <String>{startSwitchId};
    final resultLinks = <NetworkLinkEdge>{};
    final queue = <String>[startSwitchId];
    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      for (final l in vlanLinks) {
        if (!l.connectsNode(curr)) continue;
        resultLinks.add(l);
        final next = l.otherNodeId(curr);
        if (visitedNodes.add(next)) {
          queue.add(next);
        }
      }
    }
    return resultLinks;
  }

  Set<NetworkLinkEdge> _collectSnoopingDisabledFloodLinks({
    required String startSwitchId,
    required Set<NetworkLinkEdge> deliveredLinks,
    required Set<NetworkLinkEdge> reachableVlanLinks,
    required bool Function(String switchId) isSnoopingActive,
  }) {
    final receivingSwitchIds = <String>{
      startSwitchId,
      for (final l in deliveredLinks) ...[l.sourceNodeId, l.targetNodeId],
    };
    final floodVisited = <String>{};
    final floodQueue = <String>[];
    for (final swId in receivingSwitchIds) {
      if (!isSnoopingActive(swId) && floodVisited.add(swId)) {
        floodQueue.add(swId);
      }
    }

    final floodedLinks = <NetworkLinkEdge>{};
    while (floodQueue.isNotEmpty) {
      final curr = floodQueue.removeAt(0);
      for (final l in reachableVlanLinks) {
        if (!l.connectsNode(curr)) continue;
        if (!deliveredLinks.contains(l)) {
          floodedLinks.add(l);
        }
        final next = l.otherNodeId(curr);
        if (!isSnoopingActive(next) && floodVisited.add(next)) {
          floodQueue.add(next);
        }
      }
    }
    return floodedLinks;
  }

  Set<NetworkLinkEdge> _collectShortestPathUnion({
    required String startSwitchId,
    required Set<String> targetSwitchIds,
    required List<NetworkLinkEdge> vlanLinks,
  }) {
    final bfs = buildBfsTree(
      rootSwitchId: startSwitchId,
      links: vlanLinks,
    );

    final unionLinks = <NetworkLinkEdge>{};
    for (final target in targetSwitchIds) {
      if (!bfs.visited.contains(target)) continue;
      String? cursor = target;
      while (cursor != null && cursor != startSwitchId) {
        final l = bfs.parentLink[cursor];
        if (l == null) break;
        unionLinks.add(l);
        cursor = bfs.parentNode[cursor];
      }
    }
    return unionLinks;
  }
}
