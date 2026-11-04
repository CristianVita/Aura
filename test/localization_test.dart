import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:aura/app_language.dart';
import 'package:aura/app_strings.dart';
import 'package:aura/appearance_app.dart';
import 'package:aura/audio_runtime.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/aura_backup.dart';
import 'package:aura/day_greeting.dart';
import 'package:aura/l10n/app_localizations.dart';
import 'package:aura/language_settings_screen.dart';
import 'package:aura/main.dart';
import 'package:aura/playback_memory.dart';
import 'package:aura/saved_music.dart';
import 'package:aura/saved_music_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

const track = AudioTrack(
  id: 'test',
  title: 'Titre original',
  artist: '日本語のアーティスト',
  album: 'Album original',
  durationMs: 90000,
  uri: 'file:///test.mp3',
);

void main() {
  tearDown(() => AppText.useLocale(const Locale('ro')));

  test(
    'all twenty bundled catalogs have complete keys and matching parameters',
    () {
      final files = Directory('lib/l10n')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.arb'))
          .toList();
      expect(files.length, 20);
      final reference = jsonDecode(
        File('lib/l10n/app_en.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      final keys = reference.keys.where((key) => !key.startsWith('@')).toSet();
      expect(keys.length, greaterThan(400));
      final locales = <String>{};
      for (final file in files) {
        final catalog =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final language = catalog['@@locale'] as String;
        locales.add(language);
        expect(
          catalog.keys.where((key) => !key.startsWith('@')).toSet(),
          keys,
          reason: language,
        );
        for (final key in keys) {
          expect(catalog[key], isA<String>(), reason: '$language/$key');
          expect(
            (catalog[key] as String).trim(),
            isNotEmpty,
            reason: '$language/$key',
          );
          expect(
            catalog[key],
            isNot(contains('9876543')),
            reason: '$language/$key',
          );
          expect(
            catalog['@$key']?['placeholders']?.keys.toSet() ?? <String>{},
            reference['@$key']?['placeholders']?.keys.toSet() ?? <String>{},
            reason: '$language/$key',
          );
        }
        final strings = lookupAppLocalizations(Locale(language));
        expect(strings.languageHelp, isNotEmpty);
        if (language != 'en') {
          expect(
            strings.languageHelp,
            isNot(reference['languageHelp']),
            reason: language,
          );
        }
        for (final count in [0, 1, 2, 5, 21]) {
          expect(strings.groupTracks(count), isNotEmpty);
        }
      }
      expect(
        locales,
        AppLanguage.values
            .where((value) => value != AppLanguage.system)
            .map((value) => value.name)
            .toSet(),
      );
      expect(
        AppLocalizations.supportedLocales
            .map((locale) => locale.languageCode)
            .toSet(),
        locales,
      );
    },
  );

  test(
    'locale resolution respects language, device priority and English fallback',
    () {
      expect(
        resolveAuraLocale(AppLanguage.system, [const Locale('fr', 'CA')]),
        const Locale('fr'),
      );
      expect(
        resolveAuraLocale(AppLanguage.system, [
          const Locale('xx'),
          const Locale('ar', 'EG'),
        ]),
        const Locale('ar'),
      );
      expect(
        resolveAuraLocale(AppLanguage.system, [const Locale('xx')]),
        const Locale('en'),
      );
      expect(
        resolveAuraLocale(AppLanguage.ro, [const Locale('en')]),
        const Locale('ro'),
      );
      expect(
        SavedMusicData.decode('{"version":1,"favorites":[],"playlists":[]}')
            .language,
        AppLanguage.ro,
      );
    },
  );

  test('language persists with ratings and restores only with backup settings opt-in', () async {
    final storage = MemorySavedMusicStorage();
    final store = SavedMusicStore(storage);
    await store.load();
    await Future.wait([
      store.setLanguage(AppLanguage.ja),
      store.setRating(track.uri, 4.5),
    ]);
    expect(SavedMusicData.decode(storage.value!).language, AppLanguage.ja);
    expect(store.data.ratingOf(track.uri), 4.5);
    final plan = BackupPlan(
      AuraBackup.decode(
        AuraBackup.capture(store.data, PlaybackMemoryData(), [track]).encode(),
      ),
      [track],
    );
    final current = SavedMusicData(language: AppLanguage.de);
    expect(
      plan.savedResult(current, replace: false, settings: false).language,
      AppLanguage.de,
    );
    expect(
      plan.savedResult(current, replace: false, settings: true).language,
      AppLanguage.ja,
    );
    storage.failNextWrite = true;
    await expectLater(store.setLanguage(AppLanguage.en), throwsStateError);
    expect(store.data.language, AppLanguage.ja);
    expect(SavedMusicData.decode(storage.value!).language, AppLanguage.ja);
    store.dispose();
  });

  test(
    'reviewed plural forms and media labels preserve the underlying actions',
    () {
      final ru = lookupAppLocalizations(const Locale('ru'));
      expect(ru.groupTracks(1), '1 трек');
      expect(ru.groupTracks(2), '2 трека');
      expect(ru.groupTracks(5), '5 треков');
      final ar = lookupAppLocalizations(const Locale('ar'));
      expect(ar.groupTracks(2), 'مقطعان');
      for (final language in AppLanguage.values.where(
        (value) => value != AppLanguage.system,
      )) {
        AppText.useLocale(Locale(language.name));
        for (final control in [
          MediaControl.play,
          MediaControl.pause,
          MediaControl.stop,
          MediaControl.skipToNext,
          MediaControl.skipToPrevious,
          MediaControl.rewind,
          MediaControl.fastForward,
        ]) {
          final localized = localizedMediaControl(control);
          expect(localized.action, control.action);
          expect(localized.androidIcon, control.androidIcon);
          expect(localized.label, isNotEmpty);
        }
        expect(track.displayTitle, track.title);
        expect(track.displayArtist, track.artist);
        expect(track.toMediaItem().extras!['originalTitle'], track.title);
      }
    },
  );

  testWidgets(
    'language updates a pushed route immediately and failed writes keep selection',
    (tester) async {
      final storage = MemorySavedMusicStorage();
      final store = SavedMusicStore(storage);
      await store.load();
      await store.setLanguage(AppLanguage.ro);
      await store.setRating(track.uri, 4.5);
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: store,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LanguageSettingsScreen(),
                  ),
                ),
                child: Text(context.appStrings.languageTitle),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Limba aplicației'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-en')));
      await tester.pumpAndSettle();
      expect(find.byType(LanguageSettingsScreen), findsOneWidget);
      expect(find.text('App language'), findsOneWidget);
      storage.failNextWrite = true;
      await tester.tap(find.byKey(const ValueKey('language-ro')));
      await tester.pumpAndSettle();
      expect(store.data.language, AppLanguage.en);
      expect(
        find.text(
          'Could not save the language. Your previous choice was kept.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('language-ar')),
        200,
      );
      await tester.tap(find.byKey(const ValueKey('language-ar')));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(LanguageSettingsScreen));
      expect(Directionality.of(context), TextDirection.rtl);
      expect(Localizations.localeOf(context), const Locale('ar'));
      expect(store.data.ratingOf(track.uri), 4.5);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text(AppText.current.languageTitle), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'system locale changes and all twenty catalogs render on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      tester.platformDispatcher.localesTestValue = [const Locale('fr', 'CA')];
      await tester.pumpWidget(
        AuraAppearanceApp(store: store, home: const _LocaleProbe()),
      );
      await tester.pumpAndSettle();
      expect(
        Localizations.localeOf(tester.element(find.byType(_LocaleProbe))),
        const Locale('fr'),
      );
      tester.platformDispatcher.localesTestValue = [const Locale('ar', 'EG')];
      await tester.pumpAndSettle();
      expect(
        Directionality.of(tester.element(find.byType(_LocaleProbe))),
        TextDirection.rtl,
      );
      for (final language in AppLanguage.values.where(
        (value) => value != AppLanguage.system,
      )) {
        await store.setLanguage(language);
        await tester.pumpAndSettle();
        final context = tester.element(find.byType(_LocaleProbe));
        expect(Localizations.localeOf(context).languageCode, language.name);
        expect(context.dateTime(DateTime(2026, 11, 4, 13, 5)), isNotEmpty);
        expect(find.byType(DayGreeting), findsOneWidget);
        expect(tester.takeException(), isNull, reason: language.name);
      }
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'Arabic star dragging rates from the right and search selections survive language changes',
    (tester) async {
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      await store.setLanguage(AppLanguage.ar);
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: store,
          home: const Scaffold(
            body: Center(child: TrackRating(uri: 'test')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final area = find.byKey(const ValueKey('rating-drag-area'));
      final rect = tester.getRect(area);
      final gesture = await tester.startGesture(
        Offset(rect.right - 2, rect.center.dy),
      );
      await gesture.moveTo(
        Offset(rect.right - rect.width * .49, rect.center.dy),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.data.ratingOf('test'), 2.5);
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: store,
          home: Scaffold(
            body: SearchScreen(
              tracks: const [track],
              isScanning: false,
              onAddSource: () {},
              onTrackSelected: (_, index) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'original');
      await tester.pumpAndSettle();
      final first = find.byType(FilterChip).at(1);
      await tester.tap(first);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip).at(1)).selected,
        isFalse,
      );
      await store.setLanguage(AppLanguage.en);
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilterChip>(find.byType(FilterChip).at(1)).selected,
        isFalse,
      );
      expect(find.text('Titre original'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}

class _LocaleProbe extends StatelessWidget {
  const _LocaleProbe();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      children: [
        Text(context.appStrings.languageHelp),
        const DayGreeting(),
        const TrackRating(uri: 'probe'),
      ],
    ),
  );
}
