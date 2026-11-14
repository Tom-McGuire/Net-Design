import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/enums.dart';
import '../../../domain/models/network_link_edge.dart';
import '../../../domain/models/switch_node_instance.dart';
import '../../../domain/models/switch_port_config.dart';
import '../../theme/app_theme.dart';
import '../sandbox_view_model.dart';

/// Clickable switch faceplate matrix and per-port VLAN/PoE editor.
class PortVlanMatrixEditor extends StatefulWidget {
  const PortVlanMatrixEditor({
    super.key,
    required this.switchNode,
  });

  final SwitchNodeInstance switchNode;

  @override
  State<PortVlanMatrixEditor> createState() => _PortVlanMatrixEditorState();
}

class _PortVlanMatrixEditorState extends State<PortVlanMatrixEditor> {
  final TextEditingController _labelCtrl = TextEditingController();
  String? _syncedPortKey;

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  void _syncController(SwitchPortConfig port) {
    final key = '${widget.switchNode.id}:${port.portNumber}';
    if (_syncedPortKey != key) {
      _syncedPortKey = key;
      _labelCtrl.text = port.customLabel ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SandboxViewModel>();
    final sw = widget.switchNode;
    final selectedPortNum = vm.selectedPortNumber ??
        (sw.ports.isNotEmpty ? sw.ports.first.portNumber : null);
    final selectedPort =
        selectedPortNum != null ? sw.portByNumber(selectedPortNum) : null;

    if (selectedPort != null) {
      _syncController(selectedPort);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Switch Faceplate Matrix (${sw.ports.length} Ports)',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),

        // Faceplate grid
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.scaffoldBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.border),
          ),
          child: Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final port in sw.ports)
                _FaceplatePortTile(
                  port: port,
                  switchNode: sw,
                  isSelected: selectedPort?.portNumber == port.portNumber,
                  link: _findPortLink(vm.project.links, sw.id, port.portNumber),
                  onTap: () =>
                      vm.selectSwitch(sw.id, portNumber: port.portNumber),
                ),
            ],
          ),
        ),

        if (selectedPort != null) ...[
          const SizedBox(height: 10),
          _buildSelectedPortEditor(context, vm, sw, selectedPort),
        ],
      ],
    );
  }

  NetworkLinkEdge? _findPortLink(
    List<NetworkLinkEdge> links,
    String switchId,
    int portNum,
  ) {
    for (final l in links) {
      if (l.connectsEndpointPort(switchId, portNum)) return l;
    }
    return null;
  }

  Widget _buildSelectedPortEditor(
    BuildContext context,
    SandboxViewModel vm,
    SwitchNodeInstance sw,
    SwitchPortConfig port,
  ) {
    final link = _findPortLink(vm.project.links, sw.id, port.portNumber);
    final availableVlans = vm.availableVlanIds;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Port ${port.portNumber} (${port.maxSpeed.label})',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              if (link != null)
                OutlinedButton.icon(
                  onPressed: () => vm.removeLink(link.id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(color: AppTheme.error.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  icon: const Icon(Icons.link_off, size: 13),
                  label: const Text('Unplug', style: TextStyle(fontSize: 11)),
                )
              else
                FilledButton.icon(
                  onPressed: () => vm.startWiringFromPort(sw.id, port.portNumber),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                  icon: const Icon(Icons.cable, size: 13),
                  label: const Text('Wire Port', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Custom Port Label
          TextField(
            controller: _labelCtrl,
            style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Port Label (Optional)',
              hintText: 'e.g., FOH Trunk / Console Pri',
            ),
            onChanged: (val) {
              vm.updatePort(
                sw.id,
                port.copyWith(
                  customLabel: val.trim().isEmpty ? null : val,
                  clearCustomLabel: val.trim().isEmpty,
                ),
              );
            },
          ),
          const SizedBox(height: 8),

          // Port Mode (Access vs Trunk) & Native VLAN
          if (sw.supportsVlans) ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<SwitchPortMode>(
                    initialValue: port.portMode,
                    decoration: const InputDecoration(labelText: 'Port Mode'),
                    dropdownColor: AppTheme.surfaceElevated,
                    style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                    items: SwitchPortMode.values
                        .map(
                          (m) => DropdownMenuItem(
                            value: m,
                            child: Text(m.label),
                          ),
                        )
                        .toList(),
                    onChanged: (mode) {
                      if (mode == null) return;
                      final nextAllowed = mode == SwitchPortMode.trunk
                          ? {...port.allowedVlans, port.nativeVlan, ...availableVlans}
                          : {port.nativeVlan};
                      vm.updatePort(
                        sw.id,
                        port.copyWith(
                          portMode: mode,
                          allowedVlans: nextAllowed,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: availableVlans.contains(port.nativeVlan)
                        ? port.nativeVlan
                        : availableVlans.first,
                    decoration: InputDecoration(
                      labelText: port.portMode == SwitchPortMode.access
                          ? 'Access VLAN'
                          : 'Native VLAN',
                    ),
                    dropdownColor: AppTheme.surfaceElevated,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppTheme.textPrimary,
                    ),
                    items: availableVlans
                        .map(
                          (v) => DropdownMenuItem(
                            value: v,
                            child: Text('VLAN $v'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      final nextAllowed = port.portMode == SwitchPortMode.access
                          ? {v}
                          : {...port.allowedVlans, v};
                      vm.updatePort(
                        sw.id,
                        port.copyWith(
                          nativeVlan: v,
                          allowedVlans: nextAllowed,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            // Trunk Allowed VLANs matrix chips
            if (port.portMode == SwitchPortMode.trunk) ...[
              const SizedBox(height: 8),
              Text(
                'Trunk Allowed VLANs',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final v in availableVlans)
                    FilterChip(
                      visualDensity: VisualDensity.compact,
                      selected: port.allowedVlans.contains(v),
                      selectedColor: AppTheme.success.withValues(alpha: 0.25),
                      checkmarkColor: AppTheme.success,
                      label: Text(
                        'V$v',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 10.5,
                          color: port.allowedVlans.contains(v)
                              ? AppTheme.success
                              : AppTheme.textSecondary,
                        ),
                      ),
                      onSelected: (enabled) {
                        final next = Set<int>.from(port.allowedVlans);
                        if (enabled) {
                          next.add(v);
                        } else if (next.length > 1) {
                          next.remove(v);
                        }
                        vm.updatePort(sw.id, port.copyWith(allowedVlans: next));
                      },
                    ),
                ],
              ),
            ],
          ] else
            Text(
              'Unmanaged switch — 802.1Q VLAN tagging is not configurable.',
              style: TextStyle(fontSize: 11, color: AppTheme.warning),
            ),

          // PoE Capability toggle
          if (sw.poeBudgetWatts > 0) ...[
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                port.poeCapable
                    ? 'PoE Power Supply Enabled'
                    : 'Port Not PoE Capable (Uplink)',
                style: TextStyle(fontSize: 11.5, color: AppTheme.textPrimary),
              ),
              value: port.poeCapable && port.poeEnabled,
              onChanged: port.poeCapable
                  ? (val) => vm.updatePort(sw.id, port.copyWith(poeEnabled: val))
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _FaceplatePortTile extends StatelessWidget {
  const _FaceplatePortTile({
    required this.port,
    required this.switchNode,
    required this.isSelected,
    required this.link,
    required this.onTap,
  });

  final SwitchPortConfig port;
  final SwitchNodeInstance switchNode;
  final bool isSelected;
  final NetworkLinkEdge? link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isBlocked = link != null &&
        link!.stpState == LinkStpState.blocking &&
        link!.blockedAtNodeId == switchNode.id &&
        link!.blockedAtPortNumber == port.portNumber;
    final isConnected = link != null;

    Color borderColor = AppTheme.border;
    Color bgColor = AppTheme.surface;
    if (isBlocked) {
      borderColor = AppTheme.error;
      bgColor = AppTheme.error.withValues(alpha: 0.14);
    } else if (isConnected) {
      borderColor = AppTheme.success.withValues(alpha: 0.7);
      bgColor = AppTheme.success.withValues(alpha: 0.12);
    }
    if (isSelected) {
      borderColor = AppTheme.accent;
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor, width: isSelected ? 1.8 : 1.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'P${port.portNumber}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (port.poeCapable && port.poeEnabled)
                  Icon(Icons.bolt, size: 10, color: AppTheme.warning),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              port.maxSpeed.label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 8.5,
                color: AppTheme.textSecondary,
              ),
            ),
            Text(
              isBlocked
                  ? 'BLK'
                  : (port.portMode == SwitchPortMode.trunk
                      ? 'TRK'
                      : 'V${port.nativeVlan}'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 8.5,
                fontWeight: FontWeight.bold,
                color: isBlocked
                    ? AppTheme.error
                    : (port.portMode == SwitchPortMode.trunk
                        ? AppTheme.accent
                        : AppTheme.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
