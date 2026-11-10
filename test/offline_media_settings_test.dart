import 'dart:io';

import 'package:aura/appearance_app.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/offline_media_settings.dart';
import 'package:aura/offline_storage.dart';
import 'package:aura/playback_cache.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

class FakeMediaStore extends OfflineStorage {
  OfflineMediaUsage data = const OfflineMediaUsage(tracks: 2, bytes: 1536);
  @override
  Future<OfflineMediaUsage> mediaUsage() async => data;
  void update() {
    data = const OfflineMediaUsage(tracks: 1, bytes: 512);
    notifyListeners();
  }

  @override
  bool busy(String uri) => false;
  @override
  Future<List<Map<String, Object?>>> cachedTracks() async => [];
  @override
  Future<void> download(AudioTrack track) async =>
      throw StateError('unexpected');
  @override
  Future<bool> hasRecord(String uri) async => false;
  @override
  Future<Uri?> localUri(String uri) async => null;
  @override
  Future<void> remove(String uri) async => throw StateError('unexpected');
}

class FakePlaybackCache extends PlaybackCache {
  FakePlaybackCache() {
    ready = true;
  }
  int clearCalls = 0;
  @override
  bool get available => true;
  @override
  Future<void> load() async {}
  @override
  Future<int> clear() async {
    clearCalls++;
    return 0;
  }
}

void main() {
  testWidgets(
    'shows usage, opens the manager and refreshes after a store change',
    (tester) async {
      final saved = SavedMusicStore(MemorySavedMusicStorage());
      await saved.load();
      final store = FakeMediaStore();
      var opened = false;
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: saved,
          locale: const Locale('en'),
          home: OfflineMediaSettings(
            store: store,
            onOpenDownloads: () => opened = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1.50 KiB'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('offline-media-manage')));
      expect(opened, isTrue);
      store.update();
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('512 B'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
      saved.dispose();
    },
  );
  testWidgets(
    'cache setting is disabled initially and persists the user choice',
    (tester) async {
      final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('aura-cache-setting-'),
      ))!;
      final saved = SavedMusicStore(MemorySavedMusicStorage());
      final store = FakeMediaStore();
      final cache = (await tester.runAsync(() async {
        final instance = PlaybackCache(directory: () async => dir);
        await instance.load();
        return instance;
      }))!;
      try {
        await saved.load();
        await tester.pumpWidget(
          AuraAppearanceApp(
            store: saved,
            locale: const Locale('en'),
            home: OfflineMediaSettings(
              store: store,
              onOpenDownloads: null,
              cache: cache,
            ),
          ),
        );
        final control = find.byKey(const ValueKey('playback-cache-enabled'));
        expect(tester.widget<SwitchListTile>(control).value, false);
        await tester.runAsync(() async {
          tester.widget<SwitchListTile>(control).onChanged!(true);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.widget<SwitchListTile>(control).value, true);
        await tester.runAsync(cache.close);
        final reloaded = PlaybackCache(directory: () async => dir);
        await tester.runAsync(reloaded.load);
        expect(reloaded.enabled, true);
        await tester.runAsync(reloaded.close);
        reloaded.dispose();
        await tester.pumpWidget(const SizedBox());
      } finally {
        await tester.runAsync(cache.close);
        cache.dispose();
        store.dispose();
        saved.dispose();
        await tester.runAsync(() => dir.delete(recursive: true));
      }
    },
  );
  testWidgets('clearing audio cache requires confirmation', (tester) async {
    final saved = SavedMusicStore(MemorySavedMusicStorage());
    await saved.load();
    final store = FakeMediaStore();
    final cache = FakePlaybackCache();
    await tester.pumpWidget(
      AuraAppearanceApp(
        store: saved,
        locale: const Locale('en'),
        home: OfflineMediaSettings(
          store: store,
          onOpenDownloads: null,
          cache: cache,
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('playback-cache-clear')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(cache.clearCalls, 0);
    await tester.tap(find.byKey(const ValueKey('playback-cache-clear')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('playback-cache-clear-confirm')),
    );
    await tester.pumpAndSettle();
    expect(cache.clearCalls, 1);
    await tester.pumpWidget(const SizedBox());
    cache.dispose();
    store.dispose();
    saved.dispose();
  });
}
