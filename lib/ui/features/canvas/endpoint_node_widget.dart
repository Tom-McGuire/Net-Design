import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/endpoint_node_instance.dart';
import '../../../domain/models/endpoint_template.dart';
import '../../../domain/models/enums.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rename_device_dialog.dart';
import '../sandbox_view_model.dart';

const double kEndpointCardWidth = 228.0;
const double kEndpointCardMinHeight = 104.0;

/// Interactive Endpoint card rendered on the topology design canvas.
class EndpointNodeWidget extends StatefulWidget {
  const EndpointNodeWidget({
    super.key,
    required this.endpointNode,
    this.canvasScale = 1.0,
  });

  final EndpointNodeInstance endpointNode;
  final double canvasScale;

  @override
  State<EndpointNodeWidget> createState() => _EndpointNodeWidgetState();
}

class _EndpointNodeWidgetState extends State<EndpointNodeWidget> {
  Offset? _dragStartNodePos;
  Offset? _dragStartGlobalPos;

  @override
  Widget build(BuildContext context) {
    final endpointNode = widget.endpointNode;
    final vm = context.watch<SandboxViewModel>();
    final isSelected = vm.selectedEndpointId == endpointNode.id;
    final highlightedVlan = vm.highlightedVlanId;
    final isTrunkFilter = vm.isTrunkFilterActive;
    final isStreamTrace = vm.isStreamTraceActive;
    final effectivePorts = endpointNode.effectivePorts;

    final freeAnyPort = effectivePorts
        .where((p) => !vm.isPortConnected(endpointNode.id, p.portNumber))
        .firstOrNull
        ?.portNumber;
    final compatibleFreePort = vm.pendingWireSource != null
        ? vm.firstAvailablePortForNode(endpointNode.id)
        : null;
    final isFullyConnected = freeAnyPort == null;
    final isPendingSource = vm.pendingWireSource?.nodeId == endpointNode.id;

    final matchesHighlightedVlan = !isTrunkFilter &&
        (highlightedVlan == null ||
            endpointNode.activeTrafficFlows
                .any((f) => f.defaultVlanId == highlightedVlan));

    final isTraceSource =
        vm.activeStreamTraceTarget?.sourceEndpointId == endpointNode.id;
    final hasDeliveredTrace = vm.project.links.any(
      (l) =>
          (l.sourceNodeId == endpointNode.id ||
              l.targetNodeId == endpointNode.id) &&
          l.streamTraceState == LinkStreamTraceState.delivered,
    );
    final hasFloodedTrace = vm.project.links.any(
      (l) =>
          (l.sourceNodeId == endpointNode.id ||
              l.targetNodeId == endpointNode.id) &&
          l.streamTraceState == LinkStreamTraceState.flooded,
    );
    final matchesStreamTrace =
        !isStreamTrace || isTraceSource || hasDeliveredTrace || hasFloodedTrace;
    final matchesFilter =
        isStreamTrace ? matchesStreamTrace : matchesHighlightedVlan;

    final borderColor = isSelected
        ? AppTheme.accent
        : (isPendingSource
            ? AppTheme.warning
            : (isStreamTrace && (isTraceSource || hasDeliveredTrace)
                ? AppTheme.success
                : (isStreamTrace && hasFloodedTrace
                    ? AppTheme.warning
                    : (highlightedVlan != null && matchesHighlightedVlan
                        ? AppTheme.success
                        : AppTheme.border))));

    final totalPoe = endpointNode.totalPoeDrawWatts;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: matchesFilter ? 1.0 : 0.35,
      child: GestureDetector(
        dragStartBehavior: DragStartBehavior.down,
        supportedDevices: const {
          PointerDeviceKind.mouse,
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
        onTap: () {
          if (vm.pendingWireSource != null && compatibleFreePort != null) {
            vm.completeWiringToPort(endpointNode.id, compatibleFreePort);
          } else if (vm.pendingWireSource != null && freeAnyPort != null) {
            // Triggers descriptive media-mismatch feedback banner cleanly.
            vm.completeWiringToPort(endpointNode.id, freeAnyPort);
          } else {
            vm.selectEndpoint(endpointNode.id);
          }
        },
        onPanStart: (details) {
          _dragStartNodePos = Offset(endpointNode.dx, endpointNode.dy);
          _dragStartGlobalPos = details.globalPosition;
        },
        onPanUpdate: (details) {
          final startNode = _dragStartNodePos;
          final startGlobal = _dragStartGlobalPos;
          if (startNode == null || startGlobal == null) return;
          final scale = widget.canvasScale <= 0 ? 1.0 : widget.canvasScale;
          final delta = (details.globalPosition - startGlobal) / scale;
          vm.moveNode(
            endpointNode.id,
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
          width: kEndpointCardWidth,
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
                    .withValues(alpha: 0.2),
                blurRadius: isSelected ? 10 : 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
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
                      endpointNode.category.icon,
                      size: 15,
                      color: AppTheme.success,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        endpointNode.userLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => _renameEndpoint(context, vm),
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
                        if (vm.pendingWireSource != null && freeAnyPort != null) {
                          vm.completeWiringToPort(
                            endpointNode.id,
                            compatibleFreePort ?? freeAnyPort,
                          );
                        } else if (freeAnyPort != null) {
                          vm.startWiringFromPort(endpointNode.id, freeAnyPort);
                        }
                      },
                      child: Tooltip(
                        message: isFullyConnected
                            ? 'All NIC ports connected'
                            : (vm.pendingWireSource != null
                                ? 'Connect cable to free NIC'
                                : 'Wire cable from NIC $freeAnyPort'),
                        child: Icon(
                          Icons.cable,
                          size: 14,
                          color: isFullyConnected
                              ? AppTheme.textMuted
                              : (vm.pendingWireSource != null
                                  ? (compatibleFreePort != null
                                      ? AppTheme.success
                                      : AppTheme.error)
                                  : AppTheme.accent),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final port in effectivePorts)
                            _EndpointNicBadge(
                              port: port,
                              multiPort: effectivePorts.length > 1,
                              isConnected: vm.isPortConnected(
                                endpointNode.id,
                                port.portNumber,
                              ),
                              isDimmedForWiring: vm.pendingWireSource != null &&
                                  !vm.isPortConnected(
                                    endpointNode.id,
                                    port.portNumber,
                                  ) &&
                                  !vm.isPortMediaCompatibleWithPendingWire(
                                    endpointNode.id,
                                    port.portNumber,
                                  ),
                            ),
                          if (totalPoe > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.warning.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${totalPoe.toStringAsFixed(1)}W PoE',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.warning,
                                ),
                              ),
                            ),
                          if (endpointNode.ipAddress != null &&
                              endpointNode.ipAddress!.isNotEmpty)
                            Text(
                              endpointNode.ipAddress!,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 9.5,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (endpointNode.activeTrafficFlows.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          for (final flow in endpointNode.activeTrafficFlows)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceHigh,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: Text(
                                flow.displayPill,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 9.5,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _renameEndpoint(
    BuildContext context,
    SandboxViewModel vm,
  ) async {
    final newName = await RenameDeviceDialog.show(
      context,
      initialName: widget.endpointNode.userLabel,
      macAddress: widget.endpointNode.macAddress,
      subtitle: widget.endpointNode.category.label,
    );
    if (newName != null) {
      vm.updateEndpoint(widget.endpointNode.copyWith(userLabel: newName));
    }
  }
}

class _EndpointNicBadge extends StatelessWidget {
  const _EndpointNicBadge({
    required this.port,
    required this.multiPort,
    required this.isConnected,
    required this.isDimmedForWiring,
  });

  final EndpointPortConfig port;
  final bool multiPort;
  final bool isConnected;
  final bool isDimmedForWiring;

  @override
  Widget build(BuildContext context) {
    final isSfp = port.mediaType == PortMediaType.sfpFibre;
    final label = multiPort ? port.shortBadge : port.mediaSpeedLabel;

    return Opacity(
      opacity: isDimmedForWiring ? 0.25 : 1.0,
      child: Tooltip(
        message: '${port.displayName} (${port.mediaSpeedLabel})',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: (isSfp ? AppTheme.accent : AppTheme.accent)
                .withValues(alpha: isConnected ? 0.20 : 0.11),
            borderRadius: BorderRadius.circular(isSfp ? 3 : 4),
            border: Border.all(
              color: isConnected
                  ? AppTheme.accent.withValues(alpha: 0.75)
                  : AppTheme.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: isConnected ? AppTheme.success : AppTheme.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
