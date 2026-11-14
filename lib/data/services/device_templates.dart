import '../../domain/models/endpoint_node_instance.dart';
import '../../domain/models/endpoint_template.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/network_link_edge.dart';
import '../../domain/models/switch_node_instance.dart';
import '../../domain/models/switch_template.dart';
import '../../domain/models/topology_project.dart';

/// Starter vendor-neutral switch/endpoint templates and interactive demo scenarios.
class DeviceTemplates {
  DeviceTemplates._();

  static List<SwitchTemplate> defaultSwitchTemplates() {
    return [
      SwitchTemplate(
        id: 'tpl-sw-8g-2sfp-poe',
        name: 'Compact 8-Port 1G PoE + 2x 1G Uplink',
        ports1G: 10,
        poeBudgetWatts: 120,
        poeStartPort: 1,
        poeEndPort: 8,
        supportsStp: true,
        supportsVlans: true,
        supportsIgmpSnooping: true,
        supportsIgmpQuerier: true,
        isBuiltIn: true,
      ),
      SwitchTemplate(
        id: 'tpl-sw-16g-4x10g-core',
        name: '16-Port 1G PoE + 4x 10G Core',
        ports1G: 16,
        ports10G: 4,
        poeBudgetWatts: 370,
        poeStartPort: 1,
        poeEndPort: 16,
        supportsStp: true,
        supportsVlans: true,
        supportsIgmpSnooping: true,
        supportsIgmpQuerier: true,
        isBuiltIn: true,
      ),
      SwitchTemplate(
        id: 'tpl-sw-24g-4x10g-dist',
        name: '24-Port 1G + 4x 10G Distribution',
        ports1G: 24,
        ports10G: 4,
        poeBudgetWatts: 0,
        supportsStp: true,
        supportsVlans: true,
        supportsIgmpSnooping: true,
        supportsIgmpQuerier: true,
        isBuiltIn: true,
      ),
      SwitchTemplate(
        id: 'tpl-sw-8x100m-4x1g-legacy',
        name: '8-Port 100M Legacy + 2x 1G Managed',
        ports100M: 8,
        ports1G: 2,
        poeBudgetWatts: 65,
        poeStartPort: 1,
        poeEndPort: 4,
        supportsStp: true,
        supportsVlans: true,
        supportsIgmpSnooping: true,
        supportsIgmpQuerier: false,
        isBuiltIn: true,
      ),
      SwitchTemplate(
        id: 'tpl-sw-5g-unmanaged',
        name: '5-Port 1G Unmanaged Switch (No STP/VLAN)',
        ports1G: 5,
        poeBudgetWatts: 0,
        supportsStp: false,
        supportsVlans: false,
        supportsIgmpSnooping: false,
        supportsIgmpQuerier: false,
        isBuiltIn: true,
      ),
    ];
  }

  static List<EndpointTemplate> defaultEndpointTemplates() {
    return [
      const EndpointTemplate(
        id: 'tpl-ep-lighting-console',
        name: 'Lighting Console (Primary)',
        category: EndpointCategory.console,
        nicSpeed: PortSpeed.speed1G,
        poeDrawWatts: 0.0,
        isBuiltIn: true,
        trafficProfiles: [
          TrafficRequirement(
            id: 'flow-sacn-tx',
            protocol: TrafficProtocol.sacn,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 4.0,
            requiresIgmp: true,
            defaultVlanId: 20,
            label: '16x sACN Univ',
          ),
        ],
      ),
      const EndpointTemplate(
        id: 'tpl-ep-sacn-node',
        name: '4-Port DMX/sACN Node (PoE)',
        category: EndpointCategory.gatewayNode,
        nicSpeed: PortSpeed.speed100M,
        poeDrawWatts: 12.5,
        isBuiltIn: true,
        trafficProfiles: [
          TrafficRequirement(
            id: 'flow-sacn-rx',
            protocol: TrafficProtocol.sacn,
            direction: TrafficDirection.rxSubscriber,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 1.0,
            requiresIgmp: true,
            defaultVlanId: 20,
            label: '4x sACN Univ',
          ),
        ],
      ),
      const EndpointTemplate(
        id: 'tpl-ep-dante-stagebox',
        name: '64-Ch Audio Stagebox',
        category: EndpointCategory.audioDsp,
        nicSpeed: PortSpeed.speed1G,
        poeDrawWatts: 0.0,
        isBuiltIn: true,
        trafficProfiles: [
          TrafficRequirement(
            id: 'flow-dante-bidir',
            protocol: TrafficProtocol.danteAes67,
            direction: TrafficDirection.bidirectional,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 100.0,
            requiresIgmp: true,
            defaultVlanId: 30,
            label: '64-Ch AES67',
          ),
        ],
      ),
      const EndpointTemplate(
        id: 'tpl-ep-media-server',
        name: 'Video Media Server (10G NDI)',
        category: EndpointCategory.mediaServer,
        nicSpeed: PortSpeed.speed10G,
        poeDrawWatts: 0.0,
        isBuiltIn: true,
        trafficProfiles: [
          TrafficRequirement(
            id: 'flow-ndi-tx',
            protocol: TrafficProtocol.ndiVideo,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 250.0,
            requiresIgmp: true,
            defaultVlanId: 40,
            label: '2x NDI HD',
          ),
        ],
      ),
      const EndpointTemplate(
        id: 'tpl-ep-poe-touchscreen',
        name: 'Control Touchscreen / Wall Panel',
        category: EndpointCategory.controlPc,
        nicSpeed: PortSpeed.speed1G,
        poeDrawWatts: 25.0,
        isBuiltIn: true,
        trafficProfiles: [
          TrafficRequirement(
            id: 'flow-ctrl-unicast',
            protocol: TrafficProtocol.controlUnicast,
            direction: TrafficDirection.bidirectional,
            deliveryType: DeliveryType.unicast,
            estimatedBandwidthMbps: 5.0,
            requiresIgmp: false,
            defaultVlanId: 1,
            label: 'OSC / Control',
          ),
        ],
      ),
      const EndpointTemplate(
        id: 'tpl-ep-artnet-pixel',
        name: 'High-Density Art-Net Pixel Controller',
        category: EndpointCategory.gatewayNode,
        nicSpeed: PortSpeed.speed1G,
        poeDrawWatts: 0.0,
        isBuiltIn: true,
        trafficProfiles: [
          TrafficRequirement(
            id: 'flow-artnet-bcast',
            protocol: TrafficProtocol.artNet,
            direction: TrafficDirection.bidirectional,
            deliveryType: DeliveryType.broadcast,
            estimatedBandwidthMbps: 85.0,
            requiresIgmp: false,
            defaultVlanId: 1,
            label: '340x Art-Net Univ',
          ),
        ],
      ),
    ];
  }

  /// Reference healthy ring with deterministic Root Bridge (priority 4096),
  /// symmetric trunks (VLAN 1, 20, 30), and Root-colocated IGMP Queriers.
  static TopologyProject healthyReferenceRingDemo() {
    final coreTpl = defaultSwitchTemplates()[1]; // 16x 1G + 4x 10G
    final edgeTpl = defaultSwitchTemplates()[0]; // 8x 1G + 2x 1G uplink

    final swCore = _makeSwitch(
      id: 'sw-core-foh',
      template: coreTpl,
      label: 'FOH Core Switch A',
      mac: '02:10:00:00:00:10',
      ip: '10.0.1.1',
      stpPriority: 4096,
      dx: 380,
      dy: 90,
      vlans: {
        1: const SwitchVlanSettings(vlanId: 1, vlanName: 'Default / Mgmt'),
        20: const SwitchVlanSettings(
          vlanId: 20,
          vlanName: 'sACN / Lighting',
          igmpSnoopingEnabled: true,
          igmpQuerierEnabled: true,
          igmpQuerierVersion: IgmpVersion.v2,
        ),
        30: const SwitchVlanSettings(
          vlanId: 30,
          vlanName: 'Dante / Audio',
          igmpSnoopingEnabled: true,
          igmpQuerierEnabled: true,
          igmpQuerierVersion: IgmpVersion.v2,
        ),
      },
    );
    _setPortTrunk(swCore, 17, {1, 20, 30}, label: 'Uplink -> Stage L');
    _setPortTrunk(swCore, 18, {1, 20, 30}, label: 'Uplink -> Stage R');
    _setPortAccess(swCore, 1, 20, label: 'Console Pri');
    _setPortAccess(swCore, 2, 30, label: 'FOH Audio DSP');

    final swLeft = _makeSwitch(
      id: 'sw-stage-left',
      template: edgeTpl,
      label: 'Stage Left Rack B',
      mac: '02:10:00:00:00:20',
      ip: '10.0.1.2',
      stpPriority: 32768,
      dx: 130,
      dy: 320,
      vlans: {
        1: const SwitchVlanSettings(vlanId: 1, vlanName: 'Default / Mgmt'),
        20: const SwitchVlanSettings(
          vlanId: 20,
          vlanName: 'sACN / Lighting',
          igmpSnoopingEnabled: true,
          igmpQuerierEnabled: false,
          igmpQuerierVersion: IgmpVersion.v2,
        ),
        30: const SwitchVlanSettings(
          vlanId: 30,
          vlanName: 'Dante / Audio',
          igmpSnoopingEnabled: true,
          igmpQuerierEnabled: false,
          igmpQuerierVersion: IgmpVersion.v2,
        ),
      },
    );
    _setPortTrunk(swLeft, 9, {1, 20, 30}, label: 'Trunk -> Core');
    _setPortTrunk(swLeft, 10, {1, 20, 30}, label: 'Ring -> Stage R');
    _setPortAccess(swLeft, 1, 20, label: 'Dimmer Node L');

    final swRight = _makeSwitch(
      id: 'sw-stage-right',
      template: edgeTpl,
      label: 'Stage Right Rack C',
      mac: '02:10:00:00:00:30',
      ip: '10.0.1.3',
      stpPriority: 32768,
      dx: 630,
      dy: 320,
      vlans: {
        1: const SwitchVlanSettings(vlanId: 1, vlanName: 'Default / Mgmt'),
        20: const SwitchVlanSettings(
          vlanId: 20,
          vlanName: 'sACN / Lighting',
          igmpSnoopingEnabled: true,
          igmpQuerierEnabled: false,
          igmpQuerierVersion: IgmpVersion.v2,
        ),
        30: const SwitchVlanSettings(
          vlanId: 30,
          vlanName: 'Dante / Audio',
          igmpSnoopingEnabled: true,
          igmpQuerierEnabled: false,
          igmpQuerierVersion: IgmpVersion.v2,
        ),
      },
    );
    _setPortTrunk(swRight, 9, {1, 20, 30}, label: 'Trunk -> Core');
    _setPortTrunk(swRight, 10, {1, 20, 30}, label: 'Ring -> Stage L');
    _setPortAccess(swRight, 1, 20, label: 'Truss Node R');
    _setPortAccess(swRight, 2, 30, label: 'Stagebox R');

    final epTemplates = defaultEndpointTemplates();
    final epConsole = _makeEndpoint(
      id: 'ep-console',
      template: epTemplates[0],
      label: 'Main Lighting Console',
      ip: '10.20.0.10',
      dx: 130,
      dy: 75,
    );
    final epFohAudio = _makeEndpoint(
      id: 'ep-foh-audio',
      template: epTemplates[2],
      label: 'FOH Mix Engine',
      ip: '10.30.0.10',
      dx: 650,
      dy: 75,
    );
    final epNodeL = _makeEndpoint(
      id: 'ep-node-l',
      template: epTemplates[1],
      label: 'Stage Left sACN Node',
      ip: '10.20.0.21',
      dx: 110,
      dy: 530,
    );
    final epNodeR = _makeEndpoint(
      id: 'ep-node-r',
      template: epTemplates[1],
      label: 'Stage Right sACN Node',
      ip: '10.20.0.22',
      dx: 540,
      dy: 530,
    );
    final epStagebox = _makeEndpoint(
      id: 'ep-stagebox-r',
      template: epTemplates[2],
      label: 'Stage Right 64-Ch Box',
      ip: '10.30.0.21',
      dx: 760,
      dy: 530,
    );

    final links = [
      NetworkLinkEdge(
        id: 'lnk-core-left',
        sourceNodeId: swCore.id,
        sourcePortNumber: 17,
        targetNodeId: swLeft.id,
        targetPortNumber: 9,
      ),
      NetworkLinkEdge(
        id: 'lnk-core-right',
        sourceNodeId: swCore.id,
        sourcePortNumber: 18,
        targetNodeId: swRight.id,
        targetPortNumber: 9,
      ),
      NetworkLinkEdge(
        id: 'lnk-left-right',
        sourceNodeId: swLeft.id,
        sourcePortNumber: 10,
        targetNodeId: swRight.id,
        targetPortNumber: 10,
      ),
      NetworkLinkEdge(
        id: 'lnk-ep-console',
        sourceNodeId: epConsole.id,
        sourcePortNumber: 1,
        targetNodeId: swCore.id,
        targetPortNumber: 1,
      ),
      NetworkLinkEdge(
        id: 'lnk-ep-foh-audio',
        sourceNodeId: epFohAudio.id,
        sourcePortNumber: 1,
        targetNodeId: swCore.id,
        targetPortNumber: 2,
      ),
      NetworkLinkEdge(
        id: 'lnk-ep-node-l',
        sourceNodeId: epNodeL.id,
        sourcePortNumber: 1,
        targetNodeId: swLeft.id,
        targetPortNumber: 1,
      ),
      NetworkLinkEdge(
        id: 'lnk-ep-node-r',
        sourceNodeId: epNodeR.id,
        sourcePortNumber: 1,
        targetNodeId: swRight.id,
        targetPortNumber: 1,
      ),
      NetworkLinkEdge(
        id: 'lnk-ep-stagebox',
        sourceNodeId: epStagebox.id,
        sourcePortNumber: 1,
        targetNodeId: swRight.id,
        targetPortNumber: 2,
      ),
    ];

    return TopologyProject(
      name: 'Touring Lighting & Dante Ring (Healthy Reference)',
      description:
          'Explicit Root Bridge (Priority 4096), symmetric trunks carrying VLANs 1/20/30, and Root-colocated IGMP Queriers.',
      switches: [swCore, swLeft, swRight],
      endpoints: [epConsole, epFohAudio, epNodeL, epNodeR, epStagebox],
      links: links,
    );
  }

  /// Diagnostic ring showcasing common field mistakes:
  /// - All switches left at default STP priority 32768 (arbitrary MAC Root)
  /// - Trunk missing VLAN 20 causing sACN Blackhole + IGMP Querier isolation
  /// - PoE endpoint plugged into a non-PoE uplink port
  static TopologyProject brokenRingFaultDemo() {
    final coreTpl = defaultSwitchTemplates()[1];
    final edgeTpl = defaultSwitchTemplates()[0];

    final swCore = _makeSwitch(
      id: 'sw-foh-broken',
      template: coreTpl,
      label: 'FOH Rack Switch A',
      mac: '02:99:00:AA:11:40',
      ip: '10.0.1.10',
      stpPriority: 32768,
      dx: 380,
      dy: 90,
      vlans: {
        1: const SwitchVlanSettings(vlanId: 1, vlanName: 'Default / Mgmt'),
        20: const SwitchVlanSettings(
          vlanId: 20,
          vlanName: 'sACN / Lighting',
          igmpSnoopingEnabled: true,
          igmpQuerierEnabled: true,
        ),
      },
    );
    _setPortTrunk(swCore, 17, {1, 20}, label: 'Uplink -> Truss 1');
    _setPortTrunk(swCore, 18, {1, 20}, label: 'Uplink -> Truss 2');
    _setPortAccess(swCore, 1, 20, label: 'Main Console');

    final swTruss1 = _makeSwitch(
      id: 'sw-truss-1',
      template: edgeTpl,
      label: 'Truss 1 Switch B',
      mac: '02:01:00:00:00:05', // Lowest MAC wins arbitrary Root!
      ip: '10.0.1.11',
      stpPriority: 32768,
      dx: 130,
      dy: 320,
      vlans: {
        1: const SwitchVlanSettings(vlanId: 1, vlanName: 'Default / Mgmt'),
        20: const SwitchVlanSettings(
          vlanId: 20,
          vlanName: 'sACN / Lighting',
          igmpSnoopingEnabled: true,
          igmpQuerierEnabled: false,
        ),
      },
    );
    _setPortTrunk(swTruss1, 9, {1, 20});
    _setPortTrunk(swTruss1, 10, {1, 20});
    _setPortAccess(swTruss1, 1, 20);

    final swTruss2 = _makeSwitch(
      id: 'sw-truss-2',
      template: edgeTpl,
      label: 'Truss 2 Switch C',
      mac: '02:55:00:33:44:22',
      ip: '10.0.1.12',
      stpPriority: 32768,
      dx: 630,
      dy: 320,
      vlans: {
        1: const SwitchVlanSettings(vlanId: 1, vlanName: 'Default / Mgmt'),
        20: const SwitchVlanSettings(
          vlanId: 20,
          vlanName: 'sACN / Lighting',
          igmpSnoopingEnabled: true,
          igmpQuerierEnabled: false,
        ),
      },
    );
    // Mistake: VLAN 20 pruned from both uplinks into Truss 2!
    _setPortTrunk(swTruss2, 9, {1}, label: 'Forgot V20!');
    _setPortTrunk(swTruss2, 10, {1}, label: 'Forgot V20!');
    // Mistake: PoE node plugged into Port 9/10? Let's use Port 8 vs non-PoE distribution switch or disable PoE on Port 1:
    _setPortAccess(swTruss2, 1, 20, poeEnabled: false);

    final epTemplates = defaultEndpointTemplates();
    final epConsole = _makeEndpoint(
      id: 'ep-console-broken',
      template: epTemplates[0],
      label: 'Main Console',
      ip: '10.20.0.10',
      dx: 130,
      dy: 85,
    );
    final epNode1 = _makeEndpoint(
      id: 'ep-node-truss1',
      template: epTemplates[1],
      label: 'Truss 1 DMX Node',
      ip: '10.20.0.31',
      dx: 110,
      dy: 530,
    );
    final epNode2 = _makeEndpoint(
      id: 'ep-node-truss2',
      template: epTemplates[1],
      label: 'Truss 2 DMX Node',
      ip: '10.20.0.32',
      dx: 660,
      dy: 530,
    );

    final links = [
      NetworkLinkEdge(
        id: 'lnk-brk-1',
        sourceNodeId: swCore.id,
        sourcePortNumber: 17,
        targetNodeId: swTruss1.id,
        targetPortNumber: 9,
      ),
      NetworkLinkEdge(
        id: 'lnk-brk-2',
        sourceNodeId: swCore.id,
        sourcePortNumber: 18,
        targetNodeId: swTruss2.id,
        targetPortNumber: 9,
      ),
      NetworkLinkEdge(
        id: 'lnk-brk-3',
        sourceNodeId: swTruss1.id,
        sourcePortNumber: 10,
        targetNodeId: swTruss2.id,
        targetPortNumber: 10,
      ),
      NetworkLinkEdge(
        id: 'lnk-brk-ep-c',
        sourceNodeId: epConsole.id,
        sourcePortNumber: 1,
        targetNodeId: swCore.id,
        targetPortNumber: 1,
      ),
      NetworkLinkEdge(
        id: 'lnk-brk-ep-1',
        sourceNodeId: epNode1.id,
        sourcePortNumber: 1,
        targetNodeId: swTruss1.id,
        targetPortNumber: 1,
      ),
      NetworkLinkEdge(
        id: 'lnk-brk-ep-2',
        sourceNodeId: epNode2.id,
        sourcePortNumber: 1,
        targetNodeId: swTruss2.id,
        targetPortNumber: 1,
      ),
    ];

    return TopologyProject(
      name: 'Fault Demo: Arbitrary Root, VLAN 20 Blackhole & PoE Error',
      description:
          'Demonstrates MAC-tiebreak Root election (try Randomise MACs!), missing VLAN 20 on trunks isolating the IGMP Querier, and disabled PoE.',
      switches: [swCore, swTruss1, swTruss2],
      endpoints: [epConsole, epNode1, epNode2],
      links: links,
    );
  }

  /// Unmanaged switch loop + high-volume Art-Net broadcast saturating 100M links.
  static TopologyProject unmanagedLoopAndBroadcastDemo() {
    final legacyManaged = defaultSwitchTemplates()[3]; // 8x 100M + 2x 1G
    final unmanaged = defaultSwitchTemplates()[4]; // 5x 1G Unmanaged

    final swStage = _makeSwitch(
      id: 'sw-legacy-dimmer',
      template: legacyManaged,
      label: 'Dimmer Room 100M Switch',
      mac: '02:22:00:00:00:01',
      stpPriority: 4096,
      dx: 200,
      dy: 180,
      vlans: {
        1: const SwitchVlanSettings(vlanId: 1, vlanName: 'Default / Art-Net'),
      },
    );

    final swDumb = _makeSwitch(
      id: 'sw-unmanaged-box',
      template: unmanaged,
      label: 'Unmanaged Floor Hub',
      mac: '02:33:00:00:00:02',
      stpMode: StpMode.disabled,
      dx: 580,
      dy: 180,
      vlans: {
        1: const SwitchVlanSettings(vlanId: 1, vlanName: 'Default / Art-Net'),
      },
    );

    final epTemplates = defaultEndpointTemplates();
    final epPixel = _makeEndpoint(
      id: 'ep-pixel-ctrl',
      template: epTemplates[5],
      label: 'Art-Net Pixel Matrix',
      ip: '2.0.0.50',
      dx: 580,
      dy: 420,
    );
    final epNode100M = _makeEndpoint(
      id: 'ep-100m-node',
      template: epTemplates[1].copyWith(
        trafficProfiles: [
          const TrafficRequirement(
            id: 'flow-artnet-rx',
            protocol: TrafficProtocol.artNet,
            direction: TrafficDirection.rxSubscriber,
            deliveryType: DeliveryType.broadcast,
            estimatedBandwidthMbps: 2.0,
            requiresIgmp: false,
            defaultVlanId: 1,
            label: 'Art-Net RX',
          ),
        ],
      ),
      label: 'Legacy 100M DMX Node',
      ip: '2.0.0.60',
      dx: 200,
      dy: 420,
    );

    final links = [
      // Redundant cables into an unmanaged switch = unprotected L2 loop!
      NetworkLinkEdge(
        id: 'lnk-loop-1',
        sourceNodeId: swStage.id,
        sourcePortNumber: 9,
        targetNodeId: swDumb.id,
        targetPortNumber: 1,
      ),
      NetworkLinkEdge(
        id: 'lnk-loop-2',
        sourceNodeId: swStage.id,
        sourcePortNumber: 10,
        targetNodeId: swDumb.id,
        targetPortNumber: 2,
      ),
      NetworkLinkEdge(
        id: 'lnk-ep-pixel',
        sourceNodeId: epPixel.id,
        sourcePortNumber: 1,
        targetNodeId: swDumb.id,
        targetPortNumber: 3,
      ),
      NetworkLinkEdge(
        id: 'lnk-ep-100m',
        sourceNodeId: epNode100M.id,
        sourcePortNumber: 1,
        targetNodeId: swStage.id,
        targetPortNumber: 1,
      ),
    ];

    return TopologyProject(
      name: 'Fault Demo: Unmanaged Loop & 100M Art-Net Flood',
      description:
          'Shows an unprotected Layer 2 loop through an unmanaged switch plus 85 Mbps Art-Net broadcast flooding into 100M ports.',
      switches: [swStage, swDumb],
      endpoints: [epPixel, epNode100M],
      links: links,
    );
  }

  static SwitchNodeInstance _makeSwitch({
    required String id,
    required SwitchTemplate template,
    required String label,
    required String mac,
    String? ip,
    StpMode? stpMode,
    int stpPriority = 32768,
    required double dx,
    required double dy,
    required Map<int, SwitchVlanSettings> vlans,
  }) {
    return SwitchNodeInstance(
      id: id,
      templateId: template.id,
      userLabel: label,
      macAddress: mac,
      managementIp: ip,
      stpMode: stpMode ?? (template.supportsStp ? StpMode.rstp : StpMode.disabled),
      stpPriority: stpPriority,
      poeBudgetWatts: template.poeBudgetWatts,
      supportsStp: template.supportsStp,
      supportsVlans: template.supportsVlans,
      supportsIgmpSnooping: template.supportsIgmpSnooping,
      supportsIgmpQuerier: template.supportsIgmpQuerier,
      vlanConfigs: vlans,
      ports: template.generateDefaultPorts(),
      dx: dx,
      dy: dy,
    );
  }

  static EndpointNodeInstance _makeEndpoint({
    required String id,
    required EndpointTemplate template,
    required String label,
    String? ip,
    required double dx,
    required double dy,
  }) {
    return EndpointNodeInstance(
      id: id,
      templateId: template.id,
      userLabel: label,
      category: template.category,
      nicSpeed: template.nicSpeed,
      ipAddress: ip,
      activeTrafficFlows: List.from(template.trafficProfiles),
      poeDrawWatts: template.poeDrawWatts,
      dx: dx,
      dy: dy,
    );
  }

  static void _setPortTrunk(
    SwitchNodeInstance sw,
    int portNumber,
    Set<int> allowed, {
    int nativeVlan = 1,
    String? label,
  }) {
    final idx = sw.ports.indexWhere((p) => p.portNumber == portNumber);
    if (idx < 0) return;
    sw.ports[idx] = sw.ports[idx].copyWith(
      portMode: SwitchPortMode.trunk,
      nativeVlan: nativeVlan,
      allowedVlans: allowed,
      customLabel: label,
    );
  }

  static void _setPortAccess(
    SwitchNodeInstance sw,
    int portNumber,
    int vlan, {
    bool? poeEnabled,
    String? label,
  }) {
    final idx = sw.ports.indexWhere((p) => p.portNumber == portNumber);
    if (idx < 0) return;
    sw.ports[idx] = sw.ports[idx].copyWith(
      portMode: SwitchPortMode.access,
      nativeVlan: vlan,
      allowedVlans: {vlan},
      poeEnabled: poeEnabled,
      customLabel: label,
    );
  }
}
