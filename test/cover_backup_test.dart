import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura/album_artwork.dart';
import 'package:aura/appearance_app.dart';
import 'package:aura/aura_backup.dart';
import 'package:aura/backup_files.dart';
import 'package:aura/backup_screen.dart';
import 'package:aura/cover_backup_storage.dart';
import 'package:aura/playback_memory.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

class MemoryMemory implements PlaybackMemoryStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    value = json;
  }
}

class MemoryJournal implements BackupJournal {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    value = json;
  }
}

class FakeCovers implements CoverBackupStorage {
  FakeCovers(this.data);
  Map<String, Uint8List> data;
  bool failAfterWrite = false;
  bool invalid = false;
  @override
  Future<Map<String, Uint8List>> snapshot() async => {
    for (final e in data.entries) e.key: Uint8List.fromList(e.value),
  };
  @override
  Future<void> validateSnapshot(Map<String, Uint8List> images) async {
    validateCoverBackupShape(images);
    if (invalid) throw const FormatException('invalid image');
  }

  @override
  Future<void> replaceSnapshot(Map<String, Uint8List> images) async {
    data = {for (final e in images.entries) e.key: Uint8List.fromList(e.value)};
    if (failAfterWrite) {
      failAfterWrite = false;
      throw StateError('simulated failed write');
    }
  }
}

class FakeFiles implements BackupFiles {
  Uint8List? data;
  @override
  Future<PickedBackup?> pick() async =>
      data == null ? null : PickedBackup('synthetic.json', data!);
  @override
  Future<bool> save(String name, Uint8List bytes) async {
    data = bytes;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final keyA = 'a' * 64;
  final keyB = 'b' * 64;
  final imageA = Uint8List.fromList([1, 2, 3]);
  final imageB = Uint8List.fromList([4, 5, 6]);
  AuraBackup makeBackup({Map<String, Uint8List>? covers}) => AuraBackup.capture(
    SavedMusicData(),
    PlaybackMemoryData(),
    [],
    covers: covers,
  );

  test(
    'version 2 roundtrips cover bytes and legacy version remains readable',
    () {
      final source = makeBackup(covers: {keyA: imageA});
      final decoded = AuraBackup.decode(source.encode());
      expect(decoded.covers![keyA], imageA);
      expect(AuraBackup.decode(makeBackup().encode()).covers, isNull);
      expect(jsonDecode(utf8.decode(source.encode()))['version'], 2);
      expect(
        () => makeBackup(covers: {'../bad': imageA}).encode(),
        throwsFormatException,
      );
    },
  );

  test('merge preserves current covers and replacement replaces them; legacy does not touch covers', () async {
    final saved = SavedMusicStore(MemorySavedMusicStorage());
    final memory = PlaybackMemoryStore(MemoryMemory());
    await saved.load();
    await memory.load();
    final covers = FakeCovers({keyA: imageA});
    final service = BackupRestoreService(
      saved: saved,
      memory: memory,
      journal: MemoryJournal(),
      covers: covers,
    );
    final plan = BackupPlan(
      makeBackup(covers: {keyA: imageB, keyB: imageB}),
      [],
    );
    await service.restore(plan);
    expect(covers.data[keyA], imageA);
    expect(covers.data[keyB], imageB);
    await service.restore(BackupPlan(makeBackup(), []), replace: true);
    expect(covers.data.keys, containsAll([keyA, keyB]));
    await service.restore(
      BackupPlan(makeBackup(covers: {keyB: imageA}), []),
      replace: true,
    );
    expect(covers.data.keys, [keyB]);
    expect(covers.data[keyB], imageA);
    saved.dispose();
    memory.dispose();
  });

  test(
    'invalid cover or partial write never loses previous metadata or artwork',
    () async {
      final saved = SavedMusicStore(MemorySavedMusicStorage());
      final memory = PlaybackMemoryStore(MemoryMemory());
      await saved.load();
      await memory.load();
      await saved.toggleFavorite('kept');
      final covers = FakeCovers({keyA: imageA});
      final journal = MemoryJournal();
      final service = BackupRestoreService(
        saved: saved,
        memory: memory,
        journal: journal,
        covers: covers,
      );
      final plan = BackupPlan(makeBackup(covers: {keyB: imageB}), []);
      covers.invalid = true;
      await expectLater(
        service.restore(plan, replace: true),
        throwsFormatException,
      );
      expect(saved.data.favorites, {'kept'});
      expect(covers.data[keyA], imageA);
      covers.invalid = false;
      covers.failAfterWrite = true;
      await expectLater(service.restore(plan, replace: true), throwsStateError);
      expect(saved.data.favorites, {'kept'});
      expect(covers.data.keys, [keyA]);
      expect(covers.data[keyA], imageA);
      expect(jsonDecode(journal.value!)['state'], 'complete');
      saved.dispose();
      memory.dispose();
    },
  );

  test('startup recovery restores covers together with metadata', () async {
    final saved = MemorySavedMusicStorage();
    final memory = MemoryMemory();
    final covers = FakeCovers({keyB: imageB});
    final journal = MemoryJournal()
      ..value = jsonEncode({
        'version': 1,
        'state': 'pending',
        'savedBefore': SavedMusicData(favorites: ['kept']).encode(),
        'memoryBefore': PlaybackMemoryData().encode(),
        'coversBefore': {keyA: base64Encode(imageA)},
      });
    await BackupRestoreService.recover(
      journal: journal,
      saved: saved,
      memory: memory,
      covers: covers,
    );
    expect(SavedMusicData.decode(saved.value!).favorites, {'kept'});
    expect(covers.data.keys, [keyA]);
    expect(covers.data[keyA], imageA);
    expect(jsonDecode(journal.value!)['state'], 'complete');
  });

  test('real artwork snapshots restore independent copies and reject malformed images', () async {
    final root = await Directory.systemTemp.createTemp(
      'aura-cover-backup-test-',
    );
    final store = AlbumArtworkStore(directory: () async => root);
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    try {
      await store.set('First', png);
      final before = await store.snapshot();
      expect(before.length, 1);
      await store.validateSnapshot(before);
      await store.set('Second', png);
      expect((await store.snapshot()).length, 2);
      await store.replaceSnapshot(before);
      expect((await store.snapshot()).keys, before.keys);
      expect(await store.read('First'), isNotNull);
      expect(await store.read('Second'), isNull);
      await expectLater(
        store.validateSnapshot({keyA: imageA}),
        throwsFormatException,
      );
      expect((await store.snapshot()).keys, before.keys);
      await expectLater(
        store.replaceSnapshot({'../escape': png}),
        throwsFormatException,
      );
    } finally {
      store.dispose();
      await root.delete(recursive: true);
    }
  });

  testWidgets(
    'export includes covers and preview explains merging or replacing',
    (tester) async {
      final saved = SavedMusicStore(MemorySavedMusicStorage());
      final memory = PlaybackMemoryStore(MemoryMemory());
      await saved.load();
      await memory.load();
      final covers = FakeCovers({keyA: imageA});
      final files = FakeFiles();
      final service = BackupRestoreService(
        saved: saved,
        memory: memory,
        journal: MemoryJournal(),
        covers: covers,
      );
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: saved,
          locale: const Locale('en'),
          home: BackupScreen(
            saved: saved,
            memory: memory,
            service: service,
            tracks: const [],
            files: files,
          ),
        ),
      );
      await tester.tap(find.text('Export backup'));
      await tester.pumpAndSettle();
      expect(AuraBackup.decode(files.data!).covers![keyA], imageA);
      await tester.tap(find.text('Choose a backup to restore'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Album covers: 1'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Review and restore'));
      await tester.tap(find.text('Review and restore'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Existing covers are kept'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      saved.dispose();
      memory.dispose();
    },
  );
}
