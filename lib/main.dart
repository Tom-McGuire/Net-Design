import 'dart:async';
import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await SharedDeviceDatabase.instance.init();
  } catch (e) {
    debugPrint('Shared database initialization notice: $e');
  }

  runApp(const NetDesignApp());
}

class NetDesignApp extends StatefulWidget {
  const NetDesignApp({super.key});

  @override
  State<NetDesignApp> createState() => _NetDesignAppState();
}

class _NetDesignAppState extends State<NetDesignApp> {
  StreamSubscription<void>? _dbSub;

  @override
  void initState() {
    super.initState();
    try {
      _dbSub = SharedDeviceDatabase.instance.onDatabaseChanged.listen((_) {
        if (mounted) {
          setState(() {});
        }
      });
    } catch (_) {
      // Ignored if stream unavailable
    }
  }

  @override
  void dispose() {
    _dbSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Net Design - Network Topology & Protocol Sandbox',
      debugShowCheckedModeBanner: false,
      themeMode: AppTheme.isDark ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hub_outlined, size: 64, color: Color(0xFF007ACC)),
              SizedBox(height: 16),
              Text(
                'Net Design Sandbox',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Layer 2 / Layer 3 Network Topology & Protocol Sandbox',
                style: TextStyle(fontSize: 14),
              ),
              SizedBox(height: 16),
              Text(
                'Environment configured for Windows, macOS, and Linux.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
