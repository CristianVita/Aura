import 'package:aura/audio_track.dart';
import 'package:aura/main.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

const tracks = [
  AudioTrack(
    id: '1',
    uri: 'one',
    title: 'Ocean',
    artist: 'Band',
    album: 'Blue',
    durationMs: 1000,
  ),
  AudioTrack(
    id: '2',
    uri: 'two',
    title: 'Mountain',
    artist: 'Ocean',
    album: 'Green',
    durationMs: 1000,
  ),
];

void main() {
  const channel = MethodChannel('com.example.symphonium_clone/audio_library');
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'search fields and favorites constrain the playback queue on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      await store.toggleFavorite('two');
      List<AudioTrack>? played;
      await tester.pumpWidget(
        SavedMusicScope(
          store: store,
          child: MaterialApp(
            home: Scaffold(
              body: SearchScreen(
                tracks: tracks,
                isScanning: false,
                onAddSource: () {},
                onTrackSelected: (queue, index) async {
                  played = queue;
                },
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Ocean');
      await tester.pumpAndSettle();
      expect(find.text('2 rezultate'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Artist'));
      await tester.tap(find.widgetWithText(FilterChip, 'Artist'));
      await tester.pumpAndSettle();
      expect(find.text('1 rezultate'), findsOneWidget);
      expect(find.text('Mountain'), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text('0 rezultate'), findsOneWidget);
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Toate'));
      await tester.tap(find.widgetWithText(FilterChip, 'Toate'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mountain'));
      await tester.pumpAndSettle();
      expect(played?.map((track) => track.uri), ['two']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'confirmed recent searches can be reused and removed without changing music',
    (tester) async {
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      final recent = <String>[];
      await tester.pumpWidget(
        SavedMusicScope(
          store: store,
          child: MaterialApp(
            home: Scaffold(
              body: SearchScreen(
                tracks: tracks,
                recentQueries: recent,
                isScanning: false,
                onAddSource: () {},
                onTrackSelected: (_, index) async {},
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Ocean');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(recent, ['Ocean']);
      await tester.tap(find.byTooltip('Șterge căutarea'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ocean'));
      await tester.pumpAndSettle();
      expect(find.text('2 rezultate'), findsOneWidget);
      await tester.tap(find.byTooltip('Șterge căutarea'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Elimină căutarea Ocean'));
      await tester.pumpAndSettle();
      expect(recent, isEmpty);
      expect(store.data.favorites, isEmpty);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
