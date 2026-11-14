import 'package:flutter_test/flutter_test.dart';
import 'package:net_design/domain/engine/topology_validator.dart';
import 'package:net_design/domain/models/endpoint_node_instance.dart';
import 'package:net_design/domain/models/endpoint_template.dart';
import 'package:net_design/domain/models/enums.dart';
import 'package:net_design/domain/models/network_link_edge.dart';
import 'package:net_design/domain/models/switch_node_instance.dart';
import 'package:net_design/domain/models/switch_port_config.dart';
import 'package:net_design/domain/models/topology_project.dart';

void main() {
  const validator = TopologyValidator();

  group('VlanReachabilitySolver', () {
    test('detects VLAN 20 blackhole when trunk link omits VLAN 20', () {
      final swA = SwitchNodeInstance(
        id: 'sw-a',
        templateId: 'tpl-sw',
        userLabel: 'FOH Switch',
        macAddress: '02:00:00:00:00:01',
        stpPriority: 4096,
        ports: [
          SwitchPortConfig(
            portNumber: 1,
            portMode: SwitchPortMode.access,
            nativeVlan: 20,
          ),
          SwitchPortConfig(
            portNumber: 2,
            portMode: SwitchPortMode.trunk,
            nativeVlan: 1,
            // OMITS VLAN 20 on trunk uplink!
            allowedVlans: const {1, 10},
          ),
        ],
      );

      final swB = SwitchNodeInstance(
        id: 'sw-b',
        templateId: 'tpl-sw',
        userLabel: 'Stage Switch',
        macAddress: '02:00:00:00:00:02',
        stpPriority: 32768,
        ports: [
          SwitchPortConfig(
            portNumber: 1,
            portMode: SwitchPortMode.access,
            nativeVlan: 20,
          ),
          SwitchPortConfig(
            portNumber: 2,
            portMode: SwitchPortMode.trunk,
            nativeVlan: 1,
            // Stage trunk allows VLAN 20, FOH does not
            allowedVlans: const {1, 10, 20},
          ),
        ],
      );

      final console = EndpointNodeInstance(
        id: 'ep-console',
        templateId: 'tpl-console',
        userLabel: 'Lighting Console',
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f-tx',
            protocol: TrafficProtocol.sacn,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 4.0,
            requiresIgmp: true,
            defaultVlanId: 20,
          ),
        ],
      );

      final node = EndpointNodeInstance(
        id: 'ep-node',
        templateId: 'tpl-node',
        userLabel: 'DMX Gateway',
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f-rx',
            protocol: TrafficProtocol.sacn,
            direction: TrafficDirection.rxSubscriber,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 4.0,
            requiresIgmp: true,
            defaultVlanId: 20,
          ),
        ],
      );

      final result = validator.validate(
        TopologyProject(
          name: 'VLAN 20 Blackhole',
          switches: [swA, swB],
          endpoints: [console, node],
          links: [
            NetworkLinkEdge(
              id: 'l-ep-a',
              sourceNodeId: 'ep-console',
              sourcePortNumber: 1,
              targetNodeId: 'sw-a',
              targetPortNumber: 1,
            ),
            NetworkLinkEdge(
              id: 'l-ab',
              sourceNodeId: 'sw-a',
              sourcePortNumber: 2,
              targetNodeId: 'sw-b',
              targetPortNumber: 2,
            ),
            NetworkLinkEdge(
              id: 'l-ep-b',
              sourceNodeId: 'ep-node',
              sourcePortNumber: 1,
              targetNodeId: 'sw-b',
              targetPortNumber: 1,
            ),
          ],
        ),
      );

      expect(
        result.issues.any((i) =>
            i.category == IssueCategory.vlan &&
            i.severity == IssueSeverity.critical &&
            i.id.startsWith('vlan-blackhole-') &&
            i.vlanId == 20),
        isTrue,
      );
      expect(
        result.issues.any((i) =>
            i.category == IssueCategory.vlan &&
            i.severity == IssueSeverity.warning &&
            i.id.startsWith('vlan-asym-')),
        isTrue,
      );
    });

    test('uses alternate forwarding ring path when direct path is STP-blocked', () {
      SwitchNodeInstance makeSwitch(String id, String mac, int prio) {
        return SwitchNodeInstance(
          id: id,
          templateId: 'tpl-sw',
          userLabel: id.toUpperCase(),
          macAddress: mac,
          stpPriority: prio,
          ports: [
            SwitchPortConfig(
              portNumber: 1,
              portMode: SwitchPortMode.access,
              nativeVlan: 20,
            ),
            SwitchPortConfig(
              portNumber: 2,
              portMode: SwitchPortMode.trunk,
              nativeVlan: 1,
              allowedVlans: const {1, 20},
            ),
            SwitchPortConfig(
              portNumber: 3,
              portMode: SwitchPortMode.trunk,
              nativeVlan: 1,
              allowedVlans: const {1, 20},
            ),
          ],
        );
      }

      final swA = makeSwitch('sw-a', '02:00:00:00:00:01', 4096); // Root
      final swB = makeSwitch('sw-b', '02:00:00:00:00:02', 32768);
      final swC = makeSwitch('sw-c', '02:00:00:00:00:03', 32768);

      final epB = EndpointNodeInstance(
        id: 'ep-b',
        templateId: 'tpl-tx',
        userLabel: 'Publisher B',
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f-tx',
            protocol: TrafficProtocol.sacn,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 2.0,
            requiresIgmp: true,
            defaultVlanId: 20,
          ),
        ],
      );
      final epC = EndpointNodeInstance(
        id: 'ep-c',
        templateId: 'tpl-rx',
        userLabel: 'Subscriber C',
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f-rx',
            protocol: TrafficProtocol.sacn,
            direction: TrafficDirection.rxSubscriber,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 2.0,
            requiresIgmp: true,
            defaultVlanId: 20,
          ),
        ],
      );

      final linkBC = NetworkLinkEdge(
        id: 'l-bc',
        sourceNodeId: 'sw-b',
        sourcePortNumber: 3,
        targetNodeId: 'sw-c',
        targetPortNumber: 3,
      );

      final result = validator.validate(
        TopologyProject(
          name: 'Ring Routing Around STP Block',
          switches: [swA, swB, swC],
          endpoints: [epB, epC],
          links: [
            NetworkLinkEdge(
              id: 'l-ab',
              sourceNodeId: 'sw-a',
              sourcePortNumber: 2,
              targetNodeId: 'sw-b',
              targetPortNumber: 2,
            ),
            NetworkLinkEdge(
              id: 'l-ac',
              sourceNodeId: 'sw-a',
              sourcePortNumber: 3,
              targetNodeId: 'sw-c',
              targetPortNumber: 2,
            ),
            linkBC,
            NetworkLinkEdge(
              id: 'l-ep-b',
              sourceNodeId: 'ep-b',
              sourcePortNumber: 1,
              targetNodeId: 'sw-b',
              targetPortNumber: 1,
            ),
            NetworkLinkEdge(
              id: 'l-ep-c',
              sourceNodeId: 'ep-c',
              sourcePortNumber: 1,
              targetNodeId: 'sw-c',
              targetPortNumber: 1,
            ),
          ],
        ),
      );

      // Direct B<->C link is STP blocking, so traffic must traverse B -> A (Root) -> C
      expect(linkBC.stpState, equals(LinkStpState.blocking));
      expect(
        result.issues.any((i) => i.id.startsWith('vlan-blackhole-')),
        isFalse,
      );
    });

    test('flags access-to-trunk mismatch and native VLAN mismatch as critical', () {
      final swA = SwitchNodeInstance(
        id: 'sw-a',
        templateId: 'tpl-sw',
        userLabel: 'Switch A',
        macAddress: '02:00:00:00:00:01',
        stpPriority: 4096,
        ports: [
          SwitchPortConfig(
            portNumber: 1,
            portMode: SwitchPortMode.access,
            nativeVlan: 10,
          ),
          SwitchPortConfig(
            portNumber: 2,
            portMode: SwitchPortMode.trunk,
            nativeVlan: 1,
            allowedVlans: const {1, 10, 20},
          ),
        ],
      );
      final swB = SwitchNodeInstance(
        id: 'sw-b',
        templateId: 'tpl-sw',
        userLabel: 'Switch B',
        macAddress: '02:00:00:00:00:02',
        stpPriority: 32768,
        ports: [
          SwitchPortConfig(
            portNumber: 1,
            portMode: SwitchPortMode.trunk,
            nativeVlan: 1,
            allowedVlans: const {1, 10},
          ),
          SwitchPortConfig(
            portNumber: 2,
            portMode: SwitchPortMode.trunk,
            nativeVlan: 99,
            allowedVlans: const {99, 10, 20},
          ),
        ],
      );
      final swC = SwitchNodeInstance(
        id: 'sw-c',
        templateId: 'tpl-sw',
        userLabel: 'Switch C',
        macAddress: '02:00:00:00:00:03',
        stpPriority: 32768,
        ports: [
          SwitchPortConfig(
            portNumber: 2,
            portMode: SwitchPortMode.trunk,
            nativeVlan: 1,
            allowedVlans: const {1, 10, 20},
          ),
        ],
      );

      final result = validator.validate(
        TopologyProject(
          name: 'Port Mismatches',
          switches: [swA, swB, swC],
          links: [
            // Access port 1 <-> Trunk port 1
            NetworkLinkEdge(
              id: 'l-mode',
              sourceNodeId: 'sw-a',
              sourcePortNumber: 1,
              targetNodeId: 'sw-b',
              targetPortNumber: 1,
            ),
            // Trunk native 99 <-> Trunk native 1
            NetworkLinkEdge(
              id: 'l-native',
              sourceNodeId: 'sw-b',
              sourcePortNumber: 2,
              targetNodeId: 'sw-c',
              targetPortNumber: 2,
            ),
          ],
        ),
      );

      expect(
        result.issues.any((i) =>
            i.id == 'vlan-mode-mismatch-l-mode' &&
            i.severity == IssueSeverity.critical),
        isTrue,
      );
      expect(
        result.issues.any((i) =>
            i.id == 'vlan-native-mismatch-l-native' &&
            i.severity == IssueSeverity.critical),
        isTrue,
      );
    });
  });
}
