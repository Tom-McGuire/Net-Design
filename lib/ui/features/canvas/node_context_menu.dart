import 'package:material_ui/material_ui.dart';

import '../../theme/app_theme.dart';
import '../sandbox_view_model.dart';
import 'endpoint_node_widget.dart';
import 'switch_node_widget.dart';

/// Displays a right-click context menu for a switch or endpoint card with
/// Copy, Paste, and Delete actions.
Future<void> showDeviceContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required SandboxViewModel vm,
  required String nodeLabel,
  required VoidCallback onCopy,
  required VoidCallback onDelete,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;

  final position = RelativeRect.fromRect(
    globalPosition & const Size(1, 1),
    Offset.zero & overlay.size,
  );

  final action = await showMenu<String>(
    context: context,
    position: position,
    items: [
      PopupMenuItem<String>(
        value: 'copy',
        child: _ContextMenuRow(
          icon: Icons.copy,
          label: 'Copy $nodeLabel',
          shortcut: 'Ctrl+C',
        ),
      ),
      PopupMenuItem<String>(
        value: 'paste',
        enabled: vm.hasCopiedDevice,
        child: _ContextMenuRow(
          icon: Icons.paste,
          label: vm.hasCopiedDevice
              ? 'Paste ${vm.copiedDeviceLabel}'
              : 'Paste',
          shortcut: 'Ctrl+V',
          enabled: vm.hasCopiedDevice,
        ),
      ),
      const PopupMenuDivider(height: 6),
      PopupMenuItem<String>(
        value: 'delete',
        child: _ContextMenuRow(
          icon: Icons.delete_outline,
          label: 'Delete $nodeLabel',
          shortcut: 'Del',
          color: AppTheme.error,
        ),
      ),
    ],
  );

  switch (action) {
    case 'copy':
      onCopy();
      break;
    case 'paste':
      if (vm.hasCopiedDevice) vm.pasteCopiedNode();
      break;
    case 'delete':
      onDelete();
      break;
  }
}

/// Displays a right-click context menu on empty canvas space to paste at the
/// clicked world coordinates.
Future<void> showCanvasContextMenu({
  required BuildContext context,
  required Offset globalPosition,
  required Offset localWorldPosition,
  required SandboxViewModel vm,
}) async {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (overlay == null) return;

  final position = RelativeRect.fromRect(
    globalPosition & const Size(1, 1),
    Offset.zero & overlay.size,
  );

  final action = await showMenu<String>(
    context: context,
    position: position,
    items: [
      PopupMenuItem<String>(
        value: 'paste',
        enabled: vm.hasCopiedDevice,
        child: _ContextMenuRow(
          icon: Icons.paste,
          label: vm.hasCopiedDevice
              ? 'Paste ${vm.copiedDeviceLabel}'
              : 'Paste',
          shortcut: 'Ctrl+V',
          enabled: vm.hasCopiedDevice,
        ),
      ),
    ],
  );

  if (action == 'paste' && vm.hasCopiedDevice) {
    final isSwitch = vm.copiedDeviceIsSwitch;
    final halfW = isSwitch ? kSwitchCardWidth / 2 : kEndpointCardWidth / 2;
    final halfH =
        isSwitch ? kSwitchCardMinHeight / 2 : kEndpointCardMinHeight / 2;
    vm.pasteCopiedNode(
      dx: localWorldPosition.dx - halfW,
      dy: localWorldPosition.dy - halfH,
    );
  }
}

class _ContextMenuRow extends StatelessWidget {
  const _ContextMenuRow({
    required this.icon,
    required this.label,
    required this.shortcut,
    this.color,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String shortcut;
  final Color? color;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = !enabled
        ? AppTheme.textMuted
        : (color ?? AppTheme.textPrimary);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: effectiveColor),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: effectiveColor),
          ),
        ),
        const SizedBox(width: 16),
        Text(
          shortcut,
          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
        ),
      ],
    );
  }
}
