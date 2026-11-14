import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/enums.dart';
import '../../../domain/models/switch_node_instance.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rename_device_dialog.dart';
import '../sandbox_view_model.dart';

const double kSwitchCardWidth = 268.0;
const double kSwitchCardMinHeight = 148.0;

/// Interactive Switch card rendered on the topology design canvas.
class SwitchNodeWidget extends StatefulWidget {
  const SwitchNodeWidget({
    super.key,
    required this.switchNode,
    this.canvasScale = 1.0,
  });

  final SwitchNodeInstance switchNode;
  final double canvasScale;

  @override
  State<SwitchNodeWidget> createState() => _SwitchNodeWidgetState();
}

class _SwitchNodeWidgetState extends State<SwitchNodeWidget> {
  Offset? _dragStartNodePos;
  Offset? _dragStartGlobalPos;

  @override
  Widget build(BuildContext context) {
    final switchNode = widget.switchNode;
    final vm = context.watch<SandboxViewModel>();
    final isSelected = vm.selectedSwitchId == switchNode.id;
    final highlightedVlan = vm.highlightedVlanId;
    final isTrunkFilter = vm.isTrunkFilterActive;
    final isStreamTrace = vm.isStreamTraceActive;
    final isFilterActive =
        isTrunkFilter || highlightedVlan != null || isStreamTrace;

    final carriesHighlightedFilter = !isFilterActive ||
        (isStreamTrace
            ? vm.project.links.any(
                (l) =>
                    (l.sourceNodeId == switchNode.id ||
                        l.targetNodeId == switchNode.id) &&
                    (l.streamTraceState == LinkStreamTraceState.delivered ||
                        l.streamTraceState == LinkStreamTraceState.flooded),
              )
            : (isTrunkFilter
                ? switchNode.ports.any(
                    (p) => vm.isPortValidTrunk(switchNode.id, p.portNumber),
                  )
                : switchNode.ports.any(
                    (p) => vm.doesPortCarryHighlightedVlanWorking(
                      switchNode,
                      p,
                      highlightedVlan!,
                    ),
                  )));

    final poeRatio = switchNode.poeBudgetWatts > 0
        ? (switchNode.totalPoeDrawWatts / switchNode.poeBudgetWatts)
        : 0.0;
    final poeBarColor = poeRatio > 1.0
        ? AppTheme.error
        : (poeRatio > 0.8 ? AppTheme.warning : AppTheme.success);

    final borderColor = isSelected
        ? AppTheme.accent
        : (switchNode.isRootBridge
            ? AppTheme.warning
            : (isFilterActive && carriesHighlightedFilter
                ? AppTheme.success
                : AppTheme.border));

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: carriesHighlightedFilter ? 1.0 : 0.35,
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        supportedDevices: const {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
        onTap: () => vm.selectSwitch(switchNode.id),
        onPanStart: (details) {
          _dragStartNodePos = Offset(switchNode.dx, switchNode.dy);
          _dragStartGlobalPos = details.globalPosition;
        },
        onPanUpdate: (details) {
          final startNode = _dragStartNodePos;
          final startGlobal = _dragStartGlobalPos;
          if (startNode == null || startGlobal == null) return;
          final scale = widget.canvasScale <= 0 ? 1.0 : widget.canvasScale;
          final delta = (details.globalPosition - startGlobal) / scale;
          vm.moveNode(
            switchNode.id,
            startNode.dx + delta.dx,
            startNode.dy + delta.dy,
          );
        },
        onPanEnd: (_) {
          _dragStartNodePos = null;
          _dragStartGlobalPos = null;
        },
        onPanCancel: () {
          _dragStartNodePos = null;
          _dragStartGlobalPos = null;
        },
        child: Container(
          width: kSwitchCardWidth,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: borderColor,
              width: isSelected ? 2.0 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: (isSelected ? AppTheme.accent : AppTheme.border)
                    .withValues(alpha: 0.25),
                blurRadius: isSelected ? 12 : 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHigh,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(7),
                  ),
                  border: Border(bottom: BorderSide(color: AppTheme.border)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.dns_outlined,
                      size: 16,
                      color: switchNode.supportsStp
                          ? AppTheme.accent
                          : AppTheme.warning,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        switchNode.userLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _renameSwitch(context, vm),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.edit,
                          size: 13,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () {
                        final freePort = vm.firstAvailablePortForNode(switchNode.id);
                        if (vm.pendingWireSource != null) {
                          if (freePort != null) {
                            vm.completeWiringToPort(switchNode.id, freePort);
                          }
                        } else if (freePort != null) {
                          vm.startWiringFromPort(switchNode.id, freePort);
                        }
                      },
                      child: Tooltip(
                        message: vm.pendingWireSource != null
                            ? 'Connect cable to next free port'
                            : 'Start wiring cable from next free port',
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.cable,
                            size: 14,
                            color: vm.pendingWireSource != null
                                ? AppTheme.success
                                : AppTheme.accent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Role badges: STP ROOT, IGMP QUERIER, Unmanaged
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if (switchNode.isRootBridge)
                          _RolePill(
                            icon: Icons.workspace_premium,
                            label: 'STP ROOT',
                            color: AppTheme.warning,
                          ),
                        if (switchNode.activeQuerierVlans.isNotEmpty)
                          _RolePill(
                            icon: Icons.cell_tower,
                            label:
                                'IGMP QUERIER (V${(switchNode.activeQuerierVlans.toList()..sort()).join(",")})',
                            color: AppTheme.success,
                          ),
                        if (!switchNode.isStpActive)
                          _RolePill(
                            icon: Icons.warning_amber,
                            label: switchNode.supportsStp
                                ? 'STP DISABLED'
                                : 'UNMANAGED',
                            color: AppTheme.error,
                          ),
                        for (final pill in switchNode.portSummaryPills)
                          _InfoTag(label: pill),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // MAC & STP Priority row (clickable MAC triggers RenameDeviceDialog)
                    Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _renameSwitch(context, vm),
                            child: Text(
                              switchNode.macAddress,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 10.5,
                                color: AppTheme.textSecondary,
                                decoration: TextDecoration.underline,
                                decorationColor: AppTheme.border,
                              ),
                            ),
                          ),
                        ),
                        if (switchNode.isStpActive)
                          Text(
                            'PRI ${switchNode.stpPriority}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: switchNode.stpPriority == 32768
                                  ? AppTheme.textMuted
                                  : AppTheme.accent,
                            ),
                          ),
                      ],
                    ),

                    // PoE Load Bar
                    if (switchNode.poeBudgetWatts > 0) ...[
                      const SizedBox(height: 7),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'PoE Load',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          Text(
                            '${switchNode.totalPoeDrawWatts.toStringAsFixed(0)}W / ${switchNode.poeBudgetWatts}W',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: poeBarColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: poeRatio.clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: AppTheme.surfaceHigh,
                          valueColor: AlwaysStoppedAnimation<Color>(poeBarColor),
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),

                    // Interactive Mini Port Strip (first 12 ports, or all up to 24 compact)
                    Wrap(
                      spacing: 3,
                      runSpacing: 3,
                      children: [
                        for (final port in switchNode.ports)
                          _MiniPortChip(
                            switchNode: switchNode,
                            portNumber: port.portNumber,
                            mediaType: port.mediaType,
                            speed: port.maxSpeed,
                            mediaSpeedLabel: port.mediaSpeedLabel,
                            isTrunk: port.portMode == SwitchPortMode.trunk,
                            isConnected:
                                vm.isPortConnected(switchNode.id, port.portNumber),
                            isSelected: isSelected &&
                                vm.selectedPortNumber == port.portNumber,
                            isPendingSource: vm.pendingWireSource?.nodeId ==
                                    switchNode.id &&
                                vm.pendingWireSource?.portNumber ==
                                    port.portNumber,
                            isDimmedForWiring: vm.pendingWireSource != null &&
                                !vm.isPortConnected(
                                    switchNode.id, port.portNumber) &&
                                !vm.isPortMediaCompatibleWithPendingWire(
                                  switchNode.id,
                                  port.portNumber,
                                ),
                            portTraceState: isStreamTrace
                                ? vm.linkForPort(switchNode.id, port.portNumber)
                                    ?.streamTraceState
                                : null,
                            carriesHighlightedVlan: isStreamTrace
                                ? ((vm
                                            .linkForPort(
                                              switchNode.id,
                                              port.portNumber,
                                            )
                                            ?.streamTraceState ==
                                        LinkStreamTraceState.delivered) ||
                                    (vm
                                            .linkForPort(
                                              switchNode.id,
                                              port.portNumber,
                                            )
                                            ?.streamTraceState ==
                                        LinkStreamTraceState.flooded))
                                : (isTrunkFilter
                                    ? vm.isPortValidTrunk(
                                        switchNode.id,
                                        port.portNumber,
                                      )
                                    : (highlightedVlan != null &&
                                        vm.doesPortCarryHighlightedVlanWorking(
                                          switchNode,
                                          port,
                                          highlightedVlan,
                                        ))),
                            isFilterActive: isFilterActive,
                            isBlockedOnLink: vm.project.links.any((l) =>
                                l.stpState == LinkStpState.blocking &&
                                l.blockedAtNodeId == switchNode.id &&
                                l.blockedAtPortNumber == port.portNumber),
                            onTap: () {
                              if (vm.pendingWireSource != null) {
                                vm.completeWiringToPort(
                                  switchNode.id,
                                  port.portNumber,
                                );
                              } else {
                                vm.selectSwitch(
                                  switchNode.id,
                                  portNumber: port.portNumber,
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameSwitch(BuildContext context, SandboxViewModel vm) async {
    final newName = await RenameDeviceDialog.show(
      context,
      initialName: widget.switchNode.userLabel,
      macAddress: widget.switchNode.macAddress,
      subtitle: 'Switch (${widget.switchNode.portSummaryPills.join(" • ")})',
    );
    if (newName != null) {
      vm.updateSwitch(widget.switchNode.copyWith(userLabel: newName));
    }
  }
}

class _RolePill extends StatelessWidget {
  const _RolePill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTag extends StatelessWidget {
  const _InfoTag({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 9.5,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _MiniPortChip extends StatelessWidget {
  const _MiniPortChip({
    required this.switchNode,
    required this.portNumber,
    required this.mediaType,
    required this.speed,
    required this.mediaSpeedLabel,
    required this.isTrunk,
    required this.isConnected,
    required this.isSelected,
    required this.isPendingSource,
    required this.isDimmedForWiring,
    this.portTraceState,
    required this.carriesHighlightedVlan,
    required this.isFilterActive,
    required this.isBlockedOnLink,
    required this.onTap,
  });

  final SwitchNodeInstance switchNode;
  final int portNumber;
  final PortMediaType mediaType;
  final PortSpeed speed;
  final String mediaSpeedLabel;
  final bool isTrunk;
  final bool isConnected;
  final bool isSelected;
  final bool isPendingSource;
  final bool isDimmedForWiring;
  final LinkStreamTraceState? portTraceState;
  final bool carriesHighlightedVlan;
  final bool isFilterActive;
  final bool isBlockedOnLink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSfp = mediaType == PortMediaType.sfpFibre;
    Color bg = isSfp ? AppTheme.accent.withValues(alpha: 0.06) : AppTheme.surfaceHigh;
    Color border =
        isSfp ? AppTheme.accent.withValues(alpha: 0.45) : AppTheme.border;
    Color text = isSfp ? AppTheme.accent : AppTheme.textMuted;

    if (isPendingSource) {
      bg = AppTheme.accent.withValues(alpha: 0.25);
      border = AppTheme.accent;
      text = AppTheme.textPrimary;
    } else if (portTraceState == LinkStreamTraceState.delivered) {
      bg = AppTheme.success.withValues(alpha: 0.24);
      border = AppTheme.success;
      text = AppTheme.success;
    } else if (portTraceState == LinkStreamTraceState.flooded) {
      bg = AppTheme.warning.withValues(alpha: 0.24);
      border = AppTheme.warning;
      text = AppTheme.warning;
    } else if (carriesHighlightedVlan && isConnected) {
      bg = AppTheme.success.withValues(alpha: 0.22);
      border = AppTheme.success;
      text = AppTheme.success;
    } else if (!isFilterActive && isBlockedOnLink) {
      bg = AppTheme.error.withValues(alpha: 0.22);
      border = AppTheme.error;
      text = AppTheme.error;
    } else if (!isFilterActive && isConnected) {
      bg = AppTheme.accent.withValues(alpha: 0.14);
      border = AppTheme.accent.withValues(alpha: 0.65);
      text = AppTheme.textPrimary;
    }

    if (isSelected) {
      border = AppTheme.warning;
    }

    return Opacity(
      opacity: isDimmedForWiring ? 0.22 : 1.0,
      child: Tooltip(
        message:
            'Port $portNumber ($mediaSpeedLabel • ${isTrunk ? "Trunk" : "Access"})',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(isSfp ? 2 : 3),
          child: Container(
            width: 21,
            height: 19,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(isSfp ? 2 : 3),
              border: Border.all(
                color: border,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            child: Text(
              '$portNumber',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
