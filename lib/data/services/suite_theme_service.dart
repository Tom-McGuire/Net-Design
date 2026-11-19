import 'dart:async';
import 'dart:io';

import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:sqlite3/sqlite3.dart';

/// Synchronizes Dark/Light theme mode via the Network Suite `suite_settings`
/// SQLite table (`shared_devices.db`) so Net Design responds live to theme
/// toggles from `Net-App-Launcher` and can also toggle theme locally.
class SuiteThemeService {
  SuiteThemeService({this.customDbPath});

  final String? customDbPath;
  static const String themeModeKey = 'theme_mode';
  static const Duration pollInterval = Duration(seconds: 1);

  Database? _db;
  Timer? _pollTimer;
  int? _lastDataVersion;
  bool _isDisposed = false;
  final StreamController<String> _themeController =
      StreamController<String>.broadcast();

  Stream<String> get onThemeModeChanged => _themeController.stream;

  String _currentMode = 'dark';
  String get currentMode => _currentMode;

  Future<String> initAndReadTheme() async {
    if (_isDisposed) return _currentMode;
    try {
      final path =
          customDbPath ?? SharedDeviceDatabase.getDefaultDatabasePath();
      if (path != ':memory:' && File(path).existsSync()) {
        _db = sqlite3.open(path);
        _ensureTable();
        _currentMode = _readModeFromDb();
        _startPolling();
      }
    } catch (_) {
      // Safe fallback to dark mode when shared DB isn't present or accessible.
    }
    return _currentMode;
  }

  void _ensureTable() {
    final db = _db;
    if (db == null) return;
    try {
      db.execute('PRAGMA busy_timeout = 3000;');
      db.execute('''
        CREATE TABLE IF NOT EXISTS suite_settings (
          key TEXT PRIMARY KEY NOT NULL,
          value TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
      ''');
    } catch (_) {}
  }

  String _readModeFromDb() {
    final db = _db;
    if (db == null) return _currentMode;
    try {
      final rows = db.select(
        'SELECT value FROM suite_settings WHERE key = ? LIMIT 1;',
        [themeModeKey],
      );
      if (rows.isEmpty) return 'dark';
      return rows.first['value'] == 'light' ? 'light' : 'dark';
    } catch (_) {
      return _currentMode;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _lastDataVersion = _readDataVersion();
    _pollTimer = Timer.periodic(pollInterval, (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      final v = _readDataVersion();
      if (v != null && _lastDataVersion != null && v != _lastDataVersion) {
        final nextMode = _readModeFromDb();
        if (nextMode != _currentMode && !_isDisposed && !_themeController.isClosed) {
          _currentMode = nextMode;
          _themeController.add(nextMode);
        }
      }
      if (v != null) _lastDataVersion = v;
    });
  }

  int? _readDataVersion() {
    final db = _db;
    if (db == null) return null;
    try {
      final rows = db.select('PRAGMA data_version;');
      return rows.isEmpty ? null : rows.first.columnAt(0) as int;
    } catch (_) {
      return null;
    }
  }

  Future<void> setThemeMode(String mode) async {
    if (_isDisposed) return;
    final normalized = mode == 'light' ? 'light' : 'dark';
    _currentMode = normalized;
    if (!_themeController.isClosed) {
      _themeController.add(normalized);
    }

    try {
      if (_db == null) {
        final path =
            customDbPath ?? SharedDeviceDatabase.getDefaultDatabasePath();
        if (path != ':memory:' && File(path).parent.existsSync()) {
          _db = sqlite3.open(path);
          _ensureTable();
        }
      }
      final db = _db;
      if (db != null) {
        db.execute(
          'INSERT OR REPLACE INTO suite_settings (key, value, updated_at) VALUES (?, ?, ?);',
          [themeModeKey, normalized, DateTime.now().toUtc().toIso8601String()],
        );
        _lastDataVersion = _readDataVersion();
      }
    } catch (_) {
      // In-memory toggle still updates UI immediately even if SQLite write fails.
    }
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _pollTimer?.cancel();
    _db?.close();
    _themeController.close();
  }
}
