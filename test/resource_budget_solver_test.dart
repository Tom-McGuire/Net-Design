import 'package:flutter_test/flutter_test.dart';
import 'package:net_design/data/services/device_templates.dart';
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

  group('ResourceBudgetSolver & Demo Scenarios', () {
    test('flags link utilization >75% Warning, >95% Critical, and speed step-down Info', () {
      SwitchNodeInstance makeSw(String id, String mac, int prio, PortSpeed uplinkSpeed) {
        return SwitchNodeInstance(
          id: id,
          templateId: 'tpl-sw',
          userLabel: id,
          macAddress: mac,
          stpPriority: prio,
          vlanConfigs: {
            10: const SwitchVlanSettings(
              vlanId: 10,
              vlanName: 'Video',
              igmpSnoopingEnabled: true,
              igmpQuerierEnabled: true,
            ),
          },
          ports: [
            SwitchPortConfig(
              portNumber: 1,
              maxSpeed: PortSpeed.speed1G,
              portMode: SwitchPortMode.access,
              nativeVlan: 10,
            ),
            SwitchPortConfig(
              portNumber: 2,
              maxSpeed: uplinkSpeed,
              portMode: SwitchPortMode.trunk,
              nativeVlan: 10,
              allowedVlans: const {1, 10},
            ),
          ],
        );
      }

      // 80 Mbps over 100M link -> 80% (>75% Warning), 1G <-> 100M step-down -> Info
      final swA = makeSw('sw-a', '02:00:00:00:00:01', 4096, PortSpeed.speed1G);
      final swB = makeSw('sw-b', '02:00:00:00:00:02', 32768, PortSpeed.speed100M);

      final epA = EndpointNodeInstance(
        id: 'ep-tx',
        templateId: 'tpl-tx',
        userLabel: 'Tx 80M',
        nicSpeed: PortSpeed.speed1G,
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f-tx',
            protocol: TrafficProtocol.ndiVideo,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 80.0,
            requiresIgmp: true,
            defaultVlanId: 10,
          ),
        ],
      );
      final epB = EndpointNodeInstance(
        id: 'ep-rx',
        templateId: 'tpl-rx',
        userLabel: 'Rx',
        nicSpeed: PortSpeed.speed1G,
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f-rx',
            protocol: TrafficProtocol.ndiVideo,
            direction: TrafficDirection.rxSubscriber,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 80.0,
            requiresIgmp: true,
            defaultVlanId: 10,
          ),
        ],
      );

      final uplink = NetworkLinkEdge(
        id: 'l-up',
        sourceNodeId: 'sw-a',
        sourcePortNumber: 2,
        targetNodeId: 'sw-b',
        targetPortNumber: 2,
      );

      final links = [
        NetworkLinkEdge(
          id: 'l-ep-a',
          sourceNodeId: 'ep-tx',
          sourcePortNumber: 1,
          targetNodeId: 'sw-a',
          targetPortNumber: 1,
        ),
        uplink,
        NetworkLinkEdge(
          id: 'l-ep-b',
          sourceNodeId: 'ep-rx',
          sourcePortNumber: 1,
          targetNodeId: 'sw-b',
          targetPortNumber: 1,
        ),
      ];

      final resWarn = validator.validate(
        TopologyProject(
          name: '80% Uplink',
          switches: [swA, swB],
          endpoints: [epA, epB],
          links: links,
        ),
      );

      expect(uplink.negotiatedSpeed, equals(PortSpeed.speed100M));
      expect(uplink.hasSpeedStepDown, isTrue);
      expect(uplink.utilizationPercent, closeTo(80.0, 0.01));
      expect(
        resWarn.issues.any((i) =>
            i.id == 'bw-stepdown-l-up' && i.severity == IssueSeverity.info),
        isTrue,
      );
      expect(
        resWarn.issues.any((i) =>
            i.id == 'bw-util-l-up' && i.severity == IssueSeverity.warning),
        isTrue,
      );

      // Push traffic to 98 Mbps (>95% Critical)
      final epTxHeavy = epA.copyWith(
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f-tx',
            protocol: TrafficProtocol.ndiVideo,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 98.0,
            requiresIgmp: true,
            defaultVlanId: 10,
          ),
        ],
      );

      final resCrit = validator.validate(
        TopologyProject(
          name: '98% Uplink',
          switches: [swA, swB],
          endpoints: [epTxHeavy, epB],
          links: links,
        ),
      );

      expect(
        resCrit.issues.any((i) =>
            i.id == 'bw-util-l-up' && i.severity == IssueSeverity.critical),
        isTrue,
      );
    });

    test('detects missing PoE capability and PoE budget thresholds (>80% Warning, >100% Critical)', () {
      final sw = SwitchNodeInstance(
        id: 'sw-poe',
        templateId: 'tpl-sw',
        userLabel: 'PoE Switch',
        macAddress: '02:00:00:00:00:01',
        poeBudgetWatts: 100,
        ports: [
          SwitchPortConfig(portNumber: 1, poeCapable: true, poeEnabled: true),
          SwitchPortConfig(portNumber: 2, poeCapable: true, poeEnabled: true),
          SwitchPortConfig(portNumber: 3, poeCapable: false, poeEnabled: false),
        ],
      );

      final ep1 = EndpointNodeInstance(
        id: 'ep-1',
        templateId: 'tpl-ep',
        userLabel: 'Node 1',
        poeDrawWatts: 85.0, // 85 / 100 = 85% Warning
      );
      final ep2 = EndpointNodeInstance(
        id: 'ep-2',
        templateId: 'tpl-ep',
        userLabel: 'Node 2',
        poeDrawWatts: 25.0,
      );
      final epNoPoePort = EndpointNodeInstance(
        id: 'ep-3',
        templateId: 'tpl-ep',
        userLabel: 'Node on Non-PoE',
        poeDrawWatts: 15.0,
      );

      // Case 1: 85W on 100W budget (>80% Warning)
      final res85 = validator.validate(
        TopologyProject(
          name: 'PoE 85%',
          switches: [sw],
          endpoints: [ep1],
          links: [
            NetworkLinkEdge(
              id: 'l-1',
              sourceNodeId: 'ep-1',
              sourcePortNumber: 1,
              targetNodeId: 'sw-poe',
              targetPortNumber: 1,
            ),
          ],
        ),
      );
      expect(
        res85.issues.any((i) =>
            i.id == 'poe-budget-high-sw-poe' &&
            i.severity == IssueSeverity.warning),
        isTrue,
      );

      // Case 2: 85W + 25W = 110W on 100W budget (>100% Critical) + Port 3 missing PoE
      final resOver = validator.validate(
        TopologyProject(
          name: 'PoE Over',
          switches: [sw],
          endpoints: [ep1, ep2, epNoPoePort],
          links: [
            NetworkLinkEdge(
              id: 'l-1',
              sourceNodeId: 'ep-1',
              sourcePortNumber: 1,
              targetNodeId: 'sw-poe',
              targetPortNumber: 1,
            ),
            NetworkLinkEdge(
              id: 'l-2',
              sourceNodeId: 'ep-2',
              sourcePortNumber: 1,
              targetNodeId: 'sw-poe',
              targetPortNumber: 2,
            ),
            NetworkLinkEdge(
              id: 'l-3',
              sourceNodeId: 'ep-3',
              sourcePortNumber: 1,
              targetNodeId: 'sw-poe',
              targetPortNumber: 3,
            ),
          ],
        ),
      );

      expect(
        resOver.issues.any((i) =>
            i.id == 'poe-budget-over-sw-poe' &&
            i.severity == IssueSeverity.critical),
        isTrue,
      );
      expect(
        resOver.issues.any((i) =>
            i.id == 'poe-port-incapable-ep-3' &&
            i.severity == IssueSeverity.critical),
        isTrue,
      );
    });

    test('built-in DeviceTemplates scenarios produce expected health profiles', () {
      final healthy = validator.validate(DeviceTemplates.healthyReferenceRingDemo());
      expect(healthy.isHealthy, isTrue);
      expect(healthy.criticalCount, equals(0));
      expect(healthy.warningCount, equals(0));
      expect(healthy.blockingLinkCount, equals(1));
      expect(healthy.rootBridgeIds.length, equals(1));

      final broken = validator.validate(DeviceTemplates.brokenRingFaultDemo());
      expect(broken.criticalCount, greaterThan(0));
      expect(broken.warningCount, greaterThan(0));

      final unmanaged =
          validator.validate(DeviceTemplates.unmanagedLoopAndBroadcastDemo());
      expect(unmanaged.unprotectedLoopCount, greaterThan(0));
      expect(unmanaged.criticalCount, greaterThan(0));
    });
  });
}
