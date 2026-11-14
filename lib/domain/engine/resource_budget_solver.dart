import '../models/endpoint_node_instance.dart';
import '../models/enums.dart';
import '../models/network_link_edge.dart';
import '../models/switch_node_instance.dart';
import '../models/switch_port_config.dart';
import '../models/validation_issue.dart';

/// Pass 4: Link Bandwidth Utilization, Speed Step-Down & PoE Budget Solver.
class ResourceBudgetSolver {
  const ResourceBudgetSolver();

  void solve({
    required Map<String, SwitchNodeInstance> switchesById,
    required Map<String, EndpointNodeInstance> endpointsById,
    required List<NetworkLinkEdge> links,
    required List<ValidationIssue> issues,
  }) {
    // Map endpoints to their connected switch, port, and link.
    final epAttachment =
        <String, ({SwitchNodeInstance sw, SwitchPortConfig port, NetworkLinkEdge link})>{};

    for (final link in links) {
      link.estimatedLoadMbps = 0.0;
      final epA = endpointsById[link.sourceNodeId];
      final epB = endpointsById[link.targetNodeId];
      final swA = switchesById[link.sourceNodeId];
      final swB = switchesById[link.targetNodeId];

      if (epA != null && swB != null) {
        final port = swB.portByNumber(link.targetPortNumber);
        if (port != null) {
          epAttachment[epA.id] = (sw: swB, port: port, link: link);
        }
      } else if (epB != null && swA != null) {
        final port = swA.portByNumber(link.sourcePortNumber);
        if (port != null) {
          epAttachment[epB.id] = (sw: swA, port: port, link: link);
        }
      }

      // Report speed step-downs (e.g. 10G port connected to 1G or 100M port).
      if (link.hasSpeedStepDown) {
        final nameA = swA?.userLabel ?? epA?.userLabel ?? link.sourceNodeId;
        final nameB = swB?.userLabel ?? epB?.userLabel ?? link.targetNodeId;
        final speedA = swA?.portByNumber(link.sourcePortNumber)?.maxSpeed ??
            epA?.nicSpeed ??
            link.negotiatedSpeed;
        final speedB = swB?.portByNumber(link.targetPortNumber)?.maxSpeed ??
            epB?.nicSpeed ??
            link.negotiatedSpeed;

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

    final forwardingInterSwitchLinks = links.where((l) {
      return switchesById.containsKey(l.sourceNodeId) &&
          switchesById.containsKey(l.targetNodeId) &&
          (l.stpState == LinkStpState.forwarding ||
              l.stpState == LinkStpState.loopUnprotected);
    }).toList();

    // 4.1 Accumulate bandwidth across access links & inter-switch forwarding tree.
    for (final ep in endpointsById.values) {
      final att = epAttachment[ep.id];
      if (att == null) continue;

      for (final flow in ep.activeTrafficFlows) {
        att.link.estimatedLoadMbps += flow.estimatedBandwidthMbps;

        if (!flow.direction.isPublisher) continue;
        final vlanId =
            att.sw.supportsVlans ? att.port.nativeVlan : flow.defaultVlanId;

        final vlanForwardLinks = forwardingInterSwitchLinks
            .where((l) => l.activeVlans.contains(vlanId))
            .toList();

        // Check whether traffic floods across the VLAN subgraph
        // (broadcast or un-snooped multicast).
        final isBroadcast = flow.deliveryType == DeliveryType.broadcast;
        final isUnsnoopedMulticast =
            flow.deliveryType == DeliveryType.multicast &&
                !(att.sw.supportsIgmpSnooping &&
                    (att.sw.vlanConfigs[vlanId]?.igmpSnoopingEnabled ?? false));

        if (isBroadcast || isUnsnoopedMulticast) {
          // Floods across every reachable forwarding link carrying vlanId.
          final floodedLinks = _collectReachableVlanLinks(
            startSwitchId: att.sw.id,
            vlanLinks: vlanForwardLinks,
          );
          for (final l in floodedLinks) {
            l.estimatedLoadMbps += flow.estimatedBandwidthMbps;
          }
        } else {
          // Directed/snooped flow: trace path union to matching reachable subscribers.
          final targetSwitches = <String>{};
          for (final otherEp in endpointsById.values) {
            if (otherEp.id == ep.id) continue;
            final otherAtt = epAttachment[otherEp.id];
            if (otherAtt == null || otherAtt.sw.id == att.sw.id) continue;
            final otherVlan = otherAtt.sw.supportsVlans
                ? otherAtt.port.nativeVlan
                : vlanId;
            if (otherVlan != vlanId) continue;

            final subscribes = otherEp.activeTrafficFlows.any(
              (f) => f.direction.isSubscriber && f.protocol == flow.protocol,
            );
            if (subscribes) {
              targetSwitches.add(otherAtt.sw.id);
            }
          }

          if (targetSwitches.isNotEmpty) {
            final traversedLinks = _collectShortestPathUnion(
              startSwitchId: att.sw.id,
              targetSwitchIds: targetSwitches,
              vlanLinks: vlanForwardLinks,
            );
            for (final l in traversedLinks) {
              l.estimatedLoadMbps += flow.estimatedBandwidthMbps;
            }
          }
        }
      }
    }

    // Check link utilization thresholds (> 75% Warning, > 95% Critical).
    for (final link in links) {
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

    // 4.2 PoE port capability & switch budget aggregation.
    for (final ep in endpointsById.values) {
      if (ep.poeDrawWatts <= 0) continue;
      final att = epAttachment[ep.id];
      if (att == null) continue;

      final suppliesPoe = att.sw.poeBudgetWatts > 0 &&
          att.port.poeCapable &&
          att.port.poeEnabled;
      if (!suppliesPoe) {
        issues.add(
          ValidationIssue(
            id: 'poe-port-incapable-${ep.id}',
            severity: IssueSeverity.critical,
            category: IssueCategory.poe,
            title: 'PoE Power Missing on Port',
            message:
                '${ep.userLabel} requires ${ep.poeDrawWatts.toStringAsFixed(1)}W PoE, but ${att.sw.userLabel}: Port ${att.port.portNumber} does not supply PoE.',
            recommendation:
                'Move ${ep.userLabel} to a PoE-enabled port, enable PoE on Port ${att.port.portNumber}, or use a local power supply / PoE injector.',
            nodeId: att.sw.id,
            portNumber: att.port.portNumber,
            linkId: att.link.id,
          ),
        );
      } else {
        att.sw.totalPoeDrawWatts += ep.poeDrawWatts;
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

  Set<NetworkLinkEdge> _collectShortestPathUnion({
    required String startSwitchId,
    required Set<String> targetSwitchIds,
    required List<NetworkLinkEdge> vlanLinks,
  }) {
    final visited = <String>{startSwitchId};
    final parentLink = <String, NetworkLinkEdge>{};
    final parentNode = <String, String>{};
    final queue = <String>[startSwitchId];

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

    final unionLinks = <NetworkLinkEdge>{};
    for (final target in targetSwitchIds) {
      if (!visited.contains(target)) continue;
      String? cursor = target;
      while (cursor != null && cursor != startSwitchId) {
        final l = parentLink[cursor];
        if (l == null) break;
        unionLinks.add(l);
        cursor = parentNode[cursor];
      }
    }
    return unionLinks;
  }
}
