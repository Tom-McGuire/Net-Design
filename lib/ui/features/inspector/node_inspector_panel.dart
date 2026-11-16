import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../domain/engine/multicast_flow_tracer.dart';
import '../../../domain/engine/multicast_stream_resolver.dart';
import '../../../domain/models/endpoint_node_instance.dart';
import '../../../domain/models/endpoint_template.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/network_link_edge.dart';
import '../../../domain/models/switch_node_instance.dart';
import '../../theme/app_theme.dart';
import '../sandbox_view_model.dart';
import 'port_vlan_matrix_editor.dart';

/// Right-side inspector drawer for Switch, Endpoint, and Link configuration.
class NodeInspectorPanel extends StatefulWidget {
  const NodeInspectorPanel({super.key});

  @override
  State<NodeInspectorPanel> createState() => _NodeInspectorPanelState();
}

class _NodeInspectorPanelState extends State<NodeInspectorPanel> {
  final TextEditingController _labelCtrl = TextEditingController();
  final TextEditingController _macCtrl = TextEditingController();
  final TextEditingController _ipCtrl = TextEditingController();
  final FocusNode _macFocusNode = FocusNode();
  String? _macErrorText;
  String? _syncedEntityKey;

  @override
  void initState() {
    super.initState();
    _macFocusNode.addListener(_onMacFocusChanged);
  }

  void _onMacFocusChanged() {
    if (_macFocusNode.hasFocus) return;
    final vm = context.read<SandboxViewModel>();
    final sw = vm.selectedSwitch;
    if (sw == null) return;
    final normalized = SwitchNodeInstance.normalizeMac(_macCtrl.text);
    if (normalized != null) {
      if (_macCtrl.text != normalized) {
        _macCtrl.text = normalized;
      }
      if (sw.macAddress != normalized) {
        vm.updateSwitch(sw.copyWith(macAddress: normalized));
      }
      if (_macErrorText != null) {
        setState(() => _macErrorText = null);
      }
    } else {
      _macCtrl.text = sw.macAddress;
      if (_macErrorText != null) {
        setState(() => _macErrorText = null);
      }
    }
  }

  @override
  void dispose() {
    _macFocusNode.removeListener(_onMacFocusChanged);
    _macFocusNode.dispose();
    _labelCtrl.dispose();
    _macCtrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  void _syncForSwitch(SwitchNodeInstance sw) {
    final key = 'sw:${sw.id}';
    if (_syncedEntityKey != key) {
      _syncedEntityKey = key;
      _labelCtrl.text = sw.userLabel;
      _macCtrl.text = sw.macAddress;
      _macErrorText = null;
      _ipCtrl.text = sw.managementIp ?? '';
    } else if (!_macFocusNode.hasFocus && _macCtrl.text != sw.macAddress) {
      _macCtrl.text = sw.macAddress;
      _macErrorText = null;
    }
  }

  void _syncForEndpoint(EndpointNodeInstance ep) {
    final key = 'ep:${ep.id}';
    if (_syncedEntityKey != key) {
      _syncedEntityKey = key;
      _labelCtrl.text = ep.userLabel;
      _ipCtrl.text = ep.ipAddress ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SandboxViewModel>();
    final sw = vm.selectedSwitch;
    final ep = vm.selectedEndpoint;
    final link = vm.selectedLink;

    return Container(
      width: 356,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(left: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHigh,
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              children: [
                Icon(Icons.tune, size: 15, color: AppTheme.accent),
                const SizedBox(width: 8),
                Text(
                  sw != null
                      ? 'SWITCH INSPECTOR'
                      : (ep != null
                          ? 'ENDPOINT INSPECTOR'
                          : (link != null
                              ? 'LINK INSPECTOR'
                              : 'TOPOLOGY SUMMARY')),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.7,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: sw != null
                  ? _buildSwitchInspector(context, vm, sw)
                  : (ep != null
                      ? _buildEndpointInspector(context, vm, ep)
                      : (link != null
                          ? _buildLinkInspector(context, vm, link)
                          : _buildTopologySummary(vm))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSwitchInspector(
    BuildContext context,
    SandboxViewModel vm,
    SwitchNodeInstance sw,
  ) {
    _syncForSwitch(sw);
    final priorities = [for (var p = 0; p <= 61440; p += 4096) p];
    final sortedVlanIds = sw.vlanConfigs.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Identity & Delete
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _labelCtrl,
                style: TextStyle(fontSize: 12.5, color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Switch Label'),
                onChanged: (val) {
                  if (val.trim().isNotEmpty) {
                    vm.updateSwitch(sw.copyWith(userLabel: val.trim()));
                  }
                },
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Remove Switch',
              onPressed: () => vm.removeNode(sw.id),
              icon: Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // MAC & Management IP
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _macCtrl,
                focusNode: _macFocusNode,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  labelText: 'Bridge MAC',
                  hintText: '02:10:00:00:00:10',
                  errorText: _macErrorText,
                  errorStyle: const TextStyle(fontSize: 10),
                ),
                onChanged: (val) {
                  final normalized = SwitchNodeInstance.normalizeMac(val);
                  if (normalized != null) {
                    if (_macErrorText != null) {
                      setState(() => _macErrorText = null);
                    }
                    if (sw.macAddress != normalized) {
                      vm.updateSwitch(sw.copyWith(macAddress: normalized));
                    }
                  } else {
                    if (_macErrorText == null) {
                      setState(() => _macErrorText = 'Need 12 hex digits');
                    }
                  }
                },
                onSubmitted: (val) {
                  final normalized = SwitchNodeInstance.normalizeMac(val);
                  if (normalized != null) {
                    _macCtrl.text = normalized;
                    if (sw.macAddress != normalized) {
                      vm.updateSwitch(sw.copyWith(macAddress: normalized));
                    }
                    setState(() => _macErrorText = null);
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _ipCtrl,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                ),
                decoration: const InputDecoration(
                  labelText: 'Mgmt IPv4',
                  hintText: '10.0.1.1',
                ),
                onChanged: (val) {
                  vm.updateSwitch(
                    sw.copyWith(
                      managementIp: val.trim().isEmpty ? null : val.trim(),
                      clearManagementIp: val.trim().isEmpty,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // STP Settings
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<StpMode>(
                initialValue: sw.stpMode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'STP Mode'),
                dropdownColor: AppTheme.surfaceElevated,
                style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                items: StpMode.values
                    .where((m) => sw.supportsStp || m == StpMode.disabled)
                    .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                    .toList(),
                onChanged: sw.supportsStp
                    ? (mode) {
                        if (mode != null) {
                          vm.updateSwitch(sw.copyWith(stpMode: mode));
                        }
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: sw.stpPriority,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'STP Priority'),
                dropdownColor: AppTheme.surfaceElevated,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                ),
                items: priorities.map((p) {
                  final hint = p == 4096
                      ? ' (Core)'
                      : (p == 32768 ? ' (Default)' : '');
                  return DropdownMenuItem(value: p, child: Text('$p$hint'));
                }).toList(),
                onChanged: sw.isStpActive
                    ? (prio) {
                        if (prio != null) {
                          vm.updateSwitch(sw.copyWith(stpPriority: prio));
                        }
                      }
                    : null,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 10),

        // Clickable Faceplate & Port Configurator
        PortVlanMatrixEditor(switchNode: sw),

        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 10),

        // Per-VLAN IGMP Snooping & Querier Settings
        Text(
          'Per-VLAN IGMP Snooping & Querier',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        if (!sw.supportsIgmpSnooping && !sw.supportsIgmpQuerier)
          Text(
            'This switch template does not support IGMP Snooping or Querier.',
            style: TextStyle(fontSize: 11, color: AppTheme.warning),
          )
        else
          for (final vlanId in sortedVlanIds) ...[
            _buildVlanIgmpCard(vm, sw, sw.vlanConfigs[vlanId]!),
            const SizedBox(height: 6),
          ],
      ],
    );
  }

  Widget _buildVlanIgmpCard(
    SandboxViewModel vm,
    SwitchNodeInstance sw,
    SwitchVlanSettings cfg,
  ) {
    final isElected = sw.activeQuerierVlans.contains(cfg.vlanId);
    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isElected ? AppTheme.success : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'VLAN ${cfg.vlanId}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  cfg.vlanName,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ),
              if (isElected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'ACTIVE QUERIER',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.success,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: AppTheme.border),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildIgmpToggleBox(
                  label: 'Snooping',
                  value: cfg.igmpSnoopingEnabled,
                  enabled: sw.supportsIgmpSnooping,
                  onChanged: (v) => vm.updateSwitchVlan(
                    sw.id,
                    cfg.copyWith(igmpSnoopingEnabled: v),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildIgmpToggleBox(
                  label: 'Querier',
                  value: cfg.igmpQuerierEnabled,
                  enabled: sw.supportsIgmpQuerier,
                  onChanged: (v) => vm.updateSwitchVlan(
                    sw.id,
                    cfg.copyWith(igmpQuerierEnabled: v),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'IGMP Version',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<IgmpVersion>(
                    isDense: true,
                    value: cfg.igmpQuerierVersion,
                    dropdownColor: AppTheme.surfaceElevated,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    items: IgmpVersion.values
                        .map(
                          (v) =>
                              DropdownMenuItem(value: v, child: Text(v.label)),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        vm.updateSwitchVlan(
                          sw.id,
                          cfg.copyWith(igmpQuerierVersion: v),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIgmpToggleBox({
    required String label,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    final activeColor = value ? AppTheme.accent : AppTheme.border;
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: value ? activeColor.withValues(alpha: 0.6) : AppTheme.border,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: value,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                onChanged: enabled ? (v) => onChanged(v ?? false) : null,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: enabled ? AppTheme.textPrimary : AppTheme.textMuted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEndpointInspector(
    BuildContext context,
    SandboxViewModel vm,
    EndpointNodeInstance ep,
  ) {
    _syncForEndpoint(ep);
    final effectivePorts = ep.effectivePorts;
    final swMap = {for (final s in vm.project.switches) s.id: s};
    final epMap = {for (final e in vm.project.endpoints) e.id: e};
    final atts = MulticastFlowTracer.buildEndpointAttachments(
      switchesById: swMap,
      endpointsById: epMap,
      links: vm.project.links,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _labelCtrl,
                style: TextStyle(fontSize: 12.5, color: AppTheme.textPrimary),
                decoration: const InputDecoration(labelText: 'Endpoint Label'),
                onChanged: (val) {
                  if (val.trim().isNotEmpty) {
                    vm.updateEndpoint(ep.copyWith(userLabel: val.trim()));
                  }
                },
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Remove Endpoint',
              onPressed: () => vm.removeNode(ep.id),
              icon: Icon(Icons.delete_outline, size: 18, color: AppTheme.error),
            ),
          ],
        ),
        const SizedBox(height: 8),

        TextField(
          controller: _ipCtrl,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: AppTheme.textPrimary,
          ),
          decoration: const InputDecoration(
            labelText: 'IPv4 Address',
            hintText: '10.20.0.10',
          ),
          onChanged: (val) {
            vm.updateEndpoint(
              ep.copyWith(
                ipAddress: val.trim().isEmpty ? null : val.trim(),
                clearIpAddress: val.trim().isEmpty,
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        const Divider(),
        const SizedBox(height: 8),

        // Multi-NIC Ports section
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Network Interfaces (${effectivePorts.length})',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: effectivePorts.length < 8
                  ? () => _addEndpointNicPort(vm, ep)
                  : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add NIC Port', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        for (var i = 0; i < effectivePorts.length; i++) ...[
          _buildEndpointNicCard(vm, ep, i, effectivePorts[i]),
          const SizedBox(height: 6),
        ],

        const SizedBox(height: 8),
        const Divider(),
        const SizedBox(height: 8),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Traffic Demand Profiles',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _addEndpointFlow(context, vm, ep),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Flow', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),

        for (var idx = 0; idx < ep.activeTrafficFlows.length; idx++) ...[
          Builder(
            builder: (context) {
              final flow = ep.activeTrafficFlows[idx];
              final att = atts['${ep.id}:${flow.effectivePortNumber}'];
              final effectiveVlan =
                  MulticastFlowTracer.effectiveVlanForFlow(flow, att);
              return _TrafficFlowInspectorCard(
                key: ValueKey('ep-flow-${ep.id}-${flow.id}'),
                vm: vm,
                endpoint: ep,
                flow: flow,
                effectiveVlan: effectiveVlan,
                onChanged: (updatedFlow) {
                  final next =
                      List<TrafficRequirement>.from(ep.activeTrafficFlows);
                  next[idx] = updatedFlow;
                  vm.updateEndpoint(ep.copyWith(activeTrafficFlows: next));
                },
                onDelete: () {
                  final next =
                      List<TrafficRequirement>.from(ep.activeTrafficFlows)
                        ..removeAt(idx);
                  vm.updateEndpoint(ep.copyWith(activeTrafficFlows: next));
                },
              );
            },
          ),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  void _addEndpointNicPort(SandboxViewModel vm, EndpointNodeInstance ep) {
    final current = List<EndpointPortConfig>.from(ep.effectivePorts);
    final nextNum = current.map((p) => p.portNumber).fold<int>(0, max) + 1;
    current.add(
      EndpointPortConfig(
        portNumber: nextNum,
        label: 'NIC $nextNum',
        mediaType: PortMediaType.rj45,
        speed: PortSpeed.speed1G,
      ),
    );
    vm.updateEndpoint(ep.copyWith(ports: current));
  }

  void _removeEndpointNicPort(
    SandboxViewModel vm,
    EndpointNodeInstance ep,
    int index,
  ) {
    final current = List<EndpointPortConfig>.from(ep.effectivePorts);
    if (current.length <= 1) return;
    final removed = current.removeAt(index);
    final link = vm.linkForPort(ep.id, removed.portNumber);
    if (link != null) {
      vm.removeLink(link.id);
    }
    final fallbackPort = current.first.portNumber;
    final updatedFlows = [
      for (final f in ep.activeTrafficFlows)
        f.effectivePortNumber == removed.portNumber
            ? f.copyWith(boundPortNumber: fallbackPort)
            : f,
    ];
    vm.updateEndpoint(
      ep.copyWith(ports: current, activeTrafficFlows: updatedFlows),
    );
  }

  Widget _buildEndpointNicCard(
    SandboxViewModel vm,
    EndpointNodeInstance ep,
    int index,
    EndpointPortConfig port,
  ) {
    final effectivePorts = ep.effectivePorts;
    final isSfp = port.mediaType == PortMediaType.sfpFibre;
    final link = vm.linkForPort(ep.id, port.portNumber);
    final canCompleteWire = vm.pendingWireSource != null &&
        link == null &&
        vm.isPortMediaCompatibleWithPendingWire(ep.id, port.portNumber);

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: canCompleteWire
              ? AppTheme.accent
              : (isSfp ? AppTheme.accent.withValues(alpha: 0.45) : AppTheme.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSfp
                      ? AppTheme.accent.withValues(alpha: 0.16)
                      : AppTheme.surface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isSfp ? AppTheme.accent : AppTheme.border,
                  ),
                ),
                child: Text(
                  'NIC ${port.portNumber} • ${port.mediaSpeedLabel}',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: isSfp ? AppTheme.accent : AppTheme.textPrimary,
                  ),
                ),
              ),
              const Spacer(),
              if (link != null)
                OutlinedButton.icon(
                  onPressed: () => vm.removeLink(link.id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.error,
                    side: BorderSide(
                      color: AppTheme.error.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                  ),
                  icon: const Icon(Icons.link_off, size: 12),
                  label: const Text('Unplug', style: TextStyle(fontSize: 10.5)),
                )
              else
                FilledButton.icon(
                  onPressed: () {
                    if (vm.pendingWireSource != null) {
                      vm.completeWiringToPort(ep.id, port.portNumber);
                    } else {
                      vm.startWiringFromPort(ep.id, port.portNumber);
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                  ),
                  icon: const Icon(Icons.cable, size: 12),
                  label: Text(
                    canCompleteWire ? 'Connect Here' : 'Wire NIC',
                    style: const TextStyle(fontSize: 10.5),
                  ),
                ),
              if (effectivePorts.length > 1)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Remove NIC Port',
                  onPressed: () => _removeEndpointNicPort(vm, ep, index),
                  icon: Icon(Icons.close, size: 14, color: AppTheme.error),
                ),
            ],
          ),
          const SizedBox(height: 6),
          TextFormField(
            key: ValueKey('ep-nic-lbl-${ep.id}-${port.portNumber}'),
            initialValue: port.label ?? '',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'NIC Label (Optional)',
              hintText: 'Primary / Control / Video SFP+',
            ),
            onChanged: (val) {
              final next = List<EndpointPortConfig>.from(effectivePorts);
              next[index] = port.copyWith(label: val.trim());
              vm.updateEndpoint(ep.copyWith(ports: next));
            },
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<PortMediaType>(
                  key: ValueKey(
                    'ep-nic-media-${ep.id}-${port.portNumber}-${port.mediaType.name}',
                  ),
                  initialValue: port.mediaType,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Media'),
                  dropdownColor: AppTheme.surfaceElevated,
                  style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                  items: PortMediaType.values
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(m.shortLabel),
                        ),
                      )
                      .toList(),
                  onChanged: (m) {
                    if (m == null) return;
                    final next = List<EndpointPortConfig>.from(effectivePorts);
                    next[index] = port.copyWith(
                      mediaType: m,
                      speed: m.normalizeSpeed(port.speed),
                      poeDrawWatts:
                          m == PortMediaType.sfpFibre ? 0.0 : port.poeDrawWatts,
                    );
                    vm.updateEndpoint(ep.copyWith(ports: next));
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<PortSpeed>(
                  key: ValueKey(
                    'ep-nic-spd-${ep.id}-${port.portNumber}-${port.mediaType.name}-${port.effectiveSpeed.name}',
                  ),
                  initialValue: port.effectiveSpeed,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Speed'),
                  dropdownColor: AppTheme.surfaceElevated,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppTheme.textPrimary,
                  ),
                  items: port.mediaType.allowedSpeeds
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(s.label),
                        ),
                      )
                      .toList(),
                  onChanged: (s) {
                    if (s == null) return;
                    final next = List<EndpointPortConfig>.from(effectivePorts);
                    next[index] = port.copyWith(speed: s);
                    vm.updateEndpoint(ep.copyWith(ports: next));
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 3,
                child: TextFormField(
                  key: ValueKey(
                    'ep-nic-poe-${ep.id}-${port.portNumber}-$isSfp',
                  ),
                  initialValue: port.effectivePoeDrawWatts.toStringAsFixed(1),
                  enabled: !isSfp,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: isSfp ? AppTheme.textMuted : AppTheme.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: isSfp ? 'No PoE' : 'PoE (W)',
                  ),
                  onChanged: (val) {
                    final watts = double.tryParse(val.trim());
                    if (watts != null && watts >= 0) {
                      final next = List<EndpointPortConfig>.from(effectivePorts);
                      next[index] = port.copyWith(poeDrawWatts: watts);
                      vm.updateEndpoint(ep.copyWith(ports: next));
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addEndpointFlow(
    BuildContext context,
    SandboxViewModel vm,
    EndpointNodeInstance ep,
  ) async {
    final effectivePorts = ep.effectivePorts;
    var proto = TrafficProtocol.sacn;
    var dir = TrafficDirection.txPublisher;
    var bw = 1.0;
    var vlan = 20;
    var portNumber = effectivePorts.first.portNumber;
    var sacnSpec = '1-4';
    var mcastSpec = '';

    final created = await showDialog<TrafficRequirement?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          final isSacnMcast = proto == TrafficProtocol.sacn &&
              proto.defaultDelivery == DeliveryType.multicast;
          final draftFlow = TrafficRequirement(
            id: 'draft',
            protocol: proto,
            direction: dir,
            deliveryType: proto.defaultDelivery,
            estimatedBandwidthMbps: bw,
            requiresIgmp: proto.defaultRequiresIgmp,
            defaultVlanId: vlan,
            boundPortNumber: portNumber,
            sacnUniverseSpec: isSacnMcast && sacnSpec.trim().isNotEmpty
                ? sacnSpec.trim()
                : null,
            multicastGroupSpec: !isSacnMcast && mcastSpec.trim().isNotEmpty
                ? mcastSpec.trim()
                : null,
          );
          final specError = MulticastStreamResolver.validateFlowSpec(draftFlow);

          return AlertDialog(
            backgroundColor: AppTheme.surfaceElevated,
            title: Text(
              'Add Traffic Flow',
              style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
            ),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<TrafficProtocol>(
                      initialValue: proto,
                      decoration: const InputDecoration(labelText: 'Protocol'),
                      dropdownColor: AppTheme.surfaceElevated,
                      items: TrafficProtocol.values
                          .map((p) =>
                              DropdownMenuItem(value: p, child: Text(p.label)))
                          .toList(),
                      onChanged: (val) {
                        if (val == null) return;
                        setStateDialog(() {
                          proto = val;
                          bw = val == TrafficProtocol.sacn
                              ? 1.0
                              : val.defaultUnitMbps;
                          vlan = val.defaultVlan;
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<TrafficDirection>(
                      initialValue: dir,
                      decoration: const InputDecoration(labelText: 'Direction'),
                      dropdownColor: AppTheme.surfaceElevated,
                      items: TrafficDirection.values
                          .map((d) =>
                              DropdownMenuItem(value: d, child: Text(d.label)))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setStateDialog(() => dir = val);
                      },
                    ),
                    if (effectivePorts.length > 1) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<int>(
                        initialValue: portNumber,
                        decoration:
                            const InputDecoration(labelText: 'Bound NIC Port'),
                        dropdownColor: AppTheme.surfaceElevated,
                        items: effectivePorts
                            .map(
                              (p) => DropdownMenuItem(
                                value: p.portNumber,
                                child: Text(p.displayName),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setStateDialog(() => portNumber = val);
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (isSacnMcast) ...[
                      TextFormField(
                        initialValue: sacnSpec,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'sACN Universes (e.g. 1-8, 20)',
                          hintText: '0.25 Mbps per universe',
                        ),
                        onChanged: (val) {
                          setStateDialog(() {
                            sacnSpec = val;
                            final parsed =
                                MulticastStreamResolver.parseSacnUniverses(val);
                            if (parsed.error == null &&
                                parsed.universes.isNotEmpty) {
                              bw = MulticastStreamResolver.sacnBandwidthMbps(
                                parsed.universes.length,
                              );
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                    ] else if (proto.defaultDelivery ==
                        DeliveryType.multicast) ...[
                      TextFormField(
                        initialValue: mcastSpec,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          labelText:
                              'Multicast IP / Range (optional, e.g. 239.69.0.1-4)',
                        ),
                        onChanged: (val) {
                          setStateDialog(() => mcastSpec = val);
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    TextFormField(
                      key: ValueKey('add-flow-bw-${proto.name}-$sacnSpec'),
                      initialValue: bw.toString(),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Estimated Bandwidth (Mbps)',
                      ),
                      onChanged: (val) {
                        final parsed = double.tryParse(val.trim());
                        if (parsed != null && parsed >= 0) bw = parsed;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      key: ValueKey('add-flow-vlan-${proto.name}'),
                      initialValue: vlan.toString(),
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'VLAN ID'),
                      onChanged: (val) {
                        final parsed = int.tryParse(val.trim());
                        if (parsed != null && parsed >= 1 && parsed <= 4094) {
                          vlan = parsed;
                        }
                      },
                    ),
                    if (specError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        specError,
                        style: TextStyle(fontSize: 11, color: AppTheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                ),
                onPressed: specError != null
                    ? null
                    : () {
                        Navigator.of(ctx).pop(
                          TrafficRequirement(
                            id: 'flow-${DateTime.now().microsecondsSinceEpoch}',
                            protocol: proto,
                            direction: dir,
                            deliveryType: proto.defaultDelivery,
                            estimatedBandwidthMbps: bw,
                            requiresIgmp: proto.defaultRequiresIgmp,
                            defaultVlanId: vlan,
                            boundPortNumber: portNumber,
                            sacnUniverseSpec:
                                isSacnMcast && sacnSpec.trim().isNotEmpty
                                    ? sacnSpec.trim()
                                    : null,
                            multicastGroupSpec: !isSacnMcast &&
                                    proto.defaultDelivery ==
                                        DeliveryType.multicast &&
                                    mcastSpec.trim().isNotEmpty
                                ? mcastSpec.trim()
                                : null,
                          ),
                        );
                      },
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    if (created != null) {
      final next = List<TrafficRequirement>.from(ep.activeTrafficFlows)
        ..add(created);
      vm.updateEndpoint(ep.copyWith(activeTrafficFlows: next));
    }
  }

  Widget _buildLinkInspector(
    BuildContext context,
    SandboxViewModel vm,
    NetworkLinkEdge link,
  ) {
    final nameA = vm.project.switches
            .where((s) => s.id == link.sourceNodeId)
            .firstOrNull
            ?.userLabel ??
        vm.project.endpoints
            .where((e) => e.id == link.sourceNodeId)
            .firstOrNull
            ?.userLabel ??
        link.sourceNodeId;
    final nameB = vm.project.switches
            .where((s) => s.id == link.targetNodeId)
            .firstOrNull
            ?.userLabel ??
        vm.project.endpoints
            .where((e) => e.id == link.targetNodeId)
            .firstOrNull
            ?.userLabel ??
        link.targetNodeId;

    final isInterSwitch =
        vm.project.switches.any((s) => s.id == link.sourceNodeId) &&
            vm.project.switches.any((s) => s.id == link.targetNodeId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kvCard('Endpoints', '$nameA (P${link.sourcePortNumber}) ↔ $nameB (P${link.targetPortNumber})'),
        const SizedBox(height: 8),
        if (link.hasMediaMismatch) ...[
          _kvCard(
            'Physical Media Compatibility',
            'MISMATCH: RJ45 copper connected directly to SFP/Fibre port — link non-functional.',
            valueColor: AppTheme.error,
          ),
          const SizedBox(height: 8),
        ] else if (link.isSfpStepDown) ...[
          _kvCard(
            'Physical Media Compatibility',
            '10G SFP+ ↔ 1G SFP Step-Down — check 1G SFP compatibility in 10G SFP+ cage.',
            valueColor: AppTheme.warning,
          ),
          const SizedBox(height: 8),
        ],
        _kvCard('Negotiated Speed', '${link.negotiatedSpeed.label}${link.hasSpeedStepDown ? " (Stepped Down)" : ""}'),
        const SizedBox(height: 8),
        _kvCard(
          'STP State',
          link.stpState == LinkStpState.blocking
              ? 'Blocking at Port ${link.blockedAtPortNumber}'
              : link.stpState.label,
        ),
        const SizedBox(height: 8),
        _kvCard(
          'Estimated Load',
          '${link.estimatedLoadMbps.toStringAsFixed(2)} Mbps (${link.utilizationPercent.toStringAsFixed(1)}%)',
        ),
        if (vm.isStreamTraceActive &&
            link.streamTraceState != LinkStreamTraceState.none) ...[
          const SizedBox(height: 8),
          _kvCard(
            'Traced Stream Flow',
            switch (link.streamTraceState) {
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
        _kvCard(
          'Carried VLANs',
          link.activeVlans.isEmpty
              ? 'None (Blocked/Mismatched)'
              : (link.activeVlans.toList()..sort()).map((v) => 'VLAN $v').join(', '),
        ),
        if (link.prunedVlans.isNotEmpty) ...[
          const SizedBox(height: 8),
          _kvCard(
            'Asymmetric / Pruned VLANs',
            (link.prunedVlans.toList()..sort()).map((v) => 'VLAN $v').join(', '),
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

  Widget _kvCard(String key, String value, {Color? valueColor}) {
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
            key,
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

  Widget _buildTopologySummary(SandboxViewModel vm) {
    final roots = vm.project.switches.where((s) => s.isRootBridge).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _kvCard('Project', vm.project.name),
        const SizedBox(height: 8),
        _kvCard(
          'Root Bridge(s)',
          roots.isEmpty
              ? 'None'
              : roots.map((r) => '${r.userLabel} (PRI ${r.stpPriority})').join('\n'),
        ),
        const SizedBox(height: 8),
        _kvCard(
          'STP Blocking Links',
          '${vm.validation.blockingLinkCount}',
        ),
        const SizedBox(height: 8),
        _kvCard(
          'Quick Workflow',
          '1. Click any Switch, Port, Endpoint, or Cable on the canvas to edit settings.\n'
              '2. Click a free port (or Cable icon) to wire links.\n'
              '3. Use "Randomise MACs" to test STP tie-breaking.\n'
              '4. Use "Highlight VLAN" or "Trace Stream" to inspect multicast pruning.',
        ),
      ],
    );
  }
}

class _TrafficFlowInspectorCard extends StatefulWidget {
  const _TrafficFlowInspectorCard({
    super.key,
    required this.vm,
    required this.endpoint,
    required this.flow,
    required this.effectiveVlan,
    required this.onChanged,
    required this.onDelete,
  });

  final SandboxViewModel vm;
  final EndpointNodeInstance endpoint;
  final TrafficRequirement flow;
  final int effectiveVlan;
  final ValueChanged<TrafficRequirement> onChanged;
  final VoidCallback onDelete;

  @override
  State<_TrafficFlowInspectorCard> createState() =>
      _TrafficFlowInspectorCardState();
}

class _TrafficFlowInspectorCardState extends State<_TrafficFlowInspectorCard> {
  late final TextEditingController _sacnCtrl;
  late final TextEditingController _mcastCtrl;
  late final TextEditingController _mbpsCtrl;

  @override
  void initState() {
    super.initState();
    _sacnCtrl = TextEditingController(
      text: widget.flow.sacnUniverseSpec ?? '',
    );
    _mcastCtrl = TextEditingController(
      text: widget.flow.multicastGroupSpec ?? '',
    );
    _mbpsCtrl = TextEditingController(
      text: widget.flow.estimatedBandwidthMbps.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant _TrafficFlowInspectorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newSacn = widget.flow.sacnUniverseSpec ?? '';
    if (newSacn != _sacnCtrl.text && newSacn != (oldWidget.flow.sacnUniverseSpec ?? '')) {
      _sacnCtrl.text = newSacn;
    }
    final newMcast = widget.flow.multicastGroupSpec ?? '';
    if (newMcast != _mcastCtrl.text && newMcast != (oldWidget.flow.multicastGroupSpec ?? '')) {
      _mcastCtrl.text = newMcast;
    }
    if (widget.flow.estimatedBandwidthMbps !=
        oldWidget.flow.estimatedBandwidthMbps) {
      final formatted = widget.flow.estimatedBandwidthMbps.toStringAsFixed(2);
      final currentParsed = double.tryParse(_mbpsCtrl.text.trim());
      if (currentParsed != widget.flow.estimatedBandwidthMbps) {
        _mbpsCtrl.text = formatted;
      }
    }
  }

  @override
  void dispose() {
    _sacnCtrl.dispose();
    _mcastCtrl.dispose();
    _mbpsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final ep = widget.endpoint;
    final flow = widget.flow;
    final effectivePorts = ep.effectivePorts;
    final isSacnMcast = flow.protocol == TrafficProtocol.sacn &&
        flow.deliveryType == DeliveryType.multicast;
    final isOtherMcast = flow.protocol != TrafficProtocol.sacn &&
        flow.deliveryType == DeliveryType.multicast;
    final specError = MulticastStreamResolver.validateFlowSpec(flow);
    final resolvedStreams = specError == null
        ? MulticastStreamResolver.resolveFlowStreams(
            flow,
            effectiveVlanId: widget.effectiveVlan,
          )
        : const <ResolvedMulticastStream>[];
    final rxQuickPicks =
        (flow.direction == TrafficDirection.rxSubscriber &&
                flow.deliveryType == DeliveryType.multicast)
            ? vm.advertisedTxStreamChipsForVlan(
                widget.effectiveVlan,
                flow.protocol,
                excludeEndpointId: ep.id,
              )
            : const [];

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: specError != null ? AppTheme.error : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  flow.displayPill,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, size: 14, color: AppTheme.error),
                onPressed: widget.onDelete,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TrafficDirection>(
                  key: ValueKey('flow-dir-${ep.id}-${flow.id}-${flow.direction.name}'),
                  initialValue: flow.direction,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Direction'),
                  dropdownColor: AppTheme.surfaceElevated,
                  style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                  items: TrafficDirection.values
                      .map((d) => DropdownMenuItem(value: d, child: Text(d.label)))
                      .toList(),
                  onChanged: (dir) {
                    if (dir != null) {
                      widget.onChanged(flow.copyWith(direction: dir));
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 84,
                child: DropdownButtonFormField<int>(
                  key: ValueKey('flow-vlan-${ep.id}-${flow.id}-${flow.defaultVlanId}'),
                  initialValue: vm.availableVlanIds.contains(flow.defaultVlanId)
                      ? flow.defaultVlanId
                      : vm.availableVlanIds.first,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'VLAN'),
                  dropdownColor: AppTheme.surfaceElevated,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppTheme.textPrimary,
                  ),
                  items: vm.availableVlanIds
                      .map((v) => DropdownMenuItem(value: v, child: Text('V$v')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      widget.onChanged(flow.copyWith(defaultVlanId: v));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (effectivePorts.length > 1) ...[
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey(
                      'flow-nic-${ep.id}-${flow.id}-${flow.effectivePortNumber}',
                    ),
                    initialValue: effectivePorts
                            .any((p) => p.portNumber == flow.effectivePortNumber)
                        ? flow.effectivePortNumber
                        : effectivePorts.first.portNumber,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'NIC Port'),
                    dropdownColor: AppTheme.surfaceElevated,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: AppTheme.textPrimary,
                    ),
                    items: effectivePorts
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.portNumber,
                            child: Text('NIC ${p.portNumber}'),
                          ),
                        )
                        .toList(),
                    onChanged: (pNum) {
                      if (pNum != null) {
                        widget.onChanged(flow.copyWith(boundPortNumber: pNum));
                      }
                    },
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: TextField(
                  controller: _mbpsCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(labelText: 'Mbps'),
                  onChanged: (val) {
                    final parsed = double.tryParse(val.trim());
                    if (parsed != null && parsed >= 0) {
                      widget.onChanged(
                        flow.copyWith(estimatedBandwidthMbps: parsed),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          if (isSacnMcast) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _sacnCtrl,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'sACN Universes (e.g. 1-8, 20)',
                hintText: '0.25 Mbps per universe',
              ),
              onChanged: (val) {
                final trimmed = val.trim();
                final parsed =
                    MulticastStreamResolver.parseSacnUniverses(trimmed);
                final autoBw =
                    parsed.error == null && parsed.universes.isNotEmpty
                        ? MulticastStreamResolver.sacnBandwidthMbps(
                            parsed.universes.length,
                          )
                        : flow.estimatedBandwidthMbps;
                if (parsed.error == null && parsed.universes.isNotEmpty) {
                  _mbpsCtrl.text = autoBw.toStringAsFixed(2);
                }
                widget.onChanged(
                  flow.copyWith(
                    sacnUniverseSpec: trimmed,
                    clearSacnUniverseSpec: trimmed.isEmpty,
                    estimatedBandwidthMbps: autoBw,
                  ),
                );
              },
            ),
            if (resolvedStreams.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                '${resolvedStreams.length} stream(s): '
                '${resolvedStreams.first.multicastIp}'
                '${resolvedStreams.length > 1 ? " .. ${resolvedStreams.last.multicastIp}" : ""}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ] else if (isOtherMcast) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _mcastCtrl,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: AppTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Multicast Group(s) (optional)',
                hintText: 'e.g. 239.69.0.1-4',
              ),
              onChanged: (val) {
                final trimmed = val.trim();
                widget.onChanged(
                  flow.copyWith(
                    multicastGroupSpec: trimmed,
                    clearMulticastGroupSpec: trimmed.isEmpty,
                  ),
                );
              },
            ),
            if (resolvedStreams.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                '${resolvedStreams.length} group(s): '
                '${resolvedStreams.first.multicastIp}'
                '${resolvedStreams.length > 1 ? " .. ${resolvedStreams.last.multicastIp}" : ""}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ],
          if (specError != null) ...[
            const SizedBox(height: 4),
            Text(
              specError,
              style: TextStyle(fontSize: 10.5, color: AppTheme.error),
            ),
          ],
          if (rxQuickPicks.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Quick-Pick TX on VLAN ${widget.effectiveVlan}:',
              style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 3),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final chip in rxQuickPicks)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: AppTheme.accent.withValues(alpha: 0.12),
                    side: BorderSide(
                      color: AppTheme.accent.withValues(alpha: 0.45),
                    ),
                    label: Text(
                      chip.summaryLabel,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9.5,
                        color: AppTheme.accent,
                      ),
                    ),
                    onPressed: () {
                      if (chip.sacnUniverseSpec != null) {
                        _sacnCtrl.text = chip.sacnUniverseSpec!;
                        _mbpsCtrl.text = chip.bandwidthMbps.toStringAsFixed(2);
                        widget.onChanged(
                          flow.copyWith(
                            sacnUniverseSpec: chip.sacnUniverseSpec,
                            estimatedBandwidthMbps: chip.bandwidthMbps,
                          ),
                        );
                      } else if (chip.multicastGroupSpec != null) {
                        _mcastCtrl.text = chip.multicastGroupSpec!;
                        _mbpsCtrl.text = chip.bandwidthMbps.toStringAsFixed(2);
                        widget.onChanged(
                          flow.copyWith(
                            multicastGroupSpec: chip.multicastGroupSpec,
                            estimatedBandwidthMbps: chip.bandwidthMbps,
                          ),
                        );
                      }
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
