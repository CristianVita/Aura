import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
    required this.uri,
    this.folder = '',
    this.modifiedSeconds = 0,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String uri;
  final String folder;
  final int modifiedSeconds;
  String get artworkKey => '$uri:$modifiedSeconds';
  Uri get artworkUri => Uri(
    scheme: 'content',
    host: 'com.example.symphonium_clone.artwork',
    path: '/$id/$modifiedSeconds',
  );

  MediaItem toMediaItem() => MediaItem(
    id: uri,
    title: title,
    artist: artist.isEmpty ? 'Artist necunoscut' : artist,
    album: album.isEmpty ? null : album,
    artUri: artworkUri,
    duration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
    extras: {
      'trackId': id,
      'folder': folder,
      'modifiedSeconds': modifiedSeconds,
    },
  );

  factory AudioTrack.fromMap(Map<Object?, Object?> map) {
    return AudioTrack(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? 'Piesă fără titlu',
      artist: map['artist']?.toString() ?? '',
      album: map['album']?.toString() ?? '',
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      uri: map['uri']?.toString() ?? '',
      folder: map['folder']?.toString() ?? '',
      modifiedSeconds: (map['modifiedSeconds'] as num?)?.toInt() ?? 0,
    );
  }
}

AudioTrack? audioTrackOf(IndexedAudioSource? source) {
  final item = source?.tag;
  if (item is! MediaItem) return null;
  return AudioTrack(
    id:
        item.extras?['trackId']?.toString() ??
        Uri.parse(item.id).pathSegments.last,
    title: item.title,
    artist: item.artist ?? '',
    album: item.album ?? '',
    durationMs: item.duration?.inMilliseconds ?? 0,
    uri: item.id,
    folder: item.extras?['folder']?.toString() ?? '',
    modifiedSeconds: (item.extras?['modifiedSeconds'] as num?)?.toInt() ?? 0,
  );
}
