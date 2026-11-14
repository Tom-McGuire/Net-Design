import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../../../domain/engine/multicast_stream_resolver.dart';
import '../../../domain/models/endpoint_template.dart';
import '../../../domain/models/enums.dart';
import '../../theme/app_theme.dart';

/// Dialog for creating or editing a vendor-neutral [EndpointTemplate].
class EditEndpointTemplateDialog extends StatefulWidget {
  const EditEndpointTemplateDialog({super.key, this.existing});

  final EndpointTemplate? existing;

  static Future<EndpointTemplate?> show(
    BuildContext context, {
    EndpointTemplate? existing,
  }) {
    return showDialog<EndpointTemplate>(
      context: context,
      builder: (_) => EditEndpointTemplateDialog(existing: existing),
    );
  }

  @override
  State<EditEndpointTemplateDialog> createState() =>
      _EditEndpointTemplateDialogState();
}

class _EditEndpointTemplateDialogState
    extends State<EditEndpointTemplateDialog> {
  late final TextEditingController _nameCtrl;
  late EndpointCategory _category;
  late List<EndpointPortConfig> _ports;
  late List<TrafficRequirement> _flows;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? 'Custom Endpoint');
    _category = e?.category ?? EndpointCategory.genericEndpoint;
    _ports = e != null
        ? List<EndpointPortConfig>.from(e.effectivePorts)
        : [
            const EndpointPortConfig(
              portNumber: 1,
              label: 'Primary NIC',
              mediaType: PortMediaType.rj45,
              speed: PortSpeed.speed1G,
            ),
          ];
    _flows = List<TrafficRequirement>.from(e?.trafficProfiles ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _addPort() {
    final nextNum =
        _ports.map((p) => p.portNumber).fold<int>(0, max) + 1;
    setState(() {
      _ports.add(
        EndpointPortConfig(
          portNumber: nextNum,
          label: 'NIC $nextNum',
          mediaType: PortMediaType.rj45,
          speed: PortSpeed.speed1G,
        ),
      );
    });
  }

  void _removePort(int index) {
    if (_ports.length <= 1) return;
    final removedNum = _ports[index].portNumber;
    setState(() {
      _ports.removeAt(index);
      final fallbackNum = _ports.first.portNumber;
      _flows = [
        for (final f in _flows)
          f.effectivePortNumber == removedNum
              ? f.copyWith(boundPortNumber: fallbackNum)
              : f,
      ];
    });
  }

  void _addDefaultFlow() {
    final defaultPort = _ports.isNotEmpty ? _ports.first.portNumber : 1;
    setState(() {
      _flows.add(
        TrafficRequirement(
          id: 'flow-${DateTime.now().microsecondsSinceEpoch}',
          protocol: TrafficProtocol.sacn,
          direction: TrafficDirection.txPublisher,
          deliveryType: DeliveryType.multicast,
          estimatedBandwidthMbps: 1.0,
          requiresIgmp: true,
          defaultVlanId: 20,
          boundPortNumber: defaultPort,
          sacnUniverseSpec: '1-4',
        ),
      );
    });
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    for (final flow in _flows) {
      if (MulticastStreamResolver.validateFlowSpec(flow) != null) {
        return;
      }
    }

    final validPorts = _ports.map((p) => p.portNumber).toSet();
    final sanitizedFlows = [
      for (final f in _flows)
        validPorts.contains(f.effectivePortNumber)
            ? f
            : f.copyWith(boundPortNumber: _ports.first.portNumber),
    ];

    final primary = _ports.first;
    final totalPoe = _ports.fold<double>(
      0.0,
      (sum, p) => sum + p.effectivePoeDrawWatts,
    );

    Navigator.of(context).pop(
      EndpointTemplate(
        id: widget.existing?.id ??
            'tpl-ep-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        category: _category,
        nicSpeed: primary.effectiveSpeed,
        poeDrawWatts: totalPoe,
        ports: _ports,
        trafficProfiles: sanitizedFlows,
        isBuiltIn: widget.existing?.isBuiltIn ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSpecError = _flows.any(
      (f) => MulticastStreamResolver.validateFlowSpec(f) != null,
    );

    return AlertDialog(
      backgroundColor: AppTheme.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppTheme.border),
      ),
      title: Text(
        widget.existing == null
            ? 'New Endpoint Template'
            : 'Edit Endpoint Template',
        style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _nameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Template Name'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<EndpointCategory>(
                      initialValue: _category,
                      decoration: const InputDecoration(labelText: 'Category'),
                      dropdownColor: AppTheme.surfaceElevated,
                      items: EndpointCategory.values
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Row(
                                children: [
                                  Icon(c.icon, size: 15, color: AppTheme.accent),
                                  const SizedBox(width: 6),
                                  Text(c.label,
                                      style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _category = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Network Interface Ports (${_ports.length})',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _ports.length < 8 ? _addPort : null,
                    icon: const Icon(Icons.add, size: 14),
                    label:
                        const Text('Add NIC Port', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              for (var i = 0; i < _ports.length; i++) ...[
                _buildPortEditorRow(i, _ports[i]),
                const SizedBox(height: 6),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Traffic Demand Profiles (${_flows.length})',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addDefaultFlow,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add Traffic Profile',
                        style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
              for (var i = 0; i < _flows.length; i++) ...[
                _buildFlowEditorRow(i, _flows[i]),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
          ),
          onPressed: hasSpecError ? null : _save,
          child: const Text('Save Template'),
        ),
      ],
    );
  }

  Widget _buildPortEditorRow(int index, EndpointPortConfig port) {
    final isSfp = port.mediaType == PortMediaType.sfpFibre;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: isSfp
                  ? AppTheme.accent.withValues(alpha: 0.14)
                  : AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSfp ? AppTheme.accent : AppTheme.border,
              ),
            ),
            child: Text(
              'NIC ${port.portNumber}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                color: isSfp ? AppTheme.accent : AppTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextFormField(
              key: ValueKey('tpl-port-lbl-${port.portNumber}'),
              initialValue: port.label ?? '',
              style: TextStyle(fontSize: 11.5, color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Port Label',
                hintText: 'Primary / Video',
              ),
              onChanged: (v) {
                _ports[index] = port.copyWith(label: v.trim());
              },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 116,
            child: DropdownButtonFormField<PortMediaType>(
              key: ValueKey('tpl-port-media-${port.portNumber}-${port.mediaType.name}'),
              initialValue: port.mediaType,
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
                setState(() {
                  _ports[index] = port.copyWith(
                    mediaType: m,
                    speed: m.normalizeSpeed(port.speed),
                    poeDrawWatts: m == PortMediaType.sfpFibre
                        ? 0.0
                        : port.poeDrawWatts,
                  );
                });
              },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 90,
            child: DropdownButtonFormField<PortSpeed>(
              key: ValueKey(
                'tpl-port-spd-${port.portNumber}-${port.mediaType.name}-${port.effectiveSpeed.name}',
              ),
              initialValue: port.effectiveSpeed,
              decoration: const InputDecoration(labelText: 'Speed'),
              dropdownColor: AppTheme.surfaceElevated,
              style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
              items: port.mediaType.allowedSpeeds
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s.label),
                    ),
                  )
                  .toList(),
              onChanged: (s) {
                if (s != null) {
                  setState(() => _ports[index] = port.copyWith(speed: s));
                }
              },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 78,
            child: TextFormField(
              key: ValueKey('tpl-port-poe-${port.portNumber}-$isSfp'),
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
              onChanged: (v) {
                final parsed =
                    (double.tryParse(v.trim()) ?? 0.0).clamp(0.0, 200.0);
                _ports[index] = port.copyWith(poeDrawWatts: parsed);
              },
            ),
          ),
          IconButton(
            tooltip: _ports.length > 1 ? 'Remove NIC port' : 'Minimum 1 NIC required',
            onPressed: _ports.length > 1 ? () => _removePort(index) : null,
            icon: Icon(
              Icons.delete_outline,
              size: 16,
              color: _ports.length > 1 ? AppTheme.error : AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowEditorRow(int index, TrafficRequirement flow) {
    final specError = MulticastStreamResolver.validateFlowSpec(flow);
    final isSacnMcast = flow.protocol == TrafficProtocol.sacn &&
        flow.deliveryType == DeliveryType.multicast;
    final isOtherMcast = flow.protocol != TrafficProtocol.sacn &&
        flow.deliveryType == DeliveryType.multicast;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<TrafficProtocol>(
                  initialValue: flow.protocol,
                  decoration: const InputDecoration(labelText: 'Protocol'),
                  dropdownColor: AppTheme.surfaceElevated,
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textPrimary),
                  items: TrafficProtocol.values
                      .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
                      .toList(),
                  onChanged: (p) {
                    if (p == null) return;
                    setState(() {
                      _flows[index] = flow.copyWith(
                        protocol: p,
                        deliveryType: p.defaultDelivery,
                        requiresIgmp: p.defaultRequiresIgmp,
                        defaultVlanId: p.defaultVlan,
                        estimatedBandwidthMbps: p.defaultUnitMbps,
                        clearSacnUniverseSpec: p != TrafficProtocol.sacn,
                        clearMulticastGroupSpec: p == TrafficProtocol.sacn,
                      );
                    });
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: DropdownButtonFormField<TrafficDirection>(
                  initialValue: flow.direction,
                  decoration: const InputDecoration(labelText: 'Direction'),
                  dropdownColor: AppTheme.surfaceElevated,
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textPrimary),
                  items: TrafficDirection.values
                      .map((d) => DropdownMenuItem(value: d, child: Text(d.label)))
                      .toList(),
                  onChanged: (d) {
                    if (d != null) {
                      setState(() => _flows[index] = flow.copyWith(direction: d));
                    }
                  },
                ),
              ),
              if (_ports.length > 1) ...[
                const SizedBox(width: 6),
                SizedBox(
                  width: 96,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('flow-port-${flow.id}-${flow.effectivePortNumber}'),
                    initialValue: _ports.any(
                            (p) => p.portNumber == flow.effectivePortNumber)
                        ? flow.effectivePortNumber
                        : _ports.first.portNumber,
                    decoration: const InputDecoration(labelText: 'NIC Port'),
                    dropdownColor: AppTheme.surfaceElevated,
                    style:
                        TextStyle(fontSize: 11.5, color: AppTheme.textPrimary),
                    items: _ports
                        .map(
                          (p) => DropdownMenuItem(
                            value: p.portNumber,
                            child: Text('NIC ${p.portNumber}'),
                          ),
                        )
                        .toList(),
                    onChanged: (pNum) {
                      if (pNum != null) {
                        setState(() =>
                            _flows[index] = flow.copyWith(boundPortNumber: pNum));
                      }
                    },
                  ),
                ),
              ],
              IconButton(
                onPressed: () => setState(() => _flows.removeAt(index)),
                icon: Icon(Icons.delete_outline, size: 16, color: AppTheme.error),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<DeliveryType>(
                  initialValue: flow.deliveryType,
                  decoration: const InputDecoration(labelText: 'Delivery'),
                  dropdownColor: AppTheme.surfaceElevated,
                  style: TextStyle(fontSize: 11.5, color: AppTheme.textPrimary),
                  items: DeliveryType.values
                      .map((d) => DropdownMenuItem(value: d, child: Text(d.label)))
                      .toList(),
                  onChanged: (d) {
                    if (d != null) {
                      setState(() => _flows[index] = flow.copyWith(deliveryType: d));
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 96,
                child: TextFormField(
                  key: ValueKey(
                    'tpl-flow-mbps-${flow.id}-${flow.sacnUniverseSpec ?? ""}',
                  ),
                  initialValue: flow.estimatedBandwidthMbps.toString(),
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(labelText: 'Mbps'),
                  onChanged: (v) {
                    final parsed = double.tryParse(v.trim());
                    if (parsed != null && parsed >= 0) {
                      _flows[index] =
                          flow.copyWith(estimatedBandwidthMbps: parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 82,
                child: TextFormField(
                  initialValue: flow.defaultVlanId.toString(),
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    color: AppTheme.textPrimary,
                  ),
                  decoration: const InputDecoration(labelText: 'VLAN'),
                  onChanged: (v) {
                    final parsed = int.tryParse(v.trim());
                    if (parsed != null && parsed >= 1 && parsed <= 4094) {
                      _flows[index] = flow.copyWith(defaultVlanId: parsed);
                    }
                  },
                ),
              ),
            ],
          ),
          if (isSacnMcast) ...[
            const SizedBox(height: 6),
            TextFormField(
              key: ValueKey('tpl-flow-sacn-${flow.id}'),
              initialValue: flow.sacnUniverseSpec ?? '',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: AppTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'sACN Universes (e.g. 1-8, 20)',
                hintText: '0.25 Mbps per universe',
              ),
              onChanged: (v) {
                final trimmed = v.trim();
                final parsed = MulticastStreamResolver.parseSacnUniverses(trimmed);
                setState(() {
                  _flows[index] = flow.copyWith(
                    sacnUniverseSpec: trimmed,
                    clearSacnUniverseSpec: trimmed.isEmpty,
                    estimatedBandwidthMbps:
                        parsed.error == null && parsed.universes.isNotEmpty
                            ? MulticastStreamResolver.sacnBandwidthMbps(
                                parsed.universes.length,
                              )
                            : null,
                  );
                });
              },
            ),
          ] else if (isOtherMcast) ...[
            const SizedBox(height: 6),
            TextFormField(
              key: ValueKey('tpl-flow-mcast-${flow.id}'),
              initialValue: flow.multicastGroupSpec ?? '',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                color: AppTheme.textPrimary,
              ),
              decoration: const InputDecoration(
                labelText: 'Multicast Group(s) (optional, e.g. 239.69.0.1-4)',
                hintText: 'Leave blank for generic multicast',
              ),
              onChanged: (v) {
                final trimmed = v.trim();
                setState(() {
                  _flows[index] = flow.copyWith(
                    multicastGroupSpec: trimmed,
                    clearMulticastGroupSpec: trimmed.isEmpty,
                  );
                });
              },
            ),
          ],
          if (specError != null) ...[
            const SizedBox(height: 4),
            Text(
              specError,
              style: TextStyle(fontSize: 10.5, color: AppTheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
