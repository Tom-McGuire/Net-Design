import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  final TextEditingController _ipCtrl = TextEditingController();
  final TextEditingController _poeCtrl = TextEditingController();
  String? _syncedEntityKey;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _ipCtrl.dispose();
    _poeCtrl.dispose();
    super.dispose();
  }

  void _syncForSwitch(SwitchNodeInstance sw) {
    final key = 'sw:${sw.id}';
    if (_syncedEntityKey != key) {
      _syncedEntityKey = key;
      _labelCtrl.text = sw.userLabel;
      _ipCtrl.text = sw.managementIp ?? '';
    }
  }

  void _syncForEndpoint(EndpointNodeInstance ep) {
    final key = 'ep:${ep.id}';
    if (_syncedEntityKey != key) {
      _syncedEntityKey = key;
      _labelCtrl.text = ep.userLabel;
      _ipCtrl.text = ep.ipAddress ?? '';
      _poeCtrl.text = ep.poeDrawWatts.toStringAsFixed(1);
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
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHigh,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bridge MAC',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    SelectableText(
                      sw.macAddress,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
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
      padding: const EdgeInsets.all(8),
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
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'Snooping',
                    style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                  ),
                  value: cfg.igmpSnoopingEnabled,
                  onChanged: sw.supportsIgmpSnooping
                      ? (v) => vm.updateSwitchVlan(
                            sw.id,
                            cfg.copyWith(igmpSnoopingEnabled: v ?? false),
                          )
                      : null,
                ),
              ),
              Expanded(
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    'Querier',
                    style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                  ),
                  value: cfg.igmpQuerierEnabled,
                  onChanged: sw.supportsIgmpQuerier
                      ? (v) => vm.updateSwitchVlan(
                            sw.id,
                            cfg.copyWith(igmpQuerierEnabled: v ?? false),
                          )
                      : null,
                ),
              ),
            ],
          ),
          DropdownButtonFormField<IgmpVersion>(
            initialValue: cfg.igmpQuerierVersion,
            decoration: const InputDecoration(labelText: 'IGMP Version'),
            dropdownColor: AppTheme.surfaceElevated,
            style: TextStyle(fontSize: 11.5, color: AppTheme.textPrimary),
            items: IgmpVersion.values
                .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                vm.updateSwitchVlan(sw.id, cfg.copyWith(igmpQuerierVersion: v));
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointInspector(
    BuildContext context,
    SandboxViewModel vm,
    EndpointNodeInstance ep,
  ) {
    _syncForEndpoint(ep);
    final isConnected = vm.isPortConnected(ep.id, 1);

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

        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<PortSpeed>(
                initialValue: ep.nicSpeed,
                decoration: const InputDecoration(labelText: 'NIC Speed'),
                dropdownColor: AppTheme.surfaceElevated,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                ),
                items: PortSpeed.values
                    .map(
                      (s) => DropdownMenuItem(value: s, child: Text(s.label)),
                    )
                    .toList(),
                onChanged: (s) {
                  if (s != null) vm.updateEndpoint(ep.copyWith(nicSpeed: s));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _poeCtrl,
                keyboardType: TextInputType.number,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                ),
                decoration: const InputDecoration(labelText: 'PoE Draw (W)'),
                onChanged: (val) {
                  final watts = double.tryParse(val.trim());
                  if (watts != null && watts >= 0) {
                    vm.updateEndpoint(ep.copyWith(poeDrawWatts: watts));
                  }
                },
              ),
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

        if (!isConnected)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => vm.startWiringFromPort(ep.id, 1),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.cable, size: 15),
              label: const Text('Wire NIC to Switch Port'),
            ),
          ),

        const SizedBox(height: 12),
        const Divider(),
        const SizedBox(height: 10),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Traffic Demand Profiles',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppTheme.textSecondary,
              ),
            ),
            TextButton.icon(
              onPressed: () => _addEndpointFlow(context, vm, ep),
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Add Flow', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),

        for (var idx = 0; idx < ep.activeTrafficFlows.length; idx++) ...[
          _buildTrafficFlowCard(vm, ep, idx, ep.activeTrafficFlows[idx]),
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  Widget _buildTrafficFlowCard(
    SandboxViewModel vm,
    EndpointNodeInstance ep,
    int index,
    TrafficRequirement flow,
  ) {
    return Container(
      padding: const EdgeInsets.all(8),
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
                onPressed: () {
                  final next = List<TrafficRequirement>.from(ep.activeTrafficFlows)
                    ..removeAt(index);
                  vm.updateEndpoint(ep.copyWith(activeTrafficFlows: next));
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TrafficDirection>(
                  initialValue: flow.direction,
                  decoration: const InputDecoration(labelText: 'Direction'),
                  dropdownColor: AppTheme.surfaceElevated,
                  style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                  items: TrafficDirection.values
                      .map((d) => DropdownMenuItem(value: d, child: Text(d.label)))
                      .toList(),
                  onChanged: (dir) {
                    if (dir == null) return;
                    final next =
                        List<TrafficRequirement>.from(ep.activeTrafficFlows);
                    next[index] = flow.copyWith(direction: dir);
                    vm.updateEndpoint(ep.copyWith(activeTrafficFlows: next));
                  },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 96,
                child: DropdownButtonFormField<int>(
                  initialValue: vm.availableVlanIds.contains(flow.defaultVlanId)
                      ? flow.defaultVlanId
                      : vm.availableVlanIds.first,
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
                    if (v == null) return;
                    final next =
                        List<TrafficRequirement>.from(ep.activeTrafficFlows);
                    next[index] = flow.copyWith(defaultVlanId: v);
                    vm.updateEndpoint(ep.copyWith(activeTrafficFlows: next));
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
    var proto = TrafficProtocol.sacn;
    var dir = TrafficDirection.txPublisher;
    var bw = 4.0;
    var vlan = 20;

    final created = await showDialog<TrafficRequirement?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          backgroundColor: AppTheme.surfaceElevated,
          title: Text(
            'Add Traffic Flow',
            style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<TrafficProtocol>(
                  initialValue: proto,
                  decoration: const InputDecoration(labelText: 'Protocol'),
                  dropdownColor: AppTheme.surfaceElevated,
                  items: TrafficProtocol.values
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                      .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setStateDialog(() {
                      proto = val;
                      bw = val.defaultUnitMbps;
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
                      .map((d) => DropdownMenuItem(value: d, child: Text(d.label)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setStateDialog(() => dir = val);
                  },
                ),
                const SizedBox(height: 8),
                TextFormField(
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
              ],
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
              onPressed: () {
                Navigator.of(ctx).pop(
                  TrafficRequirement(
                    id: 'flow-${DateTime.now().microsecondsSinceEpoch}',
                    protocol: proto,
                    direction: dir,
                    deliveryType: proto.defaultDelivery,
                    estimatedBandwidthMbps: bw,
                    requiresIgmp: proto.defaultRequiresIgmp,
                    defaultVlanId: vlan,
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
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
              '4. Use "Highlight VLAN" to trace VLAN reachability and trunk pruning.',
        ),
      ],
    );
  }
}
