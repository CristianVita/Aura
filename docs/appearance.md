# Theme, font and colors

Open **Setări → Interfață → Temă, font și culori**. Preferences are saved after each selection; a failed write leaves the previous appearance active. Theme changes preserve the current route, queue and player state. Reset returns to dark/mint/system font/100%.

- Theme: follow device brightness, light, dark, or OLED black. The initial default stays dark for older installations.
- Accent: mint, blue, violet, rose, gold or teal. Material color schemes generate corresponding readable foregrounds for light and dark surfaces.
- Font: system, serif or monospace. Fonts use installed platform families, with no network downloads. Android selects `serif`/`monospace`; Windows selects Georgia/Consolas. Platform glyph appearance can vary.
- Text size: 85–130%, multiplied by the system's existing text scaler. Nonlinear accessibility scaling is preserved rather than flattened into a single scale factor.

Main screens, settings, music/rating controls, search, queue, filters and Navidrome pages use semantic theme colors rather than fixed dark-background colors. The home source card grows with its content; library grid rows adapt to text scaling. Appearance settings are validated and serialized in saved music, so existing backup merge/replacement rules apply: import appearance only when restoring settings is explicitly selected. Older backups without this field retain the original defaults.

New appearance text uses ARB resources in `lib/l10n/app_ro.arb` and `app_en.arb`. `flutter pub get` generates localizations using `l10n.yaml`. The app remains Romanian by default while older screens are migrated gradually; an English resource/test does not imply the entire existing app has been translated.

Tests cover concurrent rating/appearance saves, failed writes, invalid fields, legacy data, backup settings opt-in, palette contrast, platform fonts, system brightness, nonlinear text scaling, route preservation and English/Romanian appearance controls on a narrow screen.

The optimized Android build was checked on a OnePlus 8T: light/violet/serif remained selected after restarting Aura, OLED was verified, and the default appearance was restored afterward. The home screen still showed 153 tracks and the existing rating/queue. Android ARM64 and Windows x64 release builds succeeded; native visual checks were performed on Android.
