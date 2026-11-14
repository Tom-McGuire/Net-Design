import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:net_design/data/services/library_storage_service.dart';
import 'package:net_design/data/services/project_storage_service.dart';
import 'package:net_design/domain/engine/topology_validator.dart';
import 'package:net_design/domain/models/enums.dart';
import 'package:net_design/domain/models/switch_node_instance.dart';
import 'package:net_design/domain/models/switch_port_config.dart';
import 'package:net_design/domain/models/topology_project.dart';

void main() {
  const projectStorage = ProjectStorageService();
  const validator = TopologyValidator();

  group('Security and Fuzz Tests (Parser, Persistence & Solver Resilience)', () {
    test('SwitchNodeInstance.parseMacToInt and parseIpToInt survive malformed/fuzzed inputs', () {
      final weirdInputs = <String?>[
        null,
        '',
        '   ',
        'not-a-mac',
        'ZZ:ZZ:ZZ:ZZ:ZZ:ZZ',
        '02:00:00',
        'FF:FF:FF:FF:FF:FF:FF:FF:FF:FF:FF',
        '999.999.999.999',
        '10.0.-1.5',
        '10.0.0.1; DROP TABLE suite_settings;--',
        '🚀🔥💥\n\t\r\u0000',
      ];

      for (final raw in weirdInputs) {
        if (raw != null) {
          final macVal = SwitchNodeInstance.parseMacToInt(raw);
          expect(macVal, isA<int>());
          expect(macVal, greaterThanOrEqualTo(0));
        }
        final ipVal = SwitchNodeInstance.parseIpToInt(raw);
        expect(ipVal, isA<int>());
        expect(ipVal, greaterThanOrEqualTo(0));
      }

      expect(
        SwitchNodeInstance.parseIpToInt('10.0.0.1'),
        lessThan(SwitchNodeInstance.parseIpToInt('10.0.0.2')),
      );
      expect(SwitchNodeInstance.parseIpToInt('999.1.1.1'), equals(0xFFFFFFFF));
    });

    test('SwitchPortConfig.fromJson and SwitchNodeInstance.fromJson clamp out-of-bounds & wrong-type values', () {
      final fuzzedPort = SwitchPortConfig.fromJson({
        'portNumber': -99,
        'maxSpeed': '9999G_UNKNOWN',
        'poeCapable': 'yes_please',
        'portMode': 42,
        'nativeVlan': 999999,
        'allowedVlans': ['abc', -1, 0, 20, 5000, null],
      });

      expect(fuzzedPort.portNumber, equals(1));
      expect(fuzzedPort.nativeVlan, equals(4094));
      expect(fuzzedPort.allowedVlans, equals({20}));
      expect(fuzzedPort.maxSpeed, equals(PortSpeed.speed1G));

      final emptyFallbackPort = SwitchPortConfig.fromJson({
        'nativeVlan': 30,
        'allowedVlans': [-1, 0, 5000, 'invalid'],
      });
      expect(emptyFallbackPort.allowedVlans, equals({30}));

      final fuzzedSwitch = SwitchNodeInstance.fromJson({
        'id': null,
        'stpPriority': 999999,
        'poeBudgetWatts': -500,
        'stpMode': 'proprietary_turbo',
        'vlanConfigs': {
          'not-an-int': {'vlanId': 5000, 'vlanName': 123},
          '20': 'corrupted-entry',
        },
        'ports': ['bad-item', 123, null, {'portNumber': 0, 'nativeVlan': -5}],
        'dx': 'NaN',
        'dy': null,
      });

      expect(fuzzedSwitch.stpPriority, inInclusiveRange(0, 61440));
      expect(fuzzedSwitch.poeBudgetWatts, equals(0));
      expect(fuzzedSwitch.vlanConfigs.containsKey(1), isTrue);
      expect(fuzzedSwitch.ports.length, equals(1));
      expect(fuzzedSwitch.ports.first.portNumber, equals(1));
      expect(fuzzedSwitch.ports.first.nativeVlan, equals(1));
    });

    test('TopologyProject.fromJson and TopologyValidator tolerate corrupted/truncated project schemas', () {
      final fuzzedMaps = <Map<String, dynamic>>[
        {},
        {'name': 123, 'switches': 'invalid', 'endpoints': 42, 'links': null},
        {
          'name': 'Dangling Links',
          'switches': [
            {
              'id': 'sw-1',
              'stpPriority': -4096,
              'ports': [
                {'portNumber': 1, 'nativeVlan': 9999, 'allowedVlans': 'not-a-list'},
              ],
            },
          ],
          'endpoints': ['not-a-map'],
          'links': [
            {
              'id': 'l-dangling',
              'sourceNodeId': 'missing-node',
              'sourcePortNumber': 999,
              'targetNodeId': 'sw-1',
              'targetPortNumber': 999,
            },
          ],
          'knownVlans': {'not_int': 'bad', '20': 12345},
        },
      ];

      for (final raw in fuzzedMaps) {
        final project = TopologyProject.fromJson(raw);
        final res = validator.validate(project);
        expect(res.issues, isA<List>());
      }
    });

    test('ProjectStorageService and LibraryStorageService reject non-object JSON cleanly without uncaught crashes', () async {
      final badPayloads = [
        '',
        '{truncated json',
        '[]',
        '"just a string"',
        '12345',
        'null',
        '{"unexpected": [1, 2, 3',
      ];

      final tempDir = await Directory.systemTemp.createTemp('net_design_fuzz_');
      addTearDown(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
      final libStorage = LibraryStorageService(customDirectoryPath: tempDir.path);

      for (final payload in badPayloads) {
        expect(
          () => projectStorage.deserializeProject(payload),
          throwsFormatException,
        );
        expect(
          () => libStorage.importLibraryJson(payload),
          throwsFormatException,
        );
      }

      // Corrupted inner arrays inside valid root map should parse safely without throwing
      final partialLib = libStorage.importLibraryJson(jsonEncode({
        'switchTemplates': ['bad', 123, {'ports1G': 99999, 'ports10G': -10}],
        'endpointTemplates': [null, {'trafficProfiles': 'bad'}],
      }));
      expect(partialLib.switchTemplates.length, equals(1));
      expect(partialLib.endpointTemplates.length, equals(1));

      // Corrupted disk file falls back to seeded defaults safely
      final corruptFile = File('${tempDir.path}/templates_library.json');
      await corruptFile.writeAsString('{corrupt!!!');
      final loaded = await libStorage.loadLibrary();
      expect(loaded.switchTemplates, isNotEmpty);
      expect(loaded.endpointTemplates, isNotEmpty);
    });
  });
}
