import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_design/data/services/suite_theme_service.dart';
import 'package:net_design/main.dart';
import 'package:net_design/ui/theme/app_theme.dart';

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
    },
  );
}
