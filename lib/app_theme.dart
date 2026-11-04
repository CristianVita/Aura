import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'appearance.dart';

Color accentSeed(AppearanceAccent accent) => Color(switch (accent) {
  AppearanceAccent.mint => 0xFF8BE0C0,
  AppearanceAccent.blue => 0xFF91BEFF,
  AppearanceAccent.violet => 0xFFC0A2F5,
  AppearanceAccent.rose => 0xFFF1A7C3,
  AppearanceAccent.amber => 0xFFE7C46B,
  AppearanceAccent.teal => 0xFF75D4D3,
});

String? appearanceFontFamily(AppearanceFont font, TargetPlatform platform) =>
    switch (font) {
      AppearanceFont.system => null,
      AppearanceFont.serif => switch (platform) {
        TargetPlatform.android => 'serif',
        TargetPlatform.windows => 'Georgia',
        TargetPlatform.iOS || TargetPlatform.macOS => 'Times New Roman',
        _ => 'DejaVu Serif',
      },
      AppearanceFont.monospace => switch (platform) {
        TargetPlatform.android => 'monospace',
        TargetPlatform.windows => 'Consolas',
        TargetPlatform.iOS || TargetPlatform.macOS => 'Menlo',
        _ => 'DejaVu Sans Mono',
      },
    };

ThemeMode appearanceThemeMode(AppearanceMode mode) => switch (mode) {
  AppearanceMode.system => ThemeMode.system,
  AppearanceMode.light => ThemeMode.light,
  AppearanceMode.dark || AppearanceMode.oled => ThemeMode.dark,
};

ThemeData buildAuraTheme(
  AppearancePreferences preferences,
  Brightness brightness, {
  TargetPlatform? platform,
}) {
  final dark = brightness == Brightness.dark;
  final oled = dark && preferences.mode == AppearanceMode.oled;
  final background = dark
      ? (oled ? Colors.black : const Color(0xFF0B1014))
      : const Color(0xFFF6F8FA);
  final surface = dark
      ? (oled ? const Color(0xFF101010) : const Color(0xFF141D22))
      : Colors.white;
  final settings = dark
      ? (oled ? const Color(0xFF191919) : const Color(0xFF252E39))
      : const Color(0xFFE9EEF4);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: accentSeed(preferences.accent),
        brightness: brightness,
      ).copyWith(
        surface: surface,
        surfaceContainerLow: surface,
        surfaceContainer: surface,
        surfaceContainerHigh: settings,
        onSurfaceVariant: dark
            ? const Color(0xFFA4B3B8)
            : const Color(0xFF46565E),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: scheme.onSurface,
    ),
    fontFamily: appearanceFontFamily(
      preferences.font,
      platform ?? defaultTargetPlatform,
    ),
  );
}

extension AuraThemeColors on BuildContext {
  Color get auraBackground => Theme.of(this).scaffoldBackgroundColor;
  Color get auraSurface => Theme.of(this).colorScheme.surface;
  Color get auraAccent => Theme.of(this).colorScheme.primary;
  Color get auraMuted => Theme.of(this).colorScheme.onSurfaceVariant;
  Color get auraOnSurface => Theme.of(this).colorScheme.onSurface;
  Color get auraOnAccent => Theme.of(this).colorScheme.onPrimary;
  Color get auraSettingsSurface =>
      Theme.of(this).colorScheme.surfaceContainerHigh;
  Color get auraRating => Theme.of(this).brightness == Brightness.dark
      ? const Color(0xFFBCAF85)
      : const Color(0xFF75601D);
}

class AppearanceTextScaler extends TextScaler {
  const AppearanceTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is AppearanceTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}
