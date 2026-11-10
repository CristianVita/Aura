import 'dart:async';

import 'package:aura/appearance_app.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/offline_store.dart';
import 'package:aura/offline_ui.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

const track = AudioTrack(
  id: 'song',
  title: 'Synthetic track',
  artist: 'Artist',
  album: '',
  durationMs: 10,
  uri: 'aura://navidrome/server/song',
);

class FakeDownloads extends OfflineStore {
  FakeDownloads() : super(open: (_) => throw StateError('unexpected'));
  bool exists = false, valid = true;
  int removes = 0;
  @override
  bool busy(String uri) => false;
  @override
  Future<bool> hasRecord(String uri) async => exists;
  @override
  Future<Uri?> localUri(String uri) async =>
      exists && valid ? Uri.file('/synthetic.mp3') : null;
  @override
  Future<void> download(AudioTrack track) async {
    exists = true;
    notifyListeners();
  }

  @override
  Future<void> remove(String uri) async {
    removes++;
    exists = false;
    notifyListeners();
  }

  @override
  Future<List<Map<String, Object?>>> cachedTracks() async => exists
      ? [
          {
            'id': track.id,
            'uri': track.uri,
            'title': track.title,
            'artist': track.artist,
            'album': track.album,
            'durationMs': track.durationMs,
          },
        ]
      : [];
}

void main() {
  testWidgets('offline seek bar follows playback and seeks within duration', (
    tester,
  ) async {
    final positions = StreamController<Duration>.broadcast();
    final durations = StreamController<Duration?>.broadcast();
    Duration? seek;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OfflineSeekBar(
            positions: positions.stream,
            durations: durations.stream,
            initialPosition: const Duration(seconds: 10),
            fallbackDuration: const Duration(seconds: 100),
            onSeek: (value) => seek = value,
          ),
        ),
      ),
    );
    expect(find.text('0:10'), findsOneWidget);
    expect(find.text('1:40'), findsOneWidget);
    positions.add(const Duration(seconds: 25));
    await tester.pump();
    durations.add(const Duration(seconds: 120));
    await tester.pump();
    await tester.pump();
    expect(find.text('0:25'), findsOneWidget);
    expect(find.text('2:00'), findsOneWidget);
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('offline-seek-slider')),
    );
    expect(slider.value, 25000);
    slider.onChanged!(60000);
    expect(seek, const Duration(seconds: 60));
    durations.add(Duration.zero);
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('offline-seek-slider')))
          .onChanged,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    await positions.close();
    await durations.close();
  });
  testWidgets('offline control downloads and protects a queued track', (
    tester,
  ) async {
    final saved = SavedMusicStore(MemorySavedMusicStorage());
    await saved.load();
    final offline = FakeDownloads();
    await tester.pumpWidget(
      AuraAppearanceApp(
        store: saved,
        home: Scaffold(
          body: OfflineTrackAction(
            store: offline,
            track: track,
            canRemove: (_) => false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('offline-track-action')));
    await tester.pumpAndSettle();
    expect(offline.exists, isFalse);
    await tester.tap(find.byKey(const ValueKey('offline-download-confirm')));
    await tester.pumpAndSettle();
    expect(offline.exists, isTrue);
    await tester.tap(find.byKey(const ValueKey('offline-track-action')));
    await tester.pumpAndSettle();
    expect(offline.exists, isTrue);
    expect(offline.removes, 0);
    await tester.pumpWidget(const SizedBox());
    offline.dispose();
    saved.dispose();
  });
  testWidgets(
    'offline list plays the verified local file and never streams missing files',
    (tester) async {
      final saved = SavedMusicStore(MemorySavedMusicStorage());
      await saved.load();
      final offline = FakeDownloads()..exists = true;
      Uri? played;
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: saved,
          home: OfflineDownloadsScreen(
            store: offline,
            canRemove: (_) => true,
            onPlay: (_, uri) async => played = uri,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic track'));
      await tester.pumpAndSettle();
      expect(played, Uri.file('/synthetic.mp3'));
      played = null;
      offline.valid = false;
      await tester.tap(find.text('Synthetic track'));
      await tester.pumpAndSettle();
      expect(played, isNull);
      await tester.pumpWidget(const SizedBox());
      offline.dispose();
      saved.dispose();
    },
  );
}
