import 'dart:convert';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:crypto/crypto.dart';

import 'audio_track.dart';

/// A local snapshot for a future car media browser. No network or playback is
/// started here; the hosting audio handler must resolve and play selected IDs.
class CarMediaCatalog {
  CarMediaCatalog({
    required Iterable<AudioTrack> tracks,
    required Set<String> favoriteUris,
    required this.allTracksLabel,
    required this.favoritesLabel,
  }) {
    final unique = <String, AudioTrack>{};
    for (final track in tracks) {
      if (track.uri.isNotEmpty) unique.putIfAbsent(track.uri, () => track);
    }
    final byId = <String, AudioTrack>{};
    final ids = <String>[];
    final favorites = <String>[];
    for (final track in unique.values) {
      final id = 'track:${sha256.convert(utf8.encode(track.uri))}';
      if (byId.containsKey(id)) {
        throw StateError('Media ID collision');
      }
      byId[id] = track;
      ids.add(id);
      if (favoriteUris.contains(track.uri)) favorites.add(id);
    }
    _tracksById = Map.unmodifiable(byId);
    _allTrackIds = List.unmodifiable(ids);
    _favoriteTrackIds = List.unmodifiable(favorites);
  }

  static const rootId = 'root';
  static const allTracksId = 'aura:tracks';
  static const favoritesId = 'aura:favorites';
  static const maxPageSize = 100;

  final String allTracksLabel;
  final String favoritesLabel;
  late final Map<String, AudioTrack> _tracksById;
  late final List<String> _allTrackIds;
  late final List<String> _favoriteTrackIds;

  AudioTrack? trackForId(String id) => _tracksById[id];

  /// Returns one bounded page; [offset] is the zero-based item offset.
  List<MediaItem> children(String parentId, {int offset = 0, int limit = 50}) {
    if (offset < 0 || limit < 1 || limit > maxPageSize) {
      throw RangeError('Invalid page');
    }
    if (parentId == rootId) {
      final roots = <MediaItem>[
        MediaItem(id: allTracksId, title: allTracksLabel, playable: false),
        MediaItem(id: favoritesId, title: favoritesLabel, playable: false),
      ];
      if (offset >= roots.length) return const [];
      return roots.sublist(offset, math.min(offset + limit, roots.length));
    }
    final ids = switch (parentId) {
      allTracksId => _allTrackIds,
      favoritesId => _favoriteTrackIds,
      _ => const <String>[],
    };
    if (offset >= ids.length) return const [];
    return ids
        .sublist(offset, math.min(offset + limit, ids.length))
        .map((id) {
          final track = _tracksById[id]!;
          return MediaItem(
            id: id,
            title: track.displayTitle,
            artist: track.displayArtist,
            album: track.album,
            duration: track.durationMs > 0
                ? Duration(milliseconds: track.durationMs)
                : null,
            playable: true,
          );
        })
        .toList(growable: false);
  }
}
