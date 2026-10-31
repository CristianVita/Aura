import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:aura/audio_track.dart';

void main() {
  test(
    'Queue metadata preserves the cover revision and folder after edits',
    () {
      const track = AudioTrack(
        id: '42',
        title: 'A',
        artist: 'B',
        album: 'C',
        durationMs: 123000,
        uri: 'content://media/external/audio/media/42',
        folder: 'Music/Albums/',
        modifiedSeconds: 7654,
      );
      final source = AudioSource.uri(
        Uri.parse(track.uri),
        tag: track.toMediaItem(),
      );
      final restored = audioTrackOf(source as IndexedAudioSource)!;
      expect(restored.id, track.id);
      expect(restored.title, track.title);
      expect(restored.artist, track.artist);
      expect(restored.album, track.album);
      expect(restored.durationMs, track.durationMs);
      expect(restored.folder, track.folder);
      expect(restored.artworkKey, track.artworkKey);
      expect(restored.artworkUri, track.artworkUri);
    },
  );

  test('An empty queue has no current track', () {
    expect(audioTrackOf(null), isNull);
  });
}
