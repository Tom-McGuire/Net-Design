import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../domain/models/enums.dart';
import '../../../domain/models/switch_node_instance.dart';
import '../../../domain/models/validation_issue.dart';
import '../../theme/app_theme.dart';
import '../sandbox_view_model.dart';

/// Tier 5 Collapsible Issues & CLI Preview Drawer + persistent status bar.
class IssuesDrawerPanel extends StatelessWidget {
  const IssuesDrawerPanel({super.key});

  @override
  Widget build(BuildContext context) {
    context.select<SandboxViewModel, int>((v) => v.panelRevision);
    final vm = context.read<SandboxViewModel>();
    final expanded = vm.isIssuesExpanded;
    final issues = vm.filteredIssues;
    final selectedSwitch = vm.selectedSwitch;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (expanded)
          Container(
            height: 230,
            decoration: BoxDecoration(
              color: AppTheme.surface,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Column(
              children: [
                // Tab & Filter header
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceHigh,
                    border: Border(bottom: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    children: [
                      _TabPill(
                        label: 'ISSUES (${issues.length})',
                        selected: vm.inspectorTabIndex == 0,
                        onTap: () => vm.setInspectorTabIndex(0),
                      ),
                      const SizedBox(width: 6),
                      _TabPill(
                        label: 'CLI CONFIG PREVIEW',
                        selected: vm.inspectorTabIndex == 1,
                        onTap: () => vm.setInspectorTabIndex(1),
                      ),
                      const SizedBox(width: 14),
                      if (vm.inspectorTabIndex == 0) ...[
                        _CatChip(
                          label: 'All',
                          selected: vm.issueCategoryFilter == null,
                          onTap: () => vm.setIssueCategoryFilter(null),
                        ),
                        const SizedBox(width: 4),
                        for (final cat in IssueCategory.values) ...[
                          _CatChip(
                            label: cat.label,
                            selected: vm.issueCategoryFilter == cat,
                            onTap: () => vm.setIssueCategoryFilter(
                              vm.issueCategoryFilter == cat ? null : cat,
                            ),
                          ),
                          const SizedBox(width: 4),
                        ],
                        const Spacer(),
                        SizedBox(
                          width: 190,
                          height: 26,
                          child: TextField(
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Filter issues...',
                              hintStyle: TextStyle(
                                fontSize: 11,
                                color: AppTheme.textMuted,
                              ),
                              prefixIcon: Icon(
                                Icons.search,
                                size: 14,
                                color: AppTheme.textMuted,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 0,
                              ),
                            ),
                            onChanged: vm.setIssueSearchQuery,
                          ),
                        ),
                      ] else
                        const Spacer(),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Collapse Drawer',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => vm.setIssuesExpanded(false),
                        icon: Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Content area
                Expanded(
                  child: vm.inspectorTabIndex == 0
                      ? _buildIssuesList(vm, issues)
                      : _buildCliPreview(context, vm, selectedSwitch),
                ),
              ],
            ),
          ),

        // Persistent Bottom Status Bar
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () => vm.setIssuesExpanded(!expanded),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_down
                          : Icons.keyboard_arrow_up,
                      size: 15,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      expanded ? 'Hide Inspector Drawer' : 'Show Inspector Drawer',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'Switches: ${vm.project.switches.length}  |  Endpoints: ${vm.project.endpoints.length}  |  Links: ${vm.project.links.length}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                vm.validation.isHealthy
                    ? 'TOPOLOGY HEALTHY'
                    : '${vm.validation.criticalCount} CRITICAL • ${vm.validation.warningCount} WARN',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  fontWeight: FontWeight.bold,
                  color: vm.validation.criticalCount > 0
                      ? AppTheme.error
                      : (vm.validation.warningCount > 0
                          ? AppTheme.warning
                          : AppTheme.success),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIssuesList(SandboxViewModel vm, List<ValidationIssue> issues) {
    if (issues.isEmpty) {
      return Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_outlined, size: 18, color: AppTheme.success),
            const SizedBox(width: 8),
            Text(
              'No validation faults match the current filter.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: issues.length,
      separatorBuilder: (_, _) => Divider(height: 1, color: AppTheme.border),
      itemBuilder: (context, index) {
        final issue = issues[index];
        final sevColor = switch (issue.severity) {
          IssueSeverity.critical => AppTheme.error,
          IssueSeverity.warning => AppTheme.warning,
          IssueSeverity.info => AppTheme.accent,
        };
        final sevIcon = switch (issue.severity) {
          IssueSeverity.critical => Icons.error_outline,
          IssueSeverity.warning => Icons.warning_amber_rounded,
          IssueSeverity.info => Icons.info_outline,
        };

        return InkWell(
          onTap: () => vm.focusOnIssue(issue),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(sevIcon, size: 16, color: sevColor),
                const SizedBox(width: 8),
                Container(
                  width: 66,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: sevColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    issue.severity.label.toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold,
                      color: sevColor,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 66,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceHigh,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppTheme.border),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    issue.category.label,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 9.5,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${issue.title}: ${issue.message}',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (issue.recommendation != null)
                        Text(
                          'Fix: ${issue.recommendation}',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.my_location, size: 14, color: AppTheme.textMuted),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCliPreview(
    BuildContext context,
    SandboxViewModel vm,
    SwitchNodeInstance? selectedSwitch,
  ) {
    if (selectedSwitch == null) {
      return Center(
        child: Text(
          'Select any Switch on the canvas to preview its vendor-neutral CLI reference configuration.',
          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
        ),
      );
    }

    final cli = vm.generateCliConfigPreview(selectedSwitch);
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            cli,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              height: 1.4,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 12,
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: cli));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('CLI configuration copied.')),
              );
            },
            icon: const Icon(Icons.copy, size: 13),
            label: const Text('Copy CLI', style: TextStyle(fontSize: 11)),
          ),
        ),
      ],
    );
  }
}

class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? AppTheme.accent : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10.5,
            fontWeight: FontWeight.bold,
            color: selected ? AppTheme.accent : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  const _CatChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent.withValues(alpha: 0.2) : AppTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: selected ? AppTheme.accent : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: selected ? AppTheme.accent : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
