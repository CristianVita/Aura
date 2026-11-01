import 'dart:convert';
import 'dart:io';

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
             dialogTitle: 'Alege folderul cu muzică',
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

  Future<Object?> invoke(String method, Object? arguments) async {
    final args = arguments as Map<Object?, Object?>?;
    switch (method) {
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
        final name = method == 'loadServerCache'
            ? 'server_library.json'
            : method == 'loadSavedMusic'
            ? 'saved_music.json'
            : 'playback_memory.json';
        final saved = await _read(name);
        return saved == null ? null : jsonEncode(saved);
      case 'saveSavedMusic':
      case 'savePlaybackMemory':
      case 'saveServerCache':
        final name = method == 'saveServerCache'
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
