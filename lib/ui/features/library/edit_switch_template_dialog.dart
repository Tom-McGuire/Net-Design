import 'package:material_ui/material_ui.dart';

import '../../../domain/models/switch_template.dart';
import '../../theme/app_theme.dart';

/// Dialog for creating or editing a vendor-neutral [SwitchTemplate].
class EditSwitchTemplateDialog extends StatefulWidget {
  const EditSwitchTemplateDialog({super.key, this.existing});

  final SwitchTemplate? existing;

  static Future<SwitchTemplate?> show(
    BuildContext context, {
    SwitchTemplate? existing,
  }) {
    return showDialog<SwitchTemplate>(
      context: context,
      builder: (_) => EditSwitchTemplateDialog(existing: existing),
    );
  }

  @override
  State<EditSwitchTemplateDialog> createState() =>
      _EditSwitchTemplateDialogState();
}

class _EditSwitchTemplateDialogState extends State<EditSwitchTemplateDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _p100mCtrl;
  late final TextEditingController _p1gCtrl;
  late final TextEditingController _p25gCtrl;
  late final TextEditingController _p5gCtrl;
  late final TextEditingController _p10gCtrl;
  late final TextEditingController _sfp1gCtrl;
  late final TextEditingController _sfp10gCtrl;
  late final TextEditingController _poeWattsCtrl;
  late final TextEditingController _poeStartCtrl;
  late final TextEditingController _poeEndCtrl;

  late bool _supportsStp;
  late bool _supportsVlans;
  late bool _supportsIgmpSnooping;
  late bool _supportsIgmpQuerier;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? 'Custom 8-Port Switch');
    _p100mCtrl = TextEditingController(text: '${e?.ports100M ?? 0}');
    _p1gCtrl = TextEditingController(text: '${e?.ports1G ?? 8}');
    _p25gCtrl = TextEditingController(text: '${e?.ports2_5G ?? 0}');
    _p5gCtrl = TextEditingController(text: '${e?.ports5G ?? 0}');
    _p10gCtrl = TextEditingController(text: '${e?.ports10G ?? 0}');
    _sfp1gCtrl = TextEditingController(text: '${e?.sfpPorts1G ?? 2}');
    _sfp10gCtrl = TextEditingController(text: '${e?.sfpPorts10G ?? 0}');
    _poeWattsCtrl = TextEditingController(text: '${e?.poeBudgetWatts ?? 120}');
    _poeStartCtrl = TextEditingController(
      text: e?.poeStartPort != null ? '${e!.poeStartPort}' : '',
    );
    _poeEndCtrl = TextEditingController(
      text: e?.poeEndPort != null ? '${e!.poeEndPort}' : '',
    );
    _supportsStp = e?.supportsStp ?? true;
    _supportsVlans = e?.supportsVlans ?? true;
    _supportsIgmpSnooping = e?.supportsIgmpSnooping ?? true;
    _supportsIgmpQuerier = e?.supportsIgmpQuerier ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _p100mCtrl.dispose();
    _p1gCtrl.dispose();
    _p25gCtrl.dispose();
    _p5gCtrl.dispose();
    _p10gCtrl.dispose();
    _sfp1gCtrl.dispose();
    _sfp10gCtrl.dispose();
    _poeWattsCtrl.dispose();
    _poeStartCtrl.dispose();
    _poeEndCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    int parseInt(TextEditingController c, {int min = 0, int max = 128}) =>
        (int.tryParse(c.text.trim()) ?? 0).clamp(min, max);

    final p100m = parseInt(_p100mCtrl);
    final p1g = parseInt(_p1gCtrl);
    final p25g = parseInt(_p25gCtrl);
    final p5g = parseInt(_p5gCtrl);
    final p10g = parseInt(_p10gCtrl);
    final sfp1g = parseInt(_sfp1gCtrl);
    final sfp10g = parseInt(_sfp10gCtrl);
    if (p100m + p1g + p25g + p5g + p10g + sfp1g + sfp10g == 0) return;

    final poeBudget = parseInt(_poeWattsCtrl, max: 5000);
    final poeStart = int.tryParse(_poeStartCtrl.text.trim());
    final poeEnd = int.tryParse(_poeEndCtrl.text.trim());

    Navigator.of(context).pop(
      SwitchTemplate(
        id: widget.existing?.id ??
            'tpl-sw-${DateTime.now().microsecondsSinceEpoch}',
        name: name,
        ports100M: p100m,
        ports1G: p1g,
        ports2_5G: p25g,
        ports5G: p5g,
        ports10G: p10g,
        sfpPorts1G: sfp1g,
        sfpPorts10G: sfp10g,
        poeBudgetWatts: poeBudget,
        poeStartPort: poeStart,
        poeEndPort: poeEnd,
        supportsStp: _supportsStp,
        supportsVlans: _supportsVlans,
        supportsIgmpSnooping: _supportsIgmpSnooping,
        supportsIgmpQuerier: _supportsIgmpQuerier,
        isBuiltIn: widget.existing?.isBuiltIn ?? false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surfaceElevated,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: AppTheme.border),
      ),
      title: Text(
        widget.existing == null
            ? 'New Switch Template'
            : 'Edit Switch Template',
        style: TextStyle(fontSize: 15, color: AppTheme.textPrimary),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Template Name'),
              ),
              const SizedBox(height: 12),
              Text(
                'RJ45 Copper Ports',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _numField(_p100mCtrl, '100M')),
                  const SizedBox(width: 6),
                  Expanded(child: _numField(_p1gCtrl, '1G')),
                  const SizedBox(width: 6),
                  Expanded(child: _numField(_p25gCtrl, '2.5G')),
                  const SizedBox(width: 6),
                  Expanded(child: _numField(_p5gCtrl, '5G')),
                  const SizedBox(width: 6),
                  Expanded(child: _numField(_p10gCtrl, '10G')),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'SFP / Fibre Ports (No PoE)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _numField(_sfp1gCtrl, '1G SFP')),
                  const SizedBox(width: 6),
                  Expanded(child: _numField(_sfp10gCtrl, '10G SFP+')),
                  const Expanded(flex: 3, child: SizedBox()),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'PoE Capability (RJ45 ports only)',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _numField(_poeWattsCtrl, 'Budget (W)')),
                  const SizedBox(width: 6),
                  Expanded(child: _numField(_poeStartCtrl, 'PoE Start Port')),
                  const SizedBox(width: 6),
                  Expanded(child: _numField(_poeEndCtrl, 'PoE End Port')),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Default L2 Capabilities',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textSecondary,
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Supports STP / RSTP (Managed)',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                ),
                value: _supportsStp,
                onChanged: (v) => setState(() => _supportsStp = v ?? true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Supports 802.1Q VLANs',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                ),
                value: _supportsVlans,
                onChanged: (v) => setState(() => _supportsVlans = v ?? true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Supports IGMP Snooping',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                ),
                value: _supportsIgmpSnooping,
                onChanged: (v) =>
                    setState(() => _supportsIgmpSnooping = v ?? true),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'Supports IGMP Querier',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                ),
                value: _supportsIgmpQuerier,
                onChanged: (v) =>
                    setState(() => _supportsIgmpQuerier = v ?? true),
              ),
            ],
          ),
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
          child: const Text('Save Template'),
        ),
      ],
    );
  }

  Widget _numField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      keyboardType: TextInputType.number,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 12,
        color: AppTheme.textPrimary,
      ),
      decoration: InputDecoration(labelText: label),
    );
  }
}
