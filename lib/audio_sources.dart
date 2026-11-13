import 'package:just_audio/just_audio.dart';

import 'audio_library.dart';
import 'audio_track.dart';
import 'cached_playback_source.dart';
import 'navidrome.dart';
import 'playback_cache.dart';

Future<AudioSource> sourceForTrack(
  AudioTrack track, {
  AudioLibrary library = const AudioLibrary(),
  PlaybackCache? cache,
  NavidromeStreamQuality quality = const NavidromeStreamQuality.original(),
}) async {
  var uri = Uri.parse(track.uri);
  if (uri.scheme == 'aura') {
    final activeCache = cache ?? playbackCache;
    if (quality.maxBitRateKbps == null) await activeCache.load();
    // Until cache keys include stream quality, limited streams bypass it.
    if (quality.maxBitRateKbps == null &&
        activeCache.enabled &&
        uri.host == 'navidrome' &&
        uri.pathSegments.length == 2) {
      final downloads = library.offlineStore ?? AudioLibrary.offline;
      if (!await downloads.hasRecord(track.uri)) {
        return CachedPlaybackSource(
          trackUri: track.uri,
          cache: activeCache,
          tag: track.toMediaItem(),
          resolve: () async => Uri.parse(
            (await library.invokeMethod<String>('resolvePlaybackUri', {
              'uri': track.uri,
            }))!,
          ),
        );
      }
    }
    uri = Uri.parse(
      (await library.invokeMethod<String>('resolvePlaybackUri', {
        'uri': track.uri,
        'quality': quality,
      }))!,
    );
  }
  return AudioSource.uri(uri, tag: track.toMediaItem());
}
