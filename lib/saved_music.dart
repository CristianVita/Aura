import 'audio_features.dart';
import 'audio_library.dart';

import 'dart:convert';

import 'package:flutter/widgets.dart';

import 'audio_track.dart';

enum RatingOrder { original, highest, lowest }

enum RatingStarSize { small, medium, large }

String formatRating(num rating) => rating == rating.roundToDouble()
    ? rating.toInt().toString()
    : rating.toString().replaceAll('.', ',');

bool _validRating(num value) =>
    value.isFinite && value >= 0 && value <= 5 && (value * 2) % 1 == 0;

class MusicPlaylist {
  MusicPlaylist({
    required this.id,
    required this.name,
    Iterable<String> tracks = const [],
  }) : tracks = List.unmodifiable(tracks.toSet());
  final String id;
  final String name;
  final List<String> tracks;
  MusicPlaylist copy({String? name, Iterable<String>? tracks}) => MusicPlaylist(
    id: id,
    name: name ?? this.name,
    tracks: tracks ?? this.tracks,
  );
  Map<String, Object> toJson() => {'id': id, 'name': name, 'tracks': tracks};
}

class SavedMusicData {
  SavedMusicData({
    Iterable<String> favorites = const [],
    Iterable<MusicPlaylist> playlists = const [],
    Map<String, num> ratings = const {},
    this.minimumRating = 0,
    this.ratingOrder = RatingOrder.original,
    this.starSize = RatingStarSize.medium,
    this.audioFeatures = const AudioFeatures(),
    this.playbackSpeed = 1,
    this.playbackVolume = 1,
  }) : favorites = Set.unmodifiable(favorites),
       playlists = List.unmodifiable(playlists),
       ratings = Map.unmodifiable(
         ratings.map((key, value) => MapEntry(key, value.toDouble())),
       );
  final Set<String> favorites;
  final List<MusicPlaylist> playlists;
  final Map<String, double> ratings;
  final double minimumRating;
  final RatingOrder ratingOrder;
  final RatingStarSize starSize;
  final AudioFeatures audioFeatures;
  final double playbackSpeed;
  final double playbackVolume;
  double ratingOf(String uri) => ratings[uri] ?? 0;

  SavedMusicData copy({
    Iterable<String>? favorites,
    Iterable<MusicPlaylist>? playlists,
    Map<String, num>? ratings,
    double? minimumRating,
    RatingOrder? ratingOrder,
    RatingStarSize? starSize,
    AudioFeatures? audioFeatures,
    double? playbackSpeed,
    double? playbackVolume,
  }) => SavedMusicData(
    favorites: favorites ?? this.favorites,
    playlists: playlists ?? this.playlists,
    ratings: ratings ?? this.ratings,
    minimumRating: minimumRating ?? this.minimumRating,
    ratingOrder: ratingOrder ?? this.ratingOrder,
    starSize: starSize ?? this.starSize,
    audioFeatures: audioFeatures ?? this.audioFeatures,
    playbackSpeed: playbackSpeed ?? this.playbackSpeed,
    playbackVolume: playbackVolume ?? this.playbackVolume,
  );

  /// Ratings change browsing only; an existing playback queue stays intact.
  List<AudioTrack> ratedTracks(Iterable<AudioTrack> tracks) {
    final result = tracks
        .where((track) => ratingOf(track.uri) >= minimumRating)
        .toList();
    if (ratingOrder != RatingOrder.original) {
      result.sort((a, b) {
        final left = ratingOf(a.uri), right = ratingOf(b.uri);
        if (left == 0 && right != 0) return 1;
        if (right == 0 && left != 0) return -1;
        final rating = ratingOrder == RatingOrder.highest
            ? right.compareTo(left)
            : left.compareTo(right);
        if (rating != 0) return rating;
        final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return title != 0 ? title : a.uri.compareTo(b.uri);
      });
    }
    return result;
  }

  String encode() => jsonEncode({
    'version': 1,
    'favorites': favorites.toList(),
    'playlists': playlists.map((p) => p.toJson()).toList(),
    'ratings': ratings,
    'minimumRating': minimumRating,
    'ratingOrder': ratingOrder.name,
    'starSize': starSize.name,
    'audioFeatures': audioFeatures.toJson(),
    'playbackSpeed': playbackSpeed,
    'playbackVolume': playbackVolume,
  });
  factory SavedMusicData.decode(String value) {
    final root = jsonDecode(value) as Map<String, dynamic>;
    if (root['version'] != 1) {
      throw const FormatException('Unsupported saved music version');
    }
    final favorites = (root['favorites'] as List).cast<String>();
    final playlists = (root['playlists'] as List).map((row) {
      final p = row as Map<String, dynamic>;
      final name = p['name'] as String;
      final id = p['id'] as String;
      if (name.trim().isEmpty || id.isEmpty) {
        throw const FormatException('Invalid playlist');
      }
      return MusicPlaylist(
        id: id,
        name: name,
        tracks: (p['tracks'] as List).cast<String>(),
      );
    }).toList();
    if (playlists.map((p) => p.id).toSet().length != playlists.length) {
      throw const FormatException('Duplicate playlist IDs');
    }
    final ratings = (root['ratings'] as Map<String, dynamic>? ?? {}).map((
      uri,
      value,
    ) {
      if (uri.isEmpty || value is! num || !_validRating(value) || value == 0) {
        throw const FormatException('Invalid track rating');
      }
      return MapEntry(uri, value.toDouble());
    });
    final minimum = root['minimumRating'] ?? 0;
    if (minimum is! num || !_validRating(minimum)) {
      throw const FormatException('Invalid rating filter');
    }
    final speed = root['playbackSpeed'] ?? 1;
    final volume = root['playbackVolume'] ?? 1;
    if (speed is! num ||
        !speed.isFinite ||
        speed < .5 ||
        speed > 2 ||
        volume is! num ||
        !volume.isFinite ||
        volume < 0 ||
        volume > 1) {
      throw const FormatException('Invalid playback preferences');
    }
    return SavedMusicData(
      audioFeatures: AudioFeatures.fromJson(
        root['audioFeatures'] as Map<String, dynamic>? ?? {},
      ),
      playbackSpeed: speed.toDouble(),
      playbackVolume: volume.toDouble(),
      favorites: favorites,
      playlists: playlists,
      ratings: ratings,
      minimumRating: minimum.toDouble(),
      ratingOrder: RatingOrder.values.byName(
        root['ratingOrder'] as String? ?? 'original',
      ),
      starSize: RatingStarSize.values.byName(
        root['starSize'] as String? ?? 'medium',
      ),
    );
  }
}

abstract class SavedMusicStorage {
  Future<String?> read();
  Future<void> write(String json);
}

class DeviceSavedMusicStorage implements SavedMusicStorage {
  static const _channel = AudioLibrary();
  @override
  Future<String?> read() => _channel.invokeMethod<String>('loadSavedMusic');
  @override
  Future<void> write(String json) =>
      _channel.invokeMethod<void>('saveSavedMusic', {'json': json});
}

class SavedMusicStore extends ChangeNotifier {
  SavedMusicStore(this.storage);
  final SavedMusicStorage storage;
  SavedMusicData _data = SavedMusicData();
  SavedMusicData get data => _data;
  bool ready = false;
  bool loadFailed = false;
  bool _disposed = false;
  int _counter = 0;
  Future<void> _pending = Future.value();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    ready = false;
    loadFailed = false;
    _notify();
    try {
      final saved = await storage.read();
      _data = saved == null ? SavedMusicData() : SavedMusicData.decode(saved);
      ready = true;
    } catch (_) {
      loadFailed = true;
    }
    _notify();
  }

  Future<void> _update(SavedMusicData Function(SavedMusicData) change) {
    final operation = _pending.then((_) async {
      if (!ready) throw StateError('Saved music unavailable');
      final next = change(_data);
      // Publish only after durable storage succeeds. A failed write cannot
      // erase previous state or poison the next queued edit.
      await storage.write(next.encode());
      _data = next;
      _notify();
    });
    _pending = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> toggleFavorite(String uri) => _update((data) {
    final favorites = {...data.favorites};
    if (!favorites.remove(uri)) favorites.add(uri);
    return data.copy(favorites: favorites);
  });

  Future<void> setRating(String uri, num rating) => _update((data) {
    if (uri.isEmpty || !_validRating(rating)) {
      throw ArgumentError('Invalid rating');
    }
    final ratings = {...data.ratings};
    if (rating == 0) {
      ratings.remove(uri);
    } else {
      ratings[uri] = rating.toDouble();
    }
    return data.copy(ratings: ratings);
  });

  Future<void> setRatingView({double? minimum, RatingOrder? order}) =>
      _update((data) {
        if (minimum != null && !_validRating(minimum)) {
          throw ArgumentError('Invalid rating filter');
        }
        return data.copy(minimumRating: minimum, ratingOrder: order);
      });

  Future<void> setStarSize(RatingStarSize size) =>
      _update((data) => data.copy(starSize: size));

  Future<void> setPlaybackPreferences({double? speed, double? volume}) =>
      _update((data) {
        if ((speed != null && (!speed.isFinite || speed < .5 || speed > 2)) ||
            (volume != null &&
                (!volume.isFinite || volume < 0 || volume > 1))) {
          throw ArgumentError('Invalid playback preferences');
        }
        return data.copy(playbackSpeed: speed, playbackVolume: volume);
      });

  Future<void> setAudioFeatures(AudioFeatures features) => _update(
    (data) =>
        data.copy(audioFeatures: AudioFeatures.fromJson(features.toJson())),
  );

  String _validName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 80) {
      throw ArgumentError('Invalid name');
    }
    return trimmed;
  }

  Future<String> createPlaylist(
    String name, {
    Iterable<String> tracks = const [],
  }) async {
    final clean = _validName(name);
    final id = '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
    await _update(
      (data) => data.copy(
        playlists: [
          ...data.playlists,
          MusicPlaylist(id: id, name: clean, tracks: tracks),
        ],
      ),
    );
    return id;
  }

  Future<void> _editPlaylist(
    String id,
    MusicPlaylist Function(MusicPlaylist) edit,
  ) => _update((data) {
    if (!data.playlists.any((p) => p.id == id)) {
      throw StateError('Playlist removed');
    }
    return data.copy(
      playlists: data.playlists.map((p) => p.id == id ? edit(p) : p),
    );
  });
  Future<void> renamePlaylist(String id, String name) =>
      _editPlaylist(id, (p) => p.copy(name: _validName(name)));
  Future<void> addTrack(String id, String uri) =>
      _editPlaylist(id, (p) => p.copy(tracks: [...p.tracks, uri]));
  Future<void> removeTrack(String id, String uri) =>
      _editPlaylist(id, (p) => p.copy(tracks: p.tracks.where((t) => t != uri)));
  Future<void> setTracks(String id, Iterable<String> uris) =>
      _editPlaylist(id, (p) => p.copy(tracks: uris));
  Future<void> deletePlaylist(String id) => _update(
    (data) => data.copy(playlists: data.playlists.where((p) => p.id != id)),
  );

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class SavedMusicScope extends InheritedNotifier<SavedMusicStore> {
  const SavedMusicScope({
    super.key,
    required SavedMusicStore store,
    required super.child,
  }) : super(notifier: store);
  static SavedMusicStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SavedMusicScope>()!.notifier!;
}
