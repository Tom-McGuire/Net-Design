import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/models/endpoint_template.dart';
import '../../domain/models/switch_template.dart';
import 'device_templates.dart';

/// Persisted bundle of custom and seeded switch & endpoint templates.
class TemplateLibraryBundle {
  const TemplateLibraryBundle({
    required this.switchTemplates,
    required this.endpointTemplates,
  });

  final List<SwitchTemplate> switchTemplates;
  final List<EndpointTemplate> endpointTemplates;

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'switchTemplates': switchTemplates.map((t) => t.toJson()).toList(),
        'endpointTemplates': endpointTemplates.map((t) => t.toJson()).toList(),
      };

  factory TemplateLibraryBundle.fromJson(Map<String, dynamic> json) {
    final switches = <SwitchTemplate>[];
    if (json['switchTemplates'] is List) {
      for (final item in json['switchTemplates'] as List) {
        if (item is Map) {
          switches.add(
            SwitchTemplate.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final endpoints = <EndpointTemplate>[];
    if (json['endpointTemplates'] is List) {
      for (final item in json['endpointTemplates'] as List) {
        if (item is Map) {
          endpoints.add(
            EndpointTemplate.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    return TemplateLibraryBundle(
      switchTemplates: switches,
      endpointTemplates: endpoints,
    );
  }
}

/// Manages local JSON persistence (`templates_library.json`) and JSON import/export.
class LibraryStorageService {
  LibraryStorageService({this.customDirectoryPath});

  final String? customDirectoryPath;
  static const String libraryFileName = 'templates_library.json';

  Future<File> _resolveLibraryFile() async {
    final dirPath = customDirectoryPath ??
        (await getApplicationSupportDirectory()).path;
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File(p.join(dirPath, libraryFileName));
  }

  Future<TemplateLibraryBundle> loadLibrary() async {
    try {
      final file = await _resolveLibraryFile();
      if (!file.existsSync()) {
        final seeded = TemplateLibraryBundle(
          switchTemplates: DeviceTemplates.defaultSwitchTemplates(),
          endpointTemplates: DeviceTemplates.defaultEndpointTemplates(),
        );
        await saveLibrary(seeded);
        return seeded;
      }

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final parsed = TemplateLibraryBundle.fromJson(decoded);
        if (parsed.switchTemplates.isEmpty && parsed.endpointTemplates.isEmpty) {
          return TemplateLibraryBundle(
            switchTemplates: DeviceTemplates.defaultSwitchTemplates(),
            endpointTemplates: DeviceTemplates.defaultEndpointTemplates(),
          );
        }
        return parsed;
      }
    } catch (_) {
      // Fallback safely to seeded templates
    }

    return TemplateLibraryBundle(
      switchTemplates: DeviceTemplates.defaultSwitchTemplates(),
      endpointTemplates: DeviceTemplates.defaultEndpointTemplates(),
    );
  }

  Future<void> saveLibrary(TemplateLibraryBundle bundle) async {
    final file = await _resolveLibraryFile();
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(bundle.toJson()));
  }

  String exportLibraryJson(TemplateLibraryBundle bundle) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(bundle.toJson());
  }

  TemplateLibraryBundle importLibraryJson(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Invalid template library JSON root object.');
    }
    return TemplateLibraryBundle.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }
}
