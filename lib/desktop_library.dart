import 'app_language.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:crypto/crypto.dart';

import 'playback_memory.dart';
import 'saved_music.dart';
import 'rename_filename.dart';
import 'rename_references.dart';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DesktopLibrary {
  DesktopLibrary({
    Directory? storageDirectory,
    Future<String?> Function()? chooseDirectory,
  }) : _providedDirectory = storageDirectory,
       _chooseDirectory =
           chooseDirectory ??
           (() => FilePicker.getDirectoryPath(
             dialogTitle: AppText.current.uiChooseYourMusicFolder,
           ));
  final Directory? _providedDirectory;
  final Future<String?> Function() _chooseDirectory;
  Future<Directory>? _directory;
  Future<void> _pending = Future.value();
  List<Map<String, Object?>>? _rows;

  Future<Directory> _storage() => _directory ??= () async {
    final directory =
        _providedDirectory ?? await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return directory;
  }();

  Future<Object?> _read(String name) async {
    final directory = await _storage();
    final file = File(p.join(directory.path, name));
    final backup = File('${file.path}.bak');
    if (await file.exists()) return jsonDecode(await file.readAsString());
    if (await backup.exists()) return jsonDecode(await backup.readAsString());
    return null;
  }

  Future<void> _write(String name, Object value) {
    final operation = _pending.then((_) async {
      final directory = await _storage();
      final file = File(p.join(directory.path, name));
      final temporary = File('${file.path}.new');
      final backup = File('${file.path}.bak');
      await temporary.writeAsString(jsonEncode(value), flush: true);
      if (await file.exists()) {
        if (await backup.exists()) await backup.delete();
        await file.rename(backup.path);
      }
      try {
        await temporary.rename(file.path);
      } catch (_) {
        if (!await file.exists() && await backup.exists()) {
          await backup.rename(file.path);
        }
        rethrow;
      }
      if (await backup.exists()) await backup.delete();
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<List<String>> _roots() async =>
      ((await _read('music_roots.json')) as List?)?.cast<String>() ?? [];
  Future<List<String>?> _folders() async {
    final saved = await _read('source_folders.json') as Map<String, dynamic>?;
    return (saved?['folders'] as List?)?.cast<String>();
  }

  Future<List<Map<String, Object?>>> _loadLibrary() async {
    if (_rows != null) return _rows!;
    final saved = await _read('audio_library.json') as Map<String, dynamic>?;
    _rows = saved == null
        ? []
        : (saved['tracks'] as List)
              .map((e) => Map<String, Object?>.from(e as Map))
              .toList();
    return _rows!;
  }

  Future<List<Map<String, Object?>>> _scan(List<String> roots) async {
    final rows = await compute(scanDesktopFolders, roots);
    await _write('audio_library.json', {'version': 1, 'tracks': rows});
    _rows = rows;
    return rows;
  }

  Future<String> _digest(String path) async =>
      (await sha256.bind(File(path).openRead()).first).toString();

  void _moveExclusive(String from, String to) {
    if (!Platform.isWindows) throw UnsupportedError('Windows only');
    final move = DynamicLibrary.open('kernel32.dll')
        .lookupFunction<
          Int32 Function(Pointer<Utf16>, Pointer<Utf16>),
          int Function(Pointer<Utf16>, Pointer<Utf16>)
        >('MoveFileW');
    final source = from.toNativeUtf16();
    final target = to.toNativeUtf16();
    try {
      if (move(source, target) == 0) {
        throw FileSystemException('Move failed', from);
      }
    } finally {
      calloc.free(source);
      calloc.free(target);
    }
  }

  Future<bool> _recoverRename() async {
    final journal = await _read('rename_journal.json') as Map<String, dynamic>?;
    if (journal == null || journal['state'] == 'complete') return false;
    if (journal['version'] != 1 || journal['state'] != 'pending') {
      throw const FormatException('Invalid rename journal');
    }
    final oldPath = journal['oldPath'] as String;
    final newPath = journal['newPath'] as String;
    final oldExists = await File(oldPath).exists();
    final newExists = await File(newPath).exists();
    if (oldExists == newExists) throw StateError('Ambiguous rename recovery');
    final candidate = oldExists ? oldPath : newPath;
    if (await _digest(candidate) != journal['digest']) {
      throw StateError('Changed file requires manual recovery');
    }
    if (newExists) _moveExclusive(newPath, oldPath);
    await _write('saved_music.json', journal['savedBefore']);
    await _write('playback_memory.json', journal['memoryBefore']);
    await _write('audio_library.json', journal['libraryBefore']);
    _rows = null;
    await _write('rename_journal.json', {'version': 1, 'state': 'complete'});
    return true;
  }

  Future<void> _renameAudio(String uri, String stem) async {
    if (!Platform.isWindows || Uri.tryParse(uri)?.scheme != 'file') {
      throw UnsupportedError('Only local Windows files');
    }
    await _recoverRename();
    final rows = await _loadLibrary();
    final index = rows.indexWhere((row) => row['uri'] == uri);
    if (index < 0) throw StateError('Track is not in library');
    final source = File.fromUri(Uri.parse(uri));
    final oldPath = source.absolute.path;
    final filename = renamedAudioFilename(p.basename(oldPath), stem);
    final newPath = p.join(p.dirname(oldPath), filename);
    if (oldPath.toLowerCase() == newPath.toLowerCase()) {
      throw StateError('Same name');
    }
    final newUri = File(newPath).absolute.uri.toString();
    if (await FileSystemEntity.type(newPath, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('Destination already exists');
    }
    final beforeSaved =
        await _read('saved_music.json') as Map<String, dynamic>? ??
        jsonDecode(SavedMusicData().encode()) as Map<String, dynamic>;
    final beforeMemory =
        await _read('playback_memory.json') as Map<String, dynamic>? ??
        jsonDecode(PlaybackMemoryData().encode()) as Map<String, dynamic>;
    final beforeLibrary = {'version': 1, 'tracks': rows};
    final migrated = remapRenamedTrack(
      saved: SavedMusicData.decode(jsonEncode(beforeSaved)),
      memory: PlaybackMemoryData.decode(jsonEncode(beforeMemory)),
      oldUri: uri,
      newUri: newUri,
    );
    final nextRows = [
      for (var i = 0; i < rows.length; i++)
        if (i == index) {...rows[i], 'id': newUri, 'uri': newUri} else rows[i],
    ];
    await _write('rename_journal.json', {
      'version': 1,
      'state': 'pending',
      'oldPath': oldPath,
      'newPath': newPath,
      'digest': await _digest(oldPath),
      'savedBefore': beforeSaved,
      'memoryBefore': beforeMemory,
      'libraryBefore': beforeLibrary,
    });
    var moved = false;
    try {
      _moveExclusive(oldPath, newPath);
      moved = true;
      await _write('saved_music.json', jsonDecode(migrated.saved.encode()));
      await _write(
        'playback_memory.json',
        jsonDecode(migrated.memory.encode()),
      );
      await _write('audio_library.json', {'version': 1, 'tracks': nextRows});
      await _write('rename_journal.json', {'version': 1, 'state': 'complete'});
      _rows = nextRows;
    } catch (_) {
      if (moved) {
        await _recoverRename();
      } else {
        await _write('rename_journal.json', {
          'version': 1,
          'state': 'complete',
        });
      }
      rethrow;
    }
  }

  Future<Object?> invoke(String method, Object? arguments) async {
    final args = arguments as Map<Object?, Object?>?;
    switch (method) {
      case 'recoverRename':
        return _recoverRename();
      case 'getAudioFileName':
        final uri = Uri.parse(args!['uri'] as String);
        if (uri.scheme != 'file') throw UnsupportedError('Not a local file');
        if (!(await _loadLibrary()).any(
          (row) => row['uri'] == uri.toString(),
        )) {
          throw StateError('Track not in library');
        }
        return p.basename(File.fromUri(uri).path);
      case 'renameAudioFile':
        await _renameAudio(args!['uri'] as String, args['name'] as String);
        return true;
      case 'loadLibrary':
        return _loadLibrary();
      case 'loadAudioRoots':
        return _roots();
      case 'removeAudioFolder':
        final root = args!['folder'] as String;
        final roots = await _roots();
        roots.removeWhere(
          (existing) => p.equals(existing.toLowerCase(), root.toLowerCase()),
        );
        final rows = (await _loadLibrary()).where((row) {
          final folder = (row['folder'] as String).toLowerCase();
          return roots.any(
            (remaining) =>
                p.equals(remaining.toLowerCase(), folder) ||
                p.isWithin(remaining.toLowerCase(), folder),
          );
        }).toList();
        await _write('music_roots.json', roots);
        await _write('audio_library.json', {'version': 1, 'tracks': rows});
        _rows = rows;
        return rows;
      case 'scanAudio':
        final roots = await _roots();
        if (roots.isEmpty) return invoke('chooseAudioFolder', null);
        return _scan(roots);
      case 'chooseAudioFolder':
        final selected = await _chooseDirectory();
        if (selected == null) return null;
        final root = p.normalize(p.absolute(selected));
        final roots = await _roots();
        if (!roots.any(
          (existing) => p.equals(existing.toLowerCase(), root.toLowerCase()),
        )) {
          roots.add(root);
        }
        final rows = await _scan(roots);
        await _write('music_roots.json', roots);
        final folders = await _folders();
        if (folders != null) {
          final visible = folders.cast<String>().toSet();
          visible.addAll(
            rows
                .where(
                  (row) =>
                      p.isWithin(root, row['folder'] as String) ||
                      p.equals(root, row['folder'] as String),
                )
                .map((row) => row['folder'] as String),
          );
          await _write('source_folders.json', {'folders': visible.toList()});
        }
        return rows;
      case 'loadSourceFolders':
        return _folders();
      case 'saveSourceFolders':
        // JSON null means all folders, [] means an explicitly empty selection.
        await _write('source_folders.json', {'folders': args?['folders']});
        return null;
      case 'loadSavedMusic':
      case 'loadPlaybackMemory':
      case 'loadServerCache':
      case 'loadBackupJournal':
        final name = method == 'loadBackupJournal'
            ? 'backup_restore_journal.json'
            : method == 'loadServerCache'
            ? 'server_library.json'
            : method == 'loadSavedMusic'
            ? 'saved_music.json'
            : 'playback_memory.json';
        final saved = await _read(name);
        return saved == null ? null : jsonEncode(saved);
      case 'saveSavedMusic':
      case 'savePlaybackMemory':
      case 'saveServerCache':
      case 'saveBackupJournal':
        final name = method == 'saveBackupJournal'
            ? 'backup_restore_journal.json'
            : method == 'saveServerCache'
            ? 'server_library.json'
            : method == 'saveSavedMusic'
            ? 'saved_music.json'
            : 'playback_memory.json';
        final data =
            jsonDecode(args!['json'] as String) as Map<String, dynamic>;
        if (data['version'] != 1) {
          throw const FormatException('Unsupported data version');
        }
        await _write(name, data);
        return null;
      case 'loadArtwork':
        final uri = args?['uri'] as String?;
        if (uri == null || Uri.tryParse(uri)?.scheme != 'file') return null;
        final rows = await _loadLibrary();
        if (!rows.any((row) => row['uri'] == uri)) return null;
        return compute(_embeddedArtwork, uri);
      default:
        throw MissingPluginException(
          'Unknown audio library operation: $method',
        );
    }
  }
}

Uint8List? _embeddedArtwork(String uri) {
  try {
    final metadata = readMetadata(File.fromUri(Uri.parse(uri)), getImage: true);
    final pictures = metadata.pictures;
    if (pictures.isEmpty || pictures.first.bytes.length > 8 * 1024 * 1024) {
      return null;
    }
    return pictures.first.bytes;
  } catch (_) {
    return null;
  }
}

/// Scan only user-selected roots, without following directory links or writing
/// to any music file. A malformed tag never prevents other tracks being read.
List<Map<String, Object?>> scanDesktopFolders(List<String> roots) {
  const extensions = {
    '.mp3',
    '.flac',
    '.m4a',
    '.mp4',
    '.aac',
    '.ogg',
    '.opus',
    '.wav',
    '.aiff',
    '.aif',
    '.ape',
    '.wma',
  };
  final rows = <Map<String, Object?>>[];
  final seenDirectories = <String>{};
  final seenFiles = <String>{};
  final pending = roots.map(Directory.new).toList();
  for (final root in pending) {
    if (!root.existsSync()) {
      throw FileSystemException('Folder unavailable', root.path);
    }
  }
  while (pending.isNotEmpty) {
    final directory = pending.removeLast();
    if (!seenDirectories.add(
      p.normalize(directory.absolute.path).toLowerCase(),
    )) {
      continue;
    }
    List<FileSystemEntity> children;
    try {
      children = directory.listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final child in children) {
      if (child is Directory) {
        pending.add(child);
        continue;
      }
      if (child is! File ||
          !extensions.contains(p.extension(child.path).toLowerCase())) {
        continue;
      }
      if (!seenFiles.add(p.normalize(child.absolute.path).toLowerCase())) {
        continue;
      }
      try {
        final stat = child.statSync();
        final uri = child.absolute.uri.toString();
        final row = <String, Object?>{
          'id': uri,
          'uri': uri,
          'title': p.basenameWithoutExtension(child.path),
          'artist': '',
          'album': '',
          'genre': '',
          'folder': p.normalize(child.parent.absolute.path),
          'modifiedSeconds': stat.modified.millisecondsSinceEpoch ~/ 1000,
          'durationMs': 0,
        };
        try {
          final metadata = readMetadata(child, getImage: false);
          if (metadata.title?.trim().isNotEmpty == true) {
            row['title'] = metadata.title;
          }
          row['artist'] = metadata.artist ?? '';
          row['album'] = metadata.album ?? '';
          row['genre'] = metadata.genres.firstOrNull ?? '';
          row['durationMs'] = metadata.duration?.inMilliseconds ?? 0;
        } catch (_) {
          /* Preserve filename-based playback for missing tags. */
        }
        rows.add(row);
      } on FileSystemException {
        /* A file may disappear during scanning. */
      }
    }
  }
  rows.sort(
    (a, b) => (a['title'] as String).toLowerCase().compareTo(
      (b['title'] as String).toLowerCase(),
    ),
  );
  return rows;
}
