import 'package:material_ui/material_ui.dart';

/// Physical Ethernet port link speeds.
enum PortSpeed {
  speed100M('100M', 100, 19),
  speed1G('1G', 1000, 4),
  speed2_5G('2.5G', 2500, 4),
  speed5G('5G', 5000, 3),
  speed10G('10G', 10000, 2);

  const PortSpeed(this.label, this.mbps, this.stpCost);

  final String label;
  final int mbps;

  /// IEEE 802.1D / 802.1w path cost.
  final int stpCost;

  String toJson() => name;

  static PortSpeed fromJson(Object? value) {
    if (value is String) {
      for (final speed in values) {
        if (speed.name == value || speed.label == value) return speed;
      }
    }
    return PortSpeed.speed1G;
  }

  static PortSpeed minSpeed(PortSpeed a, PortSpeed b) {
    return a.mbps <= b.mbps ? a : b;
  }
}

/// Physical port connector / media type.
enum PortMediaType {
  rj45('RJ45 Copper', 'RJ45'),
  sfpFibre('SFP / Fibre', 'SFP');

  const PortMediaType(this.label, this.shortLabel);

  final String label;
  final String shortLabel;

  List<PortSpeed> get allowedSpeeds => switch (this) {
        PortMediaType.rj45 => PortSpeed.values,
        PortMediaType.sfpFibre => const [PortSpeed.speed1G, PortSpeed.speed10G],
      };

  PortSpeed normalizeSpeed(PortSpeed speed) {
    if (allowedSpeeds.contains(speed)) return speed;
    return this == PortMediaType.sfpFibre
        ? (speed.mbps >= PortSpeed.speed10G.mbps
            ? PortSpeed.speed10G
            : PortSpeed.speed1G)
        : speed;
  }

  String toJson() => name;

  static PortMediaType fromJson(Object? value) {
    if (value is String) {
      for (final item in values) {
        if (item.name == value || item.label == value) return item;
      }
    }
    return PortMediaType.rj45;
  }
}

/// Visual delivery state of a link when tracing a multicast stream.
enum LinkStreamTraceState {
  none('None'),
  delivered('Delivered'),
  flooded('FLOODED'),
  igmpPruned('IGMP PRUNED');

  const LinkStreamTraceState(this.label);

  final String label;
}

/// Generic role category for endpoint devices.
enum EndpointCategory {
  console('Console', Icons.tune),
  gatewayNode('Gateway / Node', Icons.settings_input_hdmi),
  audioDsp('Audio / DSP', Icons.graphic_eq),
  mediaServer('Media Server', Icons.dns),
  controlPc('Control / PC', Icons.computer),
  genericEndpoint('Generic Endpoint', Icons.devices_other);

  const EndpointCategory(this.label, this.icon);

  final String label;
  final IconData icon;

  String toJson() => name;

  static EndpointCategory fromJson(Object? value) {
    if (value is String) {
      for (final cat in values) {
        if (cat.name == value || cat.label == value) return cat;
      }
    }
    return EndpointCategory.genericEndpoint;
  }
}

/// Abstract protocol classifications for traffic modeling.
enum TrafficProtocol {
  sacn('sACN / E1.31', DeliveryType.multicast, true, 20, 0.25),
  artNet('Art-Net', DeliveryType.broadcast, false, 1, 0.25),
  acn('ACN / E1.17', DeliveryType.multicast, true, 20, 2.0),
  danteAes67('Dante / AES67', DeliveryType.multicast, true, 30, 100.0),
  ndiVideo('NDI / Video', DeliveryType.multicast, true, 40, 125.0),
  controlUnicast('Control / Unicast', DeliveryType.unicast, false, 1, 5.0),
  custom('Custom', DeliveryType.unicast, false, 1, 10.0);

  const TrafficProtocol(
    this.label,
    this.defaultDelivery,
    this.defaultRequiresIgmp,
    this.defaultVlan,
    this.defaultUnitMbps,
  );

  final String label;
  final DeliveryType defaultDelivery;
  final bool defaultRequiresIgmp;
  final int defaultVlan;
  final double defaultUnitMbps;

  String toJson() => name;

  static TrafficProtocol fromJson(Object? value) {
    if (value is String) {
      for (final proto in values) {
        if (proto.name == value || proto.label == value) return proto;
      }
    }
    return TrafficProtocol.custom;
  }
}

/// Traffic flow direction on an endpoint.
enum TrafficDirection {
  txPublisher('TX / Publisher'),
  rxSubscriber('RX / Subscriber'),
  bidirectional('Bidirectional');

  const TrafficDirection(this.label);

  final String label;

  bool get isPublisher =>
      this == TrafficDirection.txPublisher ||
      this == TrafficDirection.bidirectional;

  bool get isSubscriber =>
      this == TrafficDirection.rxSubscriber ||
      this == TrafficDirection.bidirectional;

  String toJson() => name;

  static TrafficDirection fromJson(Object? value) {
    if (value is String) {
      for (final dir in values) {
        if (dir.name == value || dir.label == value) return dir;
      }
    }
    return TrafficDirection.bidirectional;
  }
}

/// Layer 2 / Layer 3 packet delivery semantics.
enum DeliveryType {
  multicast('Multicast'),
  broadcast('Broadcast'),
  unicast('Unicast');

  const DeliveryType(this.label);

  final String label;

  String toJson() => name;

  static DeliveryType fromJson(Object? value) {
    if (value is String) {
      for (final item in values) {
        if (item.name == value || item.label == value) return item;
      }
    }
    return DeliveryType.unicast;
  }
}

/// Spanning Tree Protocol mode per switch.
enum StpMode {
  disabled('Disabled'),
  stp('STP (802.1D)'),
  rstp('RSTP (802.1w)');

  const StpMode(this.label);

  final String label;

  String toJson() => name;

  static StpMode fromJson(Object? value) {
    if (value is String) {
      for (final item in values) {
        if (item.name == value || item.label == value) return item;
      }
    }
    return StpMode.rstp;
  }
}

/// Switch port VLAN forwarding mode.
enum SwitchPortMode {
  access('Access'),
  trunk('Trunk');

  const SwitchPortMode(this.label);

  final String label;

  String toJson() => name;

  static SwitchPortMode fromJson(Object? value) {
    if (value is String) {
      for (final item in values) {
        if (item.name == value || item.label == value) return item;
      }
    }
    return SwitchPortMode.access;
  }
}

/// IGMP Querier protocol version.
enum IgmpVersion {
  v2('IGMPv2'),
  v3('IGMPv3');

  const IgmpVersion(this.label);

  final String label;

  String toJson() => name;

  static IgmpVersion fromJson(Object? value) {
    if (value is String) {
      for (final item in values) {
        if (item.name == value || item.label == value) return item;
      }
    }
    return IgmpVersion.v2;
  }
}

/// Computed Spanning Tree forwarding state of a link.
enum LinkStpState {
  forwarding('Forwarding'),
  blocking('Blocking (STP)'),
  loopUnprotected('Unprotected Loop'),
  notApplicable('Endpoint Link');

  const LinkStpState(this.label);

  final String label;
}

/// Validation finding severity levels.
enum IssueSeverity {
  critical('Critical', 0),
  warning('Warning', 1),
  info('Info', 2);

  const IssueSeverity(this.label, this.sortOrder);

  final String label;
  final int sortOrder;
}

/// Validation finding domain categories.
enum IssueCategory {
  stp('STP'),
  vlan('VLAN'),
  igmp('IGMP'),
  bandwidth('Bandwidth'),
  poe('PoE');

  const IssueCategory(this.label);

  final String label;
}
