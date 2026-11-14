import 'package:material_ui/material_ui.dart';

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
