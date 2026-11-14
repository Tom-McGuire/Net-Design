import 'dart:convert';
import 'dart:io';

import '../../domain/engine/topology_validator.dart';
import '../../domain/models/topology_project.dart';

/// Saves/loads `.netdesign` JSON projects and formats validation reports.
class ProjectStorageService {
  const ProjectStorageService();

  String serializeProject(TopologyProject project) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(project.toJson());
  }

  TopologyProject deserializeProject(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('Invalid .netdesign project JSON.');
    }
    return TopologyProject.fromJson(Map<String, dynamic>.from(decoded));
  }

  Future<void> saveProjectToFile(TopologyProject project, String filePath) async {
    final file = File(filePath);
    await file.writeAsString(serializeProject(project));
  }

  Future<TopologyProject> loadProjectFromFile(String filePath) async {
    final file = File(filePath);
    final raw = await file.readAsString();
    return deserializeProject(raw);
  }

  String buildMarkdownValidationReport(
    TopologyProject project,
    ValidationResult validation,
  ) {
    final buf = StringBuffer();
    buf.writeln('# Topology Validation Report: ${project.name}');
    buf.writeln();
    buf.writeln(
      '- **Switches:** ${project.switches.length} | **Endpoints:** ${project.endpoints.length} | **Links:** ${project.links.length}',
    );
    buf.writeln(
      '- **Findings:** ${validation.criticalCount} Critical, ${validation.warningCount} Warnings, ${validation.infoCount} Info',
    );
    buf.writeln();
    buf.writeln('## Disclaimer');
    buf.writeln(
      '> While this deterministic sandbox models Layer 2/Layer 3 topology behavior as accurately as possible, real-world hardware firmware, physical cabling, microburst queuing, and environmental factors may require adjustments on live deployments.',
    );
    buf.writeln();

    if (validation.issues.isEmpty) {
      buf.writeln('No validation issues detected.');
      return buf.toString();
    }

    buf.writeln('## Validation Findings');
    for (final issue in validation.issues) {
      buf.writeln(
        '- **[${issue.severity.label.toUpperCase()} | ${issue.category.label}] ${issue.title}**: ${issue.message}',
      );
      if (issue.recommendation != null) {
        buf.writeln('  - *Recommendation:* ${issue.recommendation}');
      }
    }
    return buf.toString();
  }
}
