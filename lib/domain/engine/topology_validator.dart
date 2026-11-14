import '../models/endpoint_node_instance.dart';
import '../models/enums.dart';
import '../models/switch_node_instance.dart';
import '../models/topology_project.dart';
import '../models/validation_issue.dart';
import 'igmp_domain_solver.dart';
import 'multicast_flow_tracer.dart';
import 'resource_budget_solver.dart';
import 'stp_election_solver.dart';
import 'vlan_reachability_solver.dart';

/// Deterministic validation output returned by [TopologyValidator.validate].
class ValidationResult {
  const ValidationResult({
    required this.issues,
    required this.rootBridgeIds,
    required this.blockingLinkCount,
    required this.unprotectedLoopCount,
    required this.criticalCount,
    required this.warningCount,
    required this.infoCount,
  });

  final List<ValidationIssue> issues;
  final Set<String> rootBridgeIds;
  final int blockingLinkCount;
  final int unprotectedLoopCount;
  final int criticalCount;
  final int warningCount;
  final int infoCount;

  bool get isHealthy => criticalCount == 0 && warningCount == 0;
}

/// Orchestrates all 4 deterministic simulation & validation passes synchronously.
class TopologyValidator {
  const TopologyValidator({
    this.stpSolver = const StpElectionSolver(),
    this.vlanSolver = const VlanReachabilitySolver(),
    this.igmpSolver = const IgmpDomainSolver(),
    this.streamTracer = const MulticastFlowTracer(),
    this.budgetSolver = const ResourceBudgetSolver(),
  });

  final StpElectionSolver stpSolver;
  final VlanReachabilitySolver vlanSolver;
  final IgmpDomainSolver igmpSolver;
  final MulticastFlowTracer streamTracer;
  final ResourceBudgetSolver budgetSolver;

  ValidationResult validate(TopologyProject project) {
    final switchesById = <String, SwitchNodeInstance>{
      for (final sw in project.switches) sw.id: sw,
    };
    final endpointsById = <String, EndpointNodeInstance>{
      for (final ep in project.endpoints) ep.id: ep,
    };

    // Reset computed simulation fields on all switches and links.
    for (final sw in project.switches) {
      sw.resetSimulationState();
    }

    for (final link in project.links) {
      link.resetSimulationState();
      final speedA = _portOrNicSpeed(
        nodeId: link.sourceNodeId,
        portNumber: link.sourcePortNumber,
        switchesById: switchesById,
        endpointsById: endpointsById,
      );
      final speedB = _portOrNicSpeed(
        nodeId: link.targetNodeId,
        portNumber: link.targetPortNumber,
        switchesById: switchesById,
        endpointsById: endpointsById,
      );
      final mediaA = _portOrNicMedia(
        nodeId: link.sourceNodeId,
        portNumber: link.sourcePortNumber,
        switchesById: switchesById,
        endpointsById: endpointsById,
      );
      final mediaB = _portOrNicMedia(
        nodeId: link.targetNodeId,
        portNumber: link.targetPortNumber,
        switchesById: switchesById,
        endpointsById: endpointsById,
      );
      link.hasMediaMismatch = mediaA != mediaB;
      link.negotiatedSpeed = PortSpeed.minSpeed(speedA, speedB);
      link.hasSpeedStepDown = speedA != speedB;
      link.isSfpStepDown = mediaA == PortMediaType.sfpFibre &&
          mediaB == PortMediaType.sfpFibre &&
          speedA != speedB;
    }

    final issues = <ValidationIssue>[];

    // Pass 1: STP Election, Cycle Detection & Ring Split
    stpSolver.solve(
      switchesById: switchesById,
      links: project.links,
      issues: issues,
    );

    // Pass 2: Port VLAN Symmetry & End-to-End Reachability BFS
    vlanSolver.solve(
      switchesById: switchesById,
      endpointsById: endpointsById,
      links: project.links,
      issues: issues,
    );

    // Pass 3: Per-VLAN IGMP Snooping & Active Querier Solver
    igmpSolver.solve(
      switchesById: switchesById,
      endpointsById: endpointsById,
      links: project.links,
      issues: issues,
    );

    // Pass 3b: Multicast Stream Spec, Duplicate TX & Orphan RX Checks
    streamTracer.validateStreams(
      switchesById: switchesById,
      endpointsById: endpointsById,
      links: project.links,
      issues: issues,
    );

    // Pass 4: Link Bandwidth Utilization, Media Checks, Speed Step-Down & PoE Budget Aggregation
    budgetSolver.solve(
      switchesById: switchesById,
      endpointsById: endpointsById,
      links: project.links,
      issues: issues,
    );

    issues.sort((a, b) {
      final sevCmp = a.severity.sortOrder.compareTo(b.severity.sortOrder);
      if (sevCmp != 0) return sevCmp;
      return a.category.index.compareTo(b.category.index);
    });

    final rootBridgeIds = {
      for (final sw in project.switches)
        if (sw.isRootBridge) sw.id,
    };
    final blockingLinkCount = project.links
        .where((l) => l.stpState == LinkStpState.blocking)
        .length;
    final unprotectedLoopCount = project.links
        .where((l) => l.stpState == LinkStpState.loopUnprotected)
        .length;

    return ValidationResult(
      issues: List.unmodifiable(issues),
      rootBridgeIds: rootBridgeIds,
      blockingLinkCount: blockingLinkCount,
      unprotectedLoopCount: unprotectedLoopCount,
      criticalCount:
          issues.where((i) => i.severity == IssueSeverity.critical).length,
      warningCount:
          issues.where((i) => i.severity == IssueSeverity.warning).length,
      infoCount: issues.where((i) => i.severity == IssueSeverity.info).length,
    );
  }

  PortSpeed _portOrNicSpeed({
    required String nodeId,
    required int portNumber,
    required Map<String, SwitchNodeInstance> switchesById,
    required Map<String, EndpointNodeInstance> endpointsById,
  }) {
    final sw = switchesById[nodeId];
    if (sw != null) {
      return sw.portByNumber(portNumber)?.maxSpeed ?? PortSpeed.speed1G;
    }
    final ep = endpointsById[nodeId];
    if (ep != null) {
      return ep.portByNumber(portNumber).effectiveSpeed;
    }
    return PortSpeed.speed1G;
  }

  PortMediaType _portOrNicMedia({
    required String nodeId,
    required int portNumber,
    required Map<String, SwitchNodeInstance> switchesById,
    required Map<String, EndpointNodeInstance> endpointsById,
  }) {
    final sw = switchesById[nodeId];
    if (sw != null) {
      return sw.portByNumber(portNumber)?.mediaType ?? PortMediaType.rj45;
    }
    final ep = endpointsById[nodeId];
    if (ep != null) {
      return ep.portByNumber(portNumber).mediaType;
    }
    return PortMediaType.rj45;
  }
}
