import 'package:flutter_test/flutter_test.dart';
import 'package:net_design/domain/engine/topology_validator.dart';
import 'package:net_design/domain/models/enums.dart';
import 'package:net_design/domain/models/network_link_edge.dart';
import 'package:net_design/domain/models/switch_node_instance.dart';
import 'package:net_design/domain/models/switch_port_config.dart';
import 'package:net_design/domain/models/topology_project.dart';

void main() {
  const validator = TopologyValidator();

  List<SwitchPortConfig> buildTrunkPorts(int count, {PortSpeed speed = PortSpeed.speed1G}) {
    return [
      for (var i = 1; i <= count; i++)
        SwitchPortConfig(
          portNumber: i,
          maxSpeed: speed,
          portMode: SwitchPortMode.trunk,
          nativeVlan: 1,
          allowedVlans: const {1, 20},
        ),
    ];
  }

  group('StpElectionSolver', () {
    test('tie-breaks Bridge ID by lowest MAC at default priority 32768 without signed overflow', () {
      final swHighMac = SwitchNodeInstance(
        id: 'sw-high',
        templateId: 'tpl-sw',
        userLabel: 'High MAC Switch',
        macAddress: 'FF:00:00:00:00:01',
        stpPriority: 32768,
        ports: buildTrunkPorts(4),
      );
      final swLowMac = SwitchNodeInstance(
        id: 'sw-low',
        templateId: 'tpl-sw',
        userLabel: 'Low MAC Switch',
        macAddress: '02:00:00:00:00:99',
        stpPriority: 32768,
        ports: buildTrunkPorts(4),
      );

      // Verify compareBridgeId does not overflow into negative signed 64-bit space
      expect(swLowMac.compareBridgeId(swHighMac), lessThan(0));
      expect(swHighMac.compareBridgeId(swLowMac), greaterThan(0));

      final project = TopologyProject(
        name: 'MAC Tiebreak',
        switches: [swHighMac, swLowMac],
        links: [
          NetworkLinkEdge(
            id: 'l-1',
            sourceNodeId: 'sw-high',
            sourcePortNumber: 1,
            targetNodeId: 'sw-low',
            targetPortNumber: 1,
          ),
        ],
      );

      final result = validator.validate(project);
      expect(result.rootBridgeIds, equals({'sw-low'}));
      expect(swLowMac.isRootBridge, isTrue);
      expect(swHighMac.isRootBridge, isFalse);
    });

    test('lower STP priority (4096) overrides lower MAC at priority 32768', () {
      final core = SwitchNodeInstance(
        id: 'sw-core',
        templateId: 'tpl-sw',
        userLabel: 'Core 4096',
        macAddress: 'AA:BB:CC:DD:EE:FF',
        stpPriority: 4096,
        ports: buildTrunkPorts(4),
      );
      final edge = SwitchNodeInstance(
        id: 'sw-edge',
        templateId: 'tpl-sw',
        userLabel: 'Edge Lower MAC',
        macAddress: '02:00:00:00:00:01',
        stpPriority: 32768,
        ports: buildTrunkPorts(4),
      );

      final project = TopologyProject(
        name: 'Priority Override',
        switches: [edge, core],
        links: [
          NetworkLinkEdge(
            id: 'l-1',
            sourceNodeId: 'sw-edge',
            sourcePortNumber: 1,
            targetNodeId: 'sw-core',
            targetPortNumber: 1,
          ),
        ],
      );

      final result = validator.validate(project);
      expect(result.rootBridgeIds, equals({'sw-core'}));
      expect(core.isRootBridge, isTrue);
      expect(edge.isRootBridge, isFalse);
    });

    test('places exactly one redundant ring link into STP blocking state', () {
      final swA = SwitchNodeInstance(
        id: 'sw-a',
        templateId: 'tpl-sw',
        userLabel: 'Root Core',
        macAddress: '02:00:00:00:00:01',
        stpPriority: 4096,
        ports: buildTrunkPorts(4),
      );
      final swB = SwitchNodeInstance(
        id: 'sw-b',
        templateId: 'tpl-sw',
        userLabel: 'Edge B',
        macAddress: '02:00:00:00:00:02',
        stpPriority: 32768,
        ports: buildTrunkPorts(4),
      );
      final swC = SwitchNodeInstance(
        id: 'sw-c',
        templateId: 'tpl-sw',
        userLabel: 'Edge C',
        macAddress: '02:00:00:00:00:03',
        stpPriority: 32768,
        ports: buildTrunkPorts(4),
      );

      final links = [
        NetworkLinkEdge(
          id: 'l-ab',
          sourceNodeId: 'sw-a',
          sourcePortNumber: 1,
          targetNodeId: 'sw-b',
          targetPortNumber: 1,
        ),
        NetworkLinkEdge(
          id: 'l-ac',
          sourceNodeId: 'sw-a',
          sourcePortNumber: 2,
          targetNodeId: 'sw-c',
          targetPortNumber: 1,
        ),
        NetworkLinkEdge(
          id: 'l-bc',
          sourceNodeId: 'sw-b',
          sourcePortNumber: 2,
          targetNodeId: 'sw-c',
          targetPortNumber: 2,
        ),
      ];

      final result = validator.validate(
        TopologyProject(name: 'Ring', switches: [swA, swB, swC], links: links),
      );

      expect(result.blockingLinkCount, equals(1));
      expect(links.where((l) => l.stpState == LinkStpState.blocking).length, equals(1));
      final blockedLink = links.firstWhere((l) => l.stpState == LinkStpState.blocking);
      expect(blockedLink.blockedAtNodeId, isNotNull);
      expect(blockedLink.blockedAtPortNumber, isNotNull);
      expect(
        result.issues.any((i) =>
            i.category == IssueCategory.stp &&
            i.severity == IssueSeverity.info &&
            i.id.startsWith('stp-blocking-')),
        isTrue,
      );
    });

    test('detects critical unprotected Layer 2 loop when unmanaged switch closes cycle', () {
      final managedA = SwitchNodeInstance(
        id: 'sw-a',
        templateId: 'tpl-sw',
        userLabel: 'Managed A',
        macAddress: '02:00:00:00:00:01',
        stpPriority: 4096,
        ports: buildTrunkPorts(4),
      );
      final managedB = SwitchNodeInstance(
        id: 'sw-b',
        templateId: 'tpl-sw',
        userLabel: 'Managed B',
        macAddress: '02:00:00:00:00:02',
        stpPriority: 32768,
        ports: buildTrunkPorts(4),
      );
      final unmanaged = SwitchNodeInstance(
        id: 'sw-u',
        templateId: 'tpl-unmanaged',
        userLabel: 'Unmanaged Desk',
        macAddress: '02:00:00:00:00:03',
        stpMode: StpMode.disabled,
        supportsStp: false,
        supportsVlans: false,
        ports: [
          for (var i = 1; i <= 4; i++) SwitchPortConfig(portNumber: i),
        ],
      );

      final links = [
        NetworkLinkEdge(
          id: 'l-ab',
          sourceNodeId: 'sw-a',
          sourcePortNumber: 1,
          targetNodeId: 'sw-b',
          targetPortNumber: 1,
        ),
        NetworkLinkEdge(
          id: 'l-bu',
          sourceNodeId: 'sw-b',
          sourcePortNumber: 2,
          targetNodeId: 'sw-u',
          targetPortNumber: 1,
        ),
        NetworkLinkEdge(
          id: 'l-ua',
          sourceNodeId: 'sw-u',
          sourcePortNumber: 2,
          targetNodeId: 'sw-a',
          targetPortNumber: 2,
        ),
      ];

      final result = validator.validate(
        TopologyProject(
          name: 'Unmanaged Loop',
          switches: [managedA, managedB, unmanaged],
          links: links,
        ),
      );

      expect(result.unprotectedLoopCount, greaterThan(0));
      expect(
        links.any((l) => l.stpState == LinkStpState.loopUnprotected),
        isTrue,
      );
      expect(
        result.issues.any((i) =>
            i.category == IssueCategory.stp &&
            i.severity == IssueSeverity.critical &&
            i.title.contains('Loop')),
        isTrue,
      );
    });

    test('emits warning when switch exceeds 6 STP hops from Root Bridge', () {
      // 9 switches in a daisy chain (0..8) -> hops 7 and 8 exceed threshold (> 6).
      final switches = <SwitchNodeInstance>[
        for (var i = 0; i < 9; i++)
          SwitchNodeInstance(
            id: 'sw-$i',
            templateId: 'tpl-sw',
            userLabel: 'Switch $i',
            macAddress: '02:00:00:00:00:${(i + 1).toRadixString(16).padLeft(2, '0')}',
            stpPriority: i == 0 ? 4096 : 32768,
            ports: buildTrunkPorts(4),
          ),
      ];
      final links = <NetworkLinkEdge>[
        for (var i = 0; i < 8; i++)
          NetworkLinkEdge(
            id: 'l-$i',
            sourceNodeId: 'sw-$i',
            sourcePortNumber: 1,
            targetNodeId: 'sw-${i + 1}',
            targetPortNumber: 2,
          ),
      ];

      final result = validator.validate(
        TopologyProject(name: 'Deep Chain', switches: switches, links: links),
      );

      expect(switches[8].hopDepthFromRoot, equals(8));
      expect(switches[7].hopDepthFromRoot, equals(7));
      expect(
        result.issues.where((i) =>
            i.category == IssueCategory.stp &&
            i.severity == IssueSeverity.warning &&
            i.id.startsWith('stp-hop-depth-')).length,
        equals(2),
      );
    });
  });
}
