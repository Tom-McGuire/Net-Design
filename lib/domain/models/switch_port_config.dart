import 'enums.dart';

/// Per-port physical and VLAN configuration on a placed switch node.
class SwitchPortConfig {
  SwitchPortConfig({
    required this.portNumber,
    this.customLabel,
    this.maxSpeed = PortSpeed.speed1G,
    this.poeCapable = false,
    this.poeEnabled = false,
    this.portMode = SwitchPortMode.access,
    this.nativeVlan = 1,
    Set<int>? allowedVlans,
    this.lagGroupId,
  }) : allowedVlans = allowedVlans ?? {1};

  final int portNumber;
  final String? customLabel;
  final PortSpeed maxSpeed;
  final bool poeCapable;
  final bool poeEnabled;
  final SwitchPortMode portMode;
  final int nativeVlan;
  final Set<int> allowedVlans;
  final int? lagGroupId;

  String get displayName =>
      (customLabel != null && customLabel!.trim().isNotEmpty)
          ? customLabel!.trim()
          : 'Port $portNumber';

  /// Effective set of VLANs permitted to ingress/egress this port.
  Set<int> effectiveVlans({bool switchSupportsVlans = true}) {
    if (!switchSupportsVlans) {
      return {nativeVlan};
    }
    if (portMode == SwitchPortMode.access) {
      return {nativeVlan};
    }
    return Set<int>.unmodifiable(allowedVlans);
  }

  /// Whether [vlanId] is permitted on this port.
  bool permitsVlan(int vlanId, {bool switchSupportsVlans = true}) {
    if (!switchSupportsVlans) {
      return true;
    }
    if (portMode == SwitchPortMode.access) {
      return nativeVlan == vlanId;
    }
    return allowedVlans.contains(vlanId);
  }

  SwitchPortConfig copyWith({
    int? portNumber,
    String? customLabel,
    bool clearCustomLabel = false,
    PortSpeed? maxSpeed,
    bool? poeCapable,
    bool? poeEnabled,
    SwitchPortMode? portMode,
    int? nativeVlan,
    Set<int>? allowedVlans,
    int? lagGroupId,
    bool clearLagGroupId = false,
  }) {
    return SwitchPortConfig(
      portNumber: portNumber ?? this.portNumber,
      customLabel: clearCustomLabel ? null : (customLabel ?? this.customLabel),
      maxSpeed: maxSpeed ?? this.maxSpeed,
      poeCapable: poeCapable ?? this.poeCapable,
      poeEnabled: poeEnabled ?? this.poeEnabled,
      portMode: portMode ?? this.portMode,
      nativeVlan: nativeVlan ?? this.nativeVlan,
      allowedVlans: allowedVlans != null ? Set<int>.from(allowedVlans) : Set<int>.from(this.allowedVlans),
      lagGroupId: clearLagGroupId ? null : (lagGroupId ?? this.lagGroupId),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'portNumber': portNumber,
      if (customLabel != null) 'customLabel': customLabel,
      'maxSpeed': maxSpeed.toJson(),
      'poeCapable': poeCapable,
      'poeEnabled': poeEnabled,
      'portMode': portMode.toJson(),
      'nativeVlan': nativeVlan,
      'allowedVlans': (allowedVlans.toList()..sort()),
      if (lagGroupId != null) 'lagGroupId': lagGroupId,
    };
  }

  factory SwitchPortConfig.fromJson(Map<String, dynamic> json) {
    final rawAllowed = json['allowedVlans'];
    final parsedAllowed = <int>{};
    if (rawAllowed is List) {
      for (final item in rawAllowed) {
        if (item is num) {
          final v = item.toInt();
          if (v >= 1 && v <= 4094) parsedAllowed.add(v);
        }
      }
    }
    final nativeVlan = (json['nativeVlan'] is num)
        ? (json['nativeVlan'] as num).toInt().clamp(1, 4094)
        : 1;
    if (parsedAllowed.isEmpty) {
      parsedAllowed.add(nativeVlan);
    }

    return SwitchPortConfig(
      portNumber: (json['portNumber'] is num)
          ? (json['portNumber'] as num).toInt().clamp(1, 512)
          : 1,
      customLabel:
          json['customLabel'] is String ? json['customLabel'] as String : null,
      maxSpeed: PortSpeed.fromJson(json['maxSpeed']),
      poeCapable: json['poeCapable'] == true,
      poeEnabled: json['poeEnabled'] == true,
      portMode: SwitchPortMode.fromJson(json['portMode']),
      nativeVlan: nativeVlan,
      allowedVlans: parsedAllowed,
      lagGroupId: (json['lagGroupId'] is num)
          ? (json['lagGroupId'] as num).toInt()
          : null,
    );
  }
}
