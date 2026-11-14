import 'enums.dart';
import 'switch_port_config.dart';

/// Vendor-neutral blueprint defining physical port tiers, PoE budget,
/// and L2 protocol capabilities for a reusable switch template.
class SwitchTemplate {
  SwitchTemplate({
    required this.id,
    required this.name,
    this.ports100M = 0,
    this.ports1G = 8,
    this.ports2_5G = 0,
    this.ports5G = 0,
    this.ports10G = 0,
    this.sfpPorts1G = 0,
    this.sfpPorts10G = 0,
    this.poeBudgetWatts = 0,
    this.poeStartPort,
    this.poeEndPort,
    this.supportsStp = true,
    this.supportsVlans = true,
    this.supportsIgmpSnooping = true,
    this.supportsIgmpQuerier = true,
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final int ports100M;
  final int ports1G;
  final int ports2_5G;
  final int ports5G;
  final int ports10G;
  final int sfpPorts1G;
  final int sfpPorts10G;
  final int poeBudgetWatts;
  final int? poeStartPort;
  final int? poeEndPort;
  final bool supportsStp;
  final bool supportsVlans;
  final bool supportsIgmpSnooping;
  final bool supportsIgmpQuerier;
  final bool isBuiltIn;

  int get rj45PortCount =>
      ports100M + ports1G + ports2_5G + ports5G + ports10G;

  int get sfpPortCount => sfpPorts1G + sfpPorts10G;

  int get totalPorts => rj45PortCount + sfpPortCount;

  /// Human-readable summary pills such as `['8x 1G', '2x 10G SFP+']`.
  List<String> get summaryPills {
    final pills = <String>[];
    if (ports100M > 0) pills.add('${ports100M}x 100M');
    if (ports1G > 0) pills.add('${ports1G}x 1G');
    if (ports2_5G > 0) pills.add('${ports2_5G}x 2.5G');
    if (ports5G > 0) pills.add('${ports5G}x 5G');
    if (ports10G > 0) pills.add('${ports10G}x 10G');
    if (sfpPorts1G > 0) pills.add('${sfpPorts1G}x 1G SFP');
    if (sfpPorts10G > 0) pills.add('${sfpPorts10G}x 10G SFP+');
    return pills;
  }

  String get summaryString =>
      summaryPills.isEmpty ? '0 Ports' : summaryPills.join(' • ');

  /// Generates sequential logical ports (`Port 1..N`) with RJ45 copper bays
  /// first (with optional PoE eligibility) followed by SFP/Fibre slots (no PoE).
  List<SwitchPortConfig> generateDefaultPorts() {
    final rj45Tiers = <(int, PortSpeed)>[
      (ports100M, PortSpeed.speed100M),
      (ports1G, PortSpeed.speed1G),
      (ports2_5G, PortSpeed.speed2_5G),
      (ports5G, PortSpeed.speed5G),
      (ports10G, PortSpeed.speed10G),
    ];

    final result = <SwitchPortConfig>[];
    var portNum = 1;
    for (final (count, speed) in rj45Tiers) {
      for (var i = 0; i < count; i++) {
        final hasPoeRange = poeBudgetWatts > 0 &&
            (poeStartPort == null || portNum >= poeStartPort!) &&
            (poeEndPort == null || portNum <= poeEndPort!);
        result.add(
          SwitchPortConfig(
            portNumber: portNum,
            mediaType: PortMediaType.rj45,
            maxSpeed: speed,
            poeCapable: hasPoeRange,
            poeEnabled: hasPoeRange,
            portMode: SwitchPortMode.access,
            nativeVlan: 1,
            allowedVlans: {1},
          ),
        );
        portNum++;
      }
    }

    final sfpTiers = <(int, PortSpeed)>[
      (sfpPorts1G, PortSpeed.speed1G),
      (sfpPorts10G, PortSpeed.speed10G),
    ];
    for (final (count, speed) in sfpTiers) {
      for (var i = 0; i < count; i++) {
        result.add(
          SwitchPortConfig(
            portNumber: portNum,
            mediaType: PortMediaType.sfpFibre,
            maxSpeed: speed,
            poeCapable: false,
            poeEnabled: false,
            portMode: SwitchPortMode.access,
            nativeVlan: 1,
            allowedVlans: {1},
          ),
        );
        portNum++;
      }
    }
    return result;
  }

  SwitchTemplate copyWith({
    String? id,
    String? name,
    int? ports100M,
    int? ports1G,
    int? ports2_5G,
    int? ports5G,
    int? ports10G,
    int? sfpPorts1G,
    int? sfpPorts10G,
    int? poeBudgetWatts,
    int? poeStartPort,
    int? poeEndPort,
    bool clearPoeRange = false,
    bool? supportsStp,
    bool? supportsVlans,
    bool? supportsIgmpSnooping,
    bool? supportsIgmpQuerier,
    bool? isBuiltIn,
  }) {
    return SwitchTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      ports100M: ports100M ?? this.ports100M,
      ports1G: ports1G ?? this.ports1G,
      ports2_5G: ports2_5G ?? this.ports2_5G,
      ports5G: ports5G ?? this.ports5G,
      ports10G: ports10G ?? this.ports10G,
      sfpPorts1G: sfpPorts1G ?? this.sfpPorts1G,
      sfpPorts10G: sfpPorts10G ?? this.sfpPorts10G,
      poeBudgetWatts: poeBudgetWatts ?? this.poeBudgetWatts,
      poeStartPort: clearPoeRange ? null : (poeStartPort ?? this.poeStartPort),
      poeEndPort: clearPoeRange ? null : (poeEndPort ?? this.poeEndPort),
      supportsStp: supportsStp ?? this.supportsStp,
      supportsVlans: supportsVlans ?? this.supportsVlans,
      supportsIgmpSnooping: supportsIgmpSnooping ?? this.supportsIgmpSnooping,
      supportsIgmpQuerier: supportsIgmpQuerier ?? this.supportsIgmpQuerier,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ports100M': ports100M,
      'ports1G': ports1G,
      'ports2_5G': ports2_5G,
      'ports5G': ports5G,
      'ports10G': ports10G,
      'sfpPorts1G': sfpPorts1G,
      'sfpPorts10G': sfpPorts10G,
      'poeBudgetWatts': poeBudgetWatts,
      if (poeStartPort != null) 'poeStartPort': poeStartPort,
      if (poeEndPort != null) 'poeEndPort': poeEndPort,
      'supportsStp': supportsStp,
      'supportsVlans': supportsVlans,
      'supportsIgmpSnooping': supportsIgmpSnooping,
      'supportsIgmpQuerier': supportsIgmpQuerier,
      'isBuiltIn': isBuiltIn,
    };
  }

  factory SwitchTemplate.fromJson(Map<String, dynamic> json) {
    int clampCount(Object? v) => (v is num) ? v.toInt().clamp(0, 128) : 0;
    return SwitchTemplate(
      id: json['id'] is String ? json['id'] as String : 'switch-tpl',
      name: json['name'] is String ? json['name'] as String : 'Generic Switch',
      ports100M: clampCount(json['ports100M']),
      ports1G: clampCount(json['ports1G']),
      ports2_5G: clampCount(json['ports2_5G']),
      ports5G: clampCount(json['ports5G']),
      ports10G: clampCount(json['ports10G']),
      sfpPorts1G: clampCount(json['sfpPorts1G']),
      sfpPorts10G: clampCount(json['sfpPorts10G']),
      poeBudgetWatts: (json['poeBudgetWatts'] is num)
          ? (json['poeBudgetWatts'] as num).toInt().clamp(0, 5000)
          : 0,
      poeStartPort: (json['poeStartPort'] is num)
          ? (json['poeStartPort'] as num).toInt()
          : null,
      poeEndPort: (json['poeEndPort'] is num)
          ? (json['poeEndPort'] as num).toInt()
          : null,
      supportsStp: json['supportsStp'] != false,
      supportsVlans: json['supportsVlans'] != false,
      supportsIgmpSnooping: json['supportsIgmpSnooping'] != false,
      supportsIgmpQuerier: json['supportsIgmpQuerier'] != false,
      isBuiltIn: json['isBuiltIn'] == true,
    );
  }
}
