import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura/desktop_library.dart';
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
