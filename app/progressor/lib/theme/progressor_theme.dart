import 'package:flutter/material.dart';

/// Beautiful climbing-inspired dark theme for Progressor.
/// Deep slate + vibrant orange accents.
class ProgressorTheme {
  static const Color primaryOrange = Color(0xFFFF6B35);
  static const Color accentTeal = Color(0xFF00C4B4);
  static const Color darkBg = Color(0xFF121212);
  static const Color surface = Color(0xFF1E1E1E);
  static const Color card = Color(0xFF252525);

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      colorScheme: ColorScheme.dark(
        primary: primaryOrange,
        secondary: accentTeal,
        surface: surface,
        background: darkBg,
        onPrimary: Colors.white,
        tertiary: Colors.amberAccent,
      ),
      scaffoldBackgroundColor: darkBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBg,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        selectedIconTheme: const IconThemeData(color: primaryOrange, size: 28),
        unselectedIconTheme: IconThemeData(color: Colors.white70, size: 24),
        labelType: NavigationRailLabelType.selected,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: surface,
        selectedItemColor: primaryOrange,
        unselectedItemColor: Colors.white54,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: primaryOrange,
        foregroundColor: Colors.white,
      ),
      textTheme: base.textTheme.copyWith(
        headlineLarge: base.textTheme.headlineLarge?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 42,
        ),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
