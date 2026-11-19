import '../models/network_link_edge.dart';

typedef BfsTreeResult = ({
  Set<String> visited,
  Map<String, NetworkLinkEdge> parentLink,
  Map<String, String> parentNode,
});

/// Returns true if [targetSwitchId] is reachable from [startSwitchId] across
/// [forwardingLinks] that carry [vlanId].
bool isVlanReachable({
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
      if (!link.connectsNode(curr) || !link.activeVlans.contains(vlanId)) {
        continue;
      }
      final next = link.otherNodeId(curr);
      if (next == targetSwitchId) return true;
      if (visited.add(next)) {
        queue.add(next);
      }
    }
  }
  return false;
}

/// Builds a shortest-hop BFS tree rooted at [rootSwitchId] over [links],
/// stopping early if [stopAtSwitchId] is reached.
BfsTreeResult buildBfsTree({
  required String rootSwitchId,
  required List<NetworkLinkEdge> links,
  String? stopAtSwitchId,
}) {
  final visited = <String>{rootSwitchId};
  final parentLink = <String, NetworkLinkEdge>{};
  final parentNode = <String, String>{};
  final queue = <String>[rootSwitchId];

  while (queue.isNotEmpty) {
    final curr = queue.removeAt(0);
    for (final link in links) {
      if (!link.connectsNode(curr)) continue;
      final next = link.otherNodeId(curr);
      if (visited.add(next)) {
        parentLink[next] = link;
        parentNode[next] = curr;
        if (stopAtSwitchId != null && next == stopAtSwitchId) {
          return (
            visited: visited,
            parentLink: parentLink,
            parentNode: parentNode,
          );
        }
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
