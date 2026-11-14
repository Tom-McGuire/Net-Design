import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';

import '../theme/app_theme.dart';

/// Cross-suite device renaming & identity modal triggered by clicking a node MAC or label.
class RenameDeviceDialog extends StatefulWidget {
  const RenameDeviceDialog({
    super.key,
    required this.initialName,
    this.macAddress,
    this.subtitle,
  });

  final String initialName;
  final String? macAddress;
  final String? subtitle;

  static Future<String?> show(
    BuildContext context, {
    required String initialName,
    String? macAddress,
    String? subtitle,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => RenameDeviceDialog(
        initialName: initialName,
        macAddress: macAddress,
        subtitle: subtitle,
      ),
    );
  }

  @override
  State<RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<RenameDeviceDialog> {
  late final TextEditingController _nameController;
  bool _syncToSharedDb = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _syncToSharedDb = widget.macAddress != null &&
        widget.macAddress!.isNotEmpty &&
        SharedDeviceDatabase.instance.isInitialized;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _save() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) return;

    if (_syncToSharedDb &&
        widget.macAddress != null &&
        SharedDeviceDatabase.instance.isInitialized) {
      try {
        final mac = widget.macAddress!;
        final existing = SharedDeviceDatabase.instance.getDeviceByMac(mac);
        if (existing != null) {
          SharedDeviceDatabase.instance.updateDeviceName(mac, trimmed);
        } else {
          SharedDeviceDatabase.instance.upsertDevice(
            SharedDevice(
              macAddress: mac,
              name: trimmed,
              vendor: OuiLookup.lookupVendor(mac),
              sourceApp: 'net_design',
              createdAt: DateTime.now().toUtc(),
              updatedAt: DateTime.now().toUtc(),
            ),
          );
        }
      } catch (_) {
        // Ignore shared DB write issues for sandbox-only MACs
      }
    }

    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final mac = widget.macAddress;
    final oui =
        (mac != null && mac.isNotEmpty) ? OuiLookup.lookupVendor(mac) : null;

    return AlertDialog(
      backgroundColor: AppTheme.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppTheme.border),
      ),
      title: Row(
        children: [
          Icon(Icons.edit_note, color: AppTheme.accent, size: 22),
          const SizedBox(width: 8),
          Text(
            'Rename Device',
            style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mac != null && mac.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.memory, size: 15, color: AppTheme.accent),
                        const SizedBox(width: 6),
                        SelectableText(
                          mac,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    if (oui != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'OUI Vendor: $oui',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ],
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            TextField(
              controller: _nameController,
              autofocus: true,
              style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Device Label',
                hintText: 'e.g., FOH Core Switch A',
              ),
              onSubmitted: (_) => _save(),
            ),
            if (mac != null && SharedDeviceDatabase.instance.isInitialized) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _syncToSharedDb,
                onChanged: (v) => setState(() => _syncToSharedDb = v ?? false),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Also save to Network Suite Shared Device Database',
                  style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.accent,
            foregroundColor: Colors.white,
          ),
          onPressed: _save,
          child: const Text('Save Label'),
        ),
      ],
    );
  }
}
