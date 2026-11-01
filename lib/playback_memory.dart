import 'audio_library.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_track.dart';

class LibraryFilters {
  const LibraryFilters({this.minimumSeconds = 0, this.hideMessaging = false});
  final int minimumSeconds;
  final bool hideMessaging;
  bool includes(AudioTrack track) {
    final folder = track.folder.replaceAll('\\', '/').toLowerCase();
    if (hideMessaging &&
        folder
            .split('/')
            .any(
              (part) => part.contains('whatsapp') || part.contains('telegram'),
            )) {
      return false;
    }
    return minimumSeconds == 0 ||
        track.durationMs <= 0 ||
        track.durationMs >= minimumSeconds * 1000;
  }

  Map<String, Object> toJson() => {
    'minimumSeconds': minimumSeconds,
    'hideMessaging': hideMessaging,
  };
  factory LibraryFilters.fromJson(Map<String, dynamic> json) {
    final minimum = json['minimumSeconds'] as int;
    if (![0, 10, 30, 60].contains(minimum)) {
      throw const FormatException('Invalid filter');
    }
    return LibraryFilters(
      minimumSeconds: minimum,
      hideMessaging: json['hideMessaging'] as bool,
    );
  }
}

class ListeningEntry {
  const ListeningEntry({
    required this.uri,
    required this.lastPlayedMs,
    required this.playCount,
  });
  final String uri;
  final int lastPlayedMs;
  final int playCount;
  Map<String, Object> toJson() => {
    'uri': uri,
    'lastPlayedMs': lastPlayedMs,
    'playCount': playCount,
  };
  factory ListeningEntry.fromJson(Map<String, dynamic> json) => ListeningEntry(
    uri: json['uri'] as String,
    lastPlayedMs: json['lastPlayedMs'] as int,
    playCount: json['playCount'] as int,
  );
}

class PlaybackSession {
  PlaybackSession({
    required Iterable<String> uris,
    required this.index,
    required this.positionMs,
    required this.shuffle,
    required Iterable<int> order,
    required this.loop,
  }) : uris = List.unmodifiable(uris),
       order = List.unmodifiable(order);
  final List<String> uris;
  final int index;
  final int positionMs;
  final bool shuffle;
  final List<int> order;
  final LoopMode loop;
  Map<String, Object> toJson() => {
    'uris': uris,
    'index': index,
    'positionMs': positionMs,
    'shuffle': shuffle,
    'order': order,
    'loop': loop.name,
  };
  factory PlaybackSession.fromJson(Map<String, dynamic> json) {
    final uris = (json['uris'] as List).cast<String>();
    final index = json['index'] as int;
    final position = json['positionMs'] as int;
    final order = (json['order'] as List).cast<int>();
    if ((uris.isNotEmpty && (index < 0 || index >= uris.length)) ||
        position < 0 ||
        order.length != uris.length ||
        order.toSet().length != uris.length ||
        order.any((i) => i < 0 || i >= uris.length)) {
      throw const FormatException('Invalid queue');
    }
    return PlaybackSession(
      uris: uris,
      index: index,
      positionMs: position,
      shuffle: json['shuffle'] as bool,
      order: order,
      loop: LoopMode.values.byName(json['loop'] as String),
    );
  }

  /// Retain duplicates and map shuffle indices when files disappear. Folder
  /// filters affect browsing; they never silently rewrite an existing queue.
  RestoredSession resolve(List<AudioTrack> library) {
    final byUri = {for (final track in library) track.uri: track};
    final remap = <int, int>{};
    final tracks = <AudioTrack>[];
    for (var i = 0; i < uris.length; i++) {
      final track = byUri[uris[i]];
      if (track != null) {
        remap[i] = tracks.length;
        tracks.add(track);
      }
    }
    final restoredOrder = order
        .where(remap.containsKey)
        .map((i) => remap[i]!)
        .toList();
    var nextIndex = remap[index];
    if (nextIndex == null && tracks.isNotEmpty) {
      final effective = shuffle ? order : List.generate(uris.length, (i) => i);
      final ahead = effective
          .skip(effective.indexOf(index) + 1)
          .where(remap.containsKey);
      nextIndex = ahead.isNotEmpty
          ? remap[ahead.first]
          : remap[effective.reversed.firstWhere(remap.containsKey)];
    }
    var position = nextIndex != null && remap[index] != null ? positionMs : 0;
    if (nextIndex != null && tracks[nextIndex].durationMs > 0) {
      position = position.clamp(0, tracks[nextIndex].durationMs);
    }
    return RestoredSession(
      tracks: tracks,
      index: nextIndex ?? 0,
      positionMs: position,
      order: restoredOrder,
      shuffle: shuffle,
      loop: loop,
    );
  }
}

class RestoredSession {
  const RestoredSession({
    required this.tracks,
    required this.index,
    required this.positionMs,
    required this.order,
    required this.shuffle,
    required this.loop,
  });
  final List<AudioTrack> tracks;
  final int index;
  final int positionMs;
  final List<int> order;
  final bool shuffle;
  final LoopMode loop;
}

/// Uses the saved permutation on the first load and normal shuffling thereafter.
class RestoredShuffleOrder extends DefaultShuffleOrder {
  RestoredShuffleOrder(List<int> saved) : _saved = List.of(saved);
  List<int>? _saved;
  @override
  void shuffle({int? initialIndex}) {
    final saved = _saved;
    if (saved != null && saved.length == indices.length) {
      indices
        ..clear()
        ..addAll(saved);
      _saved = null;
    } else {
      super.shuffle(initialIndex: initialIndex);
    }
  }
}

class PlaybackMemoryData {
  PlaybackMemoryData({
    Iterable<ListeningEntry> history = const [],
    this.session,
    this.filters = const LibraryFilters(),
  }) : history = List.unmodifiable(history);
  final List<ListeningEntry> history;
  final PlaybackSession? session;
  final LibraryFilters filters;
  String encode() => jsonEncode({
    'version': 1,
    'history': history.map((e) => e.toJson()).toList(),
    'session': session?.toJson(),
    'filters': filters.toJson(),
  });
  factory PlaybackMemoryData.decode(String value) {
    final json = jsonDecode(value) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Unsupported memory version');
    }
    return PlaybackMemoryData(
      history: (json['history'] as List).map(
        (e) => ListeningEntry.fromJson(e as Map<String, dynamic>),
      ),
      session: json['session'] == null
          ? null
          : PlaybackSession.fromJson(json['session'] as Map<String, dynamic>),
      filters: LibraryFilters.fromJson(json['filters'] as Map<String, dynamic>),
    );
  }
}

abstract class PlaybackMemoryStorage {
  Future<String?> read();
  Future<void> write(String json);
}

class DevicePlaybackMemoryStorage implements PlaybackMemoryStorage {
  static const _channel = AudioLibrary();
  @override
  Future<String?> read() => _channel.invokeMethod<String>('loadPlaybackMemory');
  @override
  Future<void> write(String json) =>
      _channel.invokeMethod<void>('savePlaybackMemory', {'json': json});
}

class PlaybackMemoryStore extends ChangeNotifier {
  PlaybackMemoryStore(this.storage);
  final PlaybackMemoryStorage storage;
  PlaybackMemoryData data = PlaybackMemoryData();
  bool ready = false;
  bool failed = false;
  bool _disposed = false;
  Future<void> _pending = Future.value();
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    try {
      final saved = await storage.read();
      data = saved == null
          ? PlaybackMemoryData()
          : PlaybackMemoryData.decode(saved);
      ready = true;
    } catch (_) {
      failed = true;
    }
    _notify();
  }

  Future<void> _update(
    PlaybackMemoryData Function(PlaybackMemoryData) change, {
    bool notify = true,
  }) {
    final operation = _pending.then((_) async {
      if (!ready) throw StateError('Memory unavailable');
      final next = change(data);
      await storage.write(next.encode());
      data = next;
      if (notify) _notify();
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> saveSession(PlaybackSession session) => _update(
    (d) => PlaybackMemoryData(
      history: d.history,
      filters: d.filters,
      session: session,
    ),
    notify: false,
  );
  Future<void> setFilters(LibraryFilters filters) => _update(
    (d) => PlaybackMemoryData(
      history: d.history,
      filters: filters,
      session: d.session,
    ),
  );
  Future<void> record(String uri, DateTime when) => _update((d) {
    final previous = d.history.where((e) => e.uri == uri).firstOrNull;
    return PlaybackMemoryData(
      session: d.session,
      filters: d.filters,
      history: [
        ListeningEntry(
          uri: uri,
          lastPlayedMs: when.millisecondsSinceEpoch,
          playCount: (previous?.playCount ?? 0) + 1,
        ),
        ...d.history.where((e) => e.uri != uri).take(99),
      ],
    );
  });
  Future<void> clearHistory() => _update(
    (d) => PlaybackMemoryData(session: d.session, filters: d.filters),
  );
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Counts listening time, never the seek position. Pauses and restoring a
/// session do not create history entries; short tracks count on completion.
class ListeningProgress {
  String? _uri;
  Duration _heard = Duration.zero;
  bool _recorded = false;
  String? advance(
    String? uri,
    Duration elapsed, {
    bool completed = false,
    int durationMs = 0,
  }) {
    if (uri != _uri) {
      _uri = uri;
      _heard = Duration.zero;
      _recorded = false;
    }
    if (uri == null || _recorded) return null;
    _heard += elapsed;
    final shortTrackHeard =
        durationMs > 0 &&
        durationMs < 5000 &&
        _heard.inMilliseconds >= (durationMs - 100).clamp(500, 5000);
    if (_heard >= const Duration(seconds: 5) ||
        shortTrackHeard ||
        (completed && _heard >= const Duration(milliseconds: 500))) {
      _recorded = true;
      return uri;
    }
    return null;
  }

  void restart() {
    _uri = null;
    _heard = Duration.zero;
    _recorded = false;
  }
}
