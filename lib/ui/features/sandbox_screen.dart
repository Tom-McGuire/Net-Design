import 'package:flutter/material.dart';

import '../widgets/simulation_disclaimer_dialog.dart';
import '../widgets/top_control_bar.dart';
import 'canvas/design_canvas.dart';
import 'inspector/issues_drawer_panel.dart';
import 'inspector/node_inspector_panel.dart';

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
  @override
  void initState() {
    super.initState();
    if (widget.showStartupAdvisory) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        SimulationDisclaimerDialog.show(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Column(
        children: [
          TopControlBar(),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: DesignCanvas()),
                NodeInspectorPanel(),
              ],
            ),
          ),
          IssuesDrawerPanel(),
        ],
      ),
    );
  }
}
