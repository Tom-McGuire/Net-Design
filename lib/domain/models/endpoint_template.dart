import 'enums.dart';

/// Physical network interface port definition on an endpoint device.
class EndpointPortConfig {
  const EndpointPortConfig({
    required this.portNumber,
    this.label,
    this.mediaType = PortMediaType.rj45,
    this.speed = PortSpeed.speed1G,
    this.poeDrawWatts = 0.0,
  });

  final int portNumber;
  final String? label;
  final PortMediaType mediaType;
  final PortSpeed speed;
  final double poeDrawWatts;

  PortSpeed get effectiveSpeed => mediaType.normalizeSpeed(speed);

  double get effectivePoeDrawWatts =>
      mediaType == PortMediaType.rj45 ? poeDrawWatts : 0.0;

  String get mediaSpeedLabel {
    final s = effectiveSpeed;
    if (mediaType == PortMediaType.sfpFibre) {
      return s == PortSpeed.speed10G ? '10G SFP+' : '${s.label} SFP';
    }
    return '${s.label} RJ45';
  }

  String get displayName {
    final trimmed = label?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return 'P$portNumber ($trimmed)';
    }
    return 'Port $portNumber';
  }

  String get shortBadge => 'P$portNumber $mediaSpeedLabel';

  EndpointPortConfig copyWith({
    int? portNumber,
    String? label,
    bool clearLabel = false,
    PortMediaType? mediaType,
    PortSpeed? speed,
    double? poeDrawWatts,
  }) {
    final nextMedia = mediaType ?? this.mediaType;
    final nextSpeed = nextMedia.normalizeSpeed(speed ?? this.speed);
    final nextPoe = nextMedia == PortMediaType.rj45
        ? (poeDrawWatts ?? this.poeDrawWatts)
        : 0.0;
    return EndpointPortConfig(
      portNumber: portNumber ?? this.portNumber,
      label: clearLabel ? null : (label ?? this.label),
      mediaType: nextMedia,
      speed: nextSpeed,
      poeDrawWatts: nextPoe,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'portNumber': portNumber,
      if (label != null && label!.trim().isNotEmpty) 'label': label!.trim(),
      'mediaType': mediaType.toJson(),
      'speed': effectiveSpeed.toJson(),
      'poeDrawWatts': effectivePoeDrawWatts,
    };
  }

  factory EndpointPortConfig.fromJson(Map<String, dynamic> json) {
    final media = PortMediaType.fromJson(json['mediaType']);
    final rawSpeed = PortSpeed.fromJson(json['speed']);
    final poe = (json['poeDrawWatts'] is num)
        ? (json['poeDrawWatts'] as num).toDouble().clamp(0.0, 200.0)
        : 0.0;
    return EndpointPortConfig(
      portNumber: (json['portNumber'] is num)
          ? (json['portNumber'] as num).toInt().clamp(1, 64)
          : 1,
      label: json['label'] is String ? json['label'] as String : null,
      mediaType: media,
      speed: media.normalizeSpeed(rawSpeed),
      poeDrawWatts: media == PortMediaType.rj45 ? poe : 0.0,
    );
  }
}

/// Describes a single protocol traffic flow produced or consumed by an endpoint.
class TrafficRequirement {
  const TrafficRequirement({
    required this.id,
    required this.protocol,
    required this.direction,
    required this.deliveryType,
    required this.estimatedBandwidthMbps,
    required this.requiresIgmp,
    required this.defaultVlanId,
    this.label,
    this.boundPortNumber,
    this.sacnUniverseSpec,
    this.multicastGroupSpec,
  });

  final String id;
  final TrafficProtocol protocol;
  final TrafficDirection direction;
  final DeliveryType deliveryType;
  final double estimatedBandwidthMbps;
  final bool requiresIgmp;
  final int defaultVlanId;
  final String? label;

  /// Endpoint NIC port number (`1..N`) carrying this flow. Null defaults to Port 1.
  final int? boundPortNumber;

  /// Optional sACN universe list/range spec (e.g., `"1-8, 20"`).
  final String? sacnUniverseSpec;

  /// Optional multicast IPv4 address/range spec (e.g., `"239.69.0.1-4"`).
  final String? multicastGroupSpec;

  int get effectivePortNumber =>
      (boundPortNumber != null && boundPortNumber! >= 1) ? boundPortNumber! : 1;

  String get displayPill {
    final prefix = label != null && label!.trim().isNotEmpty
        ? label!.trim()
        : protocol.label;
    final dirTag = switch (direction) {
      TrafficDirection.txPublisher => 'TX',
      TrafficDirection.rxSubscriber => 'RX',
      TrafficDirection.bidirectional => 'TX/RX',
    };
    final streamTag = protocol == TrafficProtocol.sacn &&
            sacnUniverseSpec != null &&
            sacnUniverseSpec!.trim().isNotEmpty
        ? ' U${sacnUniverseSpec!.trim()}'
        : (multicastGroupSpec != null && multicastGroupSpec!.trim().isNotEmpty
            ? ' ${multicastGroupSpec!.trim()}'
            : '');
    final portTag = effectivePortNumber > 1 ? ' • P$effectivePortNumber' : '';
    final bwStr = estimatedBandwidthMbps >= 10
        ? estimatedBandwidthMbps.toStringAsFixed(0)
        : estimatedBandwidthMbps
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'\.?0+$'), '');
    return '$prefix $dirTag$streamTag ($bwStr Mbps • V$defaultVlanId$portTag)';
  }

  TrafficRequirement copyWith({
    String? id,
    TrafficProtocol? protocol,
    TrafficDirection? direction,
    DeliveryType? deliveryType,
    double? estimatedBandwidthMbps,
    bool? requiresIgmp,
    int? defaultVlanId,
    String? label,
    int? boundPortNumber,
    String? sacnUniverseSpec,
    bool clearSacnUniverseSpec = false,
    String? multicastGroupSpec,
    bool clearMulticastGroupSpec = false,
  }) {
    return TrafficRequirement(
      id: id ?? this.id,
      protocol: protocol ?? this.protocol,
      direction: direction ?? this.direction,
      deliveryType: deliveryType ?? this.deliveryType,
      estimatedBandwidthMbps:
          estimatedBandwidthMbps ?? this.estimatedBandwidthMbps,
      requiresIgmp: requiresIgmp ?? this.requiresIgmp,
      defaultVlanId: defaultVlanId ?? this.defaultVlanId,
      label: label ?? this.label,
      boundPortNumber: boundPortNumber ?? this.boundPortNumber,
      sacnUniverseSpec: clearSacnUniverseSpec
          ? null
          : (sacnUniverseSpec ?? this.sacnUniverseSpec),
      multicastGroupSpec: clearMulticastGroupSpec
          ? null
          : (multicastGroupSpec ?? this.multicastGroupSpec),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'protocol': protocol.toJson(),
      'direction': direction.toJson(),
      'deliveryType': deliveryType.toJson(),
      'estimatedBandwidthMbps': estimatedBandwidthMbps,
      'requiresIgmp': requiresIgmp,
      'defaultVlanId': defaultVlanId,
      if (label != null) 'label': label,
      if (boundPortNumber != null) 'boundPortNumber': boundPortNumber,
      if (sacnUniverseSpec != null && sacnUniverseSpec!.trim().isNotEmpty)
        'sacnUniverseSpec': sacnUniverseSpec!.trim(),
      if (multicastGroupSpec != null && multicastGroupSpec!.trim().isNotEmpty)
        'multicastGroupSpec': multicastGroupSpec!.trim(),
    };
  }

  factory TrafficRequirement.fromJson(Map<String, dynamic> json) {
    final rawBound = json['boundPortNumber'];
    final boundPort =
        rawBound is num ? rawBound.toInt().clamp(1, 64) : null;
    final rawSacn = json['sacnUniverseSpec'];
    final rawMcast = json['multicastGroupSpec'];
    return TrafficRequirement(
      id: json['id'] is String ? json['id'] as String : 'flow-1',
      protocol: TrafficProtocol.fromJson(json['protocol']),
      direction: TrafficDirection.fromJson(json['direction']),
      deliveryType: DeliveryType.fromJson(json['deliveryType']),
      estimatedBandwidthMbps: (json['estimatedBandwidthMbps'] is num)
          ? (json['estimatedBandwidthMbps'] as num)
              .toDouble()
              .clamp(0.0, 100000.0)
          : 1.0,
      requiresIgmp: json['requiresIgmp'] == true,
      defaultVlanId: (json['defaultVlanId'] is num)
          ? (json['defaultVlanId'] as num).toInt().clamp(1, 4094)
          : 1,
      label: json['label'] is String ? json['label'] as String : null,
      boundPortNumber: boundPort,
      sacnUniverseSpec:
          rawSacn is String && rawSacn.trim().isNotEmpty ? rawSacn.trim() : null,
      multicastGroupSpec: rawMcast is String && rawMcast.trim().isNotEmpty
          ? rawMcast.trim()
          : null,
    );
  }
}

/// Vendor-neutral blueprint for an endpoint/node device.
class EndpointTemplate {
  const EndpointTemplate({
    required this.id,
    required this.name,
    this.category = EndpointCategory.genericEndpoint,
    this.nicSpeed = PortSpeed.speed1G,
    this.poeDrawWatts = 0.0,
    this.ports = const [],
    this.trafficProfiles = const [],
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final EndpointCategory category;
  final PortSpeed nicSpeed;
  final double poeDrawWatts;
  final List<EndpointPortConfig> ports;
  final List<TrafficRequirement> trafficProfiles;
  final bool isBuiltIn;

  List<EndpointPortConfig> get effectivePorts {
    if (ports.isNotEmpty) return ports;
    return [
      EndpointPortConfig(
        portNumber: 1,
        mediaType: PortMediaType.rj45,
        speed: nicSpeed,
        poeDrawWatts: poeDrawWatts,
      ),
    ];
  }

  EndpointPortConfig? tryPortByNumber(int portNumber) {
    for (final p in effectivePorts) {
      if (p.portNumber == portNumber) return p;
    }
    return null;
  }

  EndpointPortConfig portByNumber(int portNumber) =>
      tryPortByNumber(portNumber) ?? effectivePorts.first;

  double get totalPoeDrawWatts => effectivePorts.fold<double>(
        0.0,
        (sum, p) => sum + p.effectivePoeDrawWatts,
      );

  String get portsSummaryString {
    final list = effectivePorts;
    if (list.length == 1) {
      return list.first.mediaSpeedLabel;
    }
    return list.map((p) => p.shortBadge).join(' • ');
  }

  EndpointTemplate copyWith({
    String? id,
    String? name,
    EndpointCategory? category,
    PortSpeed? nicSpeed,
    double? poeDrawWatts,
    List<EndpointPortConfig>? ports,
    List<TrafficRequirement>? trafficProfiles,
    bool? isBuiltIn,
  }) {
    final nextPorts = ports ?? List<EndpointPortConfig>.from(this.ports);
    final derivedSpeed =
        nextPorts.isNotEmpty ? nextPorts.first.effectiveSpeed : (nicSpeed ?? this.nicSpeed);
    final derivedPoe = nextPorts.isNotEmpty
        ? nextPorts.fold<double>(0.0, (s, p) => s + p.effectivePoeDrawWatts)
        : (poeDrawWatts ?? this.poeDrawWatts);
    return EndpointTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      nicSpeed: nicSpeed ?? derivedSpeed,
      poeDrawWatts: poeDrawWatts ?? derivedPoe,
      ports: nextPorts,
      trafficProfiles: trafficProfiles ?? List.from(this.trafficProfiles),
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  Map<String, dynamic> toJson() {
    final list = effectivePorts;
    return {
      'id': id,
      'name': name,
      'category': category.toJson(),
      'nicSpeed': list.first.effectiveSpeed.toJson(),
      'poeDrawWatts': totalPoeDrawWatts,
      'ports': list.map((p) => p.toJson()).toList(),
      'trafficProfiles': trafficProfiles.map((e) => e.toJson()).toList(),
      'isBuiltIn': isBuiltIn,
    };
  }

  factory EndpointTemplate.fromJson(Map<String, dynamic> json) {
    final rawFlows = json['trafficProfiles'];
    final flows = <TrafficRequirement>[];
    if (rawFlows is List) {
      for (final item in rawFlows) {
        if (item is Map<String, dynamic>) {
          flows.add(TrafficRequirement.fromJson(item));
        } else if (item is Map) {
          flows.add(
            TrafficRequirement.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final legacySpeed = PortSpeed.fromJson(json['nicSpeed']);
    final legacyPoe = (json['poeDrawWatts'] is num)
        ? (json['poeDrawWatts'] as num).toDouble().clamp(0.0, 200.0)
        : 0.0;

    final rawPorts = json['ports'];
    final parsedPorts = <EndpointPortConfig>[];
    if (rawPorts is List) {
      for (var i = 0; i < rawPorts.length; i++) {
        final item = rawPorts[i];
        if (item is Map) {
          final parsed = EndpointPortConfig.fromJson(
            Map<String, dynamic>.from(item),
          );
          parsedPorts.add(parsed.copyWith(portNumber: i + 1));
        }
      }
    }
    if (parsedPorts.isEmpty) {
      parsedPorts.add(
        EndpointPortConfig(
          portNumber: 1,
          mediaType: PortMediaType.rj45,
          speed: legacySpeed,
          poeDrawWatts: legacyPoe,
        ),
      );
    }

    return EndpointTemplate(
      id: json['id'] is String ? json['id'] as String : 'endpoint-tpl',
      name: json['name'] is String ? json['name'] as String : 'Generic Endpoint',
      category: EndpointCategory.fromJson(json['category']),
      nicSpeed: parsedPorts.first.effectiveSpeed,
      poeDrawWatts: parsedPorts.fold<double>(
        0.0,
        (s, p) => s + p.effectivePoeDrawWatts,
      ),
      ports: parsedPorts,
      trafficProfiles: flows,
      isBuiltIn: json['isBuiltIn'] == true,
    );
  }
}
