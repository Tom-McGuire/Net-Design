import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';

import 'data/services/suite_theme_service.dart';
import 'ui/features/sandbox_screen.dart';
import 'ui/features/sandbox_view_model.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SharedDeviceDatabase.instance.init();
  } catch (e) {
    debugPrint('Shared database initialization notice: $e');
  }

  final themeService = SuiteThemeService();
  final initialMode = await themeService.initAndReadTheme();
  AppTheme.isDark = initialMode != 'light';

  runApp(NetDesignApp(themeService: themeService));
}

class NetDesignApp extends StatefulWidget {
  const NetDesignApp({
    super.key,
    this.themeService,
    this.showStartupAdvisory = true,
  });

  final SuiteThemeService? themeService;
  final bool showStartupAdvisory;

  @override
  State<NetDesignApp> createState() => _NetDesignAppState();
}

class _NetDesignAppState extends State<NetDesignApp>
    with WidgetsBindingObserver {
  late final SuiteThemeService _themeService;
  late final SandboxViewModel _viewModel;
  StreamSubscription<String>? _themeSub;
  String _themeMode = AppTheme.isDark ? 'dark' : 'light';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeService = widget.themeService ?? SuiteThemeService();
    _viewModel = SandboxViewModel(themeService: _themeService);
    unawaited(_viewModel.init());

    _themeSub = _themeService.onThemeModeChanged.listen((mode) {
      if (mounted && mode != _themeMode) {
        setState(() {
          _themeMode = mode;
          AppTheme.isDark = (mode == 'dark');
        });
        _viewModel.notifyThemeChanged();
      }
    });
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    _themeService.dispose();
    if (SharedDeviceDatabase.instance.isInitialized) {
      try {
        SharedDeviceDatabase.instance.close();
      } catch (_) {}
    }
    return AppExitResponse.exit;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeSub?.cancel();
    _themeService.dispose();
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<SandboxViewModel>.value(
      value: _viewModel,
      child: MaterialApp(
        title: 'Net Design - Network Topology & Protocol Sandbox',
        debugShowCheckedModeBanner: false,
        themeMode: AppTheme.isDark ? ThemeMode.dark : ThemeMode.light,
        theme: AppTheme.lightTheme(),
        darkTheme: AppTheme.darkTheme(),
        home: SandboxScreen(showStartupAdvisory: widget.showStartupAdvisory),
      ),
    );
  }
}
