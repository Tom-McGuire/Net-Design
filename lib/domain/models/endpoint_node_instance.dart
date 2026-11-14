import 'endpoint_template.dart';
import 'enums.dart';

/// Endpoint/device instance placed on the topology design canvas.
class EndpointNodeInstance {
  EndpointNodeInstance({
    required this.id,
    required this.templateId,
    required this.userLabel,
    this.category = EndpointCategory.genericEndpoint,
    this.nicSpeed = PortSpeed.speed1G,
    this.macAddress,
    this.ipAddress,
    List<TrafficRequirement>? activeTrafficFlows,
    this.poeDrawWatts = 0.0,
    this.dx = 120.0,
    this.dy = 360.0,
  }) : activeTrafficFlows = activeTrafficFlows ?? [];

  final String id;
  final String templateId;
  final String userLabel;
  final EndpointCategory category;
  final PortSpeed nicSpeed;
  final String? macAddress;
  final String? ipAddress;
  final List<TrafficRequirement> activeTrafficFlows;
  final double poeDrawWatts;
  final double dx;
  final double dy;

  double get totalTrafficMbps => activeTrafficFlows.fold<double>(
        0.0,
        (sum, flow) => sum + flow.estimatedBandwidthMbps,
      );

  EndpointNodeInstance copyWith({
    String? id,
    String? templateId,
    String? userLabel,
    EndpointCategory? category,
    PortSpeed? nicSpeed,
    String? macAddress,
    bool clearMacAddress = false,
    String? ipAddress,
    bool clearIpAddress = false,
    List<TrafficRequirement>? activeTrafficFlows,
    double? poeDrawWatts,
    double? dx,
    double? dy,
  }) {
    return EndpointNodeInstance(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      userLabel: userLabel ?? this.userLabel,
      category: category ?? this.category,
      nicSpeed: nicSpeed ?? this.nicSpeed,
      macAddress: clearMacAddress ? null : (macAddress ?? this.macAddress),
      ipAddress: clearIpAddress ? null : (ipAddress ?? this.ipAddress),
      activeTrafficFlows: activeTrafficFlows != null
          ? List<TrafficRequirement>.from(activeTrafficFlows)
          : List<TrafficRequirement>.from(this.activeTrafficFlows),
      poeDrawWatts: poeDrawWatts ?? this.poeDrawWatts,
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'templateId': templateId,
      'userLabel': userLabel,
      'category': category.toJson(),
      'nicSpeed': nicSpeed.toJson(),
      if (macAddress != null) 'macAddress': macAddress,
      if (ipAddress != null) 'ipAddress': ipAddress,
      'activeTrafficFlows': activeTrafficFlows.map((f) => f.toJson()).toList(),
      'poeDrawWatts': poeDrawWatts,
      'dx': dx,
      'dy': dy,
    };
  }

  factory EndpointNodeInstance.fromJson(Map<String, dynamic> json) {
    final rawFlows = json['activeTrafficFlows'];
    final flows = <TrafficRequirement>[];
    if (rawFlows is List) {
      for (final item in rawFlows) {
        if (item is Map) {
          flows.add(
            TrafficRequirement.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return EndpointNodeInstance(
      id: json['id'] is String ? json['id'] as String : 'ep-1',
      templateId:
          json['templateId'] is String ? json['templateId'] as String : 'tpl-ep',
      userLabel:
          json['userLabel'] is String ? json['userLabel'] as String : 'Endpoint',
      category: EndpointCategory.fromJson(json['category']),
      nicSpeed: PortSpeed.fromJson(json['nicSpeed']),
      macAddress: json['macAddress'] is String ? json['macAddress'] as String : null,
      ipAddress: json['ipAddress'] is String ? json['ipAddress'] as String : null,
      activeTrafficFlows: flows,
      poeDrawWatts: (json['poeDrawWatts'] is num)
          ? (json['poeDrawWatts'] as num).toDouble().clamp(0.0, 200.0)
          : 0.0,
      dx: (json['dx'] is num) ? (json['dx'] as num).toDouble() : 120.0,
      dy: (json['dy'] is num) ? (json['dy'] as num).toDouble() : 360.0,
    );
  }
}
