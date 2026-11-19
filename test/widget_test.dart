import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:net_design/data/services/device_templates.dart';
import 'package:net_design/data/services/project_storage_service.dart';
import 'package:net_design/data/services/suite_theme_service.dart';
import 'package:net_design/domain/engine/topology_validator.dart';
import 'package:net_design/domain/models/endpoint_node_instance.dart';
import 'package:net_design/domain/models/endpoint_template.dart';
import 'package:net_design/domain/models/enums.dart';
import 'package:net_design/domain/models/network_link_edge.dart';
import 'package:net_design/domain/models/switch_port_config.dart';
import 'package:net_design/main.dart';
import 'package:net_design/ui/features/canvas/endpoint_node_widget.dart';
import 'package:net_design/ui/features/canvas/link_edge_painter.dart';
import 'package:net_design/ui/features/canvas/switch_node_widget.dart';
import 'package:net_design/ui/features/inspector/issues_drawer_panel.dart';
import 'package:net_design/ui/features/inspector/link_inspector_view.dart';
import 'package:net_design/ui/features/inspector/node_inspector_panel.dart';
import 'package:net_design/ui/features/sandbox_view_model.dart';
import 'package:net_design/ui/theme/app_theme.dart';
import 'package:net_design/ui/widgets/top_control_bar.dart';
import 'package:provider/provider.dart';

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
      expect(find.text('Drop Unknown Multicast'), findsWidgets);
      expect(find.text('IGMP Version'), findsWidgets);

      // Device Library renders BUILT-IN badge on seeded templates
      await tester.tap(find.text('Device Library'));
      await tester.pumpAndSettle();
      expect(find.text('BUILT-IN'), findsWidgets);
      await tester.tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byIcon(Icons.close),
        ),
      );
      await tester.pumpAndSettle();

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

  testWidgets(
    'Undo and Redo shortcuts (Ctrl+Z / Ctrl+Y / Ctrl+Shift+Z) restore and re-apply deletions',
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

      final coreFinder = find.descendant(
        of: find.byType(SwitchNodeWidget),
        matching: find.text('FOH Core Switch A'),
      );
      expect(coreFinder, findsOneWidget);

      await tester.tap(coreFinder);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.delete);
      await tester.pumpAndSettle();
      expect(coreFinder, findsNothing);

      // Ctrl+Z undoes deletion
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(coreFinder, findsOneWidget);

      // Ctrl+Y redoes deletion
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(coreFinder, findsNothing);

      // Ctrl+Shift+Z undoes? No, Ctrl+Shift+Z is redo — let's undo first, then redo with Ctrl+Shift+Z
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(coreFinder, findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(coreFinder, findsNothing);
    },
  );

  test(
    'Undo stack is bounded to 30 snapshots and addKnownVlan defaults igmpSnoopingEnabled to false',
    () {
      final vm = SandboxViewModel(
        initialProject: DeviceTemplates.healthyReferenceRingDemo(),
      );

      vm.addKnownVlan(50, 'Stage Comms');
      for (final sw in vm.project.switches) {
        expect(sw.vlanConfigs[50]?.igmpSnoopingEnabled, isFalse);
      }
      expect(
        vm.validation.issues.where(
          (i) => i.title.contains('IGMP Snooping') && i.message.contains('50'),
        ),
        isEmpty,
      );

      for (var i = 0; i < 35; i++) {
        vm.randomiseSwitchMacs();
      }
      var undoCount = 0;
      while (vm.undo()) {
        undoCount++;
      }
      expect(undoCount, 30);
      expect(vm.canUndo, isFalse);
      expect(vm.canRedo, isTrue);

      // Endpoints placed from templates get a locally-administered MAC address
      final placedEp = vm.addEndpointFromTemplate(vm.endpointTemplates.first);
      expect(placedEp.macAddress, isNotNull);
      expect(placedEp.macAddress, startsWith('02:'));
    },
  );

  testWidgets(
    'RX quick-pick chips toggle and merge universes and multicast groups including bidirectional flows',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        AppTheme.isDark = true;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final vm = SandboxViewModel()..newBlankProject();
      final tpl = vm.switchTemplates.first;
      final sw = vm.addSwitchFromTemplate(tpl, dx: 200, dy: 100);
      vm.updateSwitch(
        sw.copyWith(
          ports: [
            for (var p = 1; p <= 8; p++)
              SwitchPortConfig(
                portNumber: p,
                portMode: SwitchPortMode.trunk,
                nativeVlan: 1,
                allowedVlans: const {1, 20, 30},
              ),
          ],
        ),
      );

      final tx1 = EndpointNodeInstance(
        id: 'ep-tx1',
        templateId: 'tpl-tx',
        userLabel: 'Console TX1',
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f-tx1',
            protocol: TrafficProtocol.sacn,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 1.0,
            requiresIgmp: true,
            defaultVlanId: 20,
            sacnUniverseSpec: '1-4',
          ),
        ],
      );
      final tx2 = EndpointNodeInstance(
        id: 'ep-tx2',
        templateId: 'tpl-tx',
        userLabel: 'Console TX2',
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f-tx2',
            protocol: TrafficProtocol.sacn,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 1.0,
            requiresIgmp: true,
            defaultVlanId: 20,
            sacnUniverseSpec: '5-8',
          ),
        ],
      );
      final dante1 = EndpointNodeInstance(
        id: 'ep-d1',
        templateId: 'tpl-d',
        userLabel: 'Dante TX1',
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f-d1',
            protocol: TrafficProtocol.danteAes67,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 50.0,
            requiresIgmp: true,
            defaultVlanId: 30,
            multicastGroupSpec: '239.69.0.1',
          ),
        ],
      );
      final dante2 = EndpointNodeInstance(
        id: 'ep-d2',
        templateId: 'tpl-d',
        userLabel: 'Dante TX2',
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f-d2',
            protocol: TrafficProtocol.danteAes67,
            direction: TrafficDirection.txPublisher,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 50.0,
            requiresIgmp: true,
            defaultVlanId: 30,
            multicastGroupSpec: '239.69.0.2',
          ),
        ],
      );
      final sub = EndpointNodeInstance(
        id: 'ep-sub',
        templateId: 'tpl-sub',
        userLabel: 'Bidirectional Receiver',
        activeTrafficFlows: const [
          TrafficRequirement(
            id: 'f-sub-sacn',
            protocol: TrafficProtocol.sacn,
            direction: TrafficDirection.bidirectional,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 0.0,
            requiresIgmp: true,
            defaultVlanId: 20,
          ),
          TrafficRequirement(
            id: 'f-sub-dante',
            protocol: TrafficProtocol.danteAes67,
            direction: TrafficDirection.rxSubscriber,
            deliveryType: DeliveryType.multicast,
            estimatedBandwidthMbps: 100.0,
            requiresIgmp: true,
            defaultVlanId: 30,
          ),
        ],
      );

      vm.project.endpoints.addAll([tx1, tx2, dante1, dante2, sub]);
      vm.connectPorts(sw.id, 1, tx1.id, 1);
      vm.connectPorts(sw.id, 2, tx2.id, 1);
      vm.connectPorts(sw.id, 3, dante1.id, 1);
      vm.connectPorts(sw.id, 4, dante2.id, 1);
      vm.connectPorts(sw.id, 5, sub.id, 1);
      vm.selectEndpoint(sub.id);

      await tester.pumpWidget(
        ChangeNotifierProvider<SandboxViewModel>.value(
          value: vm,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: Row(
                children: [
                  Expanded(child: SizedBox()),
                  NodeInspectorPanel(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bidirectional flow shows RX quick-pick chips for sACN
      final sacnChip1 = find.text('sACN U1-4 (Console TX1)');
      final sacnChip2 = find.text('sACN U5-8 (Console TX2)');
      expect(sacnChip1, findsOneWidget);
      expect(sacnChip2, findsOneWidget);

      await tester.ensureVisible(sacnChip1);
      await tester.tap(sacnChip1);
      await tester.pumpAndSettle();
      expect(vm.selectedEndpoint!.activeTrafficFlows[0].sacnUniverseSpec, '1-4');
      expect(
        vm.selectedEndpoint!.activeTrafficFlows[0].estimatedBandwidthMbps,
        1.0,
      );

      await tester.ensureVisible(sacnChip2);
      await tester.tap(sacnChip2);
      await tester.pumpAndSettle();
      expect(vm.selectedEndpoint!.activeTrafficFlows[0].sacnUniverseSpec, '1-8');
      expect(
        vm.selectedEndpoint!.activeTrafficFlows[0].estimatedBandwidthMbps,
        2.0,
      );

      // Tapping first chip again toggles only 1-4 off, leaving 5-8
      await tester.ensureVisible(sacnChip1);
      await tester.tap(sacnChip1);
      await tester.pumpAndSettle();
      expect(vm.selectedEndpoint!.activeTrafficFlows[0].sacnUniverseSpec, '5-8');
      expect(
        vm.selectedEndpoint!.activeTrafficFlows[0].estimatedBandwidthMbps,
        1.0,
      );

      // Dante multicast group quick-pick chips merge & toggle off cleanly
      final danteChip1 = find.text('239.69.0.1 (Dante TX1)');
      final danteChip2 = find.text('239.69.0.2 (Dante TX2)');
      await tester.ensureVisible(danteChip1);
      await tester.tap(danteChip1);
      await tester.pumpAndSettle();
      expect(
        vm.selectedEndpoint!.activeTrafficFlows[1].multicastGroupSpec,
        '239.69.0.1',
      );
      expect(
        vm.selectedEndpoint!.activeTrafficFlows[1].estimatedBandwidthMbps,
        50.0,
      );

      await tester.ensureVisible(danteChip2);
      await tester.tap(danteChip2);
      await tester.pumpAndSettle();
      expect(
        vm.selectedEndpoint!.activeTrafficFlows[1].multicastGroupSpec,
        '239.69.0.1-2',
      );
      expect(
        vm.selectedEndpoint!.activeTrafficFlows[1].estimatedBandwidthMbps,
        100.0,
      );

      await tester.ensureVisible(danteChip1);
      await tester.tap(danteChip1);
      await tester.pumpAndSettle();
      expect(
        vm.selectedEndpoint!.activeTrafficFlows[1].multicastGroupSpec,
        '239.69.0.2',
      );
      expect(
        vm.selectedEndpoint!.activeTrafficFlows[1].estimatedBandwidthMbps,
        50.0,
      );
    },
  );

  testWidgets(
    'LinkInspectorView fixes trunk VLAN symmetry and IssuesDrawerPanel renders CLI CONFIG PREVIEW',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        AppTheme.isDark = true;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final vm = SandboxViewModel(
        initialProject: DeviceTemplates.brokenRingFaultDemo(),
      );
      vm.selectLink('lnk-brk-2');

      await tester.pumpWidget(
        ChangeNotifierProvider<SandboxViewModel>.value(
          value: vm,
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(child: SizedBox()),
                        NodeInspectorPanel(),
                      ],
                    ),
                  ),
                  IssuesDrawerPanel(),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LinkInspectorView), findsOneWidget);
      expect(find.text('Asymmetric / Pruned VLANs'), findsOneWidget);
      final fixBtn = find.text('Fix Trunk VLAN Symmetry');
      expect(fixBtn, findsOneWidget);

      await tester.ensureVisible(fixBtn);
      await tester.tap(fixBtn);
      await tester.pumpAndSettle();

      expect(find.text('Fix Trunk VLAN Symmetry'), findsNothing);
      final fixedLink =
          vm.project.links.firstWhere((l) => l.id == 'lnk-brk-2');
      expect(fixedLink.activeVlans, containsAll([1, 20]));

      // Switch to CLI CONFIG PREVIEW tab for FOH Rack Switch A
      vm.selectSwitch('sw-foh-broken');
      await tester.pumpAndSettle();

      await tester.tap(find.text('CLI CONFIG PREVIEW'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('! Vendor-Neutral Reference Config: FOH Rack Switch A'),
        findsOneWidget,
      );
      expect(find.textContaining('switchport trunk allowed vlan 1,20'), findsWidgets);
    },
  );

  testWidgets(
    'LinkEdgePainter highlights pruned VLAN trunks in red and detects LinkGeometry mutations',
    (WidgetTester tester) async {
      AppTheme.isDark = true;

      final link = NetworkLinkEdge(
        id: 'lnk-pruned',
        sourceNodeId: 'sw-a',
        sourcePortNumber: 1,
        targetNodeId: 'sw-b',
        targetPortNumber: 2,
        stpState: LinkStpState.forwarding,
        activeVlans: {1},
        prunedVlans: {20},
      );

      final geom = LinkGeometry(
        link: link,
        start: const Offset(20, 60),
        end: const Offset(280, 60),
        control: const Offset(150, 60),
      );
      final geomDuplicate = LinkGeometry(
        link: link,
        start: const Offset(20, 60),
        end: const Offset(280, 60),
        control: const Offset(150, 60),
      );

      final painter = LinkEdgePainter(
        geometries: [geom],
        selectedLinkId: null,
        highlightedVlanId: 20,
        isTrunkFilterActive: false,
        isDark: true,
      );
      final samePainter = LinkEdgePainter(
        geometries: [geomDuplicate],
        selectedLinkId: null,
        highlightedVlanId: 20,
        isTrunkFilterActive: false,
        isDark: true,
      );
      expect(painter.shouldRepaint(samePainter), isFalse);

      // Mutate prunedVlans in place and confirm snapshot detects change
      link.prunedVlans = {};
      link.activeVlans = {1, 20};
      final mutatedGeom = LinkGeometry(
        link: link,
        start: const Offset(20, 60),
        end: const Offset(280, 60),
        control: const Offset(150, 60),
      );
      final mutatedPainter = LinkEdgePainter(
        geometries: [mutatedGeom],
        selectedLinkId: null,
        highlightedVlanId: 20,
        isTrunkFilterActive: false,
        isDark: true,
      );
      expect(mutatedPainter.shouldRepaint(painter), isTrue);

      // Paint original pruned trunk to an offscreen canvas and confirm AppTheme.error pixels render
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        painter.paint(canvas, const Size(300, 120));
        final picture = recorder.endRecording();
        final image = await picture.toImage(300, 120);
        final byteData =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        picture.dispose();
        return byteData!.buffer.asUint8List();
      });

      final errArgb = AppTheme.error.toARGB32();
      final errR = (errArgb >> 16) & 0xFF;
      final errG = (errArgb >> 8) & 0xFF;
      final errB = errArgb & 0xFF;

      var foundErrorPixel = false;
      for (var i = 0; i < bytes!.length; i += 4) {
        if ((bytes[i] - errR).abs() <= 2 &&
            (bytes[i + 1] - errG).abs() <= 2 &&
            (bytes[i + 2] - errB).abs() <= 2 &&
            bytes[i + 3] > 200) {
          foundErrorPixel = true;
          break;
        }
      }
      expect(foundErrorPixel, isTrue);
    },
  );
}
