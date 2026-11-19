import 'package:material_ui/material_ui.dart';

import '../../../domain/engine/multicast_stream_resolver.dart';
import '../../../domain/models/endpoint_node_instance.dart';
import '../../../domain/models/endpoint_template.dart';
import '../../../domain/models/enums.dart';
import '../../theme/app_theme.dart';
import '../sandbox_view_model.dart';

/// Opens a modal dialog to create a new [TrafficRequirement] on [ep].
Future<TrafficRequirement?> showAddTrafficFlowDialog(
  BuildContext context,
  EndpointNodeInstance ep,
) {
  final effectivePorts = ep.effectivePorts;
  var proto = TrafficProtocol.sacn;
  var dir = TrafficDirection.txPublisher;
  var bw = 1.0;
  var vlan = 20;
  var portNumber = effectivePorts.first.portNumber;
  var sacnSpec = '1-4';
  var mcastSpec = '';

  return showDialog<TrafficRequirement?>(
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
                        .map(
                          (p) => DropdownMenuItem(value: p, child: Text(p.label)),
                        )
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
                        .map(
                          (d) => DropdownMenuItem(value: d, child: Text(d.label)),
                        )
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
}

/// Card widget for inspecting and editing a single [TrafficRequirement] on an endpoint.
class TrafficFlowInspectorCard extends StatefulWidget {
  const TrafficFlowInspectorCard({
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
  State<TrafficFlowInspectorCard> createState() =>
      _TrafficFlowInspectorCardState();
}

class _TrafficFlowInspectorCardState extends State<TrafficFlowInspectorCard> {
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
  void didUpdateWidget(covariant TrafficFlowInspectorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final idChanged = widget.flow.id != oldWidget.flow.id;
    final newSacn = widget.flow.sacnUniverseSpec ?? '';
    if (idChanged ||
        (newSacn != _sacnCtrl.text &&
            newSacn != (oldWidget.flow.sacnUniverseSpec ?? ''))) {
      _sacnCtrl.text = newSacn;
    }
    final newMcast = widget.flow.multicastGroupSpec ?? '';
    if (idChanged ||
        (newMcast != _mcastCtrl.text &&
            newMcast != (oldWidget.flow.multicastGroupSpec ?? ''))) {
      _mcastCtrl.text = newMcast;
    }
    if (idChanged ||
        widget.flow.estimatedBandwidthMbps !=
            oldWidget.flow.estimatedBandwidthMbps) {
      final formatted = widget.flow.estimatedBandwidthMbps.toStringAsFixed(2);
      final currentParsed = double.tryParse(_mbpsCtrl.text.trim());
      if (idChanged || currentParsed != widget.flow.estimatedBandwidthMbps) {
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

  void _onProtocolChanged(TrafficProtocol? nextProto) {
    final flow = widget.flow;
    if (nextProto == null || nextProto == flow.protocol) return;
    final nextSacn = nextProto == TrafficProtocol.sacn
        ? (flow.sacnUniverseSpec?.trim().isNotEmpty == true
            ? flow.sacnUniverseSpec!.trim()
            : '1-4')
        : null;
    final parsedSacn = nextSacn != null
        ? MulticastStreamResolver.parseSacnUniverses(nextSacn)
        : null;
    final nextBw = nextProto == TrafficProtocol.sacn
        ? (parsedSacn != null &&
                parsedSacn.error == null &&
                parsedSacn.universes.isNotEmpty
            ? MulticastStreamResolver.sacnBandwidthMbps(
                parsedSacn.universes.length,
              )
            : 1.0)
        : nextProto.defaultUnitMbps;

    _sacnCtrl.text = nextSacn ?? '';
    if (nextProto == TrafficProtocol.sacn) {
      _mcastCtrl.text = '';
    }
    _mbpsCtrl.text = nextBw.toStringAsFixed(2);

    widget.onChanged(
      flow.copyWith(
        protocol: nextProto,
        deliveryType: nextProto.defaultDelivery,
        requiresIgmp: nextProto.defaultRequiresIgmp,
        defaultVlanId: nextProto.defaultVlan,
        estimatedBandwidthMbps: nextBw,
        sacnUniverseSpec: nextSacn,
        clearSacnUniverseSpec: nextProto != TrafficProtocol.sacn,
        clearMulticastGroupSpec: nextProto == TrafficProtocol.sacn,
      ),
    );
  }

  bool _isChipSelected(
    TrafficRequirement flow,
    AdvertisedTxStreamChip chip,
  ) {
    if (chip.sacnUniverseSpec != null) {
      final current = MulticastStreamResolver.parseSacnUniverses(
        flow.sacnUniverseSpec,
      ).universes.toSet();
      final chipUnivs = MulticastStreamResolver.parseSacnUniverses(
        chip.sacnUniverseSpec,
      ).universes;
      return chipUnivs.isNotEmpty && chipUnivs.every(current.contains);
    }
    if (chip.multicastGroupSpec != null) {
      final current = MulticastStreamResolver.parseMulticastGroups(
        flow.multicastGroupSpec,
      ).ips.toSet();
      final chipIps = MulticastStreamResolver.parseMulticastGroups(
        chip.multicastGroupSpec,
      ).ips;
      return chipIps.isNotEmpty && chipIps.every(current.contains);
    }
    return false;
  }

  void _toggleQuickPickChip(
    TrafficRequirement flow,
    AdvertisedTxStreamChip chip,
  ) {
    if (chip.sacnUniverseSpec != null) {
      _toggleSacnChip(flow, chip);
    } else if (chip.multicastGroupSpec != null) {
      _toggleMulticastGroupChip(flow, chip);
    }
  }

  void _toggleSacnChip(
    TrafficRequirement flow,
    AdvertisedTxStreamChip chip,
  ) {
    final currentParsed =
        MulticastStreamResolver.parseSacnUniverses(flow.sacnUniverseSpec);
    final chipParsed =
        MulticastStreamResolver.parseSacnUniverses(chip.sacnUniverseSpec);
    final current = currentParsed.error == null
        ? currentParsed.universes.toSet()
        : <int>{};
    final chipUnivs =
        chipParsed.error == null ? chipParsed.universes.toSet() : <int>{};
    if (chipUnivs.isEmpty) return;

    final allPresent = chipUnivs.every(current.contains);
    final mergedSet =
        allPresent ? current.difference(chipUnivs) : {...current, ...chipUnivs};
    final merged = mergedSet.toList()..sort();
    final nextSpec = MulticastStreamResolver.formatUniverseRanges(merged);
    final nextBw = merged.length * TrafficProtocol.sacn.defaultUnitMbps;

    _sacnCtrl.text = nextSpec;
    _mbpsCtrl.text = nextBw.toStringAsFixed(2);
    widget.onChanged(
      flow.copyWith(
        sacnUniverseSpec: nextSpec,
        clearSacnUniverseSpec: nextSpec.isEmpty,
        estimatedBandwidthMbps: nextBw,
      ),
    );
  }

  void _toggleMulticastGroupChip(
    TrafficRequirement flow,
    AdvertisedTxStreamChip chip,
  ) {
    final currentParsed =
        MulticastStreamResolver.parseMulticastGroups(flow.multicastGroupSpec);
    final chipParsed =
        MulticastStreamResolver.parseMulticastGroups(chip.multicastGroupSpec);
    final current = currentParsed.error == null
        ? List<String>.from(currentParsed.ips)
        : <String>[];
    final chipIps =
        chipParsed.error == null ? chipParsed.ips : const <String>[];
    if (chipIps.isEmpty) return;

    final currentSet = current.toSet();
    final allPresent = chipIps.every(currentSet.contains);
    final List<String> merged;
    final double nextBw;

    if (allPresent) {
      final chipSet = chipIps.toSet();
      merged = [
        for (final ip in current)
          if (!chipSet.contains(ip)) ip,
      ];
      nextBw = merged.isEmpty
          ? 0.0
          : (flow.estimatedBandwidthMbps - chip.bandwidthMbps)
              .clamp(0.0, 100000.0);
    } else {
      final seen = <String>{...current};
      merged = [...current];
      var addedCount = 0;
      for (final ip in chipIps) {
        if (seen.add(ip)) {
          merged.add(ip);
          addedCount++;
        }
      }
      if (current.isEmpty) {
        nextBw = chip.bandwidthMbps;
      } else {
        nextBw = (flow.estimatedBandwidthMbps +
                chip.bandwidthMbps * (addedCount / chipIps.length))
            .clamp(0.0, 100000.0);
      }
    }

    final nextSpec = _formatMulticastGroupRanges(merged);
    _mcastCtrl.text = nextSpec;
    _mbpsCtrl.text = nextBw.toStringAsFixed(2);
    widget.onChanged(
      flow.copyWith(
        multicastGroupSpec: nextSpec,
        clearMulticastGroupSpec: nextSpec.isEmpty,
        estimatedBandwidthMbps: nextBw,
      ),
    );
  }

  static String _formatMulticastGroupRanges(List<String> ips) {
    if (ips.isEmpty) return '';
    final unique = ips.toSet().toList();
    final parsed = <({String prefix, int last, String raw})>[];
    for (final ip in unique) {
      final parts = ip.split('.');
      if (parts.length == 4) {
        final last = int.tryParse(parts[3]);
        if (last != null) {
          parsed.add((
            prefix: '${parts[0]}.${parts[1]}.${parts[2]}',
            last: last,
            raw: ip,
          ));
          continue;
        }
      }
      parsed.add((prefix: '', last: -1, raw: ip));
    }

    parsed.sort((a, b) {
      final pCmp = a.prefix.compareTo(b.prefix);
      if (pCmp != 0) return pCmp;
      return a.last.compareTo(b.last);
    });

    final tokens = <String>[];
    var i = 0;
    while (i < parsed.length) {
      final start = parsed[i];
      if (start.last < 0) {
        tokens.add(start.raw);
        i++;
        continue;
      }
      var end = start;
      var j = i + 1;
      while (j < parsed.length &&
          parsed[j].prefix == start.prefix &&
          parsed[j].last == end.last + 1) {
        end = parsed[j];
        j++;
      }
      tokens.add(
        end.last == start.last ? start.raw : '${start.raw}-${end.last}',
      );
      i = j;
    }
    return tokens.join(', ');
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
    final rxQuickPicks = (flow.direction.isSubscriber &&
            flow.deliveryType == DeliveryType.multicast)
        ? vm.advertisedTxStreamChipsForVlan(
            widget.effectiveVlan,
            flow.protocol,
            excludeEndpointId: ep.id,
          )
        : const <AdvertisedTxStreamChip>[];

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
                flex: 3,
                child: DropdownButtonFormField<TrafficProtocol>(
                  key: ValueKey(
                    'flow-proto-${ep.id}-${flow.id}-${flow.protocol.name}',
                  ),
                  initialValue: flow.protocol,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Protocol'),
                  dropdownColor: AppTheme.surfaceElevated,
                  style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                  items: TrafficProtocol.values
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            p.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _onProtocolChanged,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<TrafficDirection>(
                  key: ValueKey(
                    'flow-dir-${ep.id}-${flow.id}-${flow.direction.name}',
                  ),
                  initialValue: flow.direction,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Direction'),
                  dropdownColor: AppTheme.surfaceElevated,
                  style: TextStyle(fontSize: 11, color: AppTheme.textPrimary),
                  items: TrafficDirection.values
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text(
                            d.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (dir) {
                    if (dir != null) {
                      widget.onChanged(flow.copyWith(direction: dir));
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<int>(
                  key: ValueKey(
                    'flow-vlan-${ep.id}-${flow.id}-${flow.defaultVlanId}',
                  ),
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
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            vm.formatVlanDisplay(v),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      widget.onChanged(flow.copyWith(defaultVlanId: v));
                    }
                  },
                ),
              ),
              if (effectivePorts.length > 1) ...[
                const SizedBox(width: 6),
                Expanded(
                  flex: 2,
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
              ],
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
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
                  Builder(
                    builder: (context) {
                      final active = _isChipSelected(flow, chip);
                      final chipColor =
                          active ? AppTheme.success : AppTheme.accent;
                      return ActionChip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor:
                            chipColor.withValues(alpha: active ? 0.2 : 0.12),
                        side: BorderSide(
                          color:
                              chipColor.withValues(alpha: active ? 0.8 : 0.45),
                        ),
                        label: Text(
                          chip.summaryLabel,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 9.5,
                            fontWeight:
                                active ? FontWeight.bold : FontWeight.normal,
                            color: chipColor,
                          ),
                        ),
                        onPressed: () => _toggleQuickPickChip(flow, chip),
                      );
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
