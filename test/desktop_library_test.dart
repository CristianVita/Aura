import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura/desktop_library.dart';
import 'package:aura/saved_music.dart';
import 'package:aura/playback_memory.dart';
import 'package:crypto/crypto.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late Directory music;
  late Directory storage;
  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('aura-library-test-');
    music = await Directory(p.join(temporary.path, 'music')).create();
    storage = Directory(p.join(temporary.path, 'state'));
    final bytes = ByteData(44 + 16000);
    void text(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    text(0, 'RIFF');
    bytes.setUint32(4, 16036, Endian.little);
    text(8, 'WAVE');
    text(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, 8000, Endian.little);
    bytes.setUint32(28, 16000, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    text(36, 'data');
    bytes.setUint32(40, 16000, Endian.little);
    await File(p.join(music.path, 'Sample.wav'))
        .writeAsBytes(bytes.buffer.asUint8List());
  });
  tearDown(() async => temporary.delete(recursive: true));

  test('desktop scanner reads year tags without modifying the file', () async {
    final file = File(p.join(music.path, 'Sample.wav'));
    final original = await file.readAsBytes();
    final info = ByteData(30);
    void text(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        info.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    text(0, 'LIST');
    info.setUint32(4, 22, Endian.little);
    text(8, 'INFO');
    text(12, 'ICRD');
    info.setUint32(16, 10, Endian.little);
    text(20, '2001-01-01');
    final updated = Uint8List.fromList([
      ...original,
      ...info.buffer.asUint8List(),
    ]);
    ByteData.sublistView(updated)
        .setUint32(4, updated.length - 8, Endian.little);
    await file.writeAsBytes(updated);
    final rows = scanDesktopFolders([music.path]);
    expect(rows.single['year'], 2001);
    expect(await file.readAsBytes(), updated);
  });

  test('rename preserves audio bytes, references, queue and rejects existing names', () async {
    final library = DesktopLibrary(
      storageDirectory: storage,
      chooseDirectory: () async => music.path,
    );
    await library.invoke('chooseAudioFolder', null);
    final original = File(p.join(music.path, 'Sample.wav'));
    final oldUri = original.absolute.uri.toString();
    final content = await original.readAsBytes();
    final saved = SavedMusicData(
      favorites: [oldUri],
      ratings: {oldUri: 4.5},
      playlists: [
        MusicPlaylist(id: 'p', name: 'P', tracks: [oldUri]),
      ],
    );
    final memory = PlaybackMemoryData(
      history: [ListeningEntry(uri: oldUri, lastPlayedMs: 10, playCount: 2)],
      session: PlaybackSession(
        uris: [oldUri, oldUri],
        index: 1,
        positionMs: 1234,
        shuffle: true,
        order: [1, 0],
        loop: LoopMode.all,
      ),
    );
    await library.invoke('saveSavedMusic', {'json': saved.encode()});
    await library.invoke('savePlaybackMemory', {'json': memory.encode()});
    final occupied = File(p.join(music.path, 'Taken.wav'));
    await occupied.writeAsBytes([1, 2, 3]);
    await expectLater(
      library.invoke('renameAudioFile', {'uri': oldUri, 'name': 'Taken'}),
      throwsStateError,
    );
    expect(await occupied.readAsBytes(), [1, 2, 3]);
    expect(await original.readAsBytes(), content);
    expect(
      await library.invoke('renameAudioFile', {
        'uri': oldUri,
        'name': 'Renamed',
      }),
      true,
    );
    final renamed = File(p.join(music.path, 'Renamed.wav'));
    final newUri = renamed.absolute.uri.toString();
    expect(await original.exists(), isFalse);
    expect(await renamed.readAsBytes(), content);
    final reopened = DesktopLibrary(storageDirectory: storage);
    final loadedSaved = SavedMusicData.decode(
      await reopened.invoke('loadSavedMusic', null) as String,
    );
    final loadedMemory = PlaybackMemoryData.decode(
      await reopened.invoke('loadPlaybackMemory', null) as String,
    );
    expect(loadedSaved.favorites, {newUri});
    expect(loadedSaved.ratings[newUri], 4.5);
    expect(loadedSaved.trackTitles[newUri], 'Renamed');
    expect(loadedSaved.playlists.single.tracks, [newUri]);
    expect(loadedMemory.history.single.uri, newUri);
    expect(loadedMemory.session!.uris, [newUri, newUri]);
    expect(loadedMemory.session!.positionMs, 1234);
    expect(
      (await reopened.invoke('loadLibrary', null) as List).single['uri'],
      newUri,
    );
  }, skip: !Platform.isWindows);

  test(
    'interrupted rename recovers the original file and saved references',
    () async {
      final library = DesktopLibrary(
        storageDirectory: storage,
        chooseDirectory: () async => music.path,
      );
      final rows = await library.invoke('chooseAudioFolder', null) as List;
      final oldFile = File(p.join(music.path, 'Sample.wav'));
      final newFile = File(p.join(music.path, 'New.wav'));
      final oldUri = oldFile.absolute.uri.toString();
      final saved = SavedMusicData(favorites: [oldUri]);
      final memory = PlaybackMemoryData();
      final digest = sha256.convert(await oldFile.readAsBytes()).toString();
      await oldFile.rename(newFile.path);
      await storage.create(recursive: true);
      await File(p.join(storage.path, 'rename_journal.json')).writeAsString(
        jsonEncode({
          'version': 1,
          'state': 'pending',
          'oldPath': oldFile.path,
          'newPath': newFile.path,
          'digest': digest,
          'savedBefore': jsonDecode(saved.encode()),
          'memoryBefore': jsonDecode(memory.encode()),
          'libraryBefore': {'version': 1, 'tracks': rows},
        }),
      );
      expect(await library.invoke('recoverRename', null), true);
      expect(await oldFile.exists(), isTrue);
      expect(await newFile.exists(), isFalse);
      expect(
        SavedMusicData.decode(
          await library.invoke('loadSavedMusic', null) as String,
        ).favorites,
        {oldUri},
      );
      expect(await library.invoke('recoverRename', null), false);
    },
    skip: !Platform.isWindows,
  );

  test('restore journal persists separately from normal saved music', () async {
    final library = DesktopLibrary(storageDirectory: storage);
    expect(await library.invoke('loadBackupJournal', null), isNull);
    final saved = jsonEncode({
      'version': 1,
      'favorites': ['synthetic'],
    });
    final pending = jsonEncode({
      'version': 1,
      'state': 'pending',
      'savedBefore': saved,
    });
    await library.invoke('saveSavedMusic', {'json': saved});
    await library.invoke('saveBackupJournal', {'json': pending});
    final reopened = DesktopLibrary(storageDirectory: storage);
    expect(
      jsonDecode(
        await reopened.invoke('loadBackupJournal', null) as String,
      )['state'],
      'pending',
    );
    expect(
      jsonDecode(
        await reopened.invoke('loadSavedMusic', null) as String,
      )['favorites'],
      ['synthetic'],
    );
    await reopened.invoke('saveBackupJournal', {
      'json': jsonEncode({'version': 1, 'state': 'complete'}),
    });
    expect(
      jsonDecode(
        await reopened.invoke('loadBackupJournal', null) as String,
      )['state'],
      'complete',
    );
  });

  test('scan reads WAV metadata, deduplicates overlapping roots and ignores unrelated files', () async {
    await File(p.join(music.path, 'notes.txt')).writeAsString('not music');
    final rows = scanDesktopFolders([music.path, music.path]);
    expect(rows, hasLength(1));
    expect(rows.single['title'], 'Sample');
    expect(rows.single['durationMs'], 1000);
    expect(
      rows.single['uri'],
      File(p.join(music.path, 'Sample.wav')).absolute.uri.toString(),
    );
  });

  test('scan reads a genre from WAV INFO metadata', () async {
    final file = File(p.join(music.path, 'Sample.wav'));
    final original = await file.readAsBytes();
    final tag = ascii.encode(
      'LIST'
      '\x00\x00\x00'
      'INFO'
      'IGNR'
      '\x00\x00\x00'
      'Rock',
    );
    final bytes = Uint8List.fromList([...original, ...tag]);
    ByteData.sublistView(bytes).setUint32(4, bytes.length - 8, Endian.little);
    await file.writeAsBytes(bytes);
    final rows = scanDesktopFolders([music.path]);
    expect(rows.single['genre'], 'Rock');
  });

  test(
    'folder selection, library and explicit visibility persist across restarts',
    () async {
      final library = DesktopLibrary(
        storageDirectory: storage,
        chooseDirectory: () async => music.path,
      );
      await library.invoke('saveSourceFolders', {'folders': <String>[]});
      expect(await library.invoke('loadSourceFolders', null), isEmpty);
      await library.invoke('chooseAudioFolder', null);
      final reopened = DesktopLibrary(storageDirectory: storage);
      expect(await reopened.invoke('loadLibrary', null), hasLength(1));
      expect(await reopened.invoke('loadSourceFolders', null), [music.path]);
      await reopened.invoke('saveSourceFolders', {'folders': null});
      expect(await reopened.invoke('loadSourceFolders', null), isNull);
    },
  );

  test('removing unavailable roots preserves the audio files and refreshes cached library', () async {
    final library = DesktopLibrary(
      storageDirectory: storage,
      chooseDirectory: () async => music.path,
    );
    await library.invoke('chooseAudioFolder', null);
    expect(
      await library.invoke('removeAudioFolder', {'folder': music.path}),
      isEmpty,
    );
    expect(await library.invoke('loadAudioRoots', null), isEmpty);
    expect(await File(p.join(music.path, 'Sample.wav')).exists(), isTrue);
    expect(
      await DesktopLibrary(storageDirectory: storage)
          .invoke('loadLibrary', null),
      isEmpty,
    );
  });

  test(
    'cancelled picker and missing roots do not erase a saved library',
    () async {
      final library = DesktopLibrary(
        storageDirectory: storage,
        chooseDirectory: () async => music.path,
      );
      await library.invoke('chooseAudioFolder', null);
      final cancelled = DesktopLibrary(
        storageDirectory: storage,
        chooseDirectory: () async => null,
      );
      expect(await cancelled.invoke('chooseAudioFolder', null), isNull);
      await File(p.join(storage.path, 'music_roots.json'))
          .writeAsString(jsonEncode([p.join(temporary.path, 'missing')]));
      await expectLater(
        cancelled.invoke('scanAudio', null),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        await DesktopLibrary(storageDirectory: storage)
            .invoke('loadLibrary', null),
        hasLength(1),
      );
    },
  );

  test(
    'concurrent saves serialize and recover an interrupted rename from backup',
    () async {
      final library = DesktopLibrary(storageDirectory: storage);
      await Future.wait(
        List.generate(
          10,
          (i) => library.invoke('savePlaybackMemory', {
            'json': jsonEncode({'version': 1, 'index': i}),
          }),
        ),
      );
      expect(
        jsonDecode(
          (await library.invoke('loadPlaybackMemory', null)) as String,
        )['index'],
        9,
      );
      await File(p.join(storage.path, 'playback_memory.json'))
          .rename(p.join(storage.path, 'playback_memory.json.bak'));
      expect(
        jsonDecode(
          (await DesktopLibrary(storageDirectory: storage)
                  .invoke('loadPlaybackMemory', null))
              as String,
        )['index'],
        9,
      );
      expect(
        await library.invoke('loadArtwork', {'uri': 'file:///unknown.wav'}),
        isNull,
      );
    },
  );
}
