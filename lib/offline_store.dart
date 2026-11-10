import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'audio_track.dart';
import 'offline_storage.dart';
import 'download_network_policy.dart';

typedef OpenOfflineDownload =
    Future<({http.StreamedResponse response, void Function() close})> Function(
      Uri uri,
    );

class OfflineStore extends OfflineStorage {
  OfflineStore({
    required this.open,
    Future<Directory> Function()? directory,
    this.maxBytes = 512 * 1024 * 1024,
    this.networkGuard,
  }) : _directory = directory ?? _defaultDirectory;
  final OpenOfflineDownload open;
  final Future<Directory> Function() _directory;
  final int maxBytes;
  final DownloadNetworkGuard? networkGuard;
  final Set<String> _busy = {};
  final Map<String, Future<void>> _operations = {};
  static Future<Directory> _defaultDirectory() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'offline_audio_v1'),
  );
  @override
  bool busy(String uri) => _busy.contains(uri);
  String _key(String uri) => sha256.convert(utf8.encode(uri)).toString();
  void _validateUri(String uri) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null ||
        parsed.scheme != 'aura' ||
        parsed.host != 'navidrome' ||
        parsed.pathSegments.length != 2 ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.userInfo.isNotEmpty ||
        parsed.pathSegments.any((part) => part.isEmpty)) {
      throw const FormatException('Invalid server track');
    }
  }

  Future<Directory> _root() async {
    final root = await _directory();
    await root.create(recursive: true);
    return root;
  }

  Future<Map<String, dynamic>?> _read(String uri, Directory root) async {
    final file = File(p.join(root.path, '${_key(uri)}.json'));
    if (!await file.exists()) return null;
    try {
      final row = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final name = row['file'] as String;
      if (row['version'] != 1 ||
          row['uri'] != uri ||
          !RegExp('^${_key(uri)}_[a-f0-9]{16}\\.(mp3|m4a|ogg|flac|wav|audio)\$')
              .hasMatch(name) ||
          row['length'] is! int ||
          (row['length'] as int) <= 0 ||
          (row['length'] as int) > maxBytes ||
          [
            'id',
            'uri',
            'title',
            'artist',
            'album',
            'genre',
            'coverId',
            'folder',
          ].any((key) => row[key] is! String) ||
          row['durationMs'] is! int ||
          row['modifiedSeconds'] is! int ||
          row['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(row['sha256'] as String)) {
        return null;
      }
      return row;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> hasRecord(String uri) async {
    _validateUri(uri);
    final root = await _root();
    return File(p.join(root.path, '${_key(uri)}.json')).exists();
  }

  @override
  Future<Uri?> localUri(String uri) async {
    _validateUri(uri);
    final root = await _root();
    final row = await _read(uri, root);
    if (row == null) return null;
    final file = File(p.join(root.path, row['file'] as String));
    try {
      if (!await file.exists() || await file.length() != row['length']) {
        return null;
      }
      final digest = (await sha256.bind(file.openRead()).first).toString();
      return digest == row['sha256'] ? file.uri : null;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<List<Map<String, Object?>>> cachedTracks() async {
    final root = await _root();
    final rows = <Map<String, Object?>>[];
    await for (final item in root.list(followLinks: false)) {
      if (item is! File ||
          !RegExp(r'^[a-f0-9]{64}\.json$').hasMatch(p.basename(item.path))) {
        continue;
      }
      try {
        final raw =
            jsonDecode(await item.readAsString()) as Map<String, dynamic>;
        final uri = raw['uri'] as String;
        _validateUri(uri);
        if (p.basename(item.path) != '${_key(uri)}.json') continue;
        final row = await _read(uri, root);
        if (row == null) continue;
        rows.add({
          for (final key in [
            'id',
            'uri',
            'title',
            'artist',
            'album',
            'genre',
            'coverId',
            'folder',
            'modifiedSeconds',
            'durationMs',
          ])
            key: row[key],
          'year': metadataYear(row['year']),
        });
      } catch (_) {
        continue;
      }
    }
    return rows;
  }

  @override
  Future<OfflineMediaUsage> mediaUsage() async {
    final root = await _root();
    var count = 0, bytes = 0;
    await for (final item in root.list(followLinks: false)) {
      if (item is! File ||
          !RegExp(r'^[a-f0-9]{64}\.json$').hasMatch(p.basename(item.path))) {
        continue;
      }
      try {
        final raw = jsonDecode(await item.readAsString());
        if (raw is! Map || raw['uri'] is! String) continue;
        final uri = raw['uri'] as String;
        _validateUri(uri);
        if (p.basename(item.path) != '${_key(uri)}.json') continue;
        final row = await _read(uri, root);
        if (row == null) continue;
        final file = File(p.join(root.path, row['file'] as String));
        final length = await file.length();
        if (length != row['length']) continue;
        count++;
        bytes += length;
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return OfflineMediaUsage(tracks: count, bytes: bytes);
  }

  @override
  Future<void> download(AudioTrack track) {
    _validateUri(track.uri);
    final active = _operations[track.uri];
    if (active != null) return active;
    if (_busy.contains(track.uri)) {
      return Future.error(StateError('Offline operation in progress'));
    }
    return _operations.putIfAbsent(track.uri, () {
      final future = _download(track);
      return future.whenComplete(() {
        _operations.remove(track.uri);
      });
    });
  }

  Future<void> _deleteOwned(File? file, bool owned) async {
    if (!owned || file == null) return;
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      /* A later cleanup can retry. */
    }
  }

  Future<void> _download(AudioTrack track) async {
    _busy.add(track.uri);
    notifyListeners();
    File? partial;
    File? finalFile;
    File? temporary;
    bool ownsPartial = false, ownsFinal = false, ownsTemporary = false;
    void Function()? close;
    StreamSubscription<bool>? networkSubscription;
    var blocked = false;
    Future<void> checkNetwork() async {
      if (networkGuard != null && !await networkGuard!.allowed()) {
        blocked = true;
        close?.call();
        throw const DownloadNetworkException();
      }
    }

    try {
      if (await localUri(track.uri) != null) return;
      final root = await _root();
      final previous = await _read(track.uri, root);
      if (networkGuard != null) {
        networkSubscription = networkGuard!.changes.listen(
          (permitted) {
            if (!permitted) {
              blocked = true;
              close?.call();
            }
          },
          onError: (_) {
            blocked = true;
            close?.call();
          },
        );
        await checkNetwork();
      }
      final response = await open(Uri.parse(track.uri));
      close = response.close;
      if (blocked) {
        close();
        throw const DownloadNetworkException();
      }
      await checkNetwork();
      if (response.response.statusCode != 200) {
        throw const FormatException('Download failed');
      }
      final mime = (response.response.headers['content-type'] ?? '')
          .split(';')
          .first
          .toLowerCase()
          .trim();
      final extension = switch (mime) {
        'audio/mpeg' || 'audio/mp3' => 'mp3',
        'audio/mp4' || 'audio/x-m4a' => 'm4a',
        'audio/ogg' || 'application/ogg' => 'ogg',
        'audio/flac' || 'audio/x-flac' => 'flac',
        'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
        'application/octet-stream' => 'audio',
        _ => throw const FormatException('Invalid audio response'),
      };
      final expected = response.response.contentLength;
      if (expected != null && (expected <= 0 || expected > maxBytes)) {
        throw const FormatException('Invalid audio size');
      }
      final random = Random.secure();
      final nonce = List.generate(
        8,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final filename = '${_key(track.uri)}_$nonce.$extension';
      finalFile = File(p.join(root.path, filename));
      partial = File(p.join(root.path, '$filename.part'));
      if (await finalFile.exists() || await partial.exists()) {
        throw const FileSystemException('Download collision');
      }
      await partial.create(exclusive: true);
      ownsPartial = true;
      final sink = partial.openWrite();
      var size = 0;
      try {
        await sink.addStream(
          response.response.stream.timeout(const Duration(seconds: 30)).map((
            chunk,
          ) {
            if (blocked) throw const DownloadNetworkException();
            size += chunk.length;
            if (size > maxBytes) throw const FormatException('Audio too large');
            return chunk;
          }),
        );
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (blocked) throw const DownloadNetworkException();
      await checkNetwork();
      if (size == 0 || (expected != null && size != expected)) {
        throw const FormatException('Incomplete audio');
      }
      final digest = (await sha256.bind(partial.openRead()).first).toString();
      await partial.rename(finalFile.path);
      ownsPartial = false;
      ownsFinal = true;
      final row = {
        'version': 1,
        'file': filename,
        'length': size,
        'sha256': digest,
        'id': track.id,
        'uri': track.uri,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'genre': track.genre,
        'year': metadataYear(track.year),
        'coverId': track.coverId,
        'folder': track.folder,
        'modifiedSeconds': track.modifiedSeconds,
        'durationMs': track.durationMs,
      };
      final manifest = File(p.join(root.path, '${_key(track.uri)}.json'));
      temporary = File(
        p.join(root.path, '${_key(track.uri)}_$nonce.json.part'),
      );
      await temporary.create(exclusive: true);
      ownsTemporary = true;
      await temporary.writeAsString(jsonEncode(row), flush: true);
      try {
        if (await manifest.exists()) {
          // Invalid or stale entries can be replaced; audio files remain untouched.
          await manifest.delete();
        }
        await temporary.rename(manifest.path);
        ownsTemporary = false;
      } finally {
        await _deleteOwned(temporary, ownsTemporary);
        ownsTemporary = false;
      }
      ownsFinal = false;
      if (previous != null && previous['file'] != filename) {
        try {
          final old = File(p.join(root.path, previous['file'] as String));
          if (await old.exists()) await old.delete();
        } on FileSystemException {
          // The prior file may still be in use.
        }
      }
    } catch (_) {
      if (blocked) throw const DownloadNetworkException();
      rethrow;
    } finally {
      await networkSubscription?.cancel();
      try {
        close?.call();
      } catch (_) {}
      await _deleteOwned(temporary, ownsTemporary);
      await _deleteOwned(partial, ownsPartial);
      await _deleteOwned(finalFile, ownsFinal);
      _busy.remove(track.uri);
      notifyListeners();
    }
  }

  @override
  Future<void> remove(String uri) async {
    _validateUri(uri);
    if (busy(uri)) throw StateError('Download in progress');
    _busy.add(uri);
    notifyListeners();
    try {
      final root = await _root();
      final row = await _read(uri, root);
      if (row == null) {
        final invalid = File(p.join(root.path, '${_key(uri)}.json'));
        if (await invalid.exists()) await invalid.delete();
        return;
      }
      final audio = File(p.join(root.path, row['file'] as String));
      if (await audio.exists()) await audio.delete();
      final manifest = File(p.join(root.path, '${_key(uri)}.json'));
      if (await manifest.exists()) await manifest.delete();
    } finally {
      _busy.remove(uri);
      notifyListeners();
    }
  }
}
