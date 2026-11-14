import '../models/endpoint_node_instance.dart';
import '../models/enums.dart';
import '../models/network_link_edge.dart';
import '../models/switch_node_instance.dart';
import '../models/switch_port_config.dart';
import '../models/validation_issue.dart';

/// Pass 2: Link-Level VLAN Symmetry Checks & Per-VLAN BFS Path Tracer.
class VlanReachabilitySolver {
  const VlanReachabilitySolver();

  void solve({
    required Map<String, SwitchNodeInstance> switchesById,
    required Map<String, EndpointNodeInstance> endpointsById,
    required List<NetworkLinkEdge> links,
    required List<ValidationIssue> issues,
  }) {
    // 2.1 Evaluate VLANs & symmetry on all links.
    for (final link in links) {
      final swA = switchesById[link.sourceNodeId];
      final swB = switchesById[link.targetNodeId];

      if (swA != null && swB != null) {
        final portA = swA.portByNumber(link.sourcePortNumber);
        final portB = swB.portByNumber(link.targetPortNumber);
        if (portA == null || portB == null) continue;

        _evaluateInterSwitchVlanSymmetry(
          link: link,
          swA: swA,
          portA: portA,
          swB: swB,
          portB: portB,
          issues: issues,
        );
      } else if (swA != null || swB != null) {
        // Endpoint <-> Switch link
        final sw = swA ?? swB!;
        final portNum =
            swA != null ? link.sourcePortNumber : link.targetPortNumber;
        final port = sw.portByNumber(portNum);
        if (port != null) {
          link.activeVlans =
              port.effectiveVlans(switchSupportsVlans: sw.supportsVlans).toSet();
        }
      }
    }

    // Map each endpoint to its attached switch, switch port, and access link.
    final epAttachment =
        <String, ({SwitchNodeInstance sw, SwitchPortConfig port, NetworkLinkEdge link})>{};
    for (final link in links) {
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
    }

    // Check endpoint flow VLAN vs connected switch port VLAN.
    for (final ep in endpointsById.values) {
      final att = epAttachment[ep.id];
      if (att == null) continue;
      if (!att.sw.supportsVlans) continue;

      for (final flow in ep.activeTrafficFlows) {
        if (!att.port.permitsVlan(flow.defaultVlanId,
            switchSupportsVlans: att.sw.supportsVlans)) {
          issues.add(
            ValidationIssue(
              id: 'vlan-ep-port-mismatch-${ep.id}-${flow.id}',
              severity: IssueSeverity.warning,
              category: IssueCategory.vlan,
              title: 'Endpoint Traffic VLAN Mismatch',
              message:
                  '${ep.userLabel} (${flow.protocol.label}) expects VLAN ${flow.defaultVlanId}, but ${att.sw.userLabel} Port ${att.port.portNumber} is ${att.port.portMode.label} VLAN ${att.port.nativeVlan}.',
              recommendation:
                  'Assign ${att.sw.userLabel} Port ${att.port.portNumber} to VLAN ${flow.defaultVlanId} or update the endpoint flow VLAN.',
              nodeId: att.sw.id,
              portNumber: att.port.portNumber,
              linkId: att.link.id,
              vlanId: flow.defaultVlanId,
            ),
          );
        }
      }
    }

    // 2.2 End-to-End VLAN-Filtered BFS reachability check across forwarding links.
    final forwardingInterSwitchLinks = links.where((l) {
      final isInterSwitch = switchesById.containsKey(l.sourceNodeId) &&
          switchesById.containsKey(l.targetNodeId);
      return isInterSwitch &&
          (l.stpState == LinkStpState.forwarding ||
              l.stpState == LinkStpState.loopUnprotected);
    }).toList();

    final endpointList = endpointsById.values.toList();
    final reportedBlackholes = <String>{};

    for (var i = 0; i < endpointList.length; i++) {
      final epA = endpointList[i];
      final attA = epAttachment[epA.id];
      if (attA == null) continue;

      for (var j = 0; j < endpointList.length; j++) {
        if (i == j) continue;
        final epB = endpointList[j];
        final attB = epAttachment[epB.id];
        if (attB == null) continue;

        for (final flowA in epA.activeTrafficFlows) {
          if (!flowA.direction.isPublisher) continue;

          for (final flowB in epB.activeTrafficFlows) {
            if (!flowB.direction.isSubscriber) continue;
            if (flowA.protocol != flowB.protocol) continue;

            // Ingress VLAN from switch port (or flow default if unmanaged).
            final vlanA = attA.sw.supportsVlans
                ? attA.port.nativeVlan
                : flowA.defaultVlanId;
            final vlanB = attB.sw.supportsVlans
                ? attB.port.nativeVlan
                : flowB.defaultVlanId;

            if (vlanA != vlanB) {
              // Also check if both flows specifically want the same VLAN
              // when they are already flagged at the port level above.
              continue;
            }

            final vlanId = vlanA;
            if (attA.sw.id == attB.sw.id) {
              // Same switch — locally reachable on same VLAN.
              continue;
            }

            final reachable = _isReachableOnVlan(
              startSwitchId: attA.sw.id,
              targetSwitchId: attB.sw.id,
              vlanId: vlanId,
              forwardingLinks: forwardingInterSwitchLinks,
            );

            if (!reachable) {
              final pairKey = '${epB.id}->${epA.id}:V$vlanId:${flowA.protocol.name}';
              if (!reportedBlackholes.add(pairKey)) continue;

              // Find exact link on the forwarding tree where VLAN is dropped.
              final blockingHop = _findBlockingVlanHop(
                startSwitchId: attA.sw.id,
                targetSwitchId: attB.sw.id,
                vlanId: vlanId,
                forwardingLinks: forwardingInterSwitchLinks,
              );

              if (blockingHop != null) {
                final hopSwA = switchesById[blockingHop.sourceNodeId]!;
                final hopSwB = switchesById[blockingHop.targetNodeId]!;
                issues.add(
                  ValidationIssue(
                    id: 'vlan-blackhole-$pairKey',
                    severity: IssueSeverity.critical,
                    category: IssueCategory.vlan,
                    title: 'Isolated Endpoint / VLAN $vlanId Blackhole',
                    message:
                        '${epB.userLabel} on VLAN $vlanId cannot reach ${epA.userLabel} — VLAN $vlanId is not carried across ${hopSwA.userLabel} Port ${blockingHop.sourcePortNumber} -> ${hopSwB.userLabel} Port ${blockingHop.targetPortNumber}.',
                    recommendation:
                        'Add VLAN $vlanId to the allowed trunk VLAN list on both ends of that link.',
                    nodeId: hopSwA.id,
                    portNumber: blockingHop.sourcePortNumber,
                    linkId: blockingHop.id,
                    vlanId: vlanId,
                  ),
                );
              } else {
                issues.add(
                  ValidationIssue(
                    id: 'vlan-disconnected-$pairKey',
                    severity: IssueSeverity.critical,
                    category: IssueCategory.vlan,
                    title: 'Unreachable Endpoint on VLAN $vlanId',
                    message:
                        '${epB.userLabel} on VLAN $vlanId cannot reach ${epA.userLabel} — no forwarding Layer 2 path exists between ${attA.sw.userLabel} and ${attB.sw.userLabel}.',
                    recommendation:
                        'Connect the switches with a trunk link carrying VLAN $vlanId.',
                    nodeId: attB.sw.id,
                    portNumber: attB.port.portNumber,
                    vlanId: vlanId,
                  ),
                );
              }
            }
          }
        }
      }
    }
  }

  void _evaluateInterSwitchVlanSymmetry({
    required NetworkLinkEdge link,
    required SwitchNodeInstance swA,
    required SwitchPortConfig portA,
    required SwitchNodeInstance swB,
    required SwitchPortConfig portB,
    required List<ValidationIssue> issues,
  }) {
    if (!swA.supportsVlans && !swB.supportsVlans) {
      link.activeVlans = {1};
      return;
    }

    if (!swA.supportsVlans || !swB.supportsVlans) {
      // Unmanaged switch passes the managed neighbor's native/access VLAN transparently.
      final managedPort = swA.supportsVlans ? portA : portB;
      final managedSw = swA.supportsVlans ? swA : swB;
      final unmanagedSw = swA.supportsVlans ? swB : swA;
      link.activeVlans = {managedPort.nativeVlan};
      if (managedPort.portMode == SwitchPortMode.trunk) {
        link.hasVlanMismatch = true;
        issues.add(
          ValidationIssue(
            id: 'vlan-unmanaged-trunk-${link.id}',
            severity: IssueSeverity.warning,
            category: IssueCategory.vlan,
            title: 'Trunk Connected to Unmanaged Switch',
            message:
                '${managedSw.userLabel} Port ${managedPort.portNumber} is a Trunk connected to unmanaged switch ${unmanagedSw.userLabel}. Tagged VLANs may be dropped or mis-forwarded.',
            recommendation:
                'Use an Access port on ${managedSw.userLabel} or replace ${unmanagedSw.userLabel} with a VLAN-capable switch.',
            nodeId: managedSw.id,
            portNumber: managedPort.portNumber,
            linkId: link.id,
          ),
        );
      }
      return;
    }

    // Both switches support 802.1Q VLANs.
    final vlansA = portA.effectiveVlans(switchSupportsVlans: true);
    final vlansB = portB.effectiveVlans(switchSupportsVlans: true);
    link.activeVlans = vlansA.intersection(vlansB);

    if (portA.portMode != portB.portMode) {
      link.hasVlanMismatch = true;
      issues.add(
        ValidationIssue(
          id: 'vlan-mode-mismatch-${link.id}',
          severity: IssueSeverity.critical,
          category: IssueCategory.vlan,
          title: 'Access-to-Trunk Port Mismatch',
          message:
              'Port mode mismatch on ${swA.userLabel} Port ${portA.portNumber} (${portA.portMode.label}) <-> ${swB.userLabel} Port ${portB.portNumber} (${portB.portMode.label}).',
          recommendation:
              'Configure both ends of an inter-switch uplink as Trunk ports with identical Native and Allowed VLANs.',
          nodeId: swA.id,
          portNumber: portA.portNumber,
          linkId: link.id,
        ),
      );
      return;
    }

    if (portA.portMode == SwitchPortMode.access &&
        portB.portMode == SwitchPortMode.access) {
      if (portA.nativeVlan != portB.nativeVlan) {
        link.hasVlanMismatch = true;
        issues.add(
          ValidationIssue(
            id: 'vlan-access-mismatch-${link.id}',
            severity: IssueSeverity.critical,
            category: IssueCategory.vlan,
            title: 'Access VLAN Mismatch on Link',
            message:
                'Access VLAN mismatch between ${swA.userLabel} Port ${portA.portNumber} (VLAN ${portA.nativeVlan}) and ${swB.userLabel} Port ${portB.portNumber} (VLAN ${portB.nativeVlan}).',
            recommendation:
                'Match the Access VLAN on both ports or convert both to Trunk mode.',
            nodeId: swA.id,
            portNumber: portA.portNumber,
            linkId: link.id,
          ),
        );
      }
      return;
    }

    // Both ports are Trunk.
    if (portA.nativeVlan != portB.nativeVlan) {
      link.hasVlanMismatch = true;
      issues.add(
        ValidationIssue(
          id: 'vlan-native-mismatch-${link.id}',
          severity: IssueSeverity.critical,
          category: IssueCategory.vlan,
          title: 'Trunk Native VLAN (PVID) Mismatch',
          message:
              'Native VLAN mismatch between ${swA.userLabel} Port ${portA.portNumber} (Native VLAN ${portA.nativeVlan}) and ${swB.userLabel} Port ${portB.portNumber} (Native VLAN ${portB.nativeVlan}).',
          recommendation:
              'Set matching Native VLANs (PVID) on both ends of the trunk link.',
          nodeId: swA.id,
          portNumber: portA.portNumber,
          linkId: link.id,
        ),
      );
    }

    final onlyInA = vlansA.difference(vlansB).toList()..sort();
    final onlyInB = vlansB.difference(vlansA).toList()..sort();
    link.prunedVlans = {...onlyInA, ...onlyInB};

    for (final v in onlyInA) {
      issues.add(
        ValidationIssue(
          id: 'vlan-asym-a-${link.id}-$v',
          severity: IssueSeverity.warning,
          category: IssueCategory.vlan,
          title: 'Asymmetric Trunk Allowed VLANs',
          message:
              'VLAN $v is allowed out of ${swA.userLabel}: Port ${portA.portNumber} but blocked on ${swB.userLabel}: Port ${portB.portNumber}.',
          recommendation:
              'Allow VLAN $v on ${swB.userLabel} Port ${portB.portNumber} or prune it from ${swA.userLabel} Port ${portA.portNumber}.',
          nodeId: swB.id,
          portNumber: portB.portNumber,
          linkId: link.id,
          vlanId: v,
        ),
      );
    }

    for (final v in onlyInB) {
      issues.add(
        ValidationIssue(
          id: 'vlan-asym-b-${link.id}-$v',
          severity: IssueSeverity.warning,
          category: IssueCategory.vlan,
          title: 'Asymmetric Trunk Allowed VLANs',
          message:
              'VLAN $v is allowed out of ${swB.userLabel}: Port ${portB.portNumber} but blocked on ${swA.userLabel}: Port ${portA.portNumber}.',
          recommendation:
              'Allow VLAN $v on ${swA.userLabel} Port ${portA.portNumber} or prune it from ${swB.userLabel} Port ${portB.portNumber}.',
          nodeId: swA.id,
          portNumber: portA.portNumber,
          linkId: link.id,
          vlanId: v,
        ),
      );
    }
  }

  bool _isReachableOnVlan({
    required String startSwitchId,
    required String targetSwitchId,
    required int vlanId,
    required List<NetworkLinkEdge> forwardingLinks,
  }) {
    if (startSwitchId == targetSwitchId) return true;
    final visited = <String>{startSwitchId};
    final queue = <String>[startSwitchId];
    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      for (final link in forwardingLinks) {
        if (!link.connectsNode(curr)) continue;
        if (!link.activeVlans.contains(vlanId)) continue;
        final next = link.otherNodeId(curr);
        if (next == targetSwitchId) return true;
        if (visited.add(next)) {
          queue.add(next);
        }
      }
    }
    return false;
  }

  NetworkLinkEdge? _findBlockingVlanHop({
    required String startSwitchId,
    required String targetSwitchId,
    required int vlanId,
    required List<NetworkLinkEdge> forwardingLinks,
  }) {
    // BFS on physical forwarding topology (ignoring VLAN filter) to reconstruct
    // the active STP path between startSwitchId and targetSwitchId.
    final visited = <String>{startSwitchId};
    final parentLink = <String, NetworkLinkEdge>{};
    final parentNode = <String, String>{};
    final queue = <String>[startSwitchId];
    var found = false;

    while (queue.isNotEmpty && !found) {
      final curr = queue.removeAt(0);
      for (final link in forwardingLinks) {
        if (!link.connectsNode(curr)) continue;
        final next = link.otherNodeId(curr);
        if (visited.add(next)) {
          parentLink[next] = link;
          parentNode[next] = curr;
          if (next == targetSwitchId) {
            found = true;
            break;
          }
          queue.add(next);
        }
      }
    }

    if (!found) return null;

    // Walk path from start -> target and return first hop missing vlanId.
    final pathLinks = <NetworkLinkEdge>[];
    String? cursor = targetSwitchId;
    while (cursor != null && cursor != startSwitchId) {
      final l = parentLink[cursor];
      if (l == null) break;
      pathLinks.add(l);
      cursor = parentNode[cursor];
    }

    for (final link in pathLinks.reversed) {
      if (!link.activeVlans.contains(vlanId)) {
        return link;
      }
    }
    return null;
  }
}
