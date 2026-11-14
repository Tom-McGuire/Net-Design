import 'enums.dart';

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
  });

  final String id;
  final TrafficProtocol protocol;
  final TrafficDirection direction;
  final DeliveryType deliveryType;
  final double estimatedBandwidthMbps;
  final bool requiresIgmp;
  final int defaultVlanId;
  final String? label;

  String get displayPill {
    final prefix = label != null && label!.trim().isNotEmpty
        ? label!.trim()
        : protocol.label;
    final dirTag = switch (direction) {
      TrafficDirection.txPublisher => 'TX',
      TrafficDirection.rxSubscriber => 'RX',
      TrafficDirection.bidirectional => 'TX/RX',
    };
    final bwStr = estimatedBandwidthMbps >= 10
        ? estimatedBandwidthMbps.toStringAsFixed(0)
        : estimatedBandwidthMbps.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
    return '$prefix $dirTag ($bwStr Mbps • V$defaultVlanId)';
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
    };
  }

  factory TrafficRequirement.fromJson(Map<String, dynamic> json) {
    return TrafficRequirement(
      id: json['id'] is String ? json['id'] as String : 'flow-1',
      protocol: TrafficProtocol.fromJson(json['protocol']),
      direction: TrafficDirection.fromJson(json['direction']),
      deliveryType: DeliveryType.fromJson(json['deliveryType']),
      estimatedBandwidthMbps: (json['estimatedBandwidthMbps'] is num)
          ? (json['estimatedBandwidthMbps'] as num).toDouble().clamp(0.0, 100000.0)
          : 1.0,
      requiresIgmp: json['requiresIgmp'] == true,
      defaultVlanId: (json['defaultVlanId'] is num)
          ? (json['defaultVlanId'] as num).toInt().clamp(1, 4094)
          : 1,
      label: json['label'] is String ? json['label'] as String : null,
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
    this.trafficProfiles = const [],
    this.isBuiltIn = false,
  });

  final String id;
  final String name;
  final EndpointCategory category;
  final PortSpeed nicSpeed;
  final double poeDrawWatts;
  final List<TrafficRequirement> trafficProfiles;
  final bool isBuiltIn;

  EndpointTemplate copyWith({
    String? id,
    String? name,
    EndpointCategory? category,
    PortSpeed? nicSpeed,
    double? poeDrawWatts,
    List<TrafficRequirement>? trafficProfiles,
    bool? isBuiltIn,
  }) {
    return EndpointTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      nicSpeed: nicSpeed ?? this.nicSpeed,
      poeDrawWatts: poeDrawWatts ?? this.poeDrawWatts,
      trafficProfiles: trafficProfiles ?? List.from(this.trafficProfiles),
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category.toJson(),
      'nicSpeed': nicSpeed.toJson(),
      'poeDrawWatts': poeDrawWatts,
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

    return EndpointTemplate(
      id: json['id'] is String ? json['id'] as String : 'endpoint-tpl',
      name: json['name'] is String ? json['name'] as String : 'Generic Endpoint',
      category: EndpointCategory.fromJson(json['category']),
      nicSpeed: PortSpeed.fromJson(json['nicSpeed']),
      poeDrawWatts: (json['poeDrawWatts'] is num)
          ? (json['poeDrawWatts'] as num).toDouble().clamp(0.0, 200.0)
          : 0.0,
      trafficProfiles: flows,
      isBuiltIn: json['isBuiltIn'] == true,
    );
  }
}
