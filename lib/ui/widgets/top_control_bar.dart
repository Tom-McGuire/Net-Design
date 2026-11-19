import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../features/library/library_drawer.dart';
import '../features/sandbox_view_model.dart';
import '../theme/app_theme.dart';
import 'simulation_disclaimer_dialog.dart';

/// Tier 1 Top Control Bar, Tier 2 Wiring/Status Banner, and Tier 3 Filter & VLAN Highlighter Bar.
class TopControlBar extends StatelessWidget {
  const TopControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    context.select<SandboxViewModel, int>((v) => v.panelRevision);
    final vm = context.read<SandboxViewModel>();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildTier1ControlBar(context, vm),
        if (vm.pendingWireSource != null) _buildWiringBanner(context, vm),
        if (vm.pendingWireSource == null && vm.lastStatusMessage != null)
          _buildStatusBanner(context, vm),
        _buildTier3SimulationBar(context, vm),
      ],
    );
  }

  Widget _buildTier1ControlBar(BuildContext context, SandboxViewModel vm) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: constraints.maxWidth,
                minHeight: constraints.maxHeight,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          'assets/app_icon.png',
                          width: 32,
                          height: 32,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.accent.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Icon(
                              Icons.hub_outlined,
                              size: 18,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NET DESIGN',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          Text(
                            'TOPOLOGY & VLAN/STP SANDBOX',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.6,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 10),
                      Container(width: 1, height: 26, color: AppTheme.border),
                      const SizedBox(width: 10),

          // Add Switch menu
          PopupMenuButton<String>(
            tooltip: 'Add Switch from Template Library',
            color: AppTheme.surfaceElevated,
            constraints: BoxConstraints(
              minWidth: 240,
              maxWidth: (MediaQuery.sizeOf(context).width - 48).clamp(320.0, 720.0),
            ),
            onSelected: (tplId) {
              final tpl = vm.switchTemplates
                  .where((t) => t.id == tplId)
                  .firstOrNull;
              if (tpl != null) vm.addSwitchFromTemplate(tpl);
            },
            itemBuilder: (_) => vm.switchTemplates
                .map(
                  (t) => PopupMenuItem<String>(
                    value: t.id,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          '${t.summaryString}${t.poeBudgetWatts > 0 ? " • ${t.poeBudgetWatts}W PoE" : ""}',
                          style: TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
            child: _ToolbarChipButton(
              icon: Icons.dns_outlined,
              label: '+ Switch',
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(width: 6),

          // Add Endpoint menu
          PopupMenuButton<String>(
            tooltip: 'Add Endpoint from Template Library',
            color: AppTheme.surfaceElevated,
            constraints: BoxConstraints(
              minWidth: 240,
              maxWidth: (MediaQuery.sizeOf(context).width - 48).clamp(320.0, 720.0),
            ),
            onSelected: (tplId) {
              final tpl = vm.endpointTemplates
                  .where((t) => t.id == tplId)
                  .firstOrNull;
              if (tpl != null) vm.addEndpointFromTemplate(tpl);
            },
            itemBuilder: (_) => vm.endpointTemplates
                .map(
                  (t) => PopupMenuItem<String>(
                    value: t.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(t.category.icon, size: 16, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.name,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                              Text(
                                '${t.portsSummaryString}${t.totalPoeDrawWatts > 0 ? " • ${t.totalPoeDrawWatts.toStringAsFixed(1)}W PoE" : ""}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
            child: _ToolbarChipButton(
              icon: Icons.devices_other,
              label: '+ Endpoint',
              color: AppTheme.success,
            ),
          ),
          const SizedBox(width: 8),

          // Device Library Manager Button
          OutlinedButton.icon(
            onPressed: () => LibraryDrawer.show(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              side: BorderSide(color: AppTheme.border),
              foregroundColor: AppTheme.textPrimary,
            ),
            icon: Icon(Icons.menu_book_outlined, size: 15, color: AppTheme.accent),
            label: const Text('Device Library', style: TextStyle(fontSize: 12)),
          ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [

          // Randomise MACs button (highlighted primary simulation action)
          FilledButton.icon(
            onPressed: vm.project.switches.isEmpty ? null : vm.randomiseSwitchMacs,
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            icon: const Icon(Icons.casino_outlined, size: 16),
            label: const Text('Randomise MACs', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),

          // Demo Scenarios menu
          PopupMenuButton<String>(
            tooltip: 'Load Built-in Topology Scenarios',
            color: AppTheme.surfaceElevated,
            onSelected: (choice) {
              switch (choice) {
                case 'healthy':
                  vm.loadDemoHealthyRing();
                case 'broken':
                  vm.loadDemoBrokenRing();
                case 'loop':
                  vm.loadDemoUnmanagedLoop();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'healthy',
                child: Row(
                  children: [
                    Icon(Icons.verified_outlined, size: 16, color: AppTheme.success),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Healthy Touring Ring (Reference)',
                        style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'broken',
                child: Row(
                  children: [
                    Icon(Icons.warning_amber, size: 16, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Fault Demo: Arbitrary Root & VLAN Blackhole',
                        style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'loop',
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: AppTheme.error),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Fault Demo: Unmanaged Loop & 100M Flood',
                        style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.science_outlined, size: 15, color: AppTheme.warning),
                  const SizedBox(width: 6),
                  Text(
                    'Scenarios',
                    style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, size: 16, color: AppTheme.textSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Theme Toggle
          IconButton(
            tooltip: AppTheme.isDark ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            onPressed: vm.toggleTheme,
            icon: Icon(
              AppTheme.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              size: 18,
              color: AppTheme.textSecondary,
            ),
          ),

          // Advisory Dialog Reopen
          IconButton(
            tooltip: 'Simulation & Engineering Advisory',
            onPressed: () => SimulationDisclaimerDialog.show(context),
            icon: Icon(Icons.info_outline, size: 18, color: AppTheme.warning),
          ),

          // User Manual (opens PDF in browser)
          IconButton(
            tooltip: 'User Manual (PDF)',
            onPressed: () => _openUserManual(context),
            icon: Icon(Icons.help_outline, size: 18, color: AppTheme.textSecondary),
          ),

          // Project Save / Load / Export Menu
          PopupMenuButton<String>(
            tooltip: 'Project File & Export',
            color: AppTheme.surfaceElevated,
            icon: Icon(Icons.more_vert, size: 18, color: AppTheme.textPrimary),
            onSelected: (action) => _handleFileAction(context, vm, action),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'new_blank',
                child: _menuRow(Icons.note_add_outlined, 'New Blank Canvas'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'open',
                child: _menuRow(Icons.folder_open, 'Open Project'),
              ),
              PopupMenuItem(
                value: 'save',
                child: _menuRow(Icons.save_outlined, 'Save Project'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'copy_json',
                child: _menuRow(Icons.data_object, 'Copy Topology JSON'),
              ),
              PopupMenuItem(
                value: 'copy_report',
                child: _menuRow(Icons.assignment_outlined, 'Copy Validation Report (MD)'),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'user_manual',
                child: _menuRow(Icons.help_outline, 'User Manual (PDF)'),
              ),
            ],
          ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _menuRow(IconData icon, String label) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textSecondary),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
          ),
        ),
      ],
    );
  }

  static final Uri _userManualUri = Uri.parse(
    'https://github.com/Tom-McGuire/Net-Design/blob/main/USER_MANUAL.pdf',
  );

  Future<void> _openUserManual(BuildContext context) async {
    final ok = await launchUrl(
      _userManualUri,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not open $_userManualUri in browser.'),
        ),
      );
    }
  }

  Future<void> _handleFileAction(
    BuildContext context,
    SandboxViewModel vm,
    String action,
  ) async {
    switch (action) {
      case 'user_manual':
        await _openUserManual(context);
      case 'new_blank':
        vm.newBlankProject();
      case 'open':
        try {
          final pickedFiles = await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['netdesign', 'json'],
          );
          if (pickedFiles.isNotEmpty) {
            final path = pickedFiles.single.path;
            if (path != null) {
              await vm.loadProjectFromFile(path);
            }
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to open project: $e')),
            );
          }
        }
      case 'save':
        try {
          final bytes = Uint8List.fromList(
            utf8.encode(vm.serializeCurrentProject()),
          );
          final outputUri = await FilePicker.saveFile(
            dialogTitle: 'Save Topology Project',
            fileName:
                '${vm.project.name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_')}.netdesign',
            bytes: bytes,
          );
          if (outputUri != null) {
            final savedTarget = outputUri.scheme == 'file'
                ? outputUri.toFilePath()
                : outputUri.toString();
            vm.recordProjectSaved(savedTarget);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Saved topology project to $savedTarget.'),
                ),
              );
            }
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to save project: $e')),
            );
          }
        }
      case 'copy_json':
        await Clipboard.setData(
          ClipboardData(text: vm.serializeCurrentProject()),
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Copied topology JSON to clipboard.')),
          );
        }
      case 'copy_report':
        await Clipboard.setData(
          ClipboardData(text: vm.buildMarkdownValidationReport()),
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Copied Markdown validation report to clipboard.')),
          );
        }
    }
  }

  Widget _buildWiringBanner(BuildContext context, SandboxViewModel vm) {
    final pending = vm.pendingWireSource!;
    final nodeLabel = vm.project.switches
            .where((s) => s.id == pending.nodeId)
            .firstOrNull
            ?.userLabel ??
        vm.project.endpoints
            .where((e) => e.id == pending.nodeId)
            .firstOrNull
            ?.userLabel ??
        pending.nodeId;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      color: AppTheme.accent.withValues(alpha: 0.18),
      child: Row(
        children: [
          Icon(Icons.cable, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'CABLE WIRING ACTIVE: Starting from $nodeLabel (Port ${pending.portNumber}) — click a free port on another device to connect.',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: vm.cancelWiring,
            icon: const Icon(Icons.close, size: 14),
            label: const Text('Cancel Wiring', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner(BuildContext context, SandboxViewModel vm) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 14, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              vm.lastStatusMessage!,
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ),
          InkWell(
            onTap: vm.clearStatusMessage,
            child: Icon(Icons.close, size: 14, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildTier3SimulationBar(BuildContext context, SandboxViewModel vm) {
    final vlans = vm.availableVlanIds;
    final val = vm.validation;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // Highlight VLAN selector
          Icon(Icons.layers_outlined, size: 15, color: AppTheme.accent),
          const SizedBox(width: 6),
          Text(
            'Highlight VLAN:',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _VlanFilterChip(
                    label: 'All',
                    selected: vm.highlightedVlanId == null &&
                        !vm.isTrunkFilterActive &&
                        !vm.isStreamTraceActive,
                    onTap: () => vm.setHighlightedVlan(null),
                  ),
                  const SizedBox(width: 4),
                  _VlanFilterChip(
                    label: 'Trunks',
                    tooltip:
                        'Highlight only Trunk links configured symmetrically at both ends',
                    selected: vm.isTrunkFilterActive,
                    onTap: () => vm.setTrunkFilterActive(!vm.isTrunkFilterActive),
                  ),
                  const SizedBox(width: 4),
                  for (final vId in vlans) ...[
                    _VlanFilterChip(
                      label: vm.formatVlanDisplay(vId),
                      tooltip: 'VLAN $vId',
                      selected: vm.highlightedVlanId == vId,
                      onTap: () => vm.setHighlightedVlan(
                        vm.highlightedVlanId == vId ? null : vId,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    side: BorderSide(color: AppTheme.border),
                    backgroundColor: AppTheme.surface,
                    label: Text(
                      '+ VLAN',
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: AppTheme.accent,
                      ),
                    ),
                    onPressed: () => _promptAddVlan(context, vm),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),
          Container(width: 1, height: 24, color: AppTheme.border),
          const SizedBox(width: 10),

          // Static Stream Trace selector
          Icon(
            Icons.alt_route,
            size: 15,
            color: vm.isStreamTraceActive ? AppTheme.success : AppTheme.accent,
          ),
          const SizedBox(width: 5),
          Text(
            'Trace Stream:',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: vm.isStreamTraceActive
                  ? AppTheme.success
                  : AppTheme.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 185,
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: vm.isStreamTraceActive
                  ? AppTheme.success.withValues(alpha: 0.14)
                  : AppTheme.surface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color:
                    vm.isStreamTraceActive ? AppTheme.success : AppTheme.border,
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: vm.activeStreamTraceTarget != null
                    ? vm.activeStreamTraceId
                    : null,
                isExpanded: true,
                isDense: true,
                menuMaxHeight: 420,
                dropdownColor: AppTheme.surfaceElevated,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10.5,
                  color: AppTheme.textPrimary,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None (Normal View)'),
                  ),
                  for (final target in vm.availableStreamTraceTargets)
                    DropdownMenuItem<String?>(
                      value: target.id,
                      child: Text(
                        target.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: vm.setActiveStreamTrace,
              ),
            ),
          ),

          const SizedBox(width: 10),
          Container(width: 1, height: 24, color: AppTheme.border),
          const SizedBox(width: 10),

          // Health summary badges
          _HealthBadge(
            count: val.criticalCount,
            label: 'Critical',
            color: val.criticalCount > 0 ? AppTheme.error : AppTheme.textMuted,
            onTap: () => vm.setIssuesExpanded(true),
          ),
          const SizedBox(width: 6),
          _HealthBadge(
            count: val.warningCount,
            label: 'Warnings',
            color: val.warningCount > 0 ? AppTheme.warning : AppTheme.textMuted,
            onTap: () => vm.setIssuesExpanded(true),
          ),
          const SizedBox(width: 6),
          _HealthBadge(
            count: val.infoCount,
            label: 'Info',
            color: AppTheme.accent,
            onTap: () => vm.setIssuesExpanded(true),
          ),
        ],
      ),
    );
  }

  Future<void> _promptAddVlan(BuildContext context, SandboxViewModel vm) async {
    final idCtrl = TextEditingController(text: '50');
    final nameCtrl = TextEditingController(text: 'Stage Comms');
    final added = await showDialog<(int, String)?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceElevated,
        title: Text(
          'Define VLAN',
          style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
        ),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'VLAN ID (1–4094)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'VLAN Name'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final id = int.tryParse(idCtrl.text.trim());
              if (id == null || id < 1 || id > 4094) return;
              Navigator.of(ctx).pop((id, nameCtrl.text.trim()));
            },
            child: const Text('Add VLAN'),
          ),
        ],
      ),
    );
    idCtrl.dispose();
    nameCtrl.dispose();

    if (added != null) {
      vm.addKnownVlan(added.$1, added.$2);
      vm.setHighlightedVlan(added.$1);
    }
  }
}

class _ToolbarChipButton extends StatelessWidget {
  const _ToolbarChipButton({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.arrow_drop_down, size: 15, color: AppTheme.textSecondary),
        ],
      ),
    );
  }
}

class _VlanFilterChip extends StatelessWidget {
  const _VlanFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.tooltip,
  });

  final String label;
  final String? tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final child = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.success.withValues(alpha: 0.2)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: selected ? AppTheme.success : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? AppTheme.success : AppTheme.textPrimary,
          ),
        ),
      ),
    );
    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: child);
    }
    return child;
  }
}

class _HealthBadge extends StatelessWidget {
  const _HealthBadge({
    required this.count,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final int count;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Text(
          '$count $label',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}
