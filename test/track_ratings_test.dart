import 'dart:convert';

import 'package:aura/audio_track.dart';
import 'package:aura/saved_music.dart';
import 'package:aura/saved_music_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

AudioTrack track(String uri, String title) => AudioTrack(
  id: uri,
  uri: uri,
  title: title,
  artist: '',
  album: '',
  durationMs: 1000,
);

void main() {
  test('legacy saved music loads without ratings and preserves existing data after upgrade', () async {
    final storage = MemorySavedMusicStorage()
      ..value =
          '{"version":1,"favorites":["a"],"playlists":[{"id":"p","name":"Saved","tracks":["a","missing"]}]}';
    final store = SavedMusicStore(storage);
    await store.load();
    expect(store.data.ratings, isEmpty);
    await store.setRating('a', 5);
    final restored = SavedMusicStore(storage);
    await restored.load();
    expect(restored.data.ratingOf('a'), 5);
    expect(restored.data.favorites, {'a'});
    expect(restored.data.playlists.single.tracks, ['a', 'missing']);
    store.dispose();
    restored.dispose();
  });

  test('ratings and view preferences survive concurrent favorite and every playlist edit', () async {
    final storage = MemorySavedMusicStorage();
    final store = SavedMusicStore(storage);
    await store.load();
    final id = await store.createPlaylist('Initial');
    await Future.wait([
      store.setRating('a', 4),
      store.setRating('missing', 2),
      store.setRatingView(minimum: 3, order: RatingOrder.highest),
      store.toggleFavorite('a'),
      store.addTrack(id, 'a'),
    ]);
    await store.renamePlaylist(id, 'Renamed');
    await store.setTracks(id, ['b']);
    await store.removeTrack(id, 'b');
    await store.deletePlaylist(id);
    await store.createPlaylist('New');
    final restored = SavedMusicData.decode(storage.value!);
    expect(restored.ratings, {'a': 4, 'missing': 2});
    expect(restored.minimumRating, 3);
    expect(restored.ratingOrder, RatingOrder.highest);
    expect(restored.favorites, {'a'});
    await store.setRating('a', 0);
    expect(store.data.ratings, {'missing': 2});
    store.dispose();
  });

  test('rating write failures and invalid values preserve the last successful state', () async {
    final storage = MemorySavedMusicStorage();
    final store = SavedMusicStore(storage);
    await store.load();
    await store.setRating('a', 3);
    storage.failNextWrite = true;
    await expectLater(store.setRating('a', 5), throwsStateError);
    expect(store.data.ratingOf('a'), 3);
    for (final value in [-1, 6]) {
      await expectLater(store.setRating('a', value), throwsArgumentError);
    }
    await expectLater(store.setRatingView(minimum: 6), throwsArgumentError);
    await store.setRating('b', 1);
    expect(SavedMusicData.decode(storage.value!).ratings, {'a': 3, 'b': 1});
    store.dispose();
  });

  test(
    'corrupt ratings cannot silently overwrite saved favorites and playlists',
    () async {
      for (final invalid in [0, 6, 2.5, '5']) {
        final storage = MemorySavedMusicStorage()
          ..value = jsonEncode({
            'version': 1,
            'favorites': ['a'],
            'playlists': [],
            'ratings': {'a': invalid},
          });
        final original = storage.value;
        final store = SavedMusicStore(storage);
        await store.load();
        expect(store.loadFailed, isTrue);
        await expectLater(store.setRating('a', 3), throwsStateError);
        expect(storage.value, original);
        store.dispose();
      }
    },
  );

  test('rating filters and sorting keep input order intact and unrated tracks last', () {
    final tracks = [
      track('u', 'Unrated'),
      track('a', 'Zeta'),
      track('b', 'Beta'),
      track('c', 'Alpha'),
    ];
    final data = SavedMusicData(ratings: {'a': 2, 'b': 5, 'c': 5});
    List<String> uris(SavedMusicData data) =>
        data.ratedTracks(tracks).map((t) => t.uri).toList();
    expect(uris(data), ['u', 'a', 'b', 'c']);
    expect(uris(data.copy(ratingOrder: RatingOrder.highest)), [
      'c',
      'b',
      'a',
      'u',
    ]);
    expect(uris(data.copy(ratingOrder: RatingOrder.lowest)), [
      'a',
      'c',
      'b',
      'u',
    ]);
    expect(uris(data.copy(minimumRating: 4)), ['b', 'c']);
    expect(data.copy(minimumRating: 5).ratedTracks([tracks.first]), isEmpty);
    expect(tracks.map((t) => t.uri), ['u', 'a', 'b', 'c']);
  });

  testWidgets(
    'five stars change, clear and preserve rating on failed writes on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final storage = MemorySavedMusicStorage();
      final store = SavedMusicStore(storage);
      await store.load();
      await tester.pumpWidget(
        SavedMusicScope(
          store: store,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () =>
                      showTrackRating(context, track('a', 'Test song')),
                  child: const Text('Rate'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Rate'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star_border_rounded), findsNWidgets(5));
      await tester.tap(find.byTooltip('Acordă 4 stele'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
      expect(store.data.ratingOf('a'), 4);
      storage.failNextWrite = true;
      await tester.tap(find.byTooltip('Acordă 5 stele'));
      await tester.pumpAndSettle();
      expect(store.data.ratingOf('a'), 4);
      await tester.tap(find.byTooltip('Șterge ratingul'));
      await tester.pumpAndSettle();
      expect(store.data.ratingOf('a'), 0);
      expect(find.byIcon(Icons.star_border_rounded), findsNWidgets(5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'rating controls persist minimum and sorting and allow resetting an empty view',
    (tester) async {
      final storage = MemorySavedMusicStorage();
      final store = SavedMusicStore(storage);
      await store.load();
      await tester.pumpWidget(
        SavedMusicScope(
          store: store,
          child: const MaterialApp(
            home: Scaffold(body: Column(children: [RatingViewControls()])),
          ),
        ),
      );
      await tester.tap(find.text('Toate ratingurile'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is CheckedPopupMenuItem<int> && widget.value == 4,
        ),
      );
      await tester.pumpAndSettle();
      expect(store.data.minimumRating, 4);
      await tester.tap(find.byTooltip('Sortează după rating'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is CheckedPopupMenuItem<RatingOrder> &&
              widget.value == RatingOrder.highest,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        SavedMusicData.decode(storage.value!).ratingOrder,
        RatingOrder.highest,
      );
      await tester.tap(find.text('Rating ≥ 4'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byWidgetPredicate(
          (widget) => widget is CheckedPopupMenuItem<int> && widget.value == 0,
        ),
      );
      await tester.pumpAndSettle();
      expect(store.data.minimumRating, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
