import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cover_backup_storage.dart';

import 'dart:convert';

class AlbumArtworkStore extends ChangeNotifier implements CoverBackupStorage {
  AlbumArtworkStore({this.directory});
  final Future<Directory> Function()? directory;
  Future<void> _pending = Future.value();
  final _cache = <String, Future<Uint8List?>>{};
  static const maxInputBytes = 10 * 1024 * 1024;

  Future<Directory> _root() async {
    final root = directory == null
        ? Directory(
            p.join(
              (await getApplicationSupportDirectory()).path,
              'album_art_v1',
            ),
          )
        : await directory!();
    await root.create(recursive: true);
    return root;
  }

  String _name(String album) => sha256.convert(utf8.encode(album)).toString();

  Future<File> _recover(String album) async {
    return _recoverKey(_name(album));
  }

  Future<File> _recoverKey(String key) async {
    if (!coverBackupKeyPattern.hasMatch(key)) {
      throw const FormatException('Invalid cover key');
    }
    final file = File(p.join((await _root()).path, '$key.png'));
    final backup = File('${file.path}.previous');
    if (await backup.exists()) {
      if (await file.exists()) {
        await backup.delete();
      } else {
        await backup.rename(file.path);
      }
    }
    return file;
  }

  @override
  Future<Map<String, Uint8List>> snapshot() async {
    final result = <String, Uint8List>{};
    await _serialize(() async {
      final root = await _root();
      final keys = <String>{};
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! File) continue;
        final match = RegExp(r'^([0-9a-f]{64})\.png(?:\.previous)?$')
            .firstMatch(p.basename(entity.path));
        if (match != null) keys.add(match.group(1)!);
      }
      if (keys.length > maxCoverBackupCount) {
        throw const FormatException('Too many covers');
      }
      var total = 0;
      for (final key in keys.toList()..sort()) {
        final file = await _recoverKey(key);
        if (!await file.exists()) continue;
        final size = await file.length();
        total += size;
        if (size <= 0 || size > maxInputBytes || total > maxCoverBackupBytes) {
          throw const FormatException('Covers too large');
        }
        result[key] = await file.readAsBytes();
      }
    });
    validateCoverBackupShape(result);
    return result;
  }

  @override
  Future<void> validateSnapshot(Map<String, Uint8List> images) async {
    validateCoverBackupShape(images);
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    for (final bytes in images.values) {
      if (bytes.length < signature.length ||
          !List.generate(
            signature.length,
            (i) => bytes[i] == signature[i],
          ).every((value) => value)) {
        throw const FormatException('Invalid cover image');
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      ui.ImageDescriptor? descriptor;
      ui.Codec? codec;
      try {
        descriptor = await ui.ImageDescriptor.encoded(buffer);
        if (descriptor.width <= 0 ||
            descriptor.height <= 0 ||
            descriptor.width > 1024 ||
            descriptor.height > 1024) {
          throw const FormatException('Invalid cover dimensions');
        }
        codec = await descriptor.instantiateCodec();
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec?.dispose();
        descriptor?.dispose();
        buffer.dispose();
      }
    }
  }

  @override
  Future<void> replaceSnapshot(Map<String, Uint8List> images) async {
    validateCoverBackupShape(images);
    await _serialize(() async {
      final root = await _root();
      final existing = <String>{};
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! File) continue;
        final match = RegExp(r'^([0-9a-f]{64})\.png(?:\.previous)?$')
            .firstMatch(p.basename(entity.path));
        if (match != null) existing.add(match.group(1)!);
      }
      for (final entry in images.entries) {
        final file = await _recoverKey(entry.key);
        final next = File('${file.path}.next');
        final previous = File('${file.path}.previous');
        await next.writeAsBytes(entry.value, flush: true);
        if (await file.exists()) await file.rename(previous.path);
        try {
          await next.rename(file.path);
        } catch (_) {
          if (await previous.exists() && !await file.exists()) {
            await previous.rename(file.path);
          }
          rethrow;
        }
        if (await previous.exists()) await previous.delete();
      }
      for (final key in existing.difference(images.keys.toSet())) {
        final file = await _recoverKey(key);
        if (await file.exists()) await file.delete();
      }
    });
    _cache.clear();
    notifyListeners();
  }

  Future<Uint8List?> read(String album) {
    if (album.trim().isEmpty) return Future.value(null);
    final cached = _cache.remove(album);
    if (cached != null) {
      _cache[album] = cached;
      return cached;
    }
    final future = () async {
      try {
        await _pending;
        final file = await _recover(album);
        if (!await file.exists()) return null;
        if (await file.length() > maxInputBytes) return null;
        return await file.readAsBytes();
      } catch (_) {
        return null;
      }
    }();
    _cache[album] = future;
    while (_cache.length > 64) {
      _cache.remove(_cache.keys.first);
    }
    return future;
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final task = _pending.then((_) => operation());
    _pending = task.catchError((Object _) {});
    return task;
  }

  Future<void> set(String album, Uint8List input) async {
    if (album.trim().isEmpty || input.isEmpty || input.length > maxInputBytes) {
      throw const FormatException('Invalid album image');
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(input);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    late Uint8List bytes;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 ||
          descriptor.height <= 0 ||
          descriptor.width > 16384 ||
          descriptor.height > 16384) {
        throw const FormatException('Image dimensions are invalid');
      }
      final largest = descriptor.width > descriptor.height
          ? descriptor.width
          : descriptor.height;
      final scale = largest > 1024 ? 1024 / largest : 1.0;
      codec = await descriptor.instantiateCodec(
        targetWidth: (descriptor.width * scale).round().clamp(1, 1024),
        targetHeight: (descriptor.height * scale).round().clamp(1, 1024),
      );
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (data == null || data.lengthInBytes > maxInputBytes) {
          throw const FormatException('Invalid album image');
        }
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
    await _serialize(() async {
      final file = await _recover(album);
      final next = File('${file.path}.next');
      final previous = File('${file.path}.previous');
      await next.writeAsBytes(bytes, flush: true);
      if (await previous.exists()) await previous.delete();
      if (await file.exists()) await file.rename(previous.path);
      try {
        await next.rename(file.path);
      } catch (_) {
        if (await previous.exists() && !await file.exists()) {
          await previous.rename(file.path);
        }
        rethrow;
      }
      if (await previous.exists()) await previous.delete();
    });
    _cache.remove(album);
    notifyListeners();
  }

  Future<void> remove(String album) async {
    if (album.trim().isEmpty) return;
    await _serialize(() async {
      final file = await _recover(album);
      if (await file.exists()) await file.delete();
    });
    _cache.remove(album);
    notifyListeners();
  }
}

final albumArtwork = AlbumArtworkStore();
