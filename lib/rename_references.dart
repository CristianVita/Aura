import 'package:aura/playback_memory.dart';
import 'package:aura/saved_music.dart';

/// Computes updated references without changing or writing the source state.
({SavedMusicData saved, PlaybackMemoryData memory}) remapRenamedTrack({
  required SavedMusicData saved,
  required PlaybackMemoryData memory,
  required String oldUri,
  required String newUri,
}) {
  if (oldUri.isEmpty || newUri.isEmpty || oldUri == newUri) {
    throw ArgumentError('Invalid track identity');
  }
  final occupied =
      saved.favorites.contains(newUri) ||
      saved.ratings.containsKey(newUri) ||
      saved.playlists.any((playlist) => playlist.tracks.contains(newUri)) ||
      memory.history.any((entry) => entry.uri == newUri) ||
      (memory.session?.uris.contains(newUri) ?? false);
  if (occupied) throw StateError('Destination already referenced');
  String map(String uri) => uri == oldUri ? newUri : uri;
  final session = memory.session;
  return (
    saved: saved.copy(
      favorites: saved.favorites.map(map),
      ratings: {
        for (final entry in saved.ratings.entries) map(entry.key): entry.value,
      },
      playlists: [
        for (final playlist in saved.playlists)
          playlist.copy(tracks: playlist.tracks.map(map)),
      ],
    ),
    memory: PlaybackMemoryData(
      filters: memory.filters,
      history: [
        for (final entry in memory.history)
          ListeningEntry(
            uri: map(entry.uri),
            lastPlayedMs: entry.lastPlayedMs,
            playCount: entry.playCount,
          ),
      ],
      session: session == null
          ? null
          : PlaybackSession(
              uris: session.uris.map(map),
              index: session.index,
              positionMs: session.positionMs,
              shuffle: session.shuffle,
              order: session.order,
              loop: session.loop,
            ),
    ),
  );
}
