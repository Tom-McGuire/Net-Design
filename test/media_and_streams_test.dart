import 'package:flutter_test/flutter_test.dart';
import 'package:net_design/data/services/device_templates.dart';
import 'package:net_design/domain/engine/multicast_flow_tracer.dart';
import 'package:net_design/domain/engine/multicast_stream_resolver.dart';
import 'package:net_design/domain/engine/topology_validator.dart';
import 'package:net_design/domain/models/endpoint_node_instance.dart';
import 'package:net_design/domain/models/endpoint_template.dart';
import 'package:net_design/domain/models/enums.dart';
import 'package:net_design/domain/models/network_link_edge.dart';
import 'package:net_design/domain/models/switch_node_instance.dart';
import 'package:net_design/domain/models/switch_port_config.dart';
import 'package:net_design/domain/models/switch_template.dart';
import 'package:net_design/domain/models/topology_project.dart';
import 'package:net_design/ui/features/sandbox_view_model.dart';

void main() {
  group('Physical Port Media & Multi-Port Endpoints', () {
    test('SwitchTemplate generates RJ45 and SFP ports with strict PoE/speed rules', () {
      final tpl = SwitchTemplate(
        id: 'tpl-test-hybrid',
        name: '8G PoE + 2x1G SFP + 2x10G SFP+',
        ports1G: 8,
        sfpPorts1G: 2,
        sfpPorts10G: 2,
        poeBudgetWatts: 180,
        poeStartPort: 1,
        poeEndPort: 12, // Intentional overshoot into SFP range
      );

      final ports = tpl.generateDefaultPorts();
      expect(ports.length, 12);
      for (var i = 0; i < 8; i++) {
        expect(ports[i].mediaType, PortMediaType.rj45);
        expect(ports[i].maxSpeed, PortSpeed.speed1G);
        expect(ports[i].poeCapable, isTrue);
      }
      for (var i = 8; i < 10; i++) {
        expect(ports[i].mediaType, PortMediaType.sfpFibre);
        expect(ports[i].maxSpeed, PortSpeed.speed1G);
        expect(ports[i].poeCapable, isFalse);
        expect(ports[i].poeEnabled, isFalse);
      }
      for (var i = 10; i < 12; i++) {
        expect(ports[i].mediaType, PortMediaType.sfpFibre);
        expect(ports[i].maxSpeed, PortSpeed.speed10G);
        expect(ports[i].poeCapable, isFalse);
      }

      // Direct SwitchPortConfig normalization prevents 100M/PoE on SFP
      final normalizedSfp = SwitchPortConfig(
        portNumber: 9,
        mediaType: PortMediaType.sfpFibre,
        maxSpeed: PortSpeed.speed100M,
        poeCapable: true,
        poeEnabled: true,
      );
      expect(normalizedSfp.maxSpeed, PortSpeed.speed1G);
      expect(normalizedSfp.poeCapable, isFalse);
      expect(normalizedSfp.poeEnabled, isFalse);
    });

    test('SandboxViewModel blocks RJ45-to-SFP wiring and solver flags injected mismatch as Critical', () {
      final swTpl = SwitchTemplate(
        id: 'tpl-sw',
        name: 'Hybrid',
        ports1G: 4,
        sfpPorts1G: 2,
      );
      final swA = SwitchNodeInstance(
        id: 'sw-a',
        templateId: swTpl.id,
        userLabel: 'Switch A',
        macAddress: '02:00:00:00:00:01',
        ports: swTpl.generateDefaultPorts(),
      );
      final swB = SwitchNodeInstance(
        id: 'sw-b',
        templateId: swTpl.id,
        userLabel: 'Switch B',
        macAddress: '02:00:00:00:00:02',
        ports: swTpl.generateDefaultPorts(),
      );

      final vm = SandboxViewModel(
        initialProject: TopologyProject(
          name: 'Media Check',
          switches: [swA, swB],
        ),
      );

      // Port 1 = RJ45, Port 5 = 1G SFP -> wiring must be refused.
      vm.startWiringFromPort('sw-a', 1);
      final ok = vm.completeWiringToPort('sw-b', 5);
      expect(ok, isFalse);
      expect(vm.project.links, isEmpty);
      expect(vm.lastStatusMessage, contains('Media mismatch'));

      // Now test injected RJ45<->SFP link in validator
      final dirtyProject = TopologyProject(
        name: 'Injected Mismatch',
        switches: [swA, swB],
        links: [
          NetworkLinkEdge(
            id: 'lnk-bad-media',
            sourceNodeId: 'sw-a',
            sourcePortNumber: 1,
            targetNodeId: 'sw-b',
            targetPortNumber: 5,
          ),
        ],
      );
      final result = const TopologyValidator().validate(dirtyProject);
      expect(dirtyProject.links.first.hasMediaMismatch, isTrue);
      final mismatchIssue = result.issues.firstWhere(
        (i) => i.id == 'media-mismatch-lnk-bad-media',
      );
      expect(mismatchIssue.severity, IssueSeverity.critical);
    });

    test('10G SFP+ to 1G SFP negotiates 1G with Warning transceiver notice', () {
      final swTpl = SwitchTemplate(
        id: 'tpl-sw-sfp',
        name: 'SFP Mix',
        ports1G: 0,
        sfpPorts1G: 1,
        sfpPorts10G: 1,
      );
      final sw1 = SwitchNodeInstance(
        id: 'sw-1',
        templateId: swTpl.id,
        userLabel: 'Core 10G SFP+',
        macAddress: '02:00:00:00:00:11',
        ports: swTpl.generateDefaultPorts(), // P1=1G SFP, P2=10G SFP+
      );
      final sw2 = SwitchNodeInstance(
        id: 'sw-2',
        templateId: swTpl.id,
        userLabel: 'Edge 1G SFP',
        macAddress: '02:00:00:00:00:12',
        ports: swTpl.generateDefaultPorts(),
      );
      final project = TopologyProject(
        name: 'SFP StepDown',
        switches: [sw1, sw2],
        links: [
          NetworkLinkEdge(
            id: 'lnk-sfp-mix',
            sourceNodeId: 'sw-1',
            sourcePortNumber: 2, // 10G SFP+
            targetNodeId: 'sw-2',
            targetPortNumber: 1, // 1G SFP
          ),
        ],
      );

      final val = const TopologyValidator().validate(project);
      final link = project.links.first;
      expect(link.hasMediaMismatch, isFalse);
      expect(link.isSfpStepDown, isTrue);
      expect(link.negotiatedSpeed, PortSpeed.speed1G);
      final warn = val.issues.firstWhere((i) => i.id == 'bw-stepdown-lnk-sfp-mix');
      expect(warn.severity, IssueSeverity.warning);
    });

    test('Multi-NIC endpoint segregates VLANs and traffic per NIC without switching across NICs', () {
      final coreTpl = SwitchTemplate(
        id: 'tpl-core',
        name: 'Core',
        ports1G: 4,
        sfpPorts10G: 2,
      );
      final swCore = SwitchNodeInstance(
        id: 'sw-core',
        templateId: coreTpl.id,
        userLabel: 'Core',
        macAddress: '02:00:00:00:00:21',
        ports: [
          for (final p in coreTpl.generateDefaultPorts())
            p.copyWith(nativeVlan: p.portNumber == 5 ? 40 : 20),
        ],
      );
      final mediaServer = EndpointNodeInstance(
        id: 'ep-srv',
        templateId: 'tpl-ep-media-server',
        userLabel: 'Dual-NIC Server',
        category: EndpointCategory.mediaServer,
        nicSpeed: PortSpeed.speed10G,
        ports: const [
          EndpointPortConfig(
            portNumber: 1,
            label: 'Video SFP+',
            mediaType: PortMediaType.sfpFibre,
            speed: PortSpeed.speed10G,
          ),
          EndpointPortConfig(
            portNumber: 2,
            label: 'Lighting Control',
            mediaType: PortMediaType.rj45,
            speed: PortSpeed.speed1G,
          ),
        ],
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'flow-ndi',
            protocol: TrafficProtocol.ndiVideo,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 250.0,
            requiresIgmp: true,
            defaultVlanId: 40,
            boundPortNumber: 1,
            multicastGroupSpec: '239.255.10.1-2',
          ),
          TrafficRequirement(
            id: 'flow-sacn',
            protocol: TrafficProtocol.sacn,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 4.0,
            requiresIgmp: true,
            defaultVlanId: 20,
            boundPortNumber: 2,
            sacnUniverseSpec: '1-16',
          ),
        ],
      );

      final project = TopologyProject(
        name: 'Multi-NIC Segregation',
        switches: [swCore],
        endpoints: [mediaServer],
        links: [
          NetworkLinkEdge(
            id: 'lnk-nic1-sfp',
            sourceNodeId: 'ep-srv',
            sourcePortNumber: 1,
            targetNodeId: 'sw-core',
            targetPortNumber: 5, // 10G SFP+ on VLAN 40
          ),
          NetworkLinkEdge(
            id: 'lnk-nic2-rj45',
            sourceNodeId: 'ep-srv',
            sourcePortNumber: 2,
            targetNodeId: 'sw-core',
            targetPortNumber: 1, // 1G RJ45 on VLAN 20
          ),
        ],
      );

      const TopologyValidator().validate(project);
      final linkSfp = project.links.firstWhere((l) => l.id == 'lnk-nic1-sfp');
      final linkRj45 = project.links.firstWhere((l) => l.id == 'lnk-nic2-rj45');
      expect(linkSfp.estimatedLoadMbps, closeTo(250.0, 0.01));
      expect(linkRj45.estimatedLoadMbps, closeTo(4.0, 0.01));
      expect(linkSfp.activeVlans, {40});
      expect(linkRj45.activeVlans, {20});
    });

    test('Backwards compatibility migrates legacy single-NIC JSON and deserializes SFP counts', () {
      final legacyTpl = EndpointTemplate.fromJson({
        'id': 'legacy-node',
        'name': 'Legacy DMX Node',
        'category': 'gatewayNode',
        'nicSpeed': 'speed100M',
        'poeDrawWatts': 12.5,
      });
      expect(legacyTpl.effectivePorts.length, 1);
      expect(legacyTpl.effectivePorts.first.mediaType, PortMediaType.rj45);
      expect(legacyTpl.effectivePorts.first.speed, PortSpeed.speed100M);
      expect(legacyTpl.effectivePorts.first.poeDrawWatts, 12.5);

      final legacyInstance = EndpointNodeInstance.fromJson({
        'id': 'ep-legacy',
        'templateId': 'legacy-node',
        'userLabel': 'Old Node',
        'category': 'gatewayNode',
        'nicSpeed': 'speed100M',
        'poeDrawWatts': 9.0,
      });
      expect(legacyInstance.effectivePorts.length, 1);
      expect(legacyInstance.totalPoeDrawWatts, 9.0);

      final swTpl = SwitchTemplate(
        id: 'sw-roundtrip',
        name: 'Roundtrip',
        ports1G: 8,
        sfpPorts1G: 2,
        sfpPorts10G: 2,
      );
      final roundtrip = SwitchTemplate.fromJson(swTpl.toJson());
      expect(roundtrip.sfpPorts1G, 2);
      expect(roundtrip.sfpPorts10G, 2);
      expect(roundtrip.totalPorts, 12);
    });
  });

  group('Multicast Stream & sACN Flow Tracer', () {
    test('MulticastStreamResolver parses sACN universe specs, IPs, bandwidth, and rejects invalid inputs', () {
      final sacn = MulticastStreamResolver.parseSacnUniverses('1-8, 20');
      expect(sacn.error, isNull);
      expect(sacn.universes, [1, 2, 3, 4, 5, 6, 7, 8, 20]);
      expect(MulticastStreamResolver.sacnBandwidthMbps(9), closeTo(2.25, 0.0001));
      expect(MulticastStreamResolver.sacnUniverseToIp(1), '239.255.0.1');
      expect(MulticastStreamResolver.sacnUniverseToIp(257), '239.255.1.1');

      final mcast = MulticastStreamResolver.parseMulticastGroups('239.69.0.1-4, 239.255.10.1');
      expect(mcast.error, isNull);
      expect(mcast.ips, [
        '239.69.0.1',
        '239.69.0.2',
        '239.69.0.3',
        '239.69.0.4',
        '239.255.10.1',
      ]);

      expect(MulticastStreamResolver.parseSacnUniverses('0').error, isNotNull);
      expect(MulticastStreamResolver.parseSacnUniverses('10-5').error, isNotNull);
      expect(MulticastStreamResolver.parseMulticastGroups('10.0.0.1').error, isNotNull);
    });

    test('Stream trace shows Delivered to subscribed branch and IGMP Pruned to unsubscribed branch, Flooded without IGMP Snooping', () {
      final project = DeviceTemplates.healthyReferenceRingDemo();
      const TopologyValidator().validate(project);

      // In healthyReferenceRingDemo, ep-node-l subscribes U1-4, ep-node-r subscribes U5-8.
      // Trace U1-4 specifically via Stage Left Node RX trace target:
      final targets = MulticastFlowTracer.buildTraceTargets(project);
      final u14Target = targets.firstWhere(
        (t) => t.id.contains('ep-node-l'),
      );

      MulticastFlowTracer.applyTrace(project: project, target: u14Target);

      final linkConsole = project.links.firstWhere((l) => l.id == 'lnk-ep-console');
      final linkCoreLeft = project.links.firstWhere((l) => l.id == 'lnk-core-left');
      final linkEpLeft = project.links.firstWhere((l) => l.id == 'lnk-ep-node-l');
      final linkCoreRight = project.links.firstWhere((l) => l.id == 'lnk-core-right');
      final linkEpRight = project.links.firstWhere((l) => l.id == 'lnk-ep-node-r');

      expect(linkConsole.streamTraceState, LinkStreamTraceState.delivered);
      expect(linkCoreLeft.streamTraceState, LinkStreamTraceState.delivered);
      expect(linkEpLeft.streamTraceState, LinkStreamTraceState.delivered);
      expect(linkCoreLeft.tracedStreamCount, 4);
      expect(linkCoreRight.streamTraceState, LinkStreamTraceState.igmpPruned);
      expect(linkEpRight.streamTraceState, LinkStreamTraceState.igmpPruned);

      // Disable IGMP Snooping on VLAN 20 across all switches -> unsubscribed branch should flood!
      final floodedSwitches = [
        for (final sw in project.switches)
          sw.copyWith(
            vlanConfigs: {
              ...sw.vlanConfigs,
              20: sw.vlanConfigs[20]!.copyWith(igmpSnoopingEnabled: false),
            },
          ),
      ];
      final floodedProject = project.copyWith(switches: floodedSwitches);
      const TopologyValidator().validate(floodedProject);
      MulticastFlowTracer.applyTrace(project: floodedProject, target: u14Target);

      final floodedCoreRight =
          floodedProject.links.firstWhere((l) => l.id == 'lnk-core-right');
      expect(floodedCoreRight.streamTraceState, LinkStreamTraceState.flooded);
    });

    test('MulticastFlowTracer detects duplicate TX publishers and orphan RX subscribers', () {
      final swTpl = SwitchTemplate(id: 'sw', name: 'SW', ports1G: 4);
      final sw = SwitchNodeInstance(
        id: 'sw-1',
        templateId: swTpl.id,
        userLabel: 'Switch 1',
        macAddress: '02:00:00:00:00:31',
        ports: [
          for (final p in swTpl.generateDefaultPorts()) p.copyWith(nativeVlan: 20),
        ],
      );
      final txA = EndpointNodeInstance(
        id: 'ep-tx-a',
        templateId: 't',
        userLabel: 'Console A',
        category: EndpointCategory.console,
        nicSpeed: PortSpeed.speed1G,
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f1',
            protocol: TrafficProtocol.sacn,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 1.0,
            requiresIgmp: true,
            defaultVlanId: 20,
            sacnUniverseSpec: '1-4',
          ),
        ],
      );
      final txB = EndpointNodeInstance(
        id: 'ep-tx-b',
        templateId: 't',
        userLabel: 'Console B',
        category: EndpointCategory.console,
        nicSpeed: PortSpeed.speed1G,
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f2',
            protocol: TrafficProtocol.sacn,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 1.0,
            requiresIgmp: true,
            defaultVlanId: 20,
            sacnUniverseSpec: '3-6', // Overlaps U3, U4!
          ),
        ],
      );
      final rxOrphan = EndpointNodeInstance(
        id: 'ep-rx-orphan',
        templateId: 't',
        userLabel: 'Node Orphan',
        category: EndpointCategory.gatewayNode,
        nicSpeed: PortSpeed.speed1G,
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f3',
            protocol: TrafficProtocol.sacn,
            direction: TrafficDirection.rxSubscriber,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 0.5,
            requiresIgmp: true,
            defaultVlanId: 20,
            sacnUniverseSpec: '99-100', // No publisher!
          ),
        ],
      );

      final project = TopologyProject(
        name: 'Conflicts',
        switches: [sw],
        endpoints: [txA, txB, rxOrphan],
        links: [
          NetworkLinkEdge(
            id: 'l1',
            sourceNodeId: 'ep-tx-a',
            sourcePortNumber: 1,
            targetNodeId: 'sw-1',
            targetPortNumber: 1,
          ),
          NetworkLinkEdge(
            id: 'l2',
            sourceNodeId: 'ep-tx-b',
            sourcePortNumber: 1,
            targetNodeId: 'sw-1',
            targetPortNumber: 2,
          ),
          NetworkLinkEdge(
            id: 'l3',
            sourceNodeId: 'ep-rx-orphan',
            sourcePortNumber: 1,
            targetNodeId: 'sw-1',
            targetPortNumber: 3,
          ),
        ],
      );

      final res = const TopologyValidator().validate(project);
      expect(
        res.issues.any((i) => i.title == 'Duplicate TX Stream Collision'),
        isTrue,
      );
      expect(
        res.issues.any((i) => i.title == 'Orphan RX Stream Subscription'),
        isTrue,
      );
    });
  });
}
