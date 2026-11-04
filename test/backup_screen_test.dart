import 'dart:typed_data';

import 'package:aura/audio_track.dart';
import 'package:aura/aura_backup.dart';
import 'package:aura/backup_files.dart';
import 'package:aura/backup_screen.dart';
import 'package:aura/playback_memory.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'aura_backup_test.dart' show BackupMemoryStorage, MemoryJournal;
import 'support/memory_saved_music_storage.dart';

class _Files implements BackupFiles {
  PickedBackup? next;
  Uint8List? exported;
  String? name;
  bool saved = false;
  @override
  Future<PickedBackup?> pick() async => next;
  @override
  Future<bool> save(String name, Uint8List bytes) async {
    this.name = name;
    exported = bytes;
    return saved;
  }
}

const _track = AudioTrack(
  id: 'same',
  uri: 'same',
  title: 'Sample',
  artist: 'Band',
  album: 'Album',
  durationMs: 10000,
);

void main() {
  late SavedMusicStore saved;
  late PlaybackMemoryStore memory;
  late _Files files;
  late BackupRestoreService service;
  var restores = 0;
  setUp(() {
    files = _Files();
    restores = 0;
  });
  tearDown(() {
    saved.dispose();
    memory.dispose();
  });
  Future<void> open(WidgetTester tester) async {
    saved = SavedMusicStore(
      MemorySavedMusicStorage()
        ..value = SavedMusicData(
          favorites: ['kept'],
          ratings: {'same': 5},
        ).encode(),
    );
    memory = PlaybackMemoryStore(BackupMemoryStorage());
    await saved.load();
    await memory.load();
    service = BackupRestoreService(
      saved: saved,
      memory: memory,
      journal: MemoryJournal(),
      beforeRestore: () async {
        restores++;
      },
    );

    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: BackupScreen(
          saved: saved,
          memory: memory,
          service: service,
          tracks: const [_track],
          files: files,
        ),
      ),
    );
  }

  PickedBackup fixture() => PickedBackup(
    'Sample.json',
    AuraBackup.capture(
      SavedMusicData(
        favorites: ['same'],
        ratings: {'same': 2},
        starSize: RatingStarSize.large,
      ),
      PlaybackMemoryData(),
      const [_track],
    ).encode(),
  );

  testWidgets('export and picker cancellation do not alter data', (
    tester,
  ) async {
    await open(tester);
    final previous = saved.data.encode();
    await tester.tap(find.text('Exportă backup'));
    await tester.pumpAndSettle();
    expect(files.name, startsWith('Aura-backup-'));
    expect(AuraBackup.decode(files.exported!).saved.ratings['same'], 5);
    expect(find.text('Backupul a fost salvat.'), findsNothing);
    await tester.tap(find.text('Alege un backup pentru restaurare'));
    await tester.pumpAndSettle();
    expect(find.text('Verifică și restaurează'), findsNothing);
    expect(saved.data.encode(), previous);
    expect(restores, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'preview and confirmation cancel are read-only; default restore merges without settings',
    (tester) async {
      files.next = fixture();
      await open(tester);
      final previous = saved.data.encode();
      await tester.tap(find.text('Alege un backup pentru restaurare'));
      await tester.pumpAndSettle();
      expect(find.text('Sample.json'), findsOneWidget);
      expect(saved.data.encode(), previous);
      expect(restores, 0);
      await tester.scrollUntilVisible(
        find.text('Verifică și restaurează'),
        150,
      );
      await tester.ensureVisible(find.text('Verifică și restaurează'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verifică și restaurează'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Renunță'));
      await tester.pumpAndSettle();
      expect(saved.data.encode(), previous);
      await tester.ensureVisible(find.text('Verifică și restaurează'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verifică și restaurează'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restaurează'));
      await tester.pumpAndSettle();
      expect(restores, 1);
      expect(saved.data.favorites, {'kept', 'same'});
      expect(saved.data.ratings['same'], 5);
      expect(saved.data.starSize, RatingStarSize.medium);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replacement and settings require opt-in; invalid files preserve data and valid preview',
    (tester) async {
      files.next = fixture();
      await open(tester);
      await tester.tap(find.text('Alege un backup pentru restaurare'));
      await tester.pumpAndSettle();
      files.next = PickedBackup('Broken.json', Uint8List.fromList([1, 2, 3]));
      await tester.tap(find.text('Alege un backup pentru restaurare'));
      await tester.pumpAndSettle();
      expect(find.text('Sample.json'), findsOneWidget);
      expect(saved.data.ratings['same'], 5);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Înlocuiește datele actuale'),
        150,
      );
      await tester.ensureVisible(find.text('Înlocuiește datele actuale'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Înlocuiește datele actuale'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Restabilește și setările'),
        150,
      );
      await tester.ensureVisible(find.text('Restabilește și setările'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restabilește și setările'));
      await tester.scrollUntilVisible(
        find.text('Verifică și restaurează'),
        150,
      );
      await tester.ensureVisible(find.text('Verifică și restaurează'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verifică și restaurează'));
      await tester.pumpAndSettle();
      expect(find.text('Înlocuiește și restaurează'), findsOneWidget);
      expect(saved.data.ratings['same'], 5);
      await tester.tap(find.text('Înlocuiește și restaurează'));
      await tester.pumpAndSettle();
      expect(saved.data.favorites, {'same'});
      expect(saved.data.ratings['same'], 2);
      expect(saved.data.starSize, RatingStarSize.large);
      expect(tester.takeException(), isNull);
    },
  );
}
