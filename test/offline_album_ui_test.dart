import 'dart:async';

import 'package:aura/appearance_app.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/offline_album_ui.dart';
import 'package:aura/offline_storage.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

AudioTrack song(String id, {bool local = false}) => AudioTrack(
  id: id,
  title: id,
  artist: 'Synthetic',
  album: 'Synthetic',
  durationMs: 1,
  uri: local ? 'file:///synthetic/$id.mp3' : 'aura://navidrome/synthetic/$id',
);

class FakeOffline extends OfflineStorage {
  final calls = <String>[];
  Completer<void>? pending;
  String? fail;
  @override
  bool busy(String uri) => false;
  @override
  Future<bool> hasRecord(String uri) async => false;
  @override
  Future<Uri?> localUri(String uri) async => null;
  @override
  Future<List<Map<String, Object?>>> cachedTracks() async => [];
  @override
  Future<void> remove(String uri) async => throw StateError('must not remove');
  @override
  Future<void> download(AudioTrack track) async {
    calls.add(track.id);
    if (pending != null) await pending!.future;
    if (track.id == fail) throw StateError('synthetic failure');
  }
}

void main() {
  testWidgets(
    'album download needs consent, deduplicates, ignores local tracks and reports failures',
    (tester) async {
      final saved = SavedMusicStore(MemorySavedMusicStorage());
      await saved.load();
      final offline = FakeOffline()..fail = 'two';
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: saved,
          locale: const Locale('en'),
          home: Scaffold(
            body: OfflineAlbumAction(
              store: offline,
              tracks: [
                song('one'),
                song('one'),
                song('two'),
                song('local', local: true),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('offline-album-action')));
      await tester.pumpAndSettle();
      expect(offline.calls, isEmpty);
      expect(find.text('Server tracks: 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('offline-album-confirm')));
      await tester.pumpAndSettle();
      expect(offline.calls, ['one', 'two']);
      expect(find.text('Processed: 2 / 2'), findsOneWidget);
      expect(find.text('Failed: 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      offline.dispose();
      saved.dispose();
    },
  );
  testWidgets('cancel stops before next track and keeps completed downloads', (
    tester,
  ) async {
    final saved = SavedMusicStore(MemorySavedMusicStorage());
    await saved.load();
    final offline = FakeOffline()..pending = Completer<void>();
    await tester.pumpWidget(
      AuraAppearanceApp(
        store: saved,
        locale: const Locale('en'),
        home: Scaffold(
          body: OfflineAlbumAction(
            store: offline,
            tracks: [song('one'), song('two')],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('offline-album-action')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('offline-album-confirm')));
    await tester.pump();
    expect(offline.calls, ['one']);
    await tester.tap(find.byKey(const ValueKey('offline-album-cancel')));
    await tester.pump();
    expect(find.text('Stopping after the current track…'), findsOneWidget);
    offline.pending!.complete();
    await tester.pumpAndSettle();
    expect(offline.calls, ['one']);
    expect(find.text('Processed: 1 / 2'), findsOneWidget);
    expect(
      find.text('Stopped. Completed downloads remain available offline.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    offline.dispose();
    saved.dispose();
  });
  testWidgets('no album action is offered for only local tracks', (
    tester,
  ) async {
    final saved = SavedMusicStore(MemorySavedMusicStorage());
    await saved.load();
    final offline = FakeOffline();
    await tester.pumpWidget(
      AuraAppearanceApp(
        store: saved,
        home: Scaffold(
          body: OfflineAlbumAction(
            store: offline,
            tracks: [song('local', local: true)],
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('offline-album-action')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    offline.dispose();
    saved.dispose();
  });
  testWidgets(
    'playlist download excludes local tracks and needs confirmation',
    (tester) async {
      final saved = SavedMusicStore(MemorySavedMusicStorage());
      await saved.load();
      final offline = FakeOffline();
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: saved,
          locale: const Locale('en'),
          home: Scaffold(
            body: OfflineAlbumAction(
              store: offline,
              group: OfflineDownloadGroup.playlist,
              tracks: [song('one'), song('one'), song('local', local: true)],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('offline-playlist-action')));
      await tester.pumpAndSettle();
      expect(find.text('Download playlist'), findsWidgets);
      expect(find.text('Server tracks: 1'), findsOneWidget);
      expect(offline.calls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('offline-album-confirm')));
      await tester.pumpAndSettle();
      expect(offline.calls, ['one']);
      await tester.pumpWidget(const SizedBox());
      offline.dispose();
      saved.dispose();
    },
  );
  for (final entry in {
    OfflineDownloadGroup.artist: 'Download artist',
    OfflineDownloadGroup.genre: 'Download genre',
  }.entries) {
    testWidgets('group download requires confirmation: ${entry.value}', (
      tester,
    ) async {
      final saved = SavedMusicStore(MemorySavedMusicStorage());
      await saved.load();
      final offline = FakeOffline();
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: saved,
          locale: const Locale('en'),
          home: Scaffold(
            body: OfflineAlbumAction(
              store: offline,
              group: entry.key,
              tracks: [song('one'), song('one'), song('local', local: true)],
            ),
          ),
        ),
      );
      await tester.tap(
        find.byKey(ValueKey('offline-${entry.key.name}-action')),
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsWidgets);
      expect(find.text('Server tracks: 1'), findsOneWidget);
      expect(offline.calls, isEmpty);
      await tester.tap(find.byKey(const ValueKey('offline-album-confirm')));
      await tester.pumpAndSettle();
      expect(offline.calls, ['one']);
      await tester.pumpWidget(const SizedBox());
      offline.dispose();
      saved.dispose();
    });
  }
}
