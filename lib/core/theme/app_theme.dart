import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

abstract final class AppTheme {
  // System fonts provide Telugu fallback without first-launch downloads.
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.green).copyWith(
      primary: AppColors.green,
      onPrimary: Colors.white,
      onSurface: AppColors.charcoal,
    ),
    scaffoldBackgroundColor: AppColors.background,
    textTheme: const TextTheme(
      headlineSmall: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
      titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      bodyLarge: TextStyle(fontSize: 18, height: 1.5),
      bodyMedium: TextStyle(fontSize: 16, height: 1.5),
      labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ).apply(bodyColor: AppColors.charcoal, displayColor: AppColors.charcoal),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 60),
        padding: const EdgeInsets.all(16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 56),
        padding: const EdgeInsets.all(16),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
      contentPadding: EdgeInsets.all(16),
    ),
  );
}
