enum AppearanceMode { system, light, dark, oled }

enum AppearanceAccent { mint, blue, violet, rose, amber, teal }

enum AppearanceFont { system, serif, monospace }

class AppearancePreferences {
  const AppearancePreferences({
    this.mode = AppearanceMode.dark,
    this.accent = AppearanceAccent.mint,
    this.font = AppearanceFont.system,
    this.textScale = 1,
  });
  final AppearanceMode mode;
  final AppearanceAccent accent;
  final AppearanceFont font;
  final double textScale;

  @override
  bool operator ==(Object other) =>
      other is AppearancePreferences &&
      other.mode == mode &&
      other.accent == accent &&
      other.font == font &&
      other.textScale == textScale;
  @override
  int get hashCode => Object.hash(mode, accent, font, textScale);

  AppearancePreferences copy({
    AppearanceMode? mode,
    AppearanceAccent? accent,
    AppearanceFont? font,
    double? textScale,
  }) => AppearancePreferences(
    mode: mode ?? this.mode,
    accent: accent ?? this.accent,
    font: font ?? this.font,
    textScale: textScale ?? this.textScale,
  );

  Map<String, Object> toJson() => {
    'mode': mode.name,
    'accent': accent.name,
    'font': font.name,
    'textScale': textScale,
  };

  factory AppearancePreferences.fromJson(Map<String, dynamic> json) {
    try {
      final scale = json['textScale'] ?? 1;
      if (scale is! num || !scale.isFinite || scale < .85 || scale > 1.3) {
        throw const FormatException('Invalid text scale');
      }
      return AppearancePreferences(
        mode: AppearanceMode.values.byName(json['mode'] as String? ?? 'dark'),
        accent: AppearanceAccent.values.byName(
          json['accent'] as String? ?? 'mint',
        ),
        font: AppearanceFont.values.byName(json['font'] as String? ?? 'system'),
        textScale: scale.toDouble(),
      );
    } catch (_) {
      throw const FormatException('Invalid appearance preferences');
    }
  }
}
