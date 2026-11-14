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

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'severity': severity.toJson(),
      'category': category.toJson(),
      'title': title,
      'message': message,
      if (recommendation != null) 'recommendation': recommendation,
      if (nodeId != null) 'nodeId': nodeId,
      if (portNumber != null) 'portNumber': portNumber,
      if (linkId != null) 'linkId': linkId,
      if (vlanId != null) 'vlanId': vlanId,
    };
  }
}
