import 'package:just_audio/just_audio.dart';

import 'audio_library.dart';
import 'audio_track.dart';

Future<AudioSource> sourceForTrack(AudioTrack track) async {
  var uri = Uri.parse(track.uri);
  if (uri.scheme == 'aura') {
    uri = Uri.parse(
      (await const AudioLibrary().invokeMethod<String>('resolvePlaybackUri', {
        'uri': track.uri,
      }))!,
    );
  }
  return AudioSource.uri(uri, tag: track.toMediaItem());
}
