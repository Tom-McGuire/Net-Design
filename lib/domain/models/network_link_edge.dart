import 'enums.dart';

/// Physical Ethernet cable connecting two nodes (Switch<->Switch or Switch<->Endpoint).
class NetworkLinkEdge {
  NetworkLinkEdge({
    required this.id,
    required this.sourceNodeId,
    required this.sourcePortNumber,
    required this.targetNodeId,
    required this.targetPortNumber,
    this.negotiatedSpeed = PortSpeed.speed1G,
    this.stpState = LinkStpState.forwarding,
    this.blockedAtNodeId,
    this.blockedAtPortNumber,
    this.directionFromRootSourceToTarget = true,
    Set<int>? activeVlans,
    Set<int>? prunedVlans,
    this.hasVlanMismatch = false,
    this.hasSpeedStepDown = false,
    this.isSfpStepDown = false,
    this.hasMediaMismatch = false,
    this.isValidTrunk = false,
    this.estimatedLoadMbps = 0.0,
    this.streamTraceState = LinkStreamTraceState.none,
    this.tracedStreamCount = 0,
    this.tracedStreamMbps = 0.0,
    this.streamDirectionSourceToTarget = true,
  })  : activeVlans = activeVlans ?? {},
        prunedVlans = prunedVlans ?? {};

  final String id;
  final String sourceNodeId;
  final int sourcePortNumber;
  final String targetNodeId;
  final int targetPortNumber;

  // --- Computed Simulation Outputs ---
  PortSpeed negotiatedSpeed;
  LinkStpState stpState;
  String? blockedAtNodeId;
  int? blockedAtPortNumber;

  /// True when STP forwarding path flows source -> target away from Root Bridge.
  bool directionFromRootSourceToTarget;
  Set<int> activeVlans;
  Set<int> prunedVlans;
  bool hasVlanMismatch;
  bool hasSpeedStepDown;
  bool isSfpStepDown;
  bool hasMediaMismatch;
  bool isValidTrunk;
  double estimatedLoadMbps;

  // --- Computed Stream Trace Outputs ---
  LinkStreamTraceState streamTraceState;
  int tracedStreamCount;
  double tracedStreamMbps;
  bool streamDirectionSourceToTarget;

  double get utilizationPercent {
    if (negotiatedSpeed.mbps <= 0) return 0.0;
    return (estimatedLoadMbps / negotiatedSpeed.mbps) * 100.0;
  }

  bool connectsNode(String nodeId) =>
      sourceNodeId == nodeId || targetNodeId == nodeId;

  bool connectsEndpointPort(String nodeId, int portNumber) =>
      (sourceNodeId == nodeId && sourcePortNumber == portNumber) ||
      (targetNodeId == nodeId && targetPortNumber == portNumber);

  String otherNodeId(String nodeId) =>
      sourceNodeId == nodeId ? targetNodeId : sourceNodeId;

  int otherPortNumber(String nodeId) =>
      sourceNodeId == nodeId ? targetPortNumber : sourcePortNumber;

  int portForNode(String nodeId) =>
      sourceNodeId == nodeId ? sourcePortNumber : targetPortNumber;

  void resetStreamTraceState() {
    streamTraceState = LinkStreamTraceState.none;
    tracedStreamCount = 0;
    tracedStreamMbps = 0.0;
    streamDirectionSourceToTarget = true;
  }

  void resetSimulationState() {
    stpState = LinkStpState.notApplicable;
    blockedAtNodeId = null;
    blockedAtPortNumber = null;
    directionFromRootSourceToTarget = true;
    activeVlans.clear();
    prunedVlans.clear();
    hasVlanMismatch = false;
    hasSpeedStepDown = false;
    isSfpStepDown = false;
    hasMediaMismatch = false;
    isValidTrunk = false;
    estimatedLoadMbps = 0.0;
    resetStreamTraceState();
  }

  NetworkLinkEdge copyWith({
    String? id,
    String? sourceNodeId,
    int? sourcePortNumber,
    String? targetNodeId,
    int? targetPortNumber,
  }) {
    return NetworkLinkEdge(
      id: id ?? this.id,
      sourceNodeId: sourceNodeId ?? this.sourceNodeId,
      sourcePortNumber: sourcePortNumber ?? this.sourcePortNumber,
      targetNodeId: targetNodeId ?? this.targetNodeId,
      targetPortNumber: targetPortNumber ?? this.targetPortNumber,
      negotiatedSpeed: negotiatedSpeed,
      stpState: stpState,
      blockedAtNodeId: blockedAtNodeId,
      blockedAtPortNumber: blockedAtPortNumber,
      directionFromRootSourceToTarget: directionFromRootSourceToTarget,
      activeVlans: Set<int>.from(activeVlans),
      prunedVlans: Set<int>.from(prunedVlans),
      hasVlanMismatch: hasVlanMismatch,
      hasSpeedStepDown: hasSpeedStepDown,
      isSfpStepDown: isSfpStepDown,
      hasMediaMismatch: hasMediaMismatch,
      isValidTrunk: isValidTrunk,
      estimatedLoadMbps: estimatedLoadMbps,
      streamTraceState: streamTraceState,
      tracedStreamCount: tracedStreamCount,
      tracedStreamMbps: tracedStreamMbps,
      streamDirectionSourceToTarget: streamDirectionSourceToTarget,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceNodeId': sourceNodeId,
      'sourcePortNumber': sourcePortNumber,
      'targetNodeId': targetNodeId,
      'targetPortNumber': targetPortNumber,
    };
  }

  factory NetworkLinkEdge.fromJson(Map<String, dynamic> json) {
    return NetworkLinkEdge(
      id: json['id'] is String ? json['id'] as String : 'link-1',
      sourceNodeId:
          json['sourceNodeId'] is String ? json['sourceNodeId'] as String : '',
      sourcePortNumber: (json['sourcePortNumber'] is num)
          ? (json['sourcePortNumber'] as num).toInt().clamp(1, 512)
          : 1,
      targetNodeId:
          json['targetNodeId'] is String ? json['targetNodeId'] as String : '',
      targetPortNumber: (json['targetPortNumber'] is num)
          ? (json['targetPortNumber'] as num).toInt().clamp(1, 512)
          : 1,
    );
  }
}
