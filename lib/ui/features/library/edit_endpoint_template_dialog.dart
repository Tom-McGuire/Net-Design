import 'package:material_ui/material_ui.dart';

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
  late final TextEditingController _poeCtrl;
  late EndpointCategory _category;
  late PortSpeed _nicSpeed;
  late List<TrafficRequirement> _flows;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? 'Custom Endpoint');
    _poeCtrl = TextEditingController(
      text: (e?.poeDrawWatts ?? 0.0).toStringAsFixed(1),
    );
    _category = e?.category ?? EndpointCategory.genericEndpoint;
    _nicSpeed = e?.nicSpeed ?? PortSpeed.speed1G;
    _flows = List<TrafficRequirement>.from(e?.trafficProfiles ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _poeCtrl.dispose();
    super.dispose();
  }

  void _addDefaultFlow() {
    setState(() {
      _flows.add(
        TrafficRequirement(
          id: 'flow-${DateTime.now().microsecondsSinceEpoch}',
          protocol: TrafficProtocol.sacn,
          direction: TrafficDirection.txPublisher,
          deliveryType: DeliveryType.multicast,
          estimatedBandwidthMbps: 4.0,
          requiresIgmp: true,
          defaultVlanId: 20,
        ),
      );
    });
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final poe = (double.tryParse(_poeCtrl.text.trim()) ?? 0.0).clamp(0.0, 200.0);

    Navigator.of(context).pop(
      EndpointTemplate(
        id: widget.existing?.id ??
            'tpl-ep-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        category: _category,
        nicSpeed: _nicSpeed,
        poeDrawWatts: poe,
        trafficProfiles: _flows,
        isBuiltIn: widget.existing?.isBuiltIn ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Template Name'),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
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
                                  Text(c.label, style: const TextStyle(fontSize: 12)),
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
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<PortSpeed>(
                      initialValue: _nicSpeed,
                      decoration: const InputDecoration(labelText: 'NIC Speed'),
                      dropdownColor: AppTheme.surfaceElevated,
                      items: PortSpeed.values
                          .map(
                            (s) => DropdownMenuItem(
                              value: s,
                              child: Text(s.label),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _nicSpeed = v);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _poeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'PoE Draw (W)'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                    label: const Text('Add Traffic Profile', style: TextStyle(fontSize: 11)),
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
          onPressed: _save,
          child: const Text('Save Template'),
        ),
      ],
    );
  }

  Widget _buildFlowEditorRow(int index, TrafficRequirement flow) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
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
        ],
      ),
    );
  }
}
