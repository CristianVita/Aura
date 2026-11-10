import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura/appearance_app.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/aura_backup.dart';
import 'package:aura/diagnostic_journal.dart';
import 'package:aura/generated_files.dart';
import 'package:aura/generated_files_screen.dart';
import 'package:aura/playback_memory.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

class MemoryPlayback implements PlaybackMemoryStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    value = json;
  }
}

class FakeGenerated extends GeneratedFileStore {
  final rows = <GeneratedEntry>[];
  final bytes = <String, Uint8List>{};
  @override
  Future<List<GeneratedEntry>> list() async => List.of(rows);
  @override
  Future<GeneratedEntry> create(GeneratedKind kind, Uint8List value) async {
    final e = GeneratedEntry(
      name: 'synthetic-${rows.length}',
      kind: kind,
      size: value.length,
      modified: DateTime.utc(2026),
    );
    rows.add(e);
    bytes[e.name] = value;
    return e;
  }

  @override
  Future<Uint8List> read(String name) async => bytes[name]!;
  @override
  Future<void> remove(String name) async {
    rows.removeWhere((entry) => entry.name == name);
    bytes.remove(name);
  }
}

const song = AudioTrack(
  id: '1',
  title: 'Synthetic title',
  artist: 'Test artist',
  album: 'Test album',
  durationMs: 1,
  uri: 'aura://navidrome/test/1',
);

void main() {
  test('generated files isolate unrelated files, reject traversal and remove only selected entry', () async {
    final root = await Directory.systemTemp.createTemp('aura-generated-');
    try {
      final store = GeneratedFileStore(directory: () async => root);
      final other = File('${root.path}${Platform.pathSeparator}user.json');
      await other.writeAsString('untouched');
      final a = await store.create(
        GeneratedKind.backup,
        Uint8List.fromList([1, 2, 3]),
      );
      final b = await store.create(
        GeneratedKind.playlist,
        encodeGeneratedJson({
          'format': 'aura.playlist',
          'name': 'Synthetic playlist',
        }),
      );
      expect((await store.list()).length, 2);
      expect(
        (await store.list())
            .singleWhere((e) => e.kind == GeneratedKind.playlist)
            .displayName,
        'Synthetic playlist',
      );
      expect(await store.read(a.name), [1, 2, 3]);
      await expectLater(store.remove('../user.json'), throwsFormatException);
      await store.remove(a.name);
      expect(await other.readAsString(), 'untouched');
      expect((await store.list()).single.name, b.name);
      expect(root.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
    } finally {
      await root.delete(recursive: true);
    }
  });
  test('playlist references omit credentials, queries, external URLs and fragments', () {
    expect(
      safePlaylistReference('aura://navidrome/account/song'),
      'aura://navidrome/account/song',
    );
    expect(
      safePlaylistReference('file:///private/song.mp3'),
      'file:///private/song.mp3',
    );
    expect(
      safePlaylistReference('https://user:pass@example.test/song?token=secret'),
      isNull,
    );
    expect(safePlaylistReference('content://test/song?token=secret'), isNull);
    expect(safePlaylistReference('aura://navidrome/a/b#secret'), isNull);
  });
  test('diagnostic journal is opt-in, bounded, and contains only fixed error codes', () {
    final log = DiagnosticJournal();
    log.record(DiagnosticEventCode.playbackMemoryError);
    expect(log.events, isEmpty);
    log.start();
    for (var i = 0; i < 205; i++) {
      log.record(DiagnosticEventCode.playbackSettingsError);
    }
    expect(log.events.length, 200);
    expect(log.events.first.toJson().keys, containsAll(['time', 'code']));
    log.stop();
    log.record(DiagnosticEventCode.playbackMemoryError);
    expect(log.events.length, 200);
    log.start();
    expect(log.events, isEmpty);
    log.dispose();
  });
  testWidgets(
    'explicit confirmation creates restorable backup and playlist JSON',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = SavedMusicStore(MemorySavedMusicStorage());
      final memory = PlaybackMemoryStore(MemoryPlayback());
      await saved.load();
      await memory.load();
      await saved.createPlaylist('Synthetic playlist', tracks: [song.uri]);
      final store = FakeGenerated();
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: saved,
          locale: const Locale('en'),
          home: GeneratedFilesScreen(
            saved: saved,
            memory: memory,
            tracks: const [song],
            covers: null,
            onBackup: null,
            store: store,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(store.rows, isEmpty);
      await tester.tap(find.byKey(const ValueKey('generate-backup')));
      await tester.pumpAndSettle();
      expect(store.rows, isEmpty);
      await tester.tap(find.text('Create').last);
      await tester.pumpAndSettle();
      expect(store.rows.single.kind, GeneratedKind.backup);
      expect(
        AuraBackup.decode(store.bytes[store.rows.single.name]!)
            .saved
            .playlists
            .single
            .name,
        'Synthetic playlist',
      );
      await tester.tap(find.byKey(const ValueKey('generate-playlist')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic playlist').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create').last);
      await tester.pumpAndSettle();
      final row = store.rows.singleWhere(
        (e) => e.kind == GeneratedKind.playlist,
      );
      final json = jsonDecode(utf8.decode(store.bytes[row.name]!));
      expect(json['name'], 'Synthetic playlist');
      expect(json['tracks'][0]['uri'], song.uri);
      await tester.tap(
        find.byKey(const ValueKey('toggle-diagnostic-recording')),
      );
      diagnosticJournal.record(DiagnosticEventCode.playbackMemoryError);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('generate-diagnostic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create').last);
      await tester.pumpAndSettle();
      final report = store.rows.singleWhere(
        (e) => e.kind == GeneratedKind.diagnostic,
      );
      final reportText = utf8.decode(store.bytes[report.name]!);
      final reportJson = jsonDecode(reportText);
      expect(reportJson['events'][0]['code'], 'playbackMemoryError');
      expect(reportText, isNot(contains('Synthetic title')));
      expect(reportText, isNot(contains('navidrome')));
      diagnosticJournal.stop();
      await tester.pumpWidget(const SizedBox());
      saved.dispose();
      memory.dispose();
    },
  );
}
