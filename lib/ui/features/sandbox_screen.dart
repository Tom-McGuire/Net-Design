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
  bool _hasShownAdvisory = false;

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
    // Watch view model so theme toggles rebuild this tree in place without
    // recreating _SandboxScreenState or re-opening the startup advisory popup.
    context.watch<SandboxViewModel>();

    return Scaffold(
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
    );
  }
}
