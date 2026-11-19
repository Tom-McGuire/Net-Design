import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../widgets/simulation_disclaimer_dialog.dart';
import '../widgets/top_control_bar.dart';
import 'canvas/design_canvas.dart';
import 'inspector/issues_drawer_panel.dart';
import 'inspector/node_inspector_panel.dart';
import 'sandbox_view_model.dart';

/// Main 5-tier desktop screen for the Network Topology & Protocol Sandbox.
class SandboxScreen extends StatefulWidget {
  const SandboxScreen({
    super.key,
    this.showStartupAdvisory = true,
  });

  final bool showStartupAdvisory;

  @override
  State<SandboxScreen> createState() => _SandboxScreenState();
}

class _SandboxScreenState extends State<SandboxScreen> {
  final FocusNode _shortcutFocusNode =
      FocusNode(debugLabel: 'SandboxShortcutFocus');
  bool _hasShownAdvisory = false;

  @override
  void dispose() {
    _shortcutFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final primaryCtx = FocusManager.instance.primaryFocus?.context;
    final isEditingText = primaryCtx != null &&
        (primaryCtx.widget is EditableText ||
            primaryCtx.findAncestorWidgetOfExactType<EditableText>() != null);
    if (isEditingText) return KeyEventResult.ignored;

    final vm = context.read<SandboxViewModel>();
    final isModifier = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isModifier && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        return vm.redo() ? KeyEventResult.handled : KeyEventResult.ignored;
      }
      return vm.undo() ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    if (isModifier && !isShift && event.logicalKey == LogicalKeyboardKey.keyY) {
      return vm.redo() ? KeyEventResult.handled : KeyEventResult.ignored;
    }

    if (isModifier && event.logicalKey == LogicalKeyboardKey.keyC) {
      return vm.copySelectedNode()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    if (isModifier && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (vm.hasCopiedDevice) {
        vm.pasteCopiedNode();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey == LogicalKeyboardKey.delete ||
        event.logicalKey == LogicalKeyboardKey.backspace) {
      return vm.deleteSelectedItem()
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    if (widget.showStartupAdvisory && !_hasShownAdvisory) {
      _hasShownAdvisory = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        SimulationDisclaimerDialog.show(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch themeRevision so theme toggles rebuild this tree in place without
    // recreating _SandboxScreenState or re-opening the startup advisory popup,
    // while avoiding full-tree rebuilds on 60Hz node drag updates.
    context.select<SandboxViewModel, int>((vm) => vm.themeRevision);

    return Focus(
      focusNode: _shortcutFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        body: Column(
          children: [
            const TopControlBar(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(child: DesignCanvas()),
                  const NodeInspectorPanel(),
                ],
              ),
            ),
            const IssuesDrawerPanel(),
          ],
        ),
      ),
    );
  }
}
