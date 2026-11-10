import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PlaybackCacheRead {
  PlaybackCacheRead(this.file, this.mime, this.release);
  final File file;
  final String mime;
  final Future<void> Function() release;
}

class PlaybackCacheWrite {
  PlaybackCacheWrite(this.file, this.length, this.finish, this.abort);
  final File file;
  final int length;
  final Future<void> Function(String mime) finish;
  final Future<void> Function() abort;
}

class PlaybackCache extends ChangeNotifier {
  PlaybackCache({
    Future<Directory> Function()? directory,
    this.maxBytes = 2 * 1000 * 1000 * 1000,
  }) : _directory = directory ?? _defaultDirectory;
  static Future<Directory> _defaultDirectory() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'playback_cache_v1'),
  );
  final Future<Directory> Function() _directory;
  final int maxBytes;
  bool enabled = false, ready = false;
  bool get available => _lockHandle != null;
  Future<void>? _loading;
  RandomAccessFile? _lockHandle;
  Future<void> _pending = Future.value();
  final Map<String, int> _pins = {};
  final Map<String, int> _reservations = {};

  String _key(String uri) => sha256.convert(utf8.encode(uri)).toString();
  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<Directory> _root() async {
    final root = await _directory();
    await root.create(recursive: true);
    return root;
  }

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final root = await _root();
      final handle = await File(p.join(root.path, 'owner.lock'))
          .open(mode: FileMode.append);
      try {
        await handle.lock(FileLock.exclusive, 0, 1);
        _lockHandle = handle;
      } catch (_) {
        await handle.close();
        rethrow;
      }
      final config = File(p.join(root.path, 'settings.json'));
      if (await config.exists()) {
        final data = jsonDecode(await config.readAsString());
        enabled = data is Map && data['enabled'] == true;
      }
      await for (final entity in root.list(followLinks: false)) {
        if (entity is File &&
            RegExp(r'^[a-f0-9]{64}\.part$').hasMatch(p.basename(entity.path))) {
          try {
            await entity.delete();
          } on FileSystemException catch (_) {}
        }
      }
    } catch (_) {
      enabled = false;
    }
    ready = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    await load();
    if (_lockHandle == null) {
      throw StateError('Playback cache is already in use');
    }
    await _locked(() async {
      final root = await _root();
      final target = File(p.join(root.path, 'settings.json'));
      final temp = File('${target.path}.tmp');
      await temp.writeAsString(
        jsonEncode({'version': 1, 'enabled': value}),
        flush: true,
      );
      await temp.rename(target.path);
      enabled = value;
    });
    notifyListeners();
  }

  Future<PlaybackCacheRead?> acquire(String uri) async {
    await load();
    if (!enabled) return null;
    return _locked(() async {
      if (!enabled) return null;
      final root = await _root(), key = _key(uri);
      final data = File(p.join(root.path, '$key.audio'));
      final meta = File(p.join(root.path, '$key.json'));
      try {
        final json = jsonDecode(await meta.readAsString());
        final length = await data.length();
        if (json is! Map ||
            json['size'] != length ||
            length <= 0 ||
            json['mime'] is! String ||
            json['sha256'] is! String ||
            (await sha256.bind(data.openRead()).first).toString() !=
                json['sha256']) {
          if (!_pins.containsKey(key)) {
            await data.delete();
            if (await meta.exists()) await meta.delete();
          }
          return null;
        }
        _pins.update(key, (v) => v + 1, ifAbsent: () => 1);
        try {
          await data.setLastModified(DateTime.now());
        } on FileSystemException catch (_) {}
        var released = false;
        return PlaybackCacheRead(
          data,
          json['mime'] as String,
          () => _locked(() async {
            if (released) return;
            released = true;
            final count = _pins[key] ?? 0;
            if (count <= 1) {
              _pins.remove(key);
            } else {
              _pins[key] = count - 1;
            }
          }),
        );
      } catch (_) {
        return null;
      }
    });
  }

  Future<PlaybackCacheWrite?> begin(String uri, int length) async {
    await load();
    if (!enabled || length <= 0 || length > maxBytes) return null;
    return _locked(() async {
      if (!enabled) return null;
      final root = await _root(), key = _key(uri);
      if (_pins.containsKey(key) || _reservations.containsKey(key)) return null;
      final data = File(p.join(root.path, '$key.audio'));
      if (await data.exists()) return null;
      final files = <File>[];
      await for (final entry in root.list(followLinks: false)) {
        if (entry is File &&
            RegExp(r'^[a-f0-9]{64}\.audio$').hasMatch(p.basename(entry.path))) {
          files.add(entry);
        }
      }
      final stats = <File, FileStat>{};
      var total = _reservations.values.fold<int>(0, (a, b) => a + b);
      for (final file in files) {
        try {
          final stat = await file.stat();
          stats[file] = stat;
          total += stat.size;
        } on FileSystemException catch (_) {
          return null;
        }
      }
      await for (final entry in root.list(followLinks: false)) {
        if (entry is! File ||
            !RegExp(r'^[a-f0-9]{64}\.part$').hasMatch(p.basename(entry.path))) {
          continue;
        }
        final oldKey = p.basenameWithoutExtension(entry.path);
        if (_reservations.containsKey(oldKey)) continue;
        try {
          total += await entry.length();
        } on FileSystemException catch (_) {
          return null;
        }
      }
      files.sort(
        (a, b) => (stats[a]?.modified ?? DateTime(0)).compareTo(
          stats[b]?.modified ?? DateTime(0),
        ),
      );
      for (final file in files) {
        if (total + length <= maxBytes) break;
        final oldKey = p.basenameWithoutExtension(file.path);
        if (_pins.containsKey(oldKey) ||
            _reservations.containsKey(oldKey) ||
            !stats.containsKey(file)) {
          continue;
        }
        try {
          await file.delete();
          total -= stats[file]!.size;
          final meta = File(p.join(root.path, '$oldKey.json'));
          if (await meta.exists()) await meta.delete();
        } on FileSystemException catch (_) {}
      }
      if (total + length > maxBytes) return null;
      _reservations[key] = length;
      final partial = File(p.join(root.path, '$key.part'));
      var finished = false;
      Future<void> abort() => _locked(() async {
        if (finished) return;
        finished = true;
        _reservations.remove(key);
        try {
          if (await partial.exists()) await partial.delete();
        } on FileSystemException catch (_) {}
      });
      Future<void> finish(String mime) => _locked(() async {
        if (finished) return;
        try {
          if (!enabled ||
              !await partial.exists() ||
              await partial.length() != length) {
            throw const FormatException('Incomplete cache entry');
          }
          final meta = File(p.join(root.path, '$key.json'));
          final temp = File(p.join(root.path, '$key.meta.tmp'));
          final digest = (await sha256.bind(partial.openRead()).first)
              .toString();
          await temp.writeAsString(
            jsonEncode({'size': length, 'mime': mime, 'sha256': digest}),
            flush: true,
          );
          await partial.rename(data.path);
          await temp.rename(meta.path);
          finished = true;
          _reservations.remove(key);
        } catch (_) {
          finished = true;
          _reservations.remove(key);
          try {
            if (await partial.exists()) await partial.delete();
            if (await data.exists()) await data.delete();
          } on FileSystemException catch (_) {}
          rethrow;
        }
      });
      return PlaybackCacheWrite(partial, length, finish, abort);
    });
  }

  Future<int> clear() async {
    await load();
    if (_lockHandle == null) {
      throw StateError('Playback cache is already in use');
    }
    return _locked(() async {
      final root = await _root();
      var skipped = 0;
      await for (final item in root.list(followLinks: false)) {
        if (item is! File) continue;
        final match = RegExp(r'^([a-f0-9]{64})\.(audio|json|part|meta\.tmp)$')
            .firstMatch(p.basename(item.path));
        if (match == null) continue;
        final key = match.group(1)!;
        if (_pins.containsKey(key) || _reservations.containsKey(key)) {
          if (match.group(2) == 'audio' || match.group(2) == 'part') skipped++;
          continue;
        }
        if (await item.exists()) await item.delete();
      }
      return skipped;
    });
  }

  Future<void> close() async {
    await _pending;
    final handle = _lockHandle;
    _lockHandle = null;
    enabled = false;
    if (handle != null) await handle.close();
  }

  @override
  void dispose() {
    unawaited(close());
    super.dispose();
  }
}

final playbackCache = PlaybackCache();
