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
    List<EndpointPortConfig>? ports,
    List<TrafficRequirement>? activeTrafficFlows,
    this.poeDrawWatts = 0.0,
    this.dx = 120.0,
    this.dy = 360.0,
  })  : ports = (ports != null && ports.isNotEmpty)
            ? List<EndpointPortConfig>.unmodifiable(ports)
            : List<EndpointPortConfig>.unmodifiable([
                EndpointPortConfig(
                  portNumber: 1,
                  mediaType: PortMediaType.rj45,
                  speed: nicSpeed,
                  poeDrawWatts: poeDrawWatts,
                ),
              ]),
        activeTrafficFlows = activeTrafficFlows ?? [];

  final String id;
  final String templateId;
  final String userLabel;
  final EndpointCategory category;
  final PortSpeed nicSpeed;
  final String? macAddress;
  final String? ipAddress;
  final List<EndpointPortConfig> ports;
  final List<TrafficRequirement> activeTrafficFlows;
  final double poeDrawWatts;
  final double dx;
  final double dy;

  List<EndpointPortConfig> get effectivePorts => ports.isNotEmpty
      ? ports
      : [
          EndpointPortConfig(
            portNumber: 1,
            mediaType: PortMediaType.rj45,
            speed: nicSpeed,
            poeDrawWatts: poeDrawWatts,
          ),
        ];

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
    List<EndpointPortConfig>? ports,
    List<TrafficRequirement>? activeTrafficFlows,
    double? poeDrawWatts,
    double? dx,
    double? dy,
  }) {
    late final List<EndpointPortConfig> nextPorts;
    if (ports != null && ports.isNotEmpty) {
      nextPorts = [
        for (var i = 0; i < ports.length; i++)
          ports[i].copyWith(portNumber: i + 1),
      ];
    } else if (nicSpeed != null || poeDrawWatts != null) {
      final base = List<EndpointPortConfig>.from(effectivePorts);
      base[0] = base[0].copyWith(
        speed: nicSpeed ?? base[0].speed,
        poeDrawWatts: poeDrawWatts ?? base[0].poeDrawWatts,
      );
      nextPorts = base;
    } else {
      nextPorts = List<EndpointPortConfig>.from(effectivePorts);
    }

    final derivedNicSpeed = nextPorts.first.effectiveSpeed;
    final derivedPoe = nextPorts.fold<double>(
      0.0,
      (sum, p) => sum + p.effectivePoeDrawWatts,
    );

    return EndpointNodeInstance(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      userLabel: userLabel ?? this.userLabel,
      category: category ?? this.category,
      nicSpeed: derivedNicSpeed,
      macAddress: clearMacAddress ? null : (macAddress ?? this.macAddress),
      ipAddress: clearIpAddress ? null : (ipAddress ?? this.ipAddress),
      ports: nextPorts,
      activeTrafficFlows: activeTrafficFlows != null
          ? List<TrafficRequirement>.from(activeTrafficFlows)
          : List<TrafficRequirement>.from(this.activeTrafficFlows),
      poeDrawWatts: derivedPoe,
      dx: dx ?? this.dx,
      dy: dy ?? this.dy,
    );
  }

  Map<String, dynamic> toJson() {
    final list = effectivePorts;
    return {
      'id': id,
      'templateId': templateId,
      'userLabel': userLabel,
      'category': category.toJson(),
      'nicSpeed': list.first.effectiveSpeed.toJson(),
      if (macAddress != null) 'macAddress': macAddress,
      if (ipAddress != null) 'ipAddress': ipAddress,
      'ports': list.map((p) => p.toJson()).toList(),
      'activeTrafficFlows': activeTrafficFlows.map((f) => f.toJson()).toList(),
      'poeDrawWatts': totalPoeDrawWatts,
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
          final p = EndpointPortConfig.fromJson(
            Map<String, dynamic>.from(item),
          );
          parsedPorts.add(p.copyWith(portNumber: i + 1));
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

    return EndpointNodeInstance(
      id: json['id'] is String ? json['id'] as String : 'ep-1',
      templateId:
          json['templateId'] is String ? json['templateId'] as String : 'tpl-ep',
      userLabel:
          json['userLabel'] is String ? json['userLabel'] as String : 'Endpoint',
      category: EndpointCategory.fromJson(json['category']),
      nicSpeed: parsedPorts.first.effectiveSpeed,
      macAddress: json['macAddress'] is String ? json['macAddress'] as String : null,
      ipAddress: json['ipAddress'] is String ? json['ipAddress'] as String : null,
      ports: parsedPorts,
      activeTrafficFlows: flows,
      poeDrawWatts: parsedPorts.fold<double>(
        0.0,
        (s, p) => s + p.effectivePoeDrawWatts,
      ),
      dx: (json['dx'] is num) ? (json['dx'] as num).toDouble() : 120.0,
      dy: (json['dy'] is num) ? (json['dy'] as num).toDouble() : 360.0,
    );
  }
}
