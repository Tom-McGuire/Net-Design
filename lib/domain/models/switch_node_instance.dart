import 'dart:math';

import 'enums.dart';
import 'switch_port_config.dart';

/// Per-VLAN IGMP Snooping and Querier configuration on a switch.
class SwitchVlanSettings {
  const SwitchVlanSettings({
    required this.vlanId,
    required this.vlanName,
    this.igmpSnoopingEnabled = false,
    this.igmpQuerierEnabled = false,
    this.igmpQuerierVersion = IgmpVersion.v2,
    this.dropUnregisteredMulticast = true,
  });

  final int vlanId;
  final String vlanName;
  final bool igmpSnoopingEnabled;
  final bool igmpQuerierEnabled;
  final IgmpVersion igmpQuerierVersion;
  final bool dropUnregisteredMulticast;

  SwitchVlanSettings copyWith({
    int? vlanId,
    String? vlanName,
    bool? igmpSnoopingEnabled,
    bool? igmpQuerierEnabled,
    IgmpVersion? igmpQuerierVersion,
    bool? dropUnregisteredMulticast,
  }) {
    return SwitchVlanSettings(
      vlanId: vlanId ?? this.vlanId,
      vlanName: vlanName ?? this.vlanName,
      igmpSnoopingEnabled: igmpSnoopingEnabled ?? this.igmpSnoopingEnabled,
      igmpQuerierEnabled: igmpQuerierEnabled ?? this.igmpQuerierEnabled,
      igmpQuerierVersion: igmpQuerierVersion ?? this.igmpQuerierVersion,
      dropUnregisteredMulticast:
          dropUnregisteredMulticast ?? this.dropUnregisteredMulticast,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'vlanId': vlanId,
      'vlanName': vlanName,
      'igmpSnoopingEnabled': igmpSnoopingEnabled,
      'igmpQuerierEnabled': igmpQuerierEnabled,
      'igmpQuerierVersion': igmpQuerierVersion.toJson(),
      'dropUnregisteredMulticast': dropUnregisteredMulticast,
    };
  }

  factory SwitchVlanSettings.fromJson(Map<String, dynamic> json) {
    return SwitchVlanSettings(
      vlanId: (json['vlanId'] is num)
          ? (json['vlanId'] as num).toInt().clamp(1, 4094)
          : 1,
      vlanName: json['vlanName'] is String ? json['vlanName'] as String : 'VLAN',
      igmpSnoopingEnabled: json['igmpSnoopingEnabled'] == true,
      igmpQuerierEnabled: json['igmpQuerierEnabled'] == true,
      igmpQuerierVersion: IgmpVersion.fromJson(json['igmpQuerierVersion']),
      dropUnregisteredMulticast: json['dropUnregisteredMulticast'] != false,
    );
  }
}

/// Switch instance placed on the topology design canvas.
class SwitchNodeInstance {
  SwitchNodeInstance({
    required this.id,
    required this.templateId,
    required this.userLabel,
    required this.macAddress,
    this.managementIp,
    this.stpMode = StpMode.rstp,
    this.stpPriority = 32768,
    this.poeBudgetWatts = 0,
    this.supportsStp = true,
    this.supportsVlans = true,
    this.supportsIgmpSnooping = true,
    this.supportsIgmpQuerier = true,
    Map<int, SwitchVlanSettings>? vlanConfigs,
    List<SwitchPortConfig>? ports,
    this.dx = 120.0,
    this.dy = 120.0,
    this.isRootBridge = false,
    this.rootPathCost = 0,
    this.hopDepthFromRoot = 0,
    Set<int>? activeQuerierVlans,
    this.totalPoeDrawWatts = 0.0,
  })  : vlanConfigs = vlanConfigs ??
            {
              1: const SwitchVlanSettings(vlanId: 1, vlanName: 'Default / Mgmt'),
            },
        ports = ports ?? [],
        activeQuerierVlans = activeQuerierVlans ?? {};

  final String id;
  final String templateId;
  final String userLabel;
  final String macAddress;
  final String? managementIp;
  final StpMode stpMode;

  /// IEEE 802.1D priority (0..61440 in increments of 4096, default 32768).
  final int stpPriority;
  final int poeBudgetWatts;
  final bool supportsStp;
  final bool supportsVlans;
  final bool supportsIgmpSnooping;
  final bool supportsIgmpQuerier;
  final Map<int, SwitchVlanSettings> vlanConfigs;
  final List<SwitchPortConfig> ports;
  final double dx;
  final double dy;

  // --- Computed Simulation Outputs ---
  bool isRootBridge;
  int rootPathCost;
  int hopDepthFromRoot;
  Set<int> activeQuerierVlans;
  double totalPoeDrawWatts;

  bool get isStpActive => supportsStp && stpMode != StpMode.disabled;

  int get macAddressInt => parseMacToInt(macAddress);

  String get bridgeIdHex {
    final prioHex = stpPriority.toRadixString(16).toUpperCase().padLeft(4, '0');
    final macClean = macAddress.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase().padLeft(12, '0');
    return '$prioHex.$macClean';
  }

  /// Compares two switches by IEEE 802.1D/1w Bridge ID without signed 64-bit overflow.
  int compareBridgeId(SwitchNodeInstance other) {
    final prioCmp = stpPriority.compareTo(other.stpPriority);
    if (prioCmp != 0) return prioCmp;
    final macCmp = macAddressInt.compareTo(other.macAddressInt);
    if (macCmp != 0) return macCmp;
    return id.compareTo(other.id);
  }

  SwitchPortConfig? portByNumber(int portNumber) {
    for (final p in ports) {
      if (p.portNumber == portNumber) return p;
    }
    return null;
  }

  /// Summarizes port counts by speed tier and media type
  /// (e.g. `['8x 1G', '2x 10G SFP+']`).
  List<String> get portSummaryPills {
    final rj45Counts = <PortSpeed, int>{};
    final sfpCounts = <PortSpeed, int>{};
    for (final p in ports) {
      if (p.mediaType == PortMediaType.sfpFibre) {
        sfpCounts[p.maxSpeed] = (sfpCounts[p.maxSpeed] ?? 0) + 1;
      } else {
        rj45Counts[p.maxSpeed] = (rj45Counts[p.maxSpeed] ?? 0) + 1;
      }
    }
    return [
      for (final speed in PortSpeed.values)
        if ((rj45Counts[speed] ?? 0) > 0) '${rj45Counts[speed]}x ${speed.label}',
      for (final speed in PortMediaType.sfpFibre.allowedSpeeds)
        if ((sfpCounts[speed] ?? 0) > 0)
          '${sfpCounts[speed]}x ${speed == PortSpeed.speed10G ? "10G SFP+" : "${speed.label} SFP"}',
    ];
  }

  void resetSimulationState() {
    isRootBridge = false;
    rootPathCost = 0;
    hopDepthFromRoot = 0;
    activeQuerierVlans.clear();
    totalPoeDrawWatts = 0.0;
  }

  /// Normalizes any 12-hex-digit MAC (colon, dash, Cisco dot, or raw hex) to
  /// uppercase `XX:XX:XX:XX:XX:XX`, or returns `null` if invalid/incomplete.
  static String? normalizeMac(String input) {
    final cleaned = input.replaceAll(RegExp(r'[:\-\.\s]'), '').toUpperCase();
    if (!RegExp(r'^[0-9A-F]{12}$').hasMatch(cleaned)) return null;
    return [
      for (var i = 0; i < 12; i += 2) cleaned.substring(i, i + 2),
    ].join(':');
  }

  static int parseMacToInt(String mac) {
    final cleaned = mac.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    if (cleaned.isEmpty) return 0;
    final truncated = cleaned.length > 12 ? cleaned.substring(0, 12) : cleaned;
    return int.tryParse(truncated, radix: 16) ?? 0;
  }

  static String generateRandomLocalMac([Random? rng]) {
    final r = rng ?? Random();
    // Locally administered unicast OUI prefix: 02:xx:xx:xx:xx:xx
    final bytes = [
      0x02,
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
      r.nextInt(256),
    ];
    return bytes
        .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
        .join(':');
  }

  static int parseIpToInt(String? ip) {
    if (ip == null || ip.trim().isEmpty) return 0xFFFFFFFF;
    final parts = ip.trim().split('.');
    if (parts.length != 4) return 0xFFFFFFFF;
    var val = 0;
    for (final part in parts) {
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) return 0xFFFFFFFF;
      val = (val << 8) | octet;
    }
    return val;
  }

  SwitchNodeInstance copyWith({
    String? id,
    String? templateId,
    String? userLabel,
    String? macAddress,
    String? managementIp,
    bool clearManagementIp = false,
    StpMode? stpMode,
    int? stpPriority,
    int? poeBudgetWatts,
    bool? supportsStp,
    bool? supportsVlans,
    bool? supportsIgmpSnooping,
    bool? supportsIgmpQuerier,
    Map<int, SwitchVlanSettings>? vlanConfigs,
    List<SwitchPortConfig>? ports,
    double? dx,
    double? dy,
  }) {
    return SwitchNodeInstance(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      userLabel: userLabel ?? this.userLabel,
      macAddress: macAddress ?? this.macAddress,
      managementIp:
          clearManagementIp ? null : (managementIp ?? this.managementIp),
      stpMode: stpMode ?? this.stpMode,
      stpPriority: stpPriority ?? this.stpPriority,
      poeBudgetWatts: poeBudgetWatts ?? this.poeBudgetWatts,
      supportsStp: supportsStp ?? this.supportsStp,
      supportsVlans: supportsVlans ?? this.supportsVlans,
      supportsIgmpSnooping: supportsIgmpSnooping ?? this.supportsIgmpSnooping,
      supportsIgmpQuerier: supportsIgmpQuerier ?? this.supportsIgmpQuerier,
      vlanConfigs: vlanConfigs != null
          ? Map<int, SwitchVlanSettings>.from(vlanConfigs)
          : Map<int, SwitchVlanSettings>.from(this.vlanConfigs),
      ports: ports != null
          ? List<SwitchPortConfig>.from(ports)
          : List<SwitchPortConfig>.from(this.ports),
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
      isRootBridge: isRootBridge,
      rootPathCost: rootPathCost,
      hopDepthFromRoot: hopDepthFromRoot,
      activeQuerierVlans: Set<int>.from(activeQuerierVlans),
      totalPoeDrawWatts: totalPoeDrawWatts,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'templateId': templateId,
      'userLabel': userLabel,
      'macAddress': macAddress,
      if (managementIp != null) 'managementIp': managementIp,
      'stpMode': stpMode.toJson(),
      'stpPriority': stpPriority,
      'poeBudgetWatts': poeBudgetWatts,
      'supportsStp': supportsStp,
      'supportsVlans': supportsVlans,
      'supportsIgmpSnooping': supportsIgmpSnooping,
      'supportsIgmpQuerier': supportsIgmpQuerier,
      'vlanConfigs': {
        for (final entry in vlanConfigs.entries)
          entry.key.toString(): entry.value.toJson(),
      },
      'ports': ports.map((p) => p.toJson()).toList(),
      'dx': dx,
      'dy': dy,
    };
  }

  factory SwitchNodeInstance.fromJson(Map<String, dynamic> json) {
    final rawVlans = json['vlanConfigs'];
    final parsedVlans = <int, SwitchVlanSettings>{};
    if (rawVlans is Map) {
      for (final entry in rawVlans.entries) {
        final k = int.tryParse(entry.key.toString());
        if (k != null && entry.value is Map) {
          parsedVlans[k] = SwitchVlanSettings.fromJson(
            Map<String, dynamic>.from(entry.value as Map),
          );
        }
      }
    }
    if (parsedVlans.isEmpty) {
      parsedVlans[1] =
          const SwitchVlanSettings(vlanId: 1, vlanName: 'Default / Mgmt');
    }

    final rawPorts = json['ports'];
    final parsedPorts = <SwitchPortConfig>[];
    if (rawPorts is List) {
      for (final item in rawPorts) {
        if (item is Map) {
          parsedPorts.add(
            SwitchPortConfig.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final rawPrio = (json['stpPriority'] is num)
        ? (json['stpPriority'] as num).toInt()
        : 32768;
    // Normalize priority to 4096 step within [0..61440]
    final normalizedPrio = ((rawPrio.clamp(0, 61440) / 4096).round() * 4096)
        .clamp(0, 61440);

    return SwitchNodeInstance(
      id: json['id'] is String ? json['id'] as String : 'sw-1',
      templateId:
          json['templateId'] is String ? json['templateId'] as String : 'tpl-sw',
      userLabel:
          json['userLabel'] is String ? json['userLabel'] as String : 'Switch',
      macAddress: json['macAddress'] is String
          ? json['macAddress'] as String
          : '02:00:00:00:00:01',
      managementIp:
          json['managementIp'] is String ? json['managementIp'] as String : null,
      stpMode: StpMode.fromJson(json['stpMode']),
      stpPriority: normalizedPrio,
      poeBudgetWatts: (json['poeBudgetWatts'] is num)
          ? (json['poeBudgetWatts'] as num).toInt().clamp(0, 5000)
          : 0,
      supportsStp: json['supportsStp'] != false,
      supportsVlans: json['supportsVlans'] != false,
      supportsIgmpSnooping: json['supportsIgmpSnooping'] != false,
      supportsIgmpQuerier: json['supportsIgmpQuerier'] != false,
      vlanConfigs: parsedVlans,
      ports: parsedPorts,
      dx: (json['dx'] is num) ? (json['dx'] as num).toDouble() : 120.0,
      dy: (json['dy'] is num) ? (json['dy'] as num).toDouble() : 120.0,
    );
  }
}
