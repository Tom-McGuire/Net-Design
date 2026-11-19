import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../../domain/engine/multicast_flow_tracer.dart';
import '../../../domain/models/endpoint_node_instance.dart';
import '../../../domain/models/endpoint_template.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/switch_node_instance.dart';
import '../../theme/app_theme.dart';
import '../sandbox_view_model.dart';
import 'link_inspector_view.dart';
import 'port_vlan_matrix_editor.dart';
import 'traffic_flow_inspector_card.dart';

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

  void _syncForSwitch(SwitchNodeInstance sw, int revision) {
    final key = 'sw:${sw.id}:$revision';
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

  void _syncForEndpoint(EndpointNodeInstance ep, int revision) {
    final key = 'ep:${ep.id}:$revision';
    if (_syncedEntityKey != key) {
      _syncedEntityKey = key;
      _labelCtrl.text = ep.userLabel;
      _ipCtrl.text = ep.ipAddress ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    context.select<SandboxViewModel, int>((v) => v.panelRevision);
    final vm = context.read<SandboxViewModel>();
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
                          ? LinkInspectorView(vm: vm, link: link)
                          : TopologySummaryView(vm: vm))),
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
    _syncForSwitch(sw, vm.templateSyncRevision);
    final priorities = [for (var p = 0; p <= 61440; p += 4096) p];
    final sortedVlanIds = sw.vlanConfigs.keys.toList()..sort();
    final matchingTpl = vm.switchTemplates
        .where((t) => t.id == sw.templateId)
        .firstOrNull;

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
            if (matchingTpl != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Update from Library Template (${matchingTpl.name})',
                onPressed: () =>
                    vm.applySwitchTemplateToPlan(matchingTpl, onlySwitchId: sw.id),
                icon: Icon(Icons.sync, size: 18, color: AppTheme.accent),
              ),
            ],
            const SizedBox(width: 2),
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
    final snoopingOn = sw.supportsIgmpSnooping && cfg.igmpSnoopingEnabled;
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
          if (snoopingOn) ...[
            const SizedBox(height: 6),
            _buildIgmpToggleBox(
              label: 'Drop Unknown Multicast',
              value: cfg.dropUnregisteredMulticast,
              enabled: true,
              onChanged: (v) => vm.updateSwitchVlan(
                sw.id,
                cfg.copyWith(dropUnregisteredMulticast: v),
              ),
            ),
          ],
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
    _syncForEndpoint(ep, vm.templateSyncRevision);
    final effectivePorts = ep.effectivePorts;
    final swMap = {for (final s in vm.project.switches) s.id: s};
    final epMap = {for (final e in vm.project.endpoints) e.id: e};
    final atts = MulticastFlowTracer.buildEndpointAttachments(
      switchesById: swMap,
      endpointsById: epMap,
      links: vm.project.links,
    );

    final matchingTpl = vm.endpointTemplates
        .where((t) => t.id == ep.templateId)
        .firstOrNull;

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
            if (matchingTpl != null) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Update from Library Template (${matchingTpl.name})',
                onPressed: () => vm.applyEndpointTemplateToPlan(
                  matchingTpl,
                  onlyEndpointId: ep.id,
                ),
                icon: Icon(Icons.sync, size: 18, color: AppTheme.accent),
              ),
            ],
            const SizedBox(width: 2),
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
              return TrafficFlowInspectorCard(
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
    final isPendingThisNic = vm.pendingWireSource?.nodeId == ep.id &&
        vm.pendingWireSource?.portNumber == port.portNumber;
    final canCompleteWire =
        vm.canCompleteWiringToPort(ep.id, port.portNumber);
    final hasOtherPendingWire = vm.pendingWireSource != null && !canCompleteWire;

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
              else if (isPendingThisNic)
                OutlinedButton.icon(
                  onPressed: vm.cancelWiring,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.warning,
                    side: BorderSide(
                      color: AppTheme.warning.withValues(alpha: 0.6),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                  ),
                  icon: const Icon(Icons.close, size: 12),
                  label: const Text('Cancel', style: TextStyle(fontSize: 10.5)),
                )
              else
                FilledButton.icon(
                  onPressed: hasOtherPendingWire
                      ? null
                      : () {
                          if (canCompleteWire) {
                            vm.completeWiringToPort(ep.id, port.portNumber);
                          } else {
                            vm.startWiringFromPort(ep.id, port.portNumber);
                          }
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: canCompleteWire
                        ? AppTheme.success
                        : AppTheme.accent,
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
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey(
              'ep-nic-lbl-${ep.id}-${port.portNumber}-${vm.templateSyncRevision}',
            ),
            initialValue: port.label ?? '',
            style: TextStyle(fontSize: 11.5, color: AppTheme.textPrimary),
            decoration: const InputDecoration(
              labelText: 'NIC Label (Optional)',
              hintText: 'Primary / Control / Video SFP+',
            ),
            onChanged: (val) {
              final trimmed = val.trim();
              final next = List<EndpointPortConfig>.from(effectivePorts);
              next[index] = port.copyWith(
                label: trimmed,
                clearLabel: trimmed.isEmpty,
              );
              vm.updateEndpoint(ep.copyWith(ports: next));
            },
          ),
          const SizedBox(height: 10),
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
                    'ep-nic-poe-${ep.id}-${port.portNumber}-${port.mediaType.name}-${vm.templateSyncRevision}',
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
    final created = await showAddTrafficFlowDialog(context, ep);
    if (created != null) {
      final next = List<TrafficRequirement>.from(ep.activeTrafficFlows)
        ..add(created);
      vm.updateEndpoint(ep.copyWith(activeTrafficFlows: next));
    }
  }
}
