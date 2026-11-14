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

  group('IgmpDomainSolver', () {
    test('flags IGMP Snooping without Active Querier as Critical (even when isolated by trunk pruning)', () {
      // Core has Querier on VLAN 20, but trunk link only carries VLAN 1 (pruning VLAN 20).
      // Stage has Snooping on VLAN 20 -> isolated subgraph without Querier -> Critical!
      final core = SwitchNodeInstance(
        id: 'sw-core',
        templateId: 'tpl-sw',
        userLabel: 'Core Switch',
        macAddress: '02:00:00:00:00:01',
        stpPriority: 4096,
        managementIp: '10.0.0.1',
        vlanConfigs: {
          1: const SwitchVlanSettings(vlanId: 1, vlanName: 'Mgmt'),
          20: const SwitchVlanSettings(
            vlanId: 20,
            vlanName: 'sACN',
            igmpSnoopingEnabled: true,
            igmpQuerierEnabled: true,
          ),
        },
        ports: [
          SwitchPortConfig(
            portNumber: 1,
            portMode: SwitchPortMode.trunk,
            nativeVlan: 1,
            allowedVlans: const {1}, // VLAN 20 missing!
          ),
        ],
      );

      final stage = SwitchNodeInstance(
        id: 'sw-stage',
        templateId: 'tpl-sw',
        userLabel: 'Stage Switch',
        macAddress: '02:00:00:00:00:02',
        stpPriority: 32768,
        managementIp: '10.0.0.2',
        vlanConfigs: {
          1: const SwitchVlanSettings(vlanId: 1, vlanName: 'Mgmt'),
          20: const SwitchVlanSettings(
            vlanId: 20,
            vlanName: 'sACN',
            igmpSnoopingEnabled: true,
            igmpQuerierEnabled: false,
          ),
        },
        ports: [
          SwitchPortConfig(
            portNumber: 1,
            portMode: SwitchPortMode.trunk,
            nativeVlan: 1,
            allowedVlans: const {1},
          ),
        ],
      );

      final result = validator.validate(
        TopologyProject(
          name: 'Isolated Querier Test',
          switches: [core, stage],
          links: [
            NetworkLinkEdge(
              id: 'l-1',
              sourceNodeId: 'sw-core',
              sourcePortNumber: 1,
              targetNodeId: 'sw-stage',
              targetPortNumber: 1,
            ),
          ],
        ),
      );

      expect(core.activeQuerierVlans.contains(20), isTrue);
      expect(stage.activeQuerierVlans.contains(20), isFalse);
      expect(
        result.issues.any((i) =>
            i.category == IssueCategory.igmp &&
            i.severity == IssueSeverity.critical &&
            i.id == 'igmp-no-querier-v20-sw-stage'),
        isTrue,
      );
    });

    test('elects Querier by lowest IPv4 IP and warns on Querier / STP Root split and IGMP v2/v3 conflict', () {
      // Core is STP Root (4096) with higher IP 10.0.0.20 and IGMPv2 snooping.
      // Edge is non-root (32768) with lower IP 10.0.0.5 and IGMPv3 querier enabled.
      final core = SwitchNodeInstance(
        id: 'sw-core',
        templateId: 'tpl-sw',
        userLabel: 'Core Root',
        macAddress: '02:00:00:00:00:01',
        stpPriority: 4096,
        managementIp: '10.0.0.20',
        vlanConfigs: {
          30: const SwitchVlanSettings(
            vlanId: 30,
            vlanName: 'Dante',
            igmpSnoopingEnabled: true,
            igmpQuerierEnabled: true,
            igmpQuerierVersion: IgmpVersion.v2,
          ),
        },
        ports: [
          SwitchPortConfig(
            portNumber: 1,
            portMode: SwitchPortMode.trunk,
            nativeVlan: 1,
            allowedVlans: const {1, 30},
          ),
        ],
      );

      final edge = SwitchNodeInstance(
        id: 'sw-edge',
        templateId: 'tpl-sw',
        userLabel: 'Edge Switch',
        macAddress: '02:00:00:00:00:02',
        stpPriority: 32768,
        managementIp: '10.0.0.5',
        vlanConfigs: {
          30: const SwitchVlanSettings(
            vlanId: 30,
            vlanName: 'Dante',
            igmpSnoopingEnabled: true,
            igmpQuerierEnabled: true,
            igmpQuerierVersion: IgmpVersion.v3,
          ),
        },
        ports: [
          SwitchPortConfig(
            portNumber: 1,
            portMode: SwitchPortMode.trunk,
            nativeVlan: 1,
            allowedVlans: const {1, 30},
          ),
        ],
      );

      final result = validator.validate(
        TopologyProject(
          name: 'Querier Split & Version Conflict',
          switches: [core, edge],
          links: [
            NetworkLinkEdge(
              id: 'l-1',
              sourceNodeId: 'sw-core',
              sourcePortNumber: 1,
              targetNodeId: 'sw-edge',
              targetPortNumber: 1,
            ),
          ],
        ),
      );

      expect(core.isRootBridge, isTrue);
      // Edge wins active querier election on VLAN 30 due to lower IP 10.0.0.5
      expect(edge.activeQuerierVlans.contains(30), isTrue);
      expect(core.activeQuerierVlans.contains(30), isFalse);

      expect(
        result.issues.any((i) =>
            i.category == IssueCategory.igmp &&
            i.severity == IssueSeverity.warning &&
            i.id.startsWith('igmp-querier-root-split-v30-')),
        isTrue,
      );
      expect(
        result.issues.any((i) =>
            i.category == IssueCategory.igmp &&
            i.severity == IssueSeverity.warning &&
            i.id.startsWith('igmp-version-conflict-v30-')),
        isTrue,
      );
    });

    test('warns when > 70 Mbps un-snooped multicast/broadcast floods 100M port, and clears when snooping enabled', () {
      SwitchNodeInstance buildLegacySwitch({required bool enableSnoopingAndQuerier}) {
        return SwitchNodeInstance(
          id: 'sw-legacy',
          templateId: 'tpl-legacy',
          userLabel: 'Legacy 100M Switch',
          macAddress: '02:00:00:00:00:01',
          stpPriority: 4096,
          vlanConfigs: {
            40: SwitchVlanSettings(
              vlanId: 40,
              vlanName: 'NDI',
              igmpSnoopingEnabled: enableSnoopingAndQuerier,
              igmpQuerierEnabled: enableSnoopingAndQuerier,
            ),
          },
          ports: [
            SwitchPortConfig(
              portNumber: 1,
              maxSpeed: PortSpeed.speed1G,
              portMode: SwitchPortMode.access,
              nativeVlan: 40,
            ),
            SwitchPortConfig(
              portNumber: 2,
              maxSpeed: PortSpeed.speed100M,
              portMode: SwitchPortMode.access,
              nativeVlan: 40,
            ),
          ],
        );
      }

      final ndiSource = EndpointNodeInstance(
        id: 'ep-ndi',
        templateId: 'tpl-ndi',
        userLabel: 'NDI Streamer',
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f-ndi',
            protocol: TrafficProtocol.ndiVideo,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 80.0,
            requiresIgmp: true,
            defaultVlanId: 40,
          ),
        ],
      );

      final link = NetworkLinkEdge(
        id: 'l-ep',
        sourceNodeId: 'ep-ndi',
        sourcePortNumber: 1,
        targetNodeId: 'sw-legacy',
        targetPortNumber: 1,
      );

      // Without snooping: 80 Mbps multicast floods 100M Port 2 -> Warning
      final resUnsnooped = validator.validate(
        TopologyProject(
          name: 'Flood 100M',
          switches: [buildLegacySwitch(enableSnoopingAndQuerier: false)],
          endpoints: [ndiSource],
          links: [link],
        ),
      );

      expect(
        resUnsnooped.issues.any((i) =>
            i.category == IssueCategory.igmp &&
            i.severity == IssueSeverity.warning &&
            i.id == 'igmp-100m-flood-v40-sw-legacy'),
        isTrue,
      );

      // With snooping + querier enabled: multicast is no longer flooded to Port 2
      final resSnooped = validator.validate(
        TopologyProject(
          name: 'Snooped 100M',
          switches: [buildLegacySwitch(enableSnoopingAndQuerier: true)],
          endpoints: [ndiSource],
          links: [link],
        ),
      );

      expect(
        resSnooped.issues.any((i) => i.id == 'igmp-100m-flood-v40-sw-legacy'),
        isFalse,
      );
    });
  });
}
