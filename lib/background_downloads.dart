import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'audio_track.dart';
import 'download_network_policy.dart';
import 'offline_storage.dart';

abstract class DownloadJobPersistence {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class DeviceDownloadJobPersistence implements DownloadJobPersistence {
  DeviceDownloadJobPersistence({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationSupportDirectory;
  final Future<Directory> Function() _directory;
  Future<File> _file() async =>
      File(p.join((await _directory()).path, 'background_download_job.json'));
  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    if (await file.length() > 8 * 1024 * 1024) {
      throw const FormatException('Job too large');
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String value) async {
    if (utf8.encode(value).length > 8 * 1024 * 1024) {
      throw const FormatException('Job too large');
    }
    final file = await _file();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(value, flush: true);
    await temp.rename(file.path);
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) await file.delete();
  }
}

abstract class DownloadForeground {
  Future<void> start({
    required String title,
    required String progress,
    required String stop,
    required int done,
    required int total,
  });
  Future<void> update(int done, int total);
  Future<void> stop();
  void onCancel(void Function()? callback);
}

class AndroidDownloadForeground implements DownloadForeground {
  static const channel = MethodChannel(
    'com.example.symphonium_clone/background_downloads',
  );
  @override
  void onCancel(void Function()? callback) {
    channel.setMethodCallHandler(
      callback == null
          ? null
          : (call) async {
              if (call.method == 'cancel' || call.method == 'stopped') {
                callback();
              }
            },
    );
  }

  @override
  Future<void> start({
    required String title,
    required String progress,
    required String stop,
    required int done,
    required int total,
  }) async {
    final allowed = await channel.invokeMethod<bool>('permission') ?? false;
    if (!allowed) throw PlatformException(code: 'notification_denied');
    await channel
        .invokeMethod<void>('start', {
          'title': title,
          'progress': progress,
          'stop': stop,
          'done': done,
          'total': total,
        })
        .timeout(const Duration(seconds: 15));
  }

  @override
  Future<void> update(int done, int total) =>
      channel.invokeMethod<void>('update', {'done': done, 'total': total});
  @override
  Future<void> stop() => channel.invokeMethod<void>('stop');
}

class BackgroundDownloads extends ChangeNotifier {
  BackgroundDownloads({
    required this.store,
    required this.persistence,
    required this.foreground,
  });
  final OfflineStorage store;
  final DownloadJobPersistence persistence;
  final DownloadForeground foreground;
  List<AudioTrack> tracks = const [];
  int done = 0, failed = 0;
  // 0 = legacy unknown, 1 = success, 2 = failure.
  List<int> outcomes = const [];
  bool starting = false, saving = false;
  bool ready = false,
      running = false,
      stopping = false,
      networkBlocked = false,
      storageError = false;
  Future<void>? _loadFuture;
  Future<void> _saves = Future.value();
  Future<void>? _operation;
  bool get hasJob => tracks.isNotEmpty;
  bool get complete => hasJob && done >= tracks.length;
  Map<String, Object?> _track(AudioTrack t) => {
    'id': t.id,
    'uri': t.uri,
    'title': t.title,
    'artist': t.artist,
    'album': t.album,
    'durationMs': t.durationMs,
    'folder': t.folder,
    'modifiedSeconds': t.modifiedSeconds,
    'coverId': t.coverId,
    'genre': t.genre,
    'year': t.year,
  };
  bool _eligible(AudioTrack t) {
    final u = Uri.tryParse(t.uri);
    return u != null &&
        u.scheme == 'aura' &&
        u.host == 'navidrome' &&
        u.pathSegments.length == 2 &&
        u.pathSegments.every((s) => s.isNotEmpty) &&
        !u.hasQuery &&
        !u.hasFragment &&
        u.userInfo.isEmpty;
  }

  String _encode() => jsonEncode({
    'version': 1,
    'done': done,
    'failed': failed,
    'outcomes': outcomes,
    'tracks': tracks.map(_track).toList(),
  });
  Future<void> _save() {
    final snapshot = _encode();
    final result = _saves.then((_) => persistence.write(snapshot));
    _saves = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> load() => _loadFuture ??= _load();
  Future<void> _load() async {
    try {
      final text = await persistence.read();
      if (text != null) {
        final json = jsonDecode(text);
        if (json is! Map ||
            json['version'] != 1 ||
            json['tracks'] is! List ||
            json['done'] is! int ||
            json['failed'] is! int) {
          throw const FormatException('Invalid job');
        }
        final rows = json['tracks'] as List;
        if (rows.isEmpty || rows.length > 5000 || rows.any((r) => r is! Map)) {
          throw const FormatException('Invalid job');
        }
        final restored = rows
            .map(
              (r) => AudioTrack.fromMap(Map<Object?, Object?>.from(r as Map)),
            )
            .toList(growable: false);
        if (restored.any((t) => !_eligible(t)) ||
            restored.map((t) => t.uri).toSet().length != restored.length) {
          throw const FormatException('Invalid job');
        }
        final count = json['done'] as int, errors = json['failed'] as int;
        if (count < 0 ||
            count > restored.length ||
            errors < 0 ||
            errors > count) {
          throw const FormatException('Invalid progress');
        }
        final rawOutcomes = json['outcomes'];
        final List<int> restoredOutcomes;
        if (rawOutcomes == null) {
          restoredOutcomes = List.filled(
            count,
            errors == 0 ? 1 : 0,
            growable: true,
          );
        } else {
          if (rawOutcomes is! List ||
              rawOutcomes.length != count ||
              rawOutcomes.any((v) => v is! int || v < 0 || v > 2)) {
            throw const FormatException('Invalid outcomes');
          }
          restoredOutcomes = List<int>.from(rawOutcomes);
          final knownFailures = restoredOutcomes.where((v) => v == 2).length;
          final unknown = restoredOutcomes.where((v) => v == 0).length;
          if (errors < knownFailures || errors > knownFailures + unknown) {
            throw const FormatException('Invalid failure count');
          }
        }
        tracks = restored;
        done = count;
        failed = errors;
        outcomes = restoredOutcomes;
      }
    } catch (_) {
      storageError = true;
    }
    ready = true;
    notifyListeners();
  }

  Future<void> create(List<AudioTrack> items) async {
    await load();
    if (storageError ||
        saving ||
        starting ||
        running ||
        (hasJob && !complete)) {
      throw StateError('Existing or unreadable job');
    }
    final unique = <String, AudioTrack>{};
    for (final t in items) {
      if (_eligible(t)) unique.putIfAbsent(t.uri, () => t);
    }
    if (unique.isEmpty || unique.length > 5000) {
      throw const FormatException('Invalid track selection');
    }
    final oldTracks = tracks, oldDone = done, oldFailed = failed;
    final oldOutcomes = outcomes;
    saving = true;
    tracks = List.unmodifiable(unique.values);
    done = 0;
    failed = 0;
    outcomes = [];
    notifyListeners();
    try {
      await _save();
    } catch (_) {
      tracks = oldTracks;
      done = oldDone;
      failed = oldFailed;
      outcomes = oldOutcomes;
      rethrow;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> resume({
    required String title,
    required String progress,
    required String stop,
  }) async {
    await load();
    if (!ready ||
        storageError ||
        saving ||
        starting ||
        running ||
        !hasJob ||
        complete) {
      throw StateError('Job cannot be resumed');
    }
    stopping = false;
    networkBlocked = false;
    storageError = false;
    starting = true;
    foreground.onCancel(requestStop);
    notifyListeners();
    try {
      await foreground.start(
        title: title,
        progress: progress,
        stop: stop,
        done: done,
        total: tracks.length,
      );
    } catch (_) {
      starting = false;
      foreground.onCancel(null);
      try {
        await foreground.stop();
      } catch (_) {}
      notifyListeners();
      rethrow;
    }
    starting = false;
    running = true;
    foreground.onCancel(requestStop);
    notifyListeners();
    _operation = _run();
    unawaited(_operation);
  }

  void requestStop() {
    if ((running || starting) && !stopping) {
      stopping = true;
      notifyListeners();
    }
  }

  /// Prepares a manual retry without starting a transfer.
  Future<void> retryFailures() async {
    await load();
    if (!complete ||
        failed == 0 ||
        storageError ||
        saving ||
        starting ||
        running) {
      throw StateError('No completed failures to retry');
    }
    final retryTracks = <AudioTrack>[
      for (var i = 0; i < done; i++)
        if (outcomes[i] == 0 || outcomes[i] == 2) tracks[i],
    ];
    if (retryTracks.isEmpty) throw StateError('No retryable tracks');
    await create(retryTracks);
  }

  Future<void> _run() async {
    try {
      while (done < tracks.length && !stopping) {
        var error = false;
        try {
          await store.download(tracks[done]);
        } on DownloadNetworkException {
          networkBlocked = true;
          break;
        } catch (_) {
          error = true;
        }
        done++;
        outcomes.add(error ? 2 : 1);
        if (error) failed++;
        try {
          await _save();
        } catch (_) {
          storageError = true;
          break;
        }
        try {
          await foreground.update(done, tracks.length);
        } catch (_) {
          stopping = true;
        }
        notifyListeners();
      }
    } finally {
      running = false;
      stopping = false;
      foreground.onCancel(null);
      try {
        await foreground.stop();
      } catch (_) {}
      notifyListeners();
    }
  }

  Future<void> discard() async {
    await load();
    if (saving || starting || running) throw StateError('Job running');
    await persistence.clear();
    tracks = const [];
    done = 0;
    failed = 0;
    outcomes = [];
    storageError = false;
    networkBlocked = false;
    notifyListeners();
  }

  Future<void> waitForCompletion() async => await _operation;
}
