import 'package:flutter/material.dart';

/// Brand palette. Team and card colours always go with a text label:
/// colour is never the only carrier of information.
abstract final class PistakColors {
  static const background = Color(0xFF0B0F14);
  static const surface = Color(0xFF151B23);
  static const surfaceHigh = Color(0xFF1E2631);
  static const accent = Color(0xFFB8F23A); // lime: primary actions
  static const home = Color(0xFF3B8BFF);
  static const away = Color(0xFFFF8A3D);
  static const yellowCard = Color(0xFFF5C518);
  static const blueCard = Color(0xFF2EA8FF);
  static const redCard = Color(0xFFE5484D);
  static const incident = Color(0xFFB18CFF);
  static const warning = Color(0xFFFFB224);
  static const danger = Color(0xFFE5484D);
  static const textMuted = Color(0xFF9AA4B2);
  static const synced = Color(0xFF3DD68C);
  static const syncing = Color(0xFFFFB224);
  static const offline = Color(0xFF7C8594);
}

ThemeData buildPistakTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: PistakColors.accent,
    brightness: Brightness.dark,
  ).copyWith(
    primary: PistakColors.accent,
    onPrimary: Colors.black,
    surface: PistakColors.surface,
    error: PistakColors.danger,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: PistakColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: PistakColors.background,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: const CardThemeData(
      color: PistakColors.surface,
      margin: EdgeInsets.zero,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 56),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: PistakColors.surfaceHigh,
    ),
  );
}

/// Tabular figures so the clock doesn't "jump" while ticking.
const tabularFigures = [FontFeature.tabularFigures()];
