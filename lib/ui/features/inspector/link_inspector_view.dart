import 'package:material_ui/material_ui.dart';

import '../../../domain/models/enums.dart';
import '../../../domain/models/network_link_edge.dart';
import '../../theme/app_theme.dart';
import '../sandbox_view_model.dart';

/// Shared key-value summary card used by Link and Topology inspectors.
class InspectorKvCard extends StatelessWidget {
  const InspectorKvCard({
    super.key,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Inspector view for a selected [NetworkLinkEdge].
class LinkInspectorView extends StatelessWidget {
  const LinkInspectorView({
    super.key,
    required this.vm,
    required this.link,
  });

  final SandboxViewModel vm;
  final NetworkLinkEdge link;

  String _resolveNodeLabel(String nodeId) {
    return vm.project.switches
            .where((s) => s.id == nodeId)
            .firstOrNull
            ?.userLabel ??
        vm.project.endpoints
            .where((e) => e.id == nodeId)
            .firstOrNull
            ?.userLabel ??
        nodeId;
  }

  @override
  Widget build(BuildContext context) {
    final nameA = _resolveNodeLabel(link.sourceNodeId);
    final nameB = _resolveNodeLabel(link.targetNodeId);

    final isInterSwitch =
        vm.project.switches.any((s) => s.id == link.sourceNodeId) &&
            vm.project.switches.any((s) => s.id == link.targetNodeId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InspectorKvCard(
          label: 'Endpoints',
          value:
              '$nameA (P${link.sourcePortNumber}) ↔ $nameB (P${link.targetPortNumber})',
        ),
        const SizedBox(height: 8),
        if (link.hasMediaMismatch) ...[
          InspectorKvCard(
            label: 'Physical Media Compatibility',
            value:
                'MISMATCH: RJ45 copper connected directly to SFP/Fibre port — link non-functional.',
            valueColor: AppTheme.error,
          ),
          const SizedBox(height: 8),
        ] else if (link.isSfpStepDown) ...[
          InspectorKvCard(
            label: 'Physical Media Compatibility',
            value:
                '10G SFP+ ↔ 1G SFP Step-Down — check 1G SFP compatibility in 10G SFP+ cage.',
            valueColor: AppTheme.warning,
          ),
          const SizedBox(height: 8),
        ],
        InspectorKvCard(
          label: 'Negotiated Speed',
          value:
              '${link.negotiatedSpeed.label}${link.hasSpeedStepDown ? " (Stepped Down)" : ""}',
        ),
        const SizedBox(height: 8),
        InspectorKvCard(
          label: 'STP State',
          value: link.stpState == LinkStpState.blocking
              ? 'Blocking at Port ${link.blockedAtPortNumber}'
              : link.stpState.label,
        ),
        const SizedBox(height: 8),
        InspectorKvCard(
          label: 'Estimated Load',
          value:
              '${link.estimatedLoadMbps.toStringAsFixed(2)} Mbps (${link.utilizationPercent.toStringAsFixed(1)}%)',
        ),
        if (vm.isStreamTraceActive &&
            link.streamTraceState != LinkStreamTraceState.none) ...[
          const SizedBox(height: 8),
          InspectorKvCard(
            label: 'Traced Stream Flow',
            value: switch (link.streamTraceState) {
              LinkStreamTraceState.delivered =>
                'DELIVERED: ${link.tracedStreamCount} stream(s) • ${link.tracedStreamMbps.toStringAsFixed(2)} Mbps',
              LinkStreamTraceState.flooded =>
                'FLOODED (No IGMP Snooping): ${link.tracedStreamCount} stream(s) • ${link.tracedStreamMbps.toStringAsFixed(2)} Mbps',
              LinkStreamTraceState.igmpPruned =>
                'IGMP PRUNED (Zero Active Subscribers Downstream)',
              LinkStreamTraceState.none => '',
            },
            valueColor: switch (link.streamTraceState) {
              LinkStreamTraceState.delivered => AppTheme.success,
              LinkStreamTraceState.flooded => AppTheme.warning,
              LinkStreamTraceState.igmpPruned => AppTheme.textMuted,
              LinkStreamTraceState.none => AppTheme.textPrimary,
            },
          ),
        ],
        const SizedBox(height: 8),
        InspectorKvCard(
          label: 'Carried VLANs',
          value: link.activeVlans.isEmpty
              ? 'None (Blocked/Mismatched)'
              : (link.activeVlans.toList()..sort())
                  .map((v) => 'VLAN $v')
                  .join(', '),
        ),
        if (link.prunedVlans.isNotEmpty) ...[
          const SizedBox(height: 8),
          InspectorKvCard(
            label: 'Asymmetric / Pruned VLANs',
            value: (link.prunedVlans.toList()..sort())
                .map((v) => 'VLAN $v')
                .join(', '),
            valueColor: AppTheme.warning,
          ),
        ],
        const SizedBox(height: 12),
        if (isInterSwitch && (link.hasVlanMismatch || link.prunedVlans.isNotEmpty))
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => vm.autoFixLinkVlanSymmetry(link.id),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.success,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: const Text('Fix Trunk VLAN Symmetry'),
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => vm.removeLink(link.id),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.error,
              side: BorderSide(color: AppTheme.error.withValues(alpha: 0.6)),
            ),
            icon: const Icon(Icons.link_off, size: 16),
            label: const Text('Disconnect Cable'),
          ),
        ),
      ],
    );
  }
}

/// Overview panel rendered when no switch, endpoint, or link is selected.
class TopologySummaryView extends StatelessWidget {
  const TopologySummaryView({super.key, required this.vm});

  final SandboxViewModel vm;

  @override
  Widget build(BuildContext context) {
    final roots = vm.project.switches.where((s) => s.isRootBridge).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InspectorKvCard(label: 'Project', value: vm.project.name),
        const SizedBox(height: 8),
        InspectorKvCard(
          label: 'Root Bridge(s)',
          value: roots.isEmpty
              ? 'None'
              : roots
                  .map((r) => '${r.userLabel} (PRI ${r.stpPriority})')
                  .join('\n'),
        ),
        const SizedBox(height: 8),
        InspectorKvCard(
          label: 'STP Blocking Links',
          value: '${vm.validation.blockingLinkCount}',
        ),
        const SizedBox(height: 8),
        const InspectorKvCard(
          label: 'Quick Workflow',
          value:
              '1. Click any Switch, Port, Endpoint, or Cable on the canvas to edit settings.\n'
              '2. Click a free port (or Cable icon) to wire links.\n'
              '3. Use "Randomise MACs" to test STP tie-breaking.\n'
              '4. Use "Highlight VLAN" or "Trace Stream" to inspect multicast pruning.',
        ),
      ],
    );
  }
}
