import 'enums.dart';

/// Deterministic validation finding emitted by [TopologyValidator].
class ValidationIssue {
  const ValidationIssue({
    required this.id,
    required this.severity,
    required this.category,
    required this.title,
    required this.message,
    this.recommendation,
    this.nodeId,
    this.portNumber,
    this.linkId,
    this.vlanId,
  });

  final String id;
  final IssueSeverity severity;
  final IssueCategory category;
  final String title;
  final String message;
  final String? recommendation;
  final String? nodeId;
  final int? portNumber;
  final String? linkId;
  final int? vlanId;
}
