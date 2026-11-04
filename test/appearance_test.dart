import 'dart:convert';

import 'package:aura/appearance.dart';
import 'package:aura/app_theme.dart';
import 'package:aura/aura_backup.dart';
import 'package:aura/playback_memory.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

void main() {
  test('legacy data retain the default dark mint appearance', () {
    final saved = SavedMusicData.decode(
      '{"version":1,"favorites":[],"playlists":[]}',
    );
    expect(saved.appearance, const AppearancePreferences());
    expect(saved.appearance.mode, AppearanceMode.dark);
  });

  test('appearance survives concurrent music edits and reloading without losing ratings', () async {
    final storage = MemorySavedMusicStorage();
    final saved = SavedMusicStore(storage);
    await saved.load();
    const preferences = AppearancePreferences(
      mode: AppearanceMode.oled,
      accent: AppearanceAccent.violet,
      font: AppearanceFont.serif,
      textScale: 1.2,
    );
    await Future.wait([
      saved.setAppearance(preferences),
      saved.setRating('song', 4.5),
      saved.toggleFavorite('song'),
    ]);
    final loaded = SavedMusicData.decode(storage.value!);
    expect(loaded.appearance, preferences);
    expect(loaded.ratings['song'], 4.5);
    expect(loaded.favorites, {'song'});
    storage.failNextWrite = true;
    await expectLater(
      saved.setAppearance(
        const AppearancePreferences(mode: AppearanceMode.light),
      ),
      throwsStateError,
    );
    expect(saved.data.appearance, preferences);
    expect(SavedMusicData.decode(storage.value!).appearance, preferences);
    saved.dispose();
  });

  test('invalid appearance fields cannot overwrite saved state', () async {
    final store = SavedMusicStore(MemorySavedMusicStorage());
    await store.load();
    for (final invalid in [0.0, .8, 1.4, double.nan, double.infinity]) {
      await expectLater(
        store.setAppearance(AppearancePreferences(textScale: invalid)),
        throwsFormatException,
      );
    }
    for (final entry in [
      {'mode': 'unknown'},
      {'accent': 7},
      {'font': 'downloaded'},
      {'textScale': 'large'},
    ]) {
      expect(
        () => AppearancePreferences.fromJson(entry),
        throwsFormatException,
      );
    }
    expect(store.data.appearance, const AppearancePreferences());
    store.dispose();
  });

  test('backup settings opt-in controls appearance restoration and old backups remain readable', () {
    final source = SavedMusicData(
      appearance: const AppearancePreferences(
        mode: AppearanceMode.light,
        accent: AppearanceAccent.blue,
        font: AppearanceFont.monospace,
        textScale: 1.3,
      ),
    );
    final encoded = AuraBackup.capture(
      source,
      PlaybackMemoryData(),
      [],
    ).encode();
    final plan = BackupPlan(AuraBackup.decode(encoded), []);
    final current = SavedMusicData();
    expect(
      plan.savedResult(current, replace: true, settings: false).appearance,
      current.appearance,
    );
    expect(
      plan.savedResult(current, replace: false, settings: true).appearance,
      source.appearance,
    );
    final old = jsonDecode(source.encode()) as Map<String, dynamic>;
    old.remove('appearance');
    expect(
      SavedMusicData.decode(jsonEncode(old)).appearance,
      const AppearancePreferences(),
    );
  });

  test('all palettes provide readable body and secondary text in both brightnesses', () {
    double contrast(Color a, Color b) {
      final first = a.computeLuminance(), second = b.computeLuminance();
      return (first > second ? first + .05 : second + .05) /
          (first > second ? second + .05 : first + .05);
    }

    for (final accent in AppearanceAccent.values) {
      for (final brightness in Brightness.values) {
        final theme = buildAuraTheme(
          AppearancePreferences(accent: accent),
          brightness,
        );
        final colors = theme.colorScheme;
        expect(
          contrast(colors.onSurface, theme.scaffoldBackgroundColor),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(colors.onSurfaceVariant, colors.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrast(colors.onPrimary, colors.primary),
          greaterThanOrEqualTo(4.5),
        );
      }
    }
    final oled = buildAuraTheme(
      const AppearancePreferences(mode: AppearanceMode.oled),
      Brightness.dark,
    );
    expect(oled.scaffoldBackgroundColor, Colors.black);
  });

  test('font families select actual platform families and text scaling preserves nonlinear system scaling', () {
    expect(
      appearanceFontFamily(AppearanceFont.system, TargetPlatform.android),
      isNull,
    );
    expect(
      appearanceFontFamily(AppearanceFont.serif, TargetPlatform.windows),
      'Georgia',
    );
    expect(
      appearanceFontFamily(AppearanceFont.monospace, TargetPlatform.android),
      'monospace',
    );
    const scaler = AppearanceTextScaler(_NonlinearScaler(), 1.3);
    expect(scaler.scale(12), closeTo(21.84, .001));
    expect(scaler.scale(24), closeTo(37.44, .001));
    expect(appearanceThemeMode(AppearanceMode.system), ThemeMode.system);
  });
}

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize * (fontSize < 20 ? 1.4 : 1.2);
  @override
  double get textScaleFactor => 1.4;
}
