import 'endpoint_node_instance.dart';
import 'network_link_edge.dart';
import 'switch_node_instance.dart';

/// Complete topology project model persisted as `.netdesign` JSON files.
class TopologyProject {
  TopologyProject({
    required this.name,
    this.description = '',
    List<SwitchNodeInstance>? switches,
    List<EndpointNodeInstance>? endpoints,
    List<NetworkLinkEdge>? links,
    Map<int, String>? knownVlans,
  })  : switches = switches ?? [],
        endpoints = endpoints ?? [],
        links = links ?? [],
        knownVlans = knownVlans ??
            {
              1: 'Default / Mgmt',
              20: 'sACN / Lighting',
              30: 'Dante / Audio',
              40: 'NDI / Video',
            };

  final String name;
  final String description;
  final List<SwitchNodeInstance> switches;
  final List<EndpointNodeInstance> endpoints;
  final List<NetworkLinkEdge> links;
  final Map<int, String> knownVlans;

  TopologyProject copyWith({
    String? name,
    String? description,
    List<SwitchNodeInstance>? switches,
    List<EndpointNodeInstance>? endpoints,
    List<NetworkLinkEdge>? links,
    Map<int, String>? knownVlans,
  }) {
    return TopologyProject(
      name: name ?? this.name,
      description: description ?? this.description,
      switches: switches ?? List<SwitchNodeInstance>.from(this.switches),
      endpoints: endpoints ?? List<EndpointNodeInstance>.from(this.endpoints),
      links: links ?? List<NetworkLinkEdge>.from(this.links),
      knownVlans: knownVlans ?? Map<int, String>.from(this.knownVlans),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': 1,
      'name': name,
      'description': description,
      'knownVlans': {
        for (final entry in knownVlans.entries)
          entry.key.toString(): entry.value,
      },
      'switches': switches.map((s) => s.toJson()).toList(),
      'endpoints': endpoints.map((e) => e.toJson()).toList(),
      'links': links.map((l) => l.toJson()).toList(),
    };
  }

  factory TopologyProject.fromJson(Map<String, dynamic> json) {
    final parsedVlans = <int, String>{};
    final rawVlans = json['knownVlans'];
    if (rawVlans is Map) {
      for (final entry in rawVlans.entries) {
        final id = int.tryParse(entry.key.toString());
        if (id != null && id >= 1 && id <= 4094) {
          parsedVlans[id] = entry.value.toString();
        }
      }
    }
    if (!parsedVlans.containsKey(1)) {
      parsedVlans[1] = 'Default / Mgmt';
    }

    final parsedSwitches = <SwitchNodeInstance>[];
    if (json['switches'] is List) {
      for (final item in json['switches'] as List) {
        if (item is Map) {
          parsedSwitches.add(
            SwitchNodeInstance.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final parsedEndpoints = <EndpointNodeInstance>[];
    if (json['endpoints'] is List) {
      for (final item in json['endpoints'] as List) {
        if (item is Map) {
          parsedEndpoints.add(
            EndpointNodeInstance.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final parsedLinks = <NetworkLinkEdge>[];
    if (json['links'] is List) {
      for (final item in json['links'] as List) {
        if (item is Map) {
          parsedLinks.add(
            NetworkLinkEdge.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return TopologyProject(
      name: json['name'] is String ? json['name'] as String : 'Untitled Topology',
      description:
          json['description'] is String ? json['description'] as String : '',
      switches: parsedSwitches,
      endpoints: parsedEndpoints,
      links: parsedLinks,
      knownVlans: parsedVlans,
    );
  }
}
