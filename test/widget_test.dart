import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_design/data/services/device_templates.dart';
import 'package:net_design/data/services/project_storage_service.dart';
import 'package:net_design/data/services/suite_theme_service.dart';
import 'package:net_design/domain/engine/topology_validator.dart';
import 'package:net_design/main.dart';
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
        find.descendant(of: topBar, matching: find.text('VLAN 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: topBar, matching: find.text('VLAN 20')),
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
        find.descendant(of: topBar, matching: find.text('VLAN 1')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: topBar, matching: find.text('VLAN 20')),
        findsNothing,
      );
      expect(
        find.descendant(of: topBar, matching: find.text('VLAN 30')),
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
}
