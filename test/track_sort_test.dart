import 'package:aura/appearance_app.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/aura_backup.dart';
import 'package:aura/library_catalog.dart';
import 'package:aura/library_preferences.dart';
import 'package:aura/playback_memory.dart';
import 'package:aura/saved_music.dart';
import 'package:aura/track_sort_control.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'support/memory_saved_music_storage.dart';

AudioTrack song(
  String id,
  String title, {
  String artist = '',
  String album = '',
  String genre = '',
  int year = 0,
  int duration = 0,
}) => AudioTrack(
  id: id,
  uri: 'file:///$id',
  title: title,
  artist: artist,
  album: album,
  genre: genre,
  year: year,
  durationMs: duration,
);

void main() {
  final a = song(
    'a',
    'Zulu',
    artist: 'Beta',
    album: 'Y',
    genre: 'Rock',
    year: 2000,
    duration: 4000,
  );
  final b = song(
    'b',
    'alpha',
    artist: 'alpha',
    album: 'X',
    genre: 'Jazz',
    year: 1990,
    duration: 1000,
  );
  final c = song('c', 'Beta', year: 0, duration: 0);
  test('each metadata sort is stable, unknown values last and input stays unchanged', () {
    final input = [a, c, b];
    List<String> ids(TrackSort sort) =>
        sortLibraryTracks(input, sort).map((t) => t.id).toList();
    expect(ids(TrackSort.original), ['a', 'c', 'b']);
    expect(ids(TrackSort.title), ['b', 'c', 'a']);
    for (final sort in [
      TrackSort.year,
      TrackSort.artist,
      TrackSort.album,
      TrackSort.genre,
      TrackSort.duration,
    ]) {
      expect(ids(sort), ['b', 'a', 'c']);
    }
    expect(input.map((track) => track.id), ['a', 'c', 'b']);
    expect(
      sortLibraryTracks([
        a,
        song('d', 'Zulu'),
      ], TrackSort.title).map((t) => t.id),
      ['a', 'd'],
    );
    expect(
      sortLibraryTracks(
        [a, b],
        TrackSort.title,
        primary: (left, right) => left.id == 'a' ? -1 : 1,
      ).first.id,
      'a',
    );
  });

  test('year and title overrides survive queue metadata and sorting preference backs up', () {
    final selected = a.withDisplayTitle('AAA');
    final source = AudioSource.uri(
      Uri.parse(selected.uri),
      tag: selected.toMediaItem(),
    );
    final restored = audioTrackOf(source as IndexedAudioSource)!;
    expect(restored.year, 2000);
    expect(sortLibraryTracks([b, restored], TrackSort.title).first.id, 'a');
    expect(AudioTrack.fromMap({'year': 0}).year, 0);
    expect(AudioTrack.fromMap({'year': '2001'}).year, 2001);
    expect(AudioTrack.fromMap({'year': -42}).year, 0);
    expect(AudioTrack.fromMap({}).year, 0);
    final prefs = LibraryPagePreferences(trackSort: TrackSort.year);
    final saved = SavedMusicData(libraryPages: prefs);
    expect(
      SavedMusicData.decode(saved.encode()).libraryPages.trackSort,
      TrackSort.year,
    );
    expect(LibraryPagePreferences.fromJson({}).trackSort, TrackSort.original);
    final plan = BackupPlan(
      AuraBackup.capture(saved, PlaybackMemoryData(), []),
      [],
    );
    expect(
      plan
          .savedResult(SavedMusicData(), replace: false, settings: true)
          .libraryPages
          .trackSort,
      TrackSort.year,
    );
    expect(
      plan
          .savedResult(SavedMusicData(), replace: false, settings: false)
          .libraryPages
          .trackSort,
      TrackSort.original,
    );
  });

  testWidgets(
    'sort picker persists selection and failed save retains previous sort',
    (tester) async {
      final disk = MemorySavedMusicStorage();
      final store = SavedMusicStore(disk);
      await store.load();
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: store,
          locale: const Locale('en'),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: TrackSortControl(store: store),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('track-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Year (metadata)').last);
      await tester.pumpAndSettle();
      expect(store.data.libraryPages.trackSort, TrackSort.year);
      expect(find.textContaining('Rescan local files'), findsOneWidget);
      expect(
        SavedMusicData.decode(disk.value!).libraryPages.trackSort,
        TrackSort.year,
      );
      disk.failNextWrite = true;
      await tester.tap(find.byKey(const ValueKey('track-sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Artist').last);
      await tester.pumpAndSettle();
      expect(store.data.libraryPages.trackSort, TrackSort.year);
      expect(find.text('Year (metadata)'), findsOneWidget);
      expect(find.text('Artist'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
