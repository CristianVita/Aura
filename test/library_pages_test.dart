import 'package:aura/appearance.dart';
import 'package:aura/appearance_app.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/aura_backup.dart';
import 'package:aura/library_catalog.dart';
import 'package:aura/library_groups.dart';
import 'package:aura/library_page_settings.dart';
import 'package:aura/library_preferences.dart';
import 'package:aura/playback_memory.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

const song = AudioTrack(
  id: 'one',
  title: 'Synthetic track',
  artist: 'Artist',
  album: 'Album',
  durationMs: 90000,
  uri: 'file:///synthetic.wav',
);

void main() {
  test('legacy preferences, final-index category moves and validation', () {
    final prefs = SavedMusicData.decode(
      '{"version":1,"favorites":[],"playlists":[]}',
    ).libraryPages;
    expect(prefs.visible, LibrarySection.values);
    expect(prefs.move(5, 0).order.first, LibrarySection.sources);
    expect(prefs.move(0, 5).order.last, LibrarySection.albums);
    expect(() => prefs.move(0, 6), throwsRangeError);
    for (final json in [
      {'hidden': LibrarySection.values.map((value) => value.name).toList()},
      {
        'order': ['albums'],
      },
      {'columns': 0},
      {
        'albums': {'columns': 5},
      },
      {
        'artists': {'layout': 'unknown'},
      },
      {
        'artists': {'showSummary': 'yes'},
      },
    ]) {
      expect(
        () => LibraryPagePreferences.fromJson(json),
        throwsFormatException,
      );
    }
    expect(
      () => prefs.order.add(LibrarySection.albums),
      throwsUnsupportedError,
    );
  });

  test('independent page settings survive concurrent ratings, backup opt-in and failed writes', () async {
    final storage = MemorySavedMusicStorage();
    final store = SavedMusicStore(storage);
    await store.load();
    final prefs = LibraryPagePreferences(
      hidden: [LibrarySection.sources],
      albums: const GroupPagePreferences(layout: GroupLayout.grid, columns: 3),
      artists: const GroupPagePreferences(
        sort: GroupSort.trackCount,
        showSummary: false,
      ),
    );
    await Future.wait([
      store.setLibraryPages(prefs),
      store.setRating(song.uri, 4.5),
      store.toggleFavorite(song.uri),
    ]);
    final loaded = SavedMusicData.decode(storage.value!);
    expect(loaded.libraryPages.toJson(), prefs.toJson());
    expect(loaded.ratings[song.uri], 4.5);
    expect(loaded.favorites, {song.uri});
    final plan = BackupPlan(
      AuraBackup.decode(
        AuraBackup.capture(loaded, PlaybackMemoryData(), [song]).encode(),
      ),
      [song],
    );
    expect(
      plan
          .savedResult(SavedMusicData(), replace: false, settings: true)
          .libraryPages
          .toJson(),
      prefs.toJson(),
    );
    expect(
      plan
          .savedResult(SavedMusicData(), replace: true, settings: false)
          .libraryPages
          .toJson(),
      LibraryPagePreferences().toJson(),
    );
    storage.failNextWrite = true;
    await expectLater(
      store.setLibraryPages(LibraryPagePreferences()),
      throwsStateError,
    );
    expect(store.data.libraryPages.toJson(), prefs.toJson());
    expect(
      SavedMusicData.decode(storage.value!).libraryPages.toJson(),
      prefs.toJson(),
    );
    store.dispose();
  });

  test(
    'group sorting is deterministic and never reorders the track queues',
    () {
      final queue = [song, song];
      final groups = {
        'z': [song],
        'alpha': queue,
        'Beta': [song],
      };
      expect(
        orderedLibraryGroups(groups, GroupSort.name).map((entry) => entry.key),
        ['alpha', 'Beta', 'z'],
      );
      expect(
        orderedLibraryGroups(
          groups,
          GroupSort.nameDescending,
        ).map((entry) => entry.key),
        ['z', 'Beta', 'alpha'],
      );
      final sorted = orderedLibraryGroups(groups, GroupSort.trackCount);
      expect(sorted.first.value, same(queue));
      expect(groups.keys, ['z', 'alpha', 'Beta']);
      expect(libraryGridColumns(296, 4, 1.3), 2);
      expect(libraryGridColumns(1000, 3, 1), 6);
    },
  );

  testWidgets(
    'cover grid remains usable with large text and opens the right group',
    (tester) async {
      tester.view.physicalSize = const Size(320, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      await store.setAppearance(const AppearancePreferences(textScale: 1.3));
      String? opened;
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: store,
          locale: const Locale('en'),
          home: Scaffold(
            body: LibraryGroups(
              groups: {
                'Zulu': [song],
                'Alpha': [song, song],
              },
              preferences: const GroupPagePreferences(
                layout: GroupLayout.grid,
                columns: 4,
              ),
              icon: Icons.album,
              onOpen: (name) => opened = name,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 tracks'), findsOneWidget);
      await tester.tap(find.text('Alpha'));
      expect(opened, 'Alpha');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: store,
          locale: const Locale('en'),
          home: const Scaffold(
            body: LibraryGroupSummary(tracks: [song, song], icon: Icons.album),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 min in total'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'category visibility and drag order persist; the last category stays reachable',
    (tester) async {
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      await tester.pumpWidget(
        AuraAppearanceApp(
          locale: const Locale('ro'),
          store: store,
          home: const LibraryPageSettings(page: LibraryPageKind.library),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<ReorderableListView>(find.byType(ReorderableListView))
          .onReorderItem!(5, 0);
      await tester.pumpAndSettle();
      expect(store.data.libraryPages.order.first, LibrarySection.sources);
      await tester.tap(find.byKey(const ValueKey('category-sources')));
      await tester.pumpAndSettle();
      expect(store.data.libraryPages.hidden, {LibrarySection.sources});
      await store.setLibraryPages(
        store.data.libraryPages.copy(
          hidden: LibrarySection.values.where(
            (section) => section != LibrarySection.tracks,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Switch>(find.byKey(const ValueKey('category-tracks')))
            .onChanged,
        isNull,
      );
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'album controls save, report failures and reset only that page on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemorySavedMusicStorage();
      final store = SavedMusicStore(storage);
      await store.load();
      await store.setLibraryPages(
        store.data.libraryPages.copy(
          artists: const GroupPagePreferences(showSummary: false),
        ),
      );
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: store,
          locale: const Locale('en'),
          home: const LibraryPageSettings(page: LibraryPageKind.albums),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('layout-grid')));
      await tester.pumpAndSettle();
      expect(store.data.libraryPages.albums.layout, GroupLayout.grid);
      await tester.tap(find.byKey(const ValueKey('columns-3')));
      await tester.pumpAndSettle();
      tester
          .widget<DropdownButton<GroupSort>>(
            find.byKey(const ValueKey('group-sort')),
          )
          .onChanged!(GroupSort.trackCount);
      await tester.pumpAndSettle();
      storage.failNextWrite = true;
      await tester.tap(find.byKey(const ValueKey('layout-list')));
      await tester.pumpAndSettle();
      expect(store.data.libraryPages.albums.layout, GroupLayout.grid);
      expect(find.textContaining('Could not save the page'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Reset this page'), 100);
      await tester.tap(find.text('Reset this page'));
      await tester.pumpAndSettle();
      expect(
        store.data.libraryPages.albums.toJson(),
        const GroupPagePreferences().toJson(),
      );
      expect(store.data.libraryPages.artists.showSummary, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
