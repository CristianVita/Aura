import 'package:aura/appearance_app.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/aura_backup.dart';
import 'package:aura/library_groups.dart';
import 'package:aura/library_preferences.dart';
import 'package:aura/personal_albums.dart';
import 'package:aura/playback_memory.dart';
import 'package:aura/rename_references.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:aura/audio_track.dart' as audio;

import 'support/memory_saved_music_storage.dart';

AudioTrack sample(String uri, String title) => AudioTrack(
  id: uri,
  uri: uri,
  title: title,
  artist: 'Artist',
  album: 'Original',
  durationMs: 1000,
);

void main() {
  test(
    'personal albums persist and failed writes preserve current data',
    () async {
      final disk = MemorySavedMusicStorage();
      final store = SavedMusicStore(disk);
      await store.load();
      final id = await store.createAlbum(
        ' Mine ',
        tracks: ['old', 'old', 'missing'],
      );
      expect(store.data.albums.single.name, 'Mine');
      expect(store.data.albums.single.tracks, ['old', 'missing']);
      expect(SavedMusicData.decode(disk.value!).albums.single.id, id);
      disk.failNextWrite = true;
      await expectLater(
        store.updateAlbum(id, name: 'Changed'),
        throwsStateError,
      );
      expect(store.data.albums.single.name, 'Mine');
      await store.updateAlbum(id, tracks: ['old', 'missing', 'new']);
      expect(store.data.albums.single.tracks, ['old', 'missing', 'new']);
      await store.deleteAlbum(id);
      expect(store.data.albums, isEmpty);
      store.dispose();
    },
  );

  test(
    'backup remaps personal album tracks and rename migrates references',
    () {
      final saved = SavedMusicData(
        albums: [
          MusicAlbum(id: 'one', name: 'Mine', tracks: ['old']),
        ],
      );
      final backup = AuraBackup.capture(saved, PlaybackMemoryData(), [
        sample('old', 'Song'),
      ]);
      final decoded = AuraBackup.decode(backup.encode());
      final plan = BackupPlan(decoded, [sample('new', 'Song')]);
      final restored = plan.savedResult(
        SavedMusicData(),
        replace: true,
        settings: false,
      );
      expect(restored.albums.single.tracks, ['new']);
      final migrated = remapRenamedTrack(
        saved: saved,
        memory: PlaybackMemoryData(),
        oldUri: 'old',
        newUri: 'renamed',
      );
      expect(migrated.saved.albums.single.tracks, ['renamed']);
      expect(saved.albums.single.tracks, ['old']);
    },
  );

  test('album artwork context survives player queue metadata', () {
    final track = sample(
      'file:///song',
      'Song',
    ).withArtworkAlbum('aura:custom-album:one');
    final source = AudioSource.uri(
      Uri.parse(track.uri),
      tag: track.toMediaItem(),
    );
    final restored = audio.audioTrackOf(source as IndexedAudioSource)!;
    expect(restored.album, 'Original');
    expect(restored.artworkAlbum, 'aura:custom-album:one');
    expect(
      restored.withDisplayTitle('New').artworkAlbum,
      restored.artworkAlbum,
    );
  });

  testWidgets(
    'album editor retains selections through search and creates a personal album',
    (tester) async {
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      final tracks = [
        sample('file:///first', 'First'),
        sample('file:///second', 'Second'),
      ];
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: store,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<String>(
                    builder: (_) =>
                        PersonalAlbumEditor(store: store, tracks: tracks),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('personal-album-name')),
        'My album',
      );
      await tester.tap(
        find.byKey(const ValueKey('personal-album-track:file:///first')),
      );
      await tester.enterText(
        find.byKey(const ValueKey('personal-album-track-search')),
        'Second',
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('personal-album-track:file:///second')),
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.data.albums.single.name, 'My album');
      expect(store.data.albums.single.tracks, [
        'file:///first',
        'file:///second',
      ]);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'personal albums appear in search and retain independent identity',
    (tester) async {
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      final controller = TextEditingController();
      final album = MusicAlbum(id: 'a', name: 'Same', tracks: []);
      MusicAlbum? opened;
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: store,
          locale: const Locale('en'),
          home: Scaffold(
            body: AlbumSearchGroups(
              groups: {
                'Same': [sample('file:///x', 'X')],
              },
              preferences: const GroupPagePreferences(),
              controller: controller,
              albums: [album],
              tracks: [],
              onOpen: (_) {},
              onOpenAlbum: (a) => opened = a,
              onCreateAlbum: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Same'), findsNWidgets(2));
      expect(find.textContaining('Personal album'), findsOneWidget);
      await tester.tap(find.textContaining('Personal album'));
      expect(opened?.id, 'a');
      await tester.enterText(
        find.byKey(const ValueKey('album-search')),
        'nothing',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No albums found. Try a different search.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      store.dispose();
    },
  );

  testWidgets(
    'editing keeps unavailable track references and delete keeps songs',
    (tester) async {
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      final id = await store.createAlbum(
        'Mine',
        tracks: ['file:///first', 'file:///unavailable'],
      );
      final first = sample('file:///first', 'First');
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: store,
          locale: const Locale('en'),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PersonalAlbumScreen(
                      albumId: id,
                      store: store,
                      tracks: [first],
                      onPlay: (_, _) async {},
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit album'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('personal-album-name')),
        'Updated',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(store.data.albums.single.tracks, [
        'file:///first',
        'file:///unavailable',
      ]);
      expect(find.text('Updated'), findsOneWidget);
      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();
      expect(
        find.text('This removes the album from Aura, not the audio files.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      expect(store.data.albums, isEmpty);
      expect(first.uri, 'file:///first');
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
