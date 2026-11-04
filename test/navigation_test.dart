import 'package:aura/appearance_app.dart';
import 'package:aura/aura_backup.dart';
import 'package:aura/navigation_preferences.dart';
import 'package:aura/navigation_settings_screen.dart';
import 'package:aura/navigation_ui.dart';
import 'package:aura/playback_memory.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

void main() {
  test('legacy defaults, stable tab identities and final-index reordering', () {
    final prefs = SavedMusicData.decode(
      '{"version":1,"favorites":[],"playlists":[]}',
    ).navigation;
    expect(prefs.visible, AppTab.values);
    expect(prefs.start, AppTab.home);
    expect(prefs.move(0, 3).order, [
      AppTab.library,
      AppTab.search,
      AppTab.settings,
      AppTab.home,
    ]);
    expect(prefs.move(3, 0).order.first, AppTab.settings);
    final hidden = prefs.copy(hidden: [AppTab.home, AppTab.search]);
    expect(hidden.start, AppTab.library);
    expect(hidden.resolve(AppTab.search), AppTab.library);
    expect(hidden.visible, [AppTab.library, AppTab.settings]);
    expect(() => prefs.move(0, 4), throwsRangeError);
  });

  test(
    'invalid navigation cannot remove required tabs or select hidden starts',
    () {
      for (final json in [
        {
          'order': ['home', 'home', 'search', 'settings'],
        },
        {
          'hidden': ['settings'],
        },
        {
          'hidden': ['library'],
        },
        {
          'hidden': ['home'],
          'start': 'home',
        },
        {'labels': 'unknown'},
        {'libraryLanding': 7},
      ]) {
        expect(
          () => NavigationPreferences.fromJson(json),
          throwsFormatException,
        );
      }
    },
  );

  test('navigation survives concurrent music edits, backup opt-in and failed writes', () async {
    final storage = MemorySavedMusicStorage();
    final store = SavedMusicStore(storage);
    await store.load();
    final prefs = NavigationPreferences(
      start: AppTab.library,
      libraryLanding: LibraryLanding.albums,
      labels: NavigationLabels.always,
    ).move(3, 0);
    await Future.wait([
      store.setNavigation(prefs),
      store.setRating('song', 4.5),
      store.toggleFavorite('song'),
    ]);
    final loaded = SavedMusicData.decode(storage.value!);
    expect(loaded.navigation.toJson(), prefs.toJson());
    expect(loaded.ratings['song'], 4.5);
    expect(loaded.favorites, {'song'});
    final backup = AuraBackup.decode(
      AuraBackup.capture(loaded, PlaybackMemoryData(), []).encode(),
    );
    final plan = BackupPlan(backup, []);
    expect(
      plan
          .savedResult(SavedMusicData(), replace: false, settings: true)
          .navigation
          .toJson(),
      prefs.toJson(),
    );
    expect(
      plan
          .savedResult(SavedMusicData(), replace: true, settings: false)
          .navigation
          .toJson(),
      NavigationPreferences().toJson(),
    );
    storage.failNextWrite = true;
    await expectLater(
      store.setNavigation(NavigationPreferences()),
      throwsStateError,
    );
    expect(store.data.navigation.toJson(), prefs.toJson());
    expect(
      SavedMusicData.decode(storage.value!).navigation.toJson(),
      prefs.toJson(),
    );
    store.dispose();
  });

  testWidgets(
    'reordered mobile and desktop destinations retain stable callbacks',
    (tester) async {
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      AppTab? selected;
      final prefs = NavigationPreferences(hidden: [AppTab.search]).move(3, 0);
      for (final rail in [false, true]) {
        await tester.pumpWidget(
          AuraAppearanceApp(
            store: store,
            locale: const Locale('en'),
            home: Scaffold(
              body: AuraNavigation(
                preferences: prefs,
                selected: AppTab.library,
                rail: rail,
                onSelected: (tab) => selected = tab,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (rail) {
          final bar = tester.widget<NavigationRail>(
            find.byType(NavigationRail),
          );
          expect(bar.selectedIndex, 2);
          expect(bar.extended, isTrue);
          bar.onDestinationSelected!(0);
        } else {
          final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
          expect(bar.selectedIndex, 2);
          expect(bar.destinations.length, 3);
          expect(
            bar.labelBehavior,
            NavigationDestinationLabelBehavior.alwaysHide,
          );
          bar.onDestinationSelected!(0);
        }
        expect(selected, AppTab.settings);
      }
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'settings persist visibility, landing and start; report failed saves and reset',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemorySavedMusicStorage();
      final store = SavedMusicStore(storage);
      await store.load();
      await tester.pumpWidget(
        AuraAppearanceApp(
          locale: const Locale('ro'),
          store: store,
          home: const NavigationSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('visible-home')));
      await tester.pumpAndSettle();
      expect(store.data.navigation.start, AppTab.library);
      expect(store.data.navigation.hidden, {AppTab.home});
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(3, 0);
      await tester.pumpAndSettle();
      expect(store.data.navigation.order.first, AppTab.settings);
      await tester.ensureVisible(
        find.byKey(const ValueKey('navigation-start')),
      );
      tester
          .widget<DropdownButton<AppTab>>(
            find.byKey(const ValueKey('navigation-start')),
          )
          .onChanged!(AppTab.settings);
      await tester.pumpAndSettle();
      expect(store.data.navigation.start, AppTab.settings);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('navigation-landing')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      tester
          .widget<DropdownButton<LibraryLanding>>(
            find.byKey(const ValueKey('navigation-landing')),
          )
          .onChanged!(LibraryLanding.favorites);
      await tester.pumpAndSettle();
      expect(store.data.navigation.libraryLanding, LibraryLanding.favorites);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('labels-always')),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      storage.failNextWrite = true;
      await tester.tap(find.byKey(const ValueKey('labels-always')));
      await tester.pumpAndSettle();
      expect(store.data.navigation.labels, NavigationLabels.adaptive);
      expect(
        find.textContaining('Nu am putut salva navigarea'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Restabilește navigarea implicită'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Restabilește navigarea implicită'));
      await tester.pumpAndSettle();
      expect(store.data.navigation.toJson(), NavigationPreferences().toJson());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
