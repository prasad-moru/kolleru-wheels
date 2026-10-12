import 'package:flutter/material.dart';

/// Delta Logistics palettes shared by directory cards and exported cards.
class DriverCardStyle {
  const DriverCardStyle(
    this.id,
    this.label,
    this.accent,
    this.surface,
    this.ink,
    this.tag,
  );

  final String id;
  final String label;
  final Color accent;
  final Color surface;
  final Color ink;
  final Color tag;

  Color get action => id == 'gold_elite' ? const Color(0xFF92400E) : accent;

  static const styles = [
    DriverCardStyle(
      'classic_delta',
      'Delta Emerald',
      Color(0xFF0F5132),
      Colors.white,
      Color(0xFF19332C),
      Color(0xFFE3F2EA),
    ),
    DriverCardStyle(
      'aqua_marine',
      'Aqua Marine',
      Color(0xFF0E7490),
      Color(0xFFF1F5F9),
      Color(0xFF0F172A),
      Color(0xFFCFFAFE),
    ),
    DriverCardStyle(
      'gold_elite',
      'Royal Gold',
      Color(0xFFD97706),
      Color(0xFF1E293B),
      Colors.white,
      Color(0xFFFEF3C7),
    ),
  ];

  static DriverCardStyle resolve(String id) => styles.firstWhere(
    (style) => style.id == id,
    orElse: () => styles.first,
  );

  ThemeData theme(ThemeData base) => base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    cardTheme: base.cardTheme.copyWith(
      color: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: accent),
      ),
    ),
  );
}
