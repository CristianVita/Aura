import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const generatedMaxBytes = 40 * 1024 * 1024;

enum GeneratedKind { backup, playlist, diagnostic }

class GeneratedEntry {
  const GeneratedEntry({
    required this.name,
    required this.kind,
    required this.size,
    required this.modified,
    this.displayName,
  });
  final String name;
  final GeneratedKind kind;
  final int size;
  final DateTime modified;
  final String? displayName;
}

class GeneratedFileStore {
  GeneratedFileStore({Future<Directory> Function()? directory})
    : _directory = directory ?? _defaultDirectory;
  final Future<Directory> Function() _directory;
  static Future<Directory> _defaultDirectory() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'generated_files_v1'),
  );
  static final _pattern = RegExp(
    r'^aura-(backup|playlist|diagnostic)-\d{8}T\d{6}-[a-f0-9]{16}\.json$',
  );
  Future<Directory> _root() async {
    final dir = await _directory();
    await dir.create(recursive: true);
    return dir;
  }

  void _validate(String name) {
    if (!_pattern.hasMatch(name)) {
      throw const FormatException('Invalid generated file name');
    }
  }

  Future<List<GeneratedEntry>> list() async {
    final root = await _root();
    final out = <GeneratedEntry>[];
    await for (final item in root.list(followLinks: false)) {
      if (item is! File) continue;
      final name = p.basename(item.path);
      final match = _pattern.firstMatch(name);
      if (match == null) continue;
      try {
        final stat = await item.stat();
        if (stat.type != FileSystemEntityType.file ||
            stat.size > generatedMaxBytes) {
          continue;
        }
        String? displayName;
        if (match.group(1) == 'playlist' && stat.size <= 2 * 1024 * 1024) {
          try {
            final data = jsonDecode(await item.readAsString());
            if (data is Map &&
                data['format'] == 'aura.playlist' &&
                data['name'] is String) {
              final title = (data['name'] as String).trim();
              if (title.isNotEmpty) {
                displayName = title.length > 200
                    ? title.substring(0, 200)
                    : title;
              }
            }
          } catch (_) {}
        }
        out.add(
          GeneratedEntry(
            name: name,
            kind: GeneratedKind.values.byName(match.group(1)!),
            size: stat.size,
            modified: stat.modified,
            displayName: displayName,
          ),
        );
      } on FileSystemException {
        continue;
      }
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  Future<GeneratedEntry> create(GeneratedKind kind, Uint8List bytes) async {
    if (bytes.isEmpty || bytes.length > generatedMaxBytes) {
      throw const FormatException('Invalid generated file size');
    }
    final root = await _root();
    final now = DateTime.now().toUtc();
    String pad(int n) => n.toString().padLeft(2, '0');
    final stamp =
        '${now.year}${pad(now.month)}${pad(now.day)}T${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
    final random = Random.secure();
    final nonce = List.generate(
      8,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final name = 'aura-${kind.name}-$stamp-$nonce.json';
    final file = File(p.join(root.path, name));
    final partial = File(p.join(root.path, '$name.part'));
    await partial.create(exclusive: true);
    try {
      await partial.writeAsBytes(bytes, flush: true);
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw const FileSystemException('Generated file collision');
      }
      await partial.rename(file.path);
    } catch (_) {
      try {
        await partial.delete();
      } catch (_) {}
      rethrow;
    }
    return GeneratedEntry(
      name: name,
      kind: kind,
      size: bytes.length,
      modified: DateTime.now(),
    );
  }

  Future<File> _file(String name) async {
    _validate(name);
    final root = await _root();
    final file = File(p.join(root.path, name));
    if (await FileSystemEntity.type(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException('Generated file unavailable');
    }
    return file;
  }

  Future<Uint8List> read(String name) async {
    final file = await _file(name);
    final length = await file.length();
    if (length <= 0 || length > generatedMaxBytes) {
      throw const FormatException('Invalid generated file size');
    }
    final bytes = await file.readAsBytes();
    if (bytes.length != length) {
      throw const FormatException('Generated file changed');
    }
    return bytes;
  }

  Future<void> remove(String name) async {
    final file = await _file(name);
    await file.delete();
  }
}

Uint8List encodeGeneratedJson(Map<String, Object?> data) => Uint8List.fromList(
  utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
);

String? safePlaylistReference(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !const {'file', 'content', 'aura'}.contains(uri.scheme) ||
      uri.userInfo.isNotEmpty) {
    return null;
  }
  if (uri.scheme == 'aura' && uri.host != 'navidrome') return null;
  if (uri.hasQuery || uri.hasFragment) return null;
  return uri.toString();
}
