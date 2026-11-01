import 'package:aura/audio_track.dart';
import 'package:aura/saved_music.dart';
import 'package:aura/saved_music_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

const tracks = [
  AudioTrack(
    id: '1',
    title: 'Song A',
    artist: 'Artist',
    album: '',
    durationMs: 1000,
    uri: 'a',
  ),
  AudioTrack(
    id: '2',
    title: 'Song B',
    artist: 'Artist',
    album: '',
    durationMs: 1000,
    uri: 'b',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.symphonium_clone/audio_library');
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'track picker keeps unavailable references and selections hidden by search',
    (tester) async {
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      await store.createPlaylist('Saved', tracks: ['missing', 'a']);
      await tester.pumpWidget(
        SavedMusicScope(
          store: store,
          child: MaterialApp(
            home: Scaffold(
              body: SavedMusicScreen(tracks: tracks, onPlay: (_, _) async {}),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Referința ei este păstrată'), findsOneWidget);
      await tester.tap(find.text('Adaugă piese'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Song B');
      await tester.pumpAndSettle();
      expect(find.text('Song A'), findsNothing);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Salvează'));
      await tester.pumpAndSettle();
      expect(store.data.playlists.single.tracks, ['missing', 'a', 'b']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'create, select tracks, play, rename and remove a playlist on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      List<AudioTrack>? played;
      await tester.pumpWidget(
        SavedMusicScope(
          store: store,
          child: MaterialApp(
            home: Scaffold(
              body: SavedMusicScreen(
                tracks: tracks,
                onPlay: (queue, index) async {
                  played = queue;
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Playlist nou'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvează'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), 'Seară');
      await tester.pump();
      await tester.tap(find.text('Salvează'));
      await tester.pumpAndSettle();
      expect(store.data.playlists.single.name, 'Seară');
      await tester.tap(find.text('Adaugă piese'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Song B'));
      await tester.tap(find.text('Salvează'));
      await tester.pumpAndSettle();
      expect(store.data.playlists.single.tracks, ['b']);
      await tester.tap(find.text('Redă toate'));
      await tester.pump();
      expect(played?.single.uri, 'b');
      await tester.tap(find.byTooltip('Opțiuni playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Redenumește'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Nou');
      await tester.pump();
      await tester.tap(find.text('Salvează'));
      await tester.pumpAndSettle();
      expect(store.data.playlists.single.name, 'Nou');
      await tester.tap(find.byTooltip('Elimină din playlist'));
      await tester.pumpAndSettle();
      expect(store.data.playlists.single.tracks, isEmpty);
      await tester.tap(find.byTooltip('Opțiuni playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Șterge playlistul'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Șterge'));
      await tester.pumpAndSettle();
      expect(store.data.playlists, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'favorite action reflects persisted state and failed writes leave heart unchanged',
    (tester) async {
      final storage = MemorySavedMusicStorage();
      final store = SavedMusicStore(storage);
      await store.load();
      await tester.pumpWidget(
        SavedMusicScope(
          store: store,
          child: MaterialApp(
            home: Scaffold(body: SavedTrackActions(track: tracks.first)),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Adaugă la favorite'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Elimină din favorite'), findsOneWidget);
      storage.failNextWrite = true;
      await tester.tap(find.byTooltip('Elimină din favorite'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Elimină din favorite'), findsOneWidget);
      expect(
        find.text('Nu am putut salva modificarea. Încearcă din nou.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
