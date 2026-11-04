import 'app_language.dart';

import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';

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
    this.coverId = '',
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final String uri;
  final String folder;
  final int modifiedSeconds;
  final String coverId;
  String get displayTitle =>
      title.trim().isEmpty ? AppText.current.uiUntitledTrack : title;
  String get displayArtist =>
      artist.trim().isEmpty ? AppText.current.uiUnknownArtist : artist;
  String get artworkKey =>
      '$uri:$modifiedSeconds${coverId.isEmpty ? '' : ':$coverId'}';
  Uri get artworkUri => Uri.parse(uri).scheme == 'aura'
      ? Uri.parse(uri).replace(
          pathSegments: [Uri.parse(uri).pathSegments.first, coverId],
          queryParameters: {'artwork': 'true'},
        )
      : Uri.parse(uri).scheme == 'file'
      ? Uri.parse(uri)
      : Uri(
          scheme: 'content',
          host: 'com.example.symphonium_clone.artwork',
          path: '/$id/$modifiedSeconds',
        );

  MediaItem toMediaItem() => MediaItem(
    id: uri,
    title: displayTitle,
    artist: displayArtist,
    album: album.isEmpty ? null : album,
    artUri: Uri.parse(uri).scheme == 'aura' ? null : artworkUri,
    duration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
    extras: {
      'trackId': id,
      'originalTitle': title,
      'originalArtist': artist,
      'folder': folder,
      'modifiedSeconds': modifiedSeconds,
      'coverId': coverId,
    },
  );

  factory AudioTrack.fromMap(Map<Object?, Object?> map) {
    return AudioTrack(
      id: map['id']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      artist: map['artist']?.toString() ?? '',
      album: map['album']?.toString() ?? '',
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      uri: map['uri']?.toString() ?? '',
      folder: map['folder']?.toString() ?? '',
      modifiedSeconds: (map['modifiedSeconds'] as num?)?.toInt() ?? 0,
      coverId: map['coverId'] as String? ?? '',
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
    title: item.extras?['originalTitle'] as String? ?? item.title,
    artist: item.extras?['originalArtist'] as String? ?? item.artist ?? '',
    album: item.album ?? '',
    durationMs: item.duration?.inMilliseconds ?? 0,
    uri: item.id,
    folder: item.extras?['folder']?.toString() ?? '',
    modifiedSeconds: (item.extras?['modifiedSeconds'] as num?)?.toInt() ?? 0,
    coverId: item.extras?['coverId'] as String? ?? '',
  );
}
