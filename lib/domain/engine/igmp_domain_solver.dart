import '../models/endpoint_node_instance.dart';
import '../models/enums.dart';
import '../models/network_link_edge.dart';
import '../models/switch_node_instance.dart';
import '../models/validation_issue.dart';
import 'multicast_flow_tracer.dart';

/// Pass 3: Per-VLAN IGMP Snooping, Active Querier & Flooded Traffic Solver.
class IgmpDomainSolver {
  const IgmpDomainSolver();

  void solve({
    required Map<String, SwitchNodeInstance> switchesById,
    required Map<String, EndpointNodeInstance> endpointsById,
    required List<NetworkLinkEdge> links,
    required List<ValidationIssue> issues,
  }) {
    final forwardingInterSwitchLinks = links.where((l) {
      return switchesById.containsKey(l.sourceNodeId) &&
          switchesById.containsKey(l.targetNodeId) &&
          !l.hasMediaMismatch &&
          (l.stpState == LinkStpState.forwarding ||
              l.stpState == LinkStpState.loopUnprotected);
    }).toList();

    // Map (endpointId, epPortNumber) -> attached switch, port & link.
    final epAttachments = MulticastFlowTracer.buildEndpointAttachments(
      switchesById: switchesById,
      endpointsById: endpointsById,
      links: links,
    );

    // Collect all VLAN IDs referenced anywhere in the topology.
    final allVlans = <int>{};
    for (final sw in switchesById.values) {
      allVlans.addAll(sw.vlanConfigs.keys);
      for (final p in sw.ports) {
        allVlans.addAll(p.effectiveVlans(switchSupportsVlans: sw.supportsVlans));
      }
    }
    for (final l in links) {
      allVlans.addAll(l.activeVlans);
    }

    final sortedVlans = allVlans.toList()..sort();

    for (final vlanId in sortedVlans) {
      // Switches participating in vlanId.
      final participatingSwitches = switchesById.values.where((sw) {
        if (sw.vlanConfigs.containsKey(vlanId)) return true;
        if (sw.ports.any(
            (p) => p.permitsVlan(vlanId, switchSupportsVlans: sw.supportsVlans))) {
          return true;
        }
        return false;
      }).toList();

      if (participatingSwitches.isEmpty) continue;

      final vlanLinks = forwardingInterSwitchLinks
          .where((l) => l.activeVlans.contains(vlanId))
          .toList();

      // Partition participating switches into connected subgraphs for this VLAN.
      final visited = <String>{};
      for (final seed in participatingSwitches) {
        if (visited.contains(seed.id)) continue;
        final compIds = <String>{seed.id};
        final queue = <String>[seed.id];
        while (queue.isNotEmpty) {
          final curr = queue.removeAt(0);
          for (final l in vlanLinks) {
            if (!l.connectsNode(curr)) continue;
            final next = l.otherNodeId(curr);
            if (switchesById.containsKey(next) && compIds.add(next)) {
              queue.add(next);
            }
          }
        }
        visited.addAll(compIds);

        final compSwitches = compIds.map((id) => switchesById[id]!).toList();

        // Check Snooping vs Querier in this reachable VLAN subgraph.
        final snoopers = compSwitches.where((sw) {
          final cfg = sw.vlanConfigs[vlanId];
          return sw.supportsIgmpSnooping &&
              cfg != null &&
              cfg.igmpSnoopingEnabled;
        }).toList();

        final queriers = compSwitches.where((sw) {
          final cfg = sw.vlanConfigs[vlanId];
          return sw.supportsIgmpQuerier &&
              cfg != null &&
              cfg.igmpQuerierEnabled;
        }).toList();

        if (snoopers.isNotEmpty && queriers.isEmpty) {
          final firstSnooper = snoopers.first;
          issues.add(
            ValidationIssue(
              id: 'igmp-no-querier-v$vlanId-${firstSnooper.id}',
              severity: IssueSeverity.critical,
              category: IssueCategory.igmp,
              title: 'IGMP Snooping Without Active Querier',
              message:
                  'VLAN $vlanId has IGMP Snooping enabled on ${firstSnooper.userLabel}, but no reachable IGMP Querier on VLAN $vlanId. Multicast streams will time out and drop after ~260 seconds.',
              recommendation:
                  'Enable an IGMP Querier for VLAN $vlanId on your core switch and ensure VLAN $vlanId is carried across all trunks.',
              nodeId: firstSnooper.id,
              vlanId: vlanId,
            ),
          );
        }

        if (queriers.isNotEmpty) {
          // Elect active querier: lowest IPv4 management IP, tie-broken by lowest MAC.
          queriers.sort((a, b) {
            final ipCmp = SwitchNodeInstance.parseIpToInt(a.managementIp)
                .compareTo(SwitchNodeInstance.parseIpToInt(b.managementIp));
            if (ipCmp != 0) return ipCmp;
            return a.macAddressInt.compareTo(b.macAddressInt);
          });
          final electedQuerier = queriers.first;
          electedQuerier.activeQuerierVlans.add(vlanId);

          // Check Querier vs Root Bridge split inside this component (if component has > 1 switch).
          final rootInComp = compSwitches.where((sw) => sw.isRootBridge).toList();
          if (compSwitches.length > 1 &&
              rootInComp.isNotEmpty &&
              electedQuerier.id != rootInComp.first.id) {
            final root = rootInComp.first;
            issues.add(
              ValidationIssue(
                id: 'igmp-querier-root-split-v$vlanId-${electedQuerier.id}',
                severity: IssueSeverity.warning,
                category: IssueCategory.igmp,
                title: 'IGMP Querier / STP Root Bridge Split',
                message:
                    'Active IGMP Querier for VLAN $vlanId (${electedQuerier.userLabel}) is not on the STP Root Bridge (${root.userLabel}), causing multicast traffic to hair-pin across trunk links.',
                recommendation:
                    'Place the IGMP Querier for VLAN $vlanId on the STP Root Bridge (${root.userLabel}).',
                nodeId: electedQuerier.id,
                vlanId: vlanId,
              ),
            );
          }
        }

        // Check IGMP version conflicts (v2 vs v3) across switches in the same VLAN subgraph.
        final igmpVersions = <IgmpVersion>{};
        for (final sw in compSwitches) {
          final cfg = sw.vlanConfigs[vlanId];
          if (cfg != null &&
              ((sw.supportsIgmpSnooping && cfg.igmpSnoopingEnabled) ||
                  (sw.supportsIgmpQuerier && cfg.igmpQuerierEnabled))) {
            igmpVersions.add(cfg.igmpQuerierVersion);
          }
        }
        if (igmpVersions.contains(IgmpVersion.v2) &&
            igmpVersions.contains(IgmpVersion.v3)) {
          issues.add(
            ValidationIssue(
              id: 'igmp-version-conflict-v$vlanId-${seed.id}',
              severity: IssueSeverity.warning,
              category: IssueCategory.igmp,
              title: 'IGMP Version Mismatch on VLAN $vlanId',
              message:
                  'Switches on VLAN $vlanId mix IGMPv2 and IGMPv3 querier/snooping configurations, which can trigger compatibility fallbacks or group membership delays.',
              recommendation:
                  'Standardize all switches on VLAN $vlanId to IGMPv2 (recommended for sACN/Dante) or IGMPv3.',
              nodeId: seed.id,
              vlanId: vlanId,
            ),
          );
        }

        // Check flooded multicast / broadcast (> 70 Mbps) into 100M ports.
        var broadcastMbps = 0.0;
        var multicastMbps = 0.0;
        for (final ep in endpointsById.values) {
          for (final flow in ep.activeTrafficFlows) {
            if (!flow.direction.isPublisher) continue;
            final att = epAttachments['${ep.id}:${flow.effectivePortNumber}'];
            if (att == null || !compIds.contains(att.sw.id)) continue;
            final flowVlan = MulticastFlowTracer.effectiveVlanForFlow(flow, att);
            if (flowVlan != vlanId) continue;

            if (flow.deliveryType == DeliveryType.broadcast) {
              broadcastMbps += flow.estimatedBandwidthMbps;
            } else if (flow.deliveryType == DeliveryType.multicast) {
              multicastMbps += flow.estimatedBandwidthMbps;
            }
          }
        }

        for (final sw in compSwitches) {
          final has100MPortOnVlan = sw.ports.any((p) =>
              p.maxSpeed == PortSpeed.speed100M &&
              p.permitsVlan(vlanId, switchSupportsVlans: sw.supportsVlans));
          if (!has100MPortOnVlan) continue;

          final cfg = sw.vlanConfigs[vlanId];
          final snoopingActive = sw.supportsIgmpSnooping &&
              cfg != null &&
              cfg.igmpSnoopingEnabled;
          final floodedMbps =
              snoopingActive ? broadcastMbps : (broadcastMbps + multicastMbps);

          if (floodedMbps > 70.0) {
            issues.add(
              ValidationIssue(
                id: 'igmp-100m-flood-v$vlanId-${sw.id}',
                severity: IssueSeverity.warning,
                category: IssueCategory.igmp,
                title: '100M Port Flood Saturation Risk',
                message:
                    '${floodedMbps.toStringAsFixed(1)} Mbps of ${snoopingActive ? "broadcast" : "un-snooped multicast/broadcast"} traffic on VLAN $vlanId exceeds 70 Mbps and risks saturating 100M access ports on ${sw.userLabel}.',
                recommendation: snoopingActive
                    ? 'Isolate high-volume broadcast protocols (like Art-Net) or upgrade 100M links to 1G.'
                    : 'Enable IGMP Snooping + Querier on VLAN $vlanId or upgrade 100M ports to 1G.',
                nodeId: sw.id,
                vlanId: vlanId,
              ),
            );
          }
        }
      }
    }
  }
}
