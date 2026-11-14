import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/endpoint_node_instance.dart';
import '../../theme/app_theme.dart';
import '../../widgets/rename_device_dialog.dart';
import '../sandbox_view_model.dart';

const double kEndpointCardWidth = 228.0;
const double kEndpointCardMinHeight = 104.0;

/// Interactive Endpoint card rendered on the topology design canvas.
class EndpointNodeWidget extends StatelessWidget {
  const EndpointNodeWidget({
    super.key,
    required this.endpointNode,
  });

  final EndpointNodeInstance endpointNode;

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SandboxViewModel>();
    final isSelected = vm.selectedEndpointId == endpointNode.id;
    final highlightedVlan = vm.highlightedVlanId;
    final isConnected = vm.isPortConnected(endpointNode.id, 1);
    final isPendingSource = vm.pendingWireSource?.nodeId == endpointNode.id;

    final matchesHighlightedVlan = highlightedVlan == null ||
        endpointNode.activeTrafficFlows
            .any((f) => f.defaultVlanId == highlightedVlan);

    final borderColor = isSelected
        ? AppTheme.accent
        : (isPendingSource
            ? AppTheme.warning
            : (highlightedVlan != null && matchesHighlightedVlan
                ? AppTheme.success
                : AppTheme.border));

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 160),
      opacity: matchesHighlightedVlan ? 1.0 : 0.35,
      child: GestureDetector(
        onTap: () {
          if (vm.pendingWireSource != null && !isConnected) {
            vm.completeWiringToPort(endpointNode.id, 1);
          } else {
            vm.selectEndpoint(endpointNode.id);
          }
        },
        onPanUpdate: (details) {
          vm.moveNode(
            endpointNode.id,
            endpointNode.dx + details.delta.dx,
            endpointNode.dy + details.delta.dy,
          );
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
                      child: InkWell(
                        onDoubleTap: () => _renameEndpoint(context, vm),
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
                    ),
                    InkWell(
                      onTap: () {
                        if (vm.pendingWireSource != null) {
                          vm.completeWiringToPort(endpointNode.id, 1);
                        } else {
                          vm.startWiringFromPort(endpointNode.id, 1);
                        }
                      },
                      child: Tooltip(
                        message: isConnected
                            ? 'NIC already connected'
                            : (vm.pendingWireSource != null
                                ? 'Connect cable to this endpoint'
                                : 'Wire cable from this endpoint'),
                        child: Icon(
                          Icons.cable,
                          size: 14,
                          color: isConnected
                              ? AppTheme.textMuted
                              : (vm.pendingWireSource != null
                                  ? AppTheme.success
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
                        spacing: 5,
                        runSpacing: 4,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'NIC ${endpointNode.nicSpeed.label}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.accent,
                              ),
                            ),
                          ),
                          if (endpointNode.poeDrawWatts > 0)
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
                                '${endpointNode.poeDrawWatts.toStringAsFixed(1)}W PoE',
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
      initialName: endpointNode.userLabel,
      macAddress: endpointNode.macAddress,
      subtitle: endpointNode.category.label,
    );
    if (newName != null) {
      vm.updateEndpoint(endpointNode.copyWith(userLabel: newName));
    }
  }
}
