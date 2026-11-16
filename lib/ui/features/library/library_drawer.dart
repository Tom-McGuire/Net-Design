import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../theme/app_theme.dart';
import '../sandbox_view_model.dart';
import 'edit_endpoint_template_dialog.dart';
import 'edit_switch_template_dialog.dart';

/// Modal manager for the Local Vendor-Neutral Device Template Library.
class LibraryDrawer extends StatelessWidget {
  const LibraryDrawer({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const LibraryDrawer(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SandboxViewModel>();

    return Dialog(
      backgroundColor: AppTheme.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.border),
      ),
      child: SizedBox(
        width: 780,
        height: 560,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              // Header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceHigh,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(10)),
                  border: Border(bottom: BorderSide(color: AppTheme.border)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.menu_book_outlined,
                        size: 20, color: AppTheme.accent),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Local Vendor-Neutral Device Library',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'Define switches by physical port speed tiers, PoE budget, and endpoint traffic profiles',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () async {
                        final pickedFiles = await FilePicker.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['json'],
                        );
                        if (pickedFiles.isNotEmpty) {
                          final path = pickedFiles.single.path;
                          if (path != null) {
                            final raw = await File(path).readAsString();
                            await vm.importLibraryJson(raw);
                          }
                        }
                      },
                      icon: const Icon(Icons.upload_file, size: 15),
                      label:
                          const Text('Import', style: TextStyle(fontSize: 11.5)),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Clipboard.setData(
                          ClipboardData(text: vm.exportLibraryJson()),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Template library JSON copied.'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 15),
                      label: const Text('Export JSON',
                          style: TextStyle(fontSize: 11.5)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.close,
                          size: 18, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),

              // Tabs
              Container(
                color: AppTheme.surface,
                child: TabBar(
                  indicatorColor: AppTheme.accent,
                  labelColor: AppTheme.accent,
                  unselectedLabelColor: AppTheme.textSecondary,
                  tabs: [
                    Tab(
                      text:
                          'Switch Templates (${vm.switchTemplates.length})',
                    ),
                    Tab(
                      text:
                          'Endpoint Templates (${vm.endpointTemplates.length})',
                    ),
                  ],
                ),
              ),

              Expanded(
                child: TabBarView(
                  children: [
                    _buildSwitchesTab(context, vm),
                    _buildEndpointsTab(context, vm),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchesTab(BuildContext context, SandboxViewModel vm) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: () async {
                  final created = await EditSwitchTemplateDialog.show(context);
                  if (created != null) {
                    await vm.saveSwitchTemplate(created);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Switch Template'),
              ),
              const Spacer(),
              TextButton(
                onPressed: vm.resetLibraryDefaults,
                child: const Text('Restore Defaults'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: vm.switchTemplates.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final tpl = vm.switchTemplates[index];
              final onPlanCount = vm.project.switches
                  .where((s) => s.templateId == tpl.id)
                  .length;
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.dns_outlined,
                        size: 20, color: AppTheme.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tpl.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            '${tpl.summaryString} • ${tpl.poeBudgetWatts}W PoE • '
                            '${tpl.supportsStp ? "STP" : "No STP"} • '
                            '${tpl.supportsVlans ? "VLANs" : "Unmanaged"} • '
                            '${tpl.supportsIgmpSnooping ? "IGMP Snoop" : "No Snoop"}'
                            '${tpl.supportsIgmpQuerier ? "/Querier" : ""}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onPlanCount > 0) ...[
                      Tooltip(
                        message:
                            'Update $onPlanCount switch${onPlanCount == 1 ? '' : 'es'} on plan from this template',
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final updated = vm.applySwitchTemplateToPlan(tpl);
                            if (updated > 0 && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Updated $updated switch${updated == 1 ? '' : 'es'} on plan from "${tpl.name}".',
                                  ),
                                ),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.accent,
                            side: BorderSide(
                              color: AppTheme.accent.withValues(alpha: 0.6),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                          icon: const Icon(Icons.sync, size: 14),
                          label: Text(
                            'Update Plan ($onPlanCount)',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    FilledButton(
                      onPressed: () {
                        vm.addSwitchFromTemplate(tpl);
                        Navigator.of(context).pop();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                      ),
                      child: const Text('Place', style: TextStyle(fontSize: 11)),
                    ),
                    IconButton(
                      tooltip: 'Edit Template',
                      onPressed: () async {
                        final edited = await EditSwitchTemplateDialog.show(
                          context,
                          existing: tpl,
                        );
                        if (edited != null) {
                          await vm.saveSwitchTemplate(edited);
                        }
                      },
                      icon: Icon(Icons.edit_outlined,
                          size: 16, color: AppTheme.textSecondary),
                    ),
                    IconButton(
                      tooltip: 'Delete Template',
                      onPressed: () => vm.deleteSwitchTemplate(tpl.id),
                      icon: Icon(Icons.delete_outline,
                          size: 16, color: AppTheme.error),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEndpointsTab(BuildContext context, SandboxViewModel vm) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: () async {
                  final created =
                      await EditEndpointTemplateDialog.show(context);
                  if (created != null) {
                    await vm.saveEndpointTemplate(created);
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('New Endpoint Template'),
              ),
              const Spacer(),
              TextButton(
                onPressed: vm.resetLibraryDefaults,
                child: const Text('Restore Defaults'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: vm.endpointTemplates.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final tpl = vm.endpointTemplates[index];
              final onPlanCount = vm.project.endpoints
                  .where((e) => e.templateId == tpl.id)
                  .length;
              final flowsText = tpl.trafficProfiles
                  .map((f) => f.displayPill)
                  .join(' | ');
              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Icon(tpl.category.icon,
                        size: 20, color: AppTheme.success),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tpl.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            '${tpl.portsSummaryString} • ${tpl.totalPoeDrawWatts.toStringAsFixed(1)}W PoE'
                            '${flowsText.isNotEmpty ? " • $flowsText" : ""}',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 10.5,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (onPlanCount > 0) ...[
                      Tooltip(
                        message:
                            'Update $onPlanCount endpoint${onPlanCount == 1 ? '' : 's'} on plan from this template',
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final updated = vm.applyEndpointTemplateToPlan(tpl);
                            if (updated > 0 && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Updated $updated endpoint${updated == 1 ? '' : 's'} on plan from "${tpl.name}".',
                                  ),
                                ),
                              );
                            }
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.accent,
                            side: BorderSide(
                              color: AppTheme.accent.withValues(alpha: 0.6),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                          icon: const Icon(Icons.sync, size: 14),
                          label: Text(
                            'Update Plan ($onPlanCount)',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    FilledButton(
                      onPressed: () {
                        vm.addEndpointFromTemplate(tpl);
                        Navigator.of(context).pop();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                      ),
                      child: const Text('Place', style: TextStyle(fontSize: 11)),
                    ),
                    IconButton(
                      tooltip: 'Edit Template',
                      onPressed: () async {
                        final edited = await EditEndpointTemplateDialog.show(
                          context,
                          existing: tpl,
                        );
                        if (edited != null) {
                          await vm.saveEndpointTemplate(edited);
                        }
                      },
                      icon: Icon(Icons.edit_outlined,
                          size: 16, color: AppTheme.textSecondary),
                    ),
                    IconButton(
                      tooltip: 'Delete Template',
                      onPressed: () => vm.deleteEndpointTemplate(tpl.id),
                      icon: Icon(Icons.delete_outline,
                          size: 16, color: AppTheme.error),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
