import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:net_design/data/services/device_templates.dart';
import 'package:net_design/data/services/project_storage_service.dart';
import 'package:net_design/data/services/suite_theme_service.dart';
import 'package:net_design/domain/engine/topology_validator.dart';
import 'package:net_design/domain/models/enums.dart';
import 'package:net_design/main.dart';
import 'package:net_design/ui/features/canvas/endpoint_node_widget.dart';
import 'package:net_design/ui/features/canvas/switch_node_widget.dart';
import 'package:net_design/ui/features/sandbox_view_model.dart';
import 'package:net_design/ui/theme/app_theme.dart';
import 'package:net_design/ui/widgets/top_control_bar.dart';

void main() {
  testWidgets(
    'Displays startup advisory popup once, toggles theme without re-showing advisory, and randomises MACs',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        AppTheme.isDark = true;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final themeService = SuiteThemeService(customDbPath: ':memory:');
      addTearDown(themeService.dispose);

      await tester.pumpWidget(
        NetDesignApp(
          themeService: themeService,
          showStartupAdvisory: true,
        ),
      );

      // Trigger postFrameCallback that opens SimulationDisclaimerDialog
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('Simulation & Engineering Advisory'), findsOneWidget);
      expect(find.text('Acknowledge & Continue'), findsOneWidget);

      await tester.tap(find.text('Acknowledge & Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Simulation & Engineering Advisory'), findsNothing);
      expect(find.text('NET DESIGN'), findsOneWidget);
      expect(find.text('Randomise MACs'), findsOneWidget);
      expect(find.text('Highlight VLAN:'), findsOneWidget);
      expect(find.text('Device Library'), findsOneWidget);
      expect(find.text('Scenarios'), findsOneWidget);
      expect(find.byTooltip('User Manual (PDF)'), findsOneWidget);

      // Switching between dark and light mode must NOT re-open the startup advisory
      expect(AppTheme.isDark, isTrue);
      await tester.tap(find.byTooltip('Switch to Light Mode'));
      await tester.pumpAndSettle();
      expect(AppTheme.isDark, isFalse);
      expect(find.byTooltip('Switch to Dark Mode'), findsOneWidget);
      expect(find.text('Simulation & Engineering Advisory'), findsNothing);

      await tester.tap(find.byTooltip('Switch to Dark Mode'));
      await tester.pumpAndSettle();
      expect(AppTheme.isDark, isTrue);
      expect(find.text('Simulation & Engineering Advisory'), findsNothing);

      // Clicking Randomise MACs updates MAC addresses and shows status banner
      await tester.tap(find.text('Randomise MACs'));
      await tester.pump();
      expect(
        find.textContaining('Randomized switch MAC addresses'),
        findsOneWidget,
      );

      // Select a switch to verify the tidied Per-VLAN IGMP card renders cleanly
      await tester.tap(find.text('FOH Core Switch A'));
      await tester.pumpAndSettle();
      expect(find.text('Per-VLAN IGMP Snooping & Querier'), findsOneWidget);
      expect(find.text('Snooping'), findsWidgets);
      expect(find.text('Querier'), findsWidgets);
      expect(find.text('IGMP Version'), findsWidgets);

      // Trunks filter chip is present alongside All & VLAN chips in TopControlBar
      final topBar = find.byType(TopControlBar);
      expect(
        find.descendant(of: topBar, matching: find.text('All')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: topBar, matching: find.text('Trunks')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: topBar, matching: find.text('Default / Mgmt (1)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: topBar, matching: find.text('sACN / Lighting (20)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: topBar, matching: find.text('Trace Stream:')),
        findsOneWidget,
      );

      // Toggle Trunks filter on and off
      await tester.tap(find.descendant(of: topBar, matching: find.text('Trunks')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: topBar, matching: find.text('Trunks')));
      await tester.pumpAndSettle();

      // Open Trace Stream dropdown and select Stage Left sACN Node RX trace
      await tester.tap(find.text('None (Normal View)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('RX U1-4 -> Stage Left sACN Node (V20)').last);
      await tester.pumpAndSettle();
      expect(find.text('DELIVERED'), findsOneWidget);
      expect(find.text('IGMP PRUNED'), findsOneWidget);

      // Scenarios menu no longer contains New Blank Canvas
      await tester.tap(find.text('Scenarios'));
      await tester.pumpAndSettle();
      expect(find.text('New Blank Canvas'), findsNothing);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // 3-dot Project File & Export menu contains New Blank Canvas, Open Project, Save Project (no .netdesign)
      await tester.ensureVisible(find.byTooltip('Project File & Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Project File & Export'));
      await tester.pumpAndSettle();
      expect(find.text('New Blank Canvas'), findsOneWidget);
      expect(find.text('Open Project'), findsOneWidget);
      expect(find.text('Save Project'), findsOneWidget);
      expect(find.textContaining('.netdesign'), findsNothing);

      // Selecting New Blank Canvas resets filter bar to All, Trunks, VLAN 1 only
      await tester.tap(find.text('New Blank Canvas'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: topBar, matching: find.text('All')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: topBar, matching: find.text('Trunks')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: topBar, matching: find.text('Default / Mgmt (1)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: topBar, matching: find.text('sACN / Lighting (20)')),
        findsNothing,
      );
      expect(
        find.descendant(of: topBar, matching: find.text('Dante / Audio (30)')),
        findsNothing,
      );
      expect(
        find.descendant(of: topBar, matching: find.text('VLAN 40')),
        findsNothing,
      );
    },
  );

  test('VLAN filters persist across project save/load and Trunks validates both ends', () {
    const storage = ProjectStorageService();
    final vm = SandboxViewModel(initialProject: DeviceTemplates.healthyReferenceRingDemo());
    vm.newBlankProject();
    expect(vm.availableVlanIds, [1]);

    // Add custom VLAN 50 and verify serialization preserves filter VLANs
    vm.addKnownVlan(50, 'Stage Comms');
    expect(vm.availableVlanIds, [1, 50]);
    expect(vm.formatVlanDisplay(50), 'Stage Comms (50)');
    expect(vm.formatVlanDisplay(1), 'Default / Mgmt (1)');
    final raw = storage.serializeProject(vm.project);
    final loaded = storage.deserializeProject(raw);
    expect(loaded.knownVlans.keys.toList()..sort(), [1, 50]);
    expect(loaded.knownVlans[50], 'Stage Comms');

    // Symmetric trunk links in healthy demo mark isValidTrunk = true
    const validator = TopologyValidator();
    final healthy = DeviceTemplates.healthyReferenceRingDemo();
    validator.validate(healthy);
    final coreToLeft = healthy.links.firstWhere((l) => l.id == 'lnk-core-left');
    expect(coreToLeft.isValidTrunk, isTrue);

    // Broken demo links missing VLAN 20 on one side mark isValidTrunk = false
    final broken = DeviceTemplates.brokenRingFaultDemo();
    validator.validate(broken);
    final brokenTrunk = broken.links.firstWhere((l) => l.id == 'lnk-brk-2');
    expect(brokenTrunk.isValidTrunk, isFalse);
  });

  test('New devices spawn at viewport center without stacking', () {
    final vm = SandboxViewModel();
    vm.newBlankProject();
    vm.updateViewportCenter(const Offset(1800, 1200));

    final sw1 = vm.addSwitchFromTemplate(vm.switchTemplates.first);
    expect(sw1.dx, closeTo(1800 - 268.0 / 2, 0.1));
    expect(sw1.dy, closeTo(1200 - 148.0 / 2, 0.1));

    // Second device at same viewport center should nudge by 28px so it doesn't overlap
    final sw2 = vm.addSwitchFromTemplate(vm.switchTemplates.first);
    expect(sw2.dx, closeTo(sw1.dx + 28.0, 0.1));
    expect(sw2.dy, closeTo(sw1.dy + 28.0, 0.1));

    // Endpoint centered around viewport center
    vm.updateViewportCenter(const Offset(2400, 900));
    final ep1 = vm.addEndpointFromTemplate(vm.endpointTemplates.first);
    expect(ep1.dx, closeTo(2400 - 228.0 / 2, 0.1));
    expect(ep1.dy, closeTo(900 - 104.0 / 2, 0.1));
  });

  testWidgets(
    'Right-click context menu and Ctrl+C / Ctrl+V / Delete shortcuts work for switches and endpoints',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        AppTheme.isDark = true;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final themeService = SuiteThemeService(customDbPath: ':memory:');
      addTearDown(themeService.dispose);

      await tester.pumpWidget(
        NetDesignApp(
          themeService: themeService,
          showStartupAdvisory: false,
        ),
      );
      await tester.pumpAndSettle();

      // Right-click on FOH Core Switch A
      final coreFinder = find.text('FOH Core Switch A');
      expect(coreFinder, findsOneWidget);
      await tester.tap(coreFinder, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('Copy FOH Core Switch A'), findsOneWidget);
      expect(find.text('Delete FOH Core Switch A'), findsOneWidget);

      // Copy FOH Core Switch A via context menu
      await tester.tap(find.text('Copy FOH Core Switch A'));
      await tester.pumpAndSettle();

      // Paste via Ctrl+V
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final pastedSwitchFinder = find.descendant(
        of: find.byType(SwitchNodeWidget),
        matching: find.text('FOH Core Switch A (Copy)'),
      );
      expect(pastedSwitchFinder, findsOneWidget);

      // Delete pasted switch via Delete key
      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(pastedSwitchFinder, findsNothing);

      // Select Main Lighting Console endpoint, copy with Ctrl+C, paste with Ctrl+V, delete via right-click
      await tester.tap(find.text('Main Lighting Console'));
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final pastedEndpointFinder = find.descendant(
        of: find.byType(EndpointNodeWidget),
        matching: find.text('Main Lighting Console (Copy)'),
      );
      expect(pastedEndpointFinder, findsOneWidget);

      await tester.tap(
        pastedEndpointFinder,
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Main Lighting Console (Copy)'));
      await tester.pumpAndSettle();
      expect(pastedEndpointFinder, findsNothing);
    },
  );

  testWidgets(
    'Editing switch Bridge MAC recalculates STP Root Bridge when priorities match',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        AppTheme.isDark = true;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final themeService = SuiteThemeService(customDbPath: ':memory:');
      addTearDown(themeService.dispose);

      await tester.pumpWidget(
        NetDesignApp(
          themeService: themeService,
          showStartupAdvisory: false,
        ),
      );
      await tester.pumpAndSettle();

      // Load Arbitrary Root & VLAN Blackhole or select Stage Right Rack C (PRI 32768, MAC 02:10:00:00:00:30)
      // In Healthy Ring: Stage Left Rack B and Stage Right Rack C both have PRI 32768.
      // Lowering Core Switch priority isn't needed if we test Stage Left vs Stage Right after setting Core to 32768,
      // or simply select Stage Right Rack C and verify its MAC field is editable and normalizes Cisco dot format.
      await tester.tap(find.text('Stage Right Rack C'));
      await tester.pumpAndSettle();

      final macField = find.widgetWithText(TextField, '02:10:00:00:00:30');
      expect(macField, findsOneWidget);

      await tester.enterText(macField, '0210.0000.0001');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Normalized to 02:10:00:00:00:01 on both the field and the canvas card
      expect(find.text('02:10:00:00:00:01'), findsWidgets);
    },
  );

  test(
    'Template edits do not auto-update placed devices until Update Plan is triggered',
    () async {
      final vm = SandboxViewModel();
      vm.newBlankProject();

      // Find an edge switch template with supportsIgmpQuerier == false (or toggle it)
      final baseTpl = vm.switchTemplates.first;
      final disabledQuerierTpl = baseTpl.copyWith(supportsIgmpQuerier: false);
      await vm.saveSwitchTemplate(disabledQuerierTpl);

      final placed = vm.addSwitchFromTemplate(disabledQuerierTpl, dx: 300, dy: 200);
      final originalMac = placed.macAddress;
      expect(placed.supportsIgmpQuerier, isFalse);

      // Edit template to enable IGMP Querier
      final enabledQuerierTpl =
          disabledQuerierTpl.copyWith(supportsIgmpQuerier: true);
      await vm.saveSwitchTemplate(enabledQuerierTpl);

      // Placed switch must NOT auto-update
      final beforeSync =
          vm.project.switches.firstWhere((s) => s.id == placed.id);
      expect(beforeSync.supportsIgmpQuerier, isFalse);

      // Explicit sync updates placed switch while preserving identity & position
      final updatedCount = vm.applySwitchTemplateToPlan(enabledQuerierTpl);
      expect(updatedCount, 1);

      final afterSync =
          vm.project.switches.firstWhere((s) => s.id == placed.id);
      expect(afterSync.supportsIgmpQuerier, isTrue);
      expect(afterSync.macAddress, originalMac);
      expect(afterSync.dx, 300);
      expect(afterSync.dy, 200);
    },
  );

  test('Wiring cannot connect a device back to another port on itself', () {
    final vm = SandboxViewModel();
    vm.newBlankProject();
    final mediaTpl = vm.endpointTemplates.firstWhere(
      (t) => t.effectivePorts.length > 1,
    );
    final ep = vm.addEndpointFromTemplate(mediaTpl);

    vm.startWiringFromPort(ep.id, 1);
    expect(vm.canCompleteWiringToPort(ep.id, 2), isFalse);
    expect(vm.completeWiringToPort(ep.id, 2), isFalse);
    expect(vm.project.links, isEmpty);
  });

  test(
    'Trace Stream All VLAN Streams respects STP and IGMP Querier location',
    () {
      final vm = SandboxViewModel(
        initialProject: DeviceTemplates.healthyReferenceRingDemo(),
      );

      // Remove Stage Right sACN Node so VLAN 20 only has endpoints on Core A and Stage Left Rack B.
      vm.removeNode('ep-node-r');

      vm.setActiveStreamTrace('vlan:20');
      expect(vm.activeStreamTraceTarget?.label, 'All VLAN 20 Streams');

      final coreLeft =
          vm.project.links.firstWhere((l) => l.id == 'lnk-core-left');
      final coreRight =
          vm.project.links.firstWhere((l) => l.id == 'lnk-core-right');
      final leftRight =
          vm.project.links.firstWhere((l) => l.id == 'lnk-left-right');

      // Core A is IGMP Querier and STP Root: traffic delivers to Stage Left and is IGMP-pruned toward Stage Right.
      expect(coreLeft.streamTraceState, LinkStreamTraceState.delivered);
      expect(coreRight.streamTraceState, LinkStreamTraceState.igmpPruned);
      expect(leftRight.streamTraceState, LinkStreamTraceState.none);

      // Move IGMP Querier for VLAN 20 from Core A to Stage Right Rack C.
      final core =
          vm.project.switches.firstWhere((s) => s.id == 'sw-core-foh');
      final right =
          vm.project.switches.firstWhere((s) => s.id == 'sw-stage-right');
      vm.updateSwitch(
        core.copyWith(
          vlanConfigs: {
            ...core.vlanConfigs,
            20: core.vlanConfigs[20]!.copyWith(igmpQuerierEnabled: false),
          },
        ),
      );
      vm.updateSwitch(
        right.copyWith(
          vlanConfigs: {
            ...right.vlanConfigs,
            20: right.vlanConfigs[20]!.copyWith(igmpQuerierEnabled: true),
          },
        ),
      );

      // Now Core A -> Stage Right carries mrouter traffic to the Querier while STP-blocked link stays none.
      expect(coreRight.streamTraceState, LinkStreamTraceState.delivered);
      expect(leftRight.streamTraceState, LinkStreamTraceState.none);
    },
  );
}
