import '../models/enums.dart';
import '../models/network_link_edge.dart';
import '../models/switch_node_instance.dart';
import '../models/validation_issue.dart';

/// Pass 1: Spanning Tree Election, Unprotected Loop Detection & Ring Split Solver.
class StpElectionSolver {
  const StpElectionSolver();

  void solve({
    required Map<String, SwitchNodeInstance> switchesById,
    required List<NetworkLinkEdge> links,
    required List<ValidationIssue> issues,
  }) {
    final interSwitchLinks = links
        .where((l) =>
            switchesById.containsKey(l.sourceNodeId) &&
            switchesById.containsKey(l.targetNodeId))
        .toList();

    // 1.1 Detect cycles containing any unmanaged or STP-disabled switch.
    final unprotectedLoopLinkIds = <String>{};

    for (final link in interSwitchLinks) {
      final swA = switchesById[link.sourceNodeId]!;
      final swB = switchesById[link.targetNodeId]!;

      final touchesUnprotected = !swA.isStpActive || !swB.isStpActive;
      if (!touchesUnprotected) continue;

      final isSelfLoop = link.sourceNodeId == link.targetNodeId;
      final inCycle = isSelfLoop ||
          _hasAlternatePath(
            startId: link.sourceNodeId,
            targetId: link.targetNodeId,
            excludedLinkId: link.id,
            links: interSwitchLinks,
          );

      if (inCycle) {
        unprotectedLoopLinkIds.add(link.id);
        link.stpState = LinkStpState.loopUnprotected;

        issues.add(
          ValidationIssue(
            id: 'stp-unprotected-loop-${link.id}',
            severity: IssueSeverity.critical,
            category: IssueCategory.stp,
            title: 'Unprotected Layer 2 Loop',
            message:
                'Unprotected Layer 2 Loop detected between ${swA.userLabel} and ${swB.userLabel} (${swA.userLabel} P${link.sourcePortNumber} <-> ${swB.userLabel} P${link.targetPortNumber}) — broadcast/multicast storm hazard.',
            recommendation:
                'Enable RSTP on both switches or remove the redundant cable on an unmanaged switch.',
            nodeId: !swA.isStpActive ? swA.id : swB.id,
            portNumber: !swA.isStpActive
                ? link.sourcePortNumber
                : link.targetPortNumber,
            linkId: link.id,
          ),
        );
      }
    }

    // 1.2 Group STP-enabled switches into connected components over STP-active links.
    final stpActiveLinks = interSwitchLinks.where((l) {
      if (unprotectedLoopLinkIds.contains(l.id)) return false;
      final swA = switchesById[l.sourceNodeId]!;
      final swB = switchesById[l.targetNodeId]!;
      return swA.isStpActive && swB.isStpActive;
    }).toList();

    final stpSwitches =
        switchesById.values.where((sw) => sw.isStpActive).toList();
    final visitedComponents = <String>{};

    for (final seed in stpSwitches) {
      if (visitedComponents.contains(seed.id)) continue;

      // Collect connected component of STP-enabled switches.
      final componentIds = <String>{seed.id};
      final queue = <String>[seed.id];
      while (queue.isNotEmpty) {
        final curr = queue.removeAt(0);
        for (final link in stpActiveLinks) {
          if (!link.connectsNode(curr)) continue;
          final next = link.otherNodeId(curr);
          if (componentIds.add(next)) {
            queue.add(next);
          }
        }
      }
      visitedComponents.addAll(componentIds);

      final componentSwitches =
          componentIds.map((id) => switchesById[id]!).toList();
      componentSwitches.sort((a, b) => a.compareBridgeId(b));
      final root = componentSwitches.first;
      root.isRootBridge = true;
      root.rootPathCost = 0;
      root.hopDepthFromRoot = 0;

      if (componentSwitches.length > 1) {
        if (root.stpPriority == 32768) {
          issues.add(
            ValidationIssue(
              id: 'stp-arbitrary-root-${root.id}',
              severity: IssueSeverity.warning,
              category: IssueCategory.stp,
              title: 'Arbitrary STP Root Bridge Election',
              message:
                  'Root Bridge elected arbitrarily by MAC address on ${root.userLabel} (default priority 32768). Set explicit priority 4096 on your core switch.',
              recommendation:
                  'Set STP Priority to 4096 on your intended core switch and 8192 on your secondary core.',
              nodeId: root.id,
            ),
          );
        } else {
          issues.add(
            ValidationIssue(
              id: 'stp-root-info-${root.id}',
              severity: IssueSeverity.info,
              category: IssueCategory.stp,
              title: 'STP Root Bridge Elected',
              message:
                  '${root.userLabel} elected as Root Bridge (Priority ${root.stpPriority}, MAC ${root.macAddress}).',
              nodeId: root.id,
            ),
          );
        }
      }

      // 1.3 Dijkstra shortest-path spanning tree from Root Bridge.
      final distCost = <String, int>{root.id: 0};
      final hopDepth = <String, int>{root.id: 0};
      final parentLink = <String, NetworkLinkEdge>{};
      final parentBridge = <String, SwitchNodeInstance>{};
      final parentUpstreamPort = <String, int>{};
      final parentDownstreamPort = <String, int>{};
      final settled = <String>{};

      final compLinks = stpActiveLinks
          .where((l) =>
              componentIds.contains(l.sourceNodeId) &&
              componentIds.contains(l.targetNodeId))
          .toList();

      while (settled.length < componentSwitches.length) {
        SwitchNodeInstance? u;
        var bestDist = 0x7FFFFFFF;
        for (final sw in componentSwitches) {
          if (settled.contains(sw.id)) continue;
          final d = distCost[sw.id];
          if (d != null &&
              (u == null ||
                  d < bestDist ||
                  (d == bestDist && sw.compareBridgeId(u) < 0))) {
            u = sw;
            bestDist = d;
          }
        }
        if (u == null) break;
        settled.add(u.id);
        u.rootPathCost = bestDist;
        u.hopDepthFromRoot = hopDepth[u.id] ?? 0;

        for (final link in compLinks) {
          if (!link.connectsNode(u.id)) continue;
          final vId = link.otherNodeId(u.id);
          if (vId == u.id || settled.contains(vId)) continue;

          final candidateCost = bestDist + link.negotiatedSpeed.stpCost;
          final existingCost = distCost[vId];
          final upstreamPort = link.portForNode(u.id);
          final downstreamPort = link.portForNode(vId);

          var shouldUpdate = existingCost == null || candidateCost < existingCost;
          if (!shouldUpdate && candidateCost == existingCost) {
            final prevParent = parentBridge[vId];
            if (prevParent != null) {
              final bridgeCmp = u.compareBridgeId(prevParent);
              if (bridgeCmp < 0) {
                shouldUpdate = true;
              } else if (bridgeCmp == 0) {
                final prevPort = parentUpstreamPort[vId] ?? 0x7FFFFFFF;
                final prevDownPort = parentDownstreamPort[vId] ?? 0x7FFFFFFF;
                if (upstreamPort < prevPort ||
                    (upstreamPort == prevPort &&
                        downstreamPort < prevDownPort)) {
                  shouldUpdate = true;
                }
              }
            }
          }

          if (shouldUpdate) {
            distCost[vId] = candidateCost;
            hopDepth[vId] = (hopDepth[u.id] ?? 0) + 1;
            parentLink[vId] = link;
            parentBridge[vId] = u;
            parentUpstreamPort[vId] = upstreamPort;
            parentDownstreamPort[vId] = downstreamPort;
          }
        }
      }

      // Assign forwarding / blocking states on component links.
      final treeLinkIds = <String>{
        for (final edge in parentLink.values) edge.id,
      };

      for (final link in compLinks) {
        if (treeLinkIds.contains(link.id)) {
          link.stpState = LinkStpState.forwarding;
          link.directionFromRootSourceToTarget =
              parentLink[link.targetNodeId]?.id == link.id;
        } else {
          link.stpState = LinkStpState.blocking;
          final swA = switchesById[link.sourceNodeId]!;
          final swB = switchesById[link.targetNodeId]!;

          if (swA.id == swB.id) {
            // Self-loop on two ports of the same switch: higher port blocks.
            final blockPort = link.sourcePortNumber >= link.targetPortNumber
                ? link.sourcePortNumber
                : link.targetPortNumber;
            link.blockedAtNodeId = swA.id;
            link.blockedAtPortNumber = blockPort;
          } else {
            // Designated vs Alternate/Blocking port decision:
            // Lower rootPathCost stays Designated (forwarding), higher cost blocks.
            // On equal rootPathCost, lower Bridge ID stays Designated, higher Bridge ID blocks.
            final costCmp = swA.rootPathCost.compareTo(swB.rootPathCost);
            final bool blockAtB;
            if (costCmp != 0) {
              blockAtB = costCmp < 0;
            } else {
              blockAtB = swA.compareBridgeId(swB) < 0;
            }
            if (blockAtB) {
              link.blockedAtNodeId = swB.id;
              link.blockedAtPortNumber = link.targetPortNumber;
              link.directionFromRootSourceToTarget = true;
            } else {
              link.blockedAtNodeId = swA.id;
              link.blockedAtPortNumber = link.sourcePortNumber;
              link.directionFromRootSourceToTarget = false;
            }
          }

          final blockedSw = switchesById[link.blockedAtNodeId]!;
          issues.add(
            ValidationIssue(
              id: 'stp-blocking-${link.id}',
              severity: IssueSeverity.info,
              category: IssueCategory.stp,
              title: 'STP Blocking Redundant Link',
              message:
                  'STP placed ${blockedSw.userLabel} Port ${link.blockedAtPortNumber} into Blocking (BLK) state to prevent a loop between ${swA.userLabel} and ${swB.userLabel}.',
              nodeId: blockedSw.id,
              portNumber: link.blockedAtPortNumber,
              linkId: link.id,
            ),
          );
        }
      }

      // 1.4 Check maximum hop depth (> 6 hops warning).
      for (final sw in componentSwitches) {
        if (sw.hopDepthFromRoot > 6) {
          issues.add(
            ValidationIssue(
              id: 'stp-hop-depth-${sw.id}',
              severity: IssueSeverity.warning,
              category: IssueCategory.stp,
              title: 'Excessive STP Hop Depth',
              message:
                  '${sw.userLabel} is ${sw.hopDepthFromRoot} hops from Root Bridge (${root.userLabel}), exceeding the 6-hop threshold for fast RSTP convergence and risking TCN multicast flushes.',
              recommendation:
                  'Reduce ring diameter or position the Root Bridge centrally.',
              nodeId: sw.id,
            ),
          );
        }
      }
    }

    // Propagate hopDepthFromRoot across non-loop unmanaged switch extensions
    // starting from all STP-active switches.
    final extVisited = <String>{
      for (final sw in switchesById.values)
        if (sw.isStpActive) sw.id,
    };
    final extQueue = extVisited.toList()
      ..sort(
        (a, b) => switchesById[a]!
            .hopDepthFromRoot
            .compareTo(switchesById[b]!.hopDepthFromRoot),
      );
    while (extQueue.isNotEmpty) {
      final currId = extQueue.removeAt(0);
      final currSw = switchesById[currId]!;
      for (final link in interSwitchLinks) {
        if (unprotectedLoopLinkIds.contains(link.id)) continue;
        if (!link.connectsNode(currId)) continue;
        final nextId = link.otherNodeId(currId);
        final nextSw = switchesById[nextId]!;
        if (nextSw.isStpActive) continue;
        if (extVisited.add(nextId)) {
          nextSw.hopDepthFromRoot = currSw.hopDepthFromRoot + 1;
          extQueue.add(nextId);
        }
      }
    }

    // Any remaining inter-switch links touching an unmanaged switch without a cycle
    // are valid tree extensions and forward traffic.
    for (final link in interSwitchLinks) {
      if (unprotectedLoopLinkIds.contains(link.id)) continue;
      final swA = switchesById[link.sourceNodeId]!;
      final swB = switchesById[link.targetNodeId]!;
      if (!swA.isStpActive || !swB.isStpActive) {
        link.stpState = LinkStpState.forwarding;
        if (swA.isStpActive != swB.isStpActive) {
          link.directionFromRootSourceToTarget = swA.isStpActive;
        } else {
          link.directionFromRootSourceToTarget =
              swA.hopDepthFromRoot <= swB.hopDepthFromRoot;
        }
      }
    }
  }

  bool _hasAlternatePath({
    required String startId,
    required String targetId,
    required String excludedLinkId,
    required List<NetworkLinkEdge> links,
  }) {
    final visited = <String>{startId};
    final queue = <String>[startId];
    while (queue.isNotEmpty) {
      final curr = queue.removeAt(0);
      for (final l in links) {
        if (l.id == excludedLinkId || !l.connectsNode(curr)) continue;
        final next = l.otherNodeId(curr);
        if (next == targetId) return true;
        if (visited.add(next)) {
          queue.add(next);
        }
      }
    }
    return false;
  }
}
