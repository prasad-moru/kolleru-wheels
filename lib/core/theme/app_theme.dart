import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

abstract final class AppTheme {
  static const _ink = Color(0xFF19332C);
  static const _muted = Color(0xFF64736D);
  static const _line = Color(0x1F19332C);

  // System fonts keep Telugu readable without adding a network font dependency.
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.green).copyWith(
      primary: AppColors.green,
      onPrimary: Colors.white,
      onSurface: _ink,
      surface: Colors.white,
      outlineVariant: _line,
    ),
    scaffoldBackgroundColor: const Color(0xFFF5F8F6),
    dividerColor: _line,
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 2,
      shadowColor: const Color(0x1219332C),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _line),
      ),
      margin: EdgeInsets.zero,
    ),
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        color: _ink,
        fontSize: 32,
        height: 1.15,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.8,
      ),
      headlineSmall: TextStyle(
        color: _ink,
        fontSize: 26,
        height: 1.2,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.45,
      ),
      titleLarge: TextStyle(
        color: _ink,
        fontSize: 20,
        height: 1.3,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
      ),
      titleMedium: TextStyle(
        color: _ink,
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
      ),
      bodyLarge: TextStyle(
        color: _ink,
        fontSize: 16,
        height: 1.45,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.1,
      ),
      bodyMedium: TextStyle(
        color: _muted,
        fontSize: 14,
        height: 1.45,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
      ),
      labelLarge: TextStyle(
        fontSize: 15,
        height: 1.2,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.1,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF5F8F6),
      foregroundColor: _ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: _ink,
        fontSize: 18,
        fontWeight: FontWeight.w500,
        letterSpacing: -0.2,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 60),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        side: const BorderSide(color: _line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.1,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.green, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD9383A)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD9383A), width: 1.4),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFF1F5F2),
      selectedColor: const Color(0xFFE3F2EA),
      side: const BorderSide(color: _line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w400, color: _ink),
    ),
  );
}
