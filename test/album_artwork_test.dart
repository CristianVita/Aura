import 'dart:convert';
import 'dart:io';

import 'package:aura/album_artwork.dart';
import 'package:aura/album_cover_ui.dart';
import 'package:aura/appearance_app.dart';
import 'package:aura/saved_music.dart';
import 'package:aura/track_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  late Directory root;
  late AlbumArtworkStore store;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('aura-album-cover-test-');
    store = AlbumArtworkStore(directory: () async => root);
  });
  tearDown(() async {
    store.dispose();
    await root.delete(recursive: true);
  });

  test(
    'album cover persists independently and invalid input does not replace it',
    () async {
      await store.set('Album A', png);
      final original = await store.read('Album A');
      expect(original, isNotNull);
      expect(await store.read('Album B'), isNull);
      await expectLater(
        store.set('Album A', Uint8List.fromList([1, 2, 3])),
        throwsA(anything),
      );
      final reopened = AlbumArtworkStore(directory: () async => root);
      expect(await reopened.read('Album A'), original);
      await reopened.remove('Album A');
      expect(await reopened.read('Album A'), isNull);
      reopened.dispose();
    },
  );

  test('interrupted replacement recovers the previous cover', () async {
    await store.set('../album', png);
    final first =
        await root.list().where((e) => e.path.endsWith('.png')).single as File;
    final originalPath = first.path;
    final original = await first.readAsBytes();
    await first.rename('$originalPath.previous');
    final reopened = AlbumArtworkStore(directory: () async => root);
    expect(await reopened.read('../album'), original);
    expect(await File(originalPath).exists(), isTrue);
    reopened.dispose();
  });

  testWidgets('album cover menu offers selection and removal', (tester) async {
    final saved = SavedMusicStore(MemorySavedMusicStorage());
    await saved.load();
    await tester.pumpWidget(
      AuraAppearanceApp(
        store: saved,
        locale: const Locale('en'),
        home: const Scaffold(body: AlbumCoverButton(album: 'Album')),
      ),
    );
    await tester.tap(find.byType(AlbumCoverButton));
    await tester.pumpAndSettle();
    expect(find.text('Choose album cover'), findsOneWidget);
    expect(find.text('Remove chosen cover'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    saved.dispose();
  });

  testWidgets(
    'chosen cover updates views and removal restores embedded artwork',
    (tester) async {
      const channel = MethodChannel(
        'com.example.symphonium_clone/audio_library',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      await tester.pumpWidget(
        MaterialApp(
          home: Row(
            children: [
              TrackArtwork(
                uri: 'content://media/a',
                cacheKey: 'cover-a',
                album: 'Album',
                albumStore: store,
                size: 40,
              ),
              TrackArtwork(
                uri: 'content://media/b',
                cacheKey: 'cover-b',
                album: 'Album',
                albumStore: store,
                size: 40,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      await tester.runAsync(() async {
        await store.set('Album', png);
        await store.read('Album');
      });
      await tester.pump();
      await tester.pumpAndSettle();
      final futures = tester
          .widgetList<FutureBuilder<Uint8List?>>(
            find.byType(FutureBuilder<Uint8List?>),
          )
          .map((item) => item.future!)
          .toList();
      await tester.runAsync(() => Future.wait(futures));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(2));
      await tester.runAsync(() async {
        await store.remove('Album');
        await store.read('Album');
      });
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      await tester.pumpWidget(const SizedBox());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
  testWidgets('Android offers the system photos picker', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final saved = SavedMusicStore(MemorySavedMusicStorage());
    await saved.load();
    await tester.pumpWidget(
      AuraAppearanceApp(
        store: saved,
        locale: const Locale('en'),
        home: const Scaffold(body: AlbumCoverButton(album: 'Album')),
      ),
    );
    await tester.tap(find.byType(AlbumCoverButton));
    await tester.pumpAndSettle();
    expect(find.text('Choose from Photos'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    saved.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
