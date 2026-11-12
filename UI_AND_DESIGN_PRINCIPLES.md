# Network & Systems Desktop Applications: UI & Design Principles

> **Reference Specification for AI Coding Agents and Developers**  
> Canonical implementations: `net-app-launcher`, `packet-inspector`, `net-services`, `syslog-server`, `socket-scout`, `arp-scout`, `net-bench`, `igmp-tester`, `net-router`, `tshark-interface`.

---

## 1. Core Philosophy & Design Goals

1. **Dark-First, High Information Density**: Built for network engineers, sysadmins, and security analysts examining high-throughput streams (packets, logs, routing tables). Crisp typography, minimal whitespace, high contrast.
2. **Desktop Viewport Ergonomics**: Sized for $1200\times700+$ on Windows, macOS, and Linux. Built-in support for hover states, resizable columns, and dual-axis scrolling.
3. **Graceful Desktop Lifecycle**: Desktop tools bind raw sockets, launch CLI daemons (`tshark`, `iperf3`, `tcpdump`), and open SQLite databases. Implement `WidgetsBindingObserver.didRequestAppExit` to cleanly shut down background daemons and close sockets on window close.
4. **Resilient Data Virtualization**: Streaming workloads ($10^4$ to $10^6$ records) leverage local SQLite caching with paginated batching (500–1,000 items) and virtualized `ListView.separated`.
5. **Shared Device Identity**: Integrates with `network_suite_shared` to resolve MAC addresses into user-friendly names seamlessly across all tools.

---

## 2. Color Palette & Theming (Design Tokens)

The suite uses a synchronized **Dark & Light Mode** architecture. Dark Mode is the high-contrast default for field/rack use, while Light Mode provides a clean, technical slate for brightly lit control rooms or offices. Theme changes are toggled globally from `Net-App-Launcher` and broadcast live across all running tools via `network_suite_shared`.

### Dynamic Token Palette

| Token | Dark Mode (VS Code Slate) | Light Mode (Clean Technical Slate) | Semantic Role |
| :--- | :--- | :--- | :--- |
| `scaffoldBg` | `#141414` | `#F3F4F6` (Cool Gray 100) | Root window / workspace background |
| `surface` | `#1E1E1E` | `#FFFFFF` (Pure White) | Tables, cards, panels, top bar |
| `surfaceHigh` | `#252526` | `#F9FAFB` (Cool Gray 50) | Inputs, hover states, table headers |
| `surfaceElevated` | `#2D2D2D` | `#FFFFFF` | Modals, inspector drawers, dropdowns |
| `border` | `#2C2C2C` | `#E5E7EB` (Cool Gray 200) | 1px clean gridlines and separators |
| `textPrimary` | `#E0E0E0` | `#111827` (Gray 900) | Primary labels, IP addresses, headings |
| `textSecondary` | `#9E9E9E` | `#4B5563` (Gray 600) | Secondary labels, descriptions, cell text |
| `textMuted` | `#6E6E6E` | `#6B7280` (Gray 500) | Disabled items, placeholders, hints |
| `accent` | `#007ACC` | `#0284C7` (Sky Blue) | Active rows, primary action buttons |
| `success` | `#10B981` | `#059669` (Emerald) | Running daemons, idle Start buttons, online |
| `warning` | `#F59E0B` | `#D97706` (Amber) | Anomalies, conflicts, Exit Demo state |
| `error` | `#EF4444` | `#DC2626` (Red) | Active Stop buttons, port collisions, errors |

### Theming Rules for New Apps

> [!IMPORTANT]
> **Never hardcode static colors or `Colors.white*` / `Colors.black*` in widget trees!**
> 1. Use `AppTheme.<token>` dynamic getters so widgets re-evaluate colors when the root `MaterialApp` rebuilds.
> 2. Avoid putting `const` on widgets that reference `AppTheme.<token>`.
> 3. Use `Colors.white` **only** for text/icons on filled colored buttons (e.g. `FilledButton` with green success / blue accent / red error backgrounds).
> 4. For `CustomPainter` canvas rendering, read `AppTheme.textPrimary`, `AppTheme.border`, etc., inside `paint()` and check `AppTheme.isDark` in `shouldRepaint()`.

### Canonical Theme Implementation (`app_theme.dart`)

```dart
import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  /// Runtime flag synchronized with SharedDeviceDatabase.instance.getThemeMode()
  static bool isDark = true;

  // --- Dynamic Surface Tokens ---
  static Color get scaffoldBg => isDark ? const Color(0xFF141414) : const Color(0xFFF3F4F6);
  static Color get surface => isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
  static Color get surfaceHigh => isDark ? const Color(0xFF252526) : const Color(0xFFF9FAFB);
  static Color get surfaceElevated => isDark ? const Color(0xFF2D2D2D) : const Color(0xFFFFFFFF);
  static Color get border => isDark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E7EB);

  // --- Dynamic Typography Tokens ---
  static Color get textPrimary => isDark ? const Color(0xFFE0E0E0) : const Color(0xFF111827);
  static Color get textSecondary => isDark ? const Color(0xFF9E9E9E) : const Color(0xFF4B5563);
  static Color get textMuted => isDark ? const Color(0xFF6E6E6E) : const Color(0xFF6B7280);

  // --- Semantic & Status Tokens ---
  static Color get accent => isDark ? const Color(0xFF007ACC) : const Color(0xFF0284C7);
  static Color get success => isDark ? const Color(0xFF10B981) : const Color(0xFF059669);
  static Color get warning => isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);
  static Color get error => isDark ? const Color(0xFFEF4444) : const Color(0xFFDC2626);

  // --- ThemeData Factory ---
  static ThemeData darkTheme() => _buildTheme(Brightness.dark);
  static ThemeData lightTheme() => _buildTheme(Brightness.light);

  static ThemeData _buildTheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final bg = dark ? const Color(0xFF141414) : const Color(0xFFF3F4F6);
    final cardBg = dark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);
    final borderCol = dark ? const Color(0xFF2C2C2C) : const Color(0xFFE5E7EB);
    final textCol = dark ? const Color(0xFFE0E0E0) : const Color(0xFF111827);
    final inputBg = dark ? const Color(0xFF252526) : const Color(0xFFF9FAFB);
    final brand = dark ? const Color(0xFF007ACC) : const Color(0xFF0284C7);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: brand,
        onPrimary: Colors.white,
        secondary: brand,
        onSecondary: Colors.white,
        error: dark ? const Color(0xFFEF4444) : const Color(0xFFDC2626),
        onError: Colors.white,
        surface: cardBg,
        onSurface: textCol,
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: borderCol),
        ),
      ),
      dividerTheme: DividerThemeData(color: borderCol, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: borderCol)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: borderCol)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: brand, width: 1.5)),
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}
```

### Cross-Process Theme Synchronization (`main.dart`)
Every new application wires its root `MaterialApp` to `SharedDeviceDatabase.instance.onDatabaseChanged`:

```dart
class SuiteAppRoot extends StatefulWidget {
  const SuiteAppRoot({super.key});

  @override
  State<SuiteAppRoot> createState() => _SuiteAppRootState();
}

class _SuiteAppRootState extends State<SuiteAppRoot> {
  StreamSubscription<void>? _dbSub;
  String _themeMode = AppTheme.isDark ? 'dark' : 'light';

  @override
  void initState() {
    super.initState();
    _syncTheme();
    _dbSub = SharedDeviceDatabase.instance.onDatabaseChanged.listen((_) => _syncTheme());
  }

  Future<void> _syncTheme() async {
    final mode = await SharedDeviceDatabase.instance.getThemeMode();
    if (mounted && mode != _themeMode) {
      setState(() {
        _themeMode = mode;
        AppTheme.isDark = (mode == 'dark');
      });
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
      debugShowCheckedModeBanner: false,
      themeMode: AppTheme.isDark ? ThemeMode.dark : ThemeMode.light,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: KeyedSubtree(key: ValueKey(_themeMode), child: const MainScreen()),
    );
  }
}
```

---

## 3. Typography & Information Density Rules

1. **System Sans-Serif (`Segoe UI`, `Inter`, `Roboto`, sans-serif)**:
   - Application headers, button labels, settings, tabs, instructional help.
2. **Fixed-Width Monospace (`monospace`, `Consolas`)**:
   - **Mandatory** for technical payloads:
     - IPv4 / IPv6 addresses (`192.168.1.1`, `fe80::1`)
     - MAC addresses (`00:1A:2B:3C:4D:5E`)
     - Timestamps (`yyyy-MM-dd HH:mm:ss.SSS`) and elapsed counters
     - Ports, Packet IDs, Syslog PRI codes, VLAN / TLV tags
     - Hex / ASCII byte dumps and CLI commands

---

## 4. Standard 5-Tier Desktop Screen Architecture

Every screen in this design system conforms to the following structural layout:

```
┌────────────────────────────────────────────────────────────────────────┐
│ 1. TOP CONTROL BAR (Height: 52px)                                      │
│    [Icon + Title + Subtitle] ... [Interface Selector] [Run/Stop] [Menu]│
├────────────────────────────────────────────────────────────────────────┤
│ 2. GLOBAL ALERT / STATUS BANNER (Conditional)                          │
│    e.g., Red Socket Bind Error + "Copy Fix Command" / Green Pulse Timer│
├────────────────────────────────────────────────────────────────────────┤
│ 3. FILTER & TRIAGE TOOLBAR (Height: 44px)                              │
│    [Search Input] [IP/MAC Filter] [Severity/Protocol Chips] [Clear All]│
├────────────────────────────────────────────────────────────────────────┤
│ 4. PRIMARY DATA WORKSPACE (Expanded)                                   │
│    - Virtualized High-Density Data Table (with resizable columns)      │
│    - OR Tabbed Multi-Service Panels (DHCP / DNS / NTP / Benchmarking)  │
├────────────────────────────────────────────────────────────────────────┤
│ 5. COLLAPSIBLE DETAIL INSPECTOR & STATUS BAR (Height: 230-260px)       │
│    - Tabs: [SUMMARY] [PARSED TREE] [HEX/ASCII DUMP] [CLI PREVIEW]      │
│    - Status Bar: [Selected Item, Total Packets, PPS, DB Sync Status]   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 5. Component Implementations & Patterns

### 5.1 Top Control Bar (Tier 1)
- **Left**: App Logo, Title, and Subtitle in bold uppercase.
- **Center/Right**:
  - **Interface Selector**: Dropdown showing detected interfaces (`eth0 (192.168.1.50/24)`) + refresh button (`NetworkInterfaceService`).
  - **Run / Stop Action**: `FilledButton.icon` with dynamic style (`AppTheme.success` when idle, `AppTheme.error` when active).
  - **Demo Presets**: `OutlinedButton.icon` injecting built-in simulation packets (ideal for lab environments without hardware).
  - **Export Menu**: `PopupMenuButton` for CSV, JSON, and Report clipboard copy or file export.

### 5.2 Global Status & Elevation Banner (Tier 2)
When socket binding requires elevated privileges (Linux `CAP_NET_RAW` / `CAP_NET_ADMIN`, `sudo`, macOS root, Windows Npcap), render an actionable error banner with an interactive **"Copy Fix Command"** button:
```dart
if (vm.lastError != null)
  Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
    child: Row(
      children: [
        const Icon(Icons.error_outline, size: 16, color: Color(0xFFEF4444)),
        const SizedBox(width: 10),
        Expanded(
          child: SelectableText(
            vm.lastError!,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white),
          ),
        ),
        if (vm.lastError!.contains('sudo') || vm.lastError!.contains('setcap'))
          OutlinedButton.icon(
            icon: const Icon(Icons.copy, size: 13),
            label: const Text('Copy Fix Command', style: TextStyle(fontSize: 11)),
            onPressed: () => Clipboard.setData(ClipboardData(text: vm.fixCommand)),
          ),
      ],
    ),
  );
```

### 5.3 4-Tab Detail Inspector (Tier 5)
When a record is selected, show a bottom inspector (height: 230–260px) with 4 standard tabs:
1. **SUMMARY**: Structured key-value cards (IP, MAC, OUI Vendor, TTL, Hostname, and a "Rename Device" action).
2. **PARSED TREE**: Protocol headers, TLVs, DNS query/answer lists, DHCP options, or IGMP group records.
3. **HEX / ASCII DUMP**: 16 bytes per line formatted dump (`0000  45 00 00 3c ...  E..<...`).
4. **CLI COMMAND**: Terminal preview card displaying the generated CLI string (`tcpdump`, `tshark`, `iperf3`) with a copy action.

### 5.4 Cross-Suite Device Renaming Modal
Include a `RenameDeviceDialog` triggered by clicking any MAC address or device name:
- Displays hardware card with MAC (monospace), OUI Vendor, and `DeviceCategory` icon.
- Saves friendly name directly to `SharedDeviceDatabase.instance.updateDeviceName(...)`.
- Instantly syncs across all running tools via `onDatabaseChanged`.

---

## 6. Architecture & Quality Standards

### 6.1 MVVM Structure
```
lib/
├── data/
│   ├── repositories/     # SharedDeviceDatabase / SQLite coordination
│   └── services/         # Sockets, parsers, CLI runners, export services
├── domain/models/        # Immutable data models
├── ui/
│   ├── features/         # Screen-specific views and view models
│   ├── theme/            # AppTheme design tokens
│   └── widgets/          # Shared components (RenameDeviceDialog, TopControlBar)
└── main.dart
```

### 6.2 Security & Fuzz Testing Requirement
Network daemons and packet decoders parse untrusted binary inputs from the network. Every project must include:
- Strict bounds checking before byte slicing (`offset + length <= byteData.lengthInBytes`).
- Endianness awareness (`Endian.big` for network byte order).
- A mandatory `test/security_and_fuzz_test.dart` asserting that truncated, oversized, zero-byte, and malformed frames fail gracefully without unhandled exceptions.

---

## 7. Instruction Prompt Template for Future Agents

When directing an AI agent to build a new network diagnostic application, provide this prompt:

```text
Build a Flutter Desktop tool following the Network Suite UI & Design Principles:
1. Theme: Dual Dark & Light mode using dynamic AppTheme tokens (scaffoldBg, surface, surfaceHigh, border, textPrimary, textSecondary, accent, success, warning, error). Never hardcode static colors or Colors.white/black on surfaces. Connect the root MaterialApp to SharedDeviceDatabase.instance.onDatabaseChanged to support live cross-process theme toggles from Net-App-Launcher.
2. Layout: Standard 5-Tier vertical architecture:
   - Tier 1: TopControlBar (App title, Network Interface dropdown with CLI --adapter-ip/--adapter-name pre-selection on startup, Run/Stop button, Demo walkthrough button with auto-clear, Export menu).
   - Tier 2: Conditional status banner with "Copy Fix Command" if root/socket privileges are missing.
   - Tier 3: High-density filter bar with clearable search and protocol chips.
   - Tier 4: Primary data table (virtualized, resizable columns, monospace addresses).
   - Tier 5: 4-Tab bottom inspector ([SUMMARY], [PARSED TREE], [HEX DUMP], [CLI PREVIEW]) + persistent status bar.
3. Integration: Use `network_suite_shared` for SharedDeviceDatabase, OuiLookup, RenameDeviceDialog, and theme preferences.
4. Lifecycle: Intercept WidgetsBindingObserver.didRequestAppExit to cleanly stop background processes/sockets.
5. Testing: Provide unit, widget, and defensive packet fuzzing tests (security_and_fuzz_test.dart).
```
