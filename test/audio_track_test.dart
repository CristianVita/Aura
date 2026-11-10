import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:aura/audio_track.dart';

void main() {
  test(
    'remote queue metadata retains logical identity and updated cover ID',
    () {
      const track = AudioTrack(
        id: 'song',
        title: 'Remote',
        artist: 'Artist',
        album: 'Album',
        durationMs: 12000,
        uri: 'aura://navidrome/server/song',
        coverId: 'cover-v2',
        genre: 'Metal',
      );
      final source = AudioSource.uri(
        Uri.parse('https://music.example/rest/stream.view?t=temporary-token'),
        tag: track.toMediaItem(),
      );
      final restored = audioTrackOf(source as IndexedAudioSource)!;
      expect(restored.uri, track.uri);
      expect(restored.coverId, 'cover-v2');
      expect(restored.genre, 'Metal');
      expect(AudioTrack.fromMap({'genre': 'Jazz'}).genre, 'Jazz');
      expect(AudioTrack.fromMap({}).genre, isEmpty);
      expect(restored.artworkUri.pathSegments, ['server', 'cover-v2']);
      expect(restored.artworkKey, contains('cover-v2'));
      expect(restored.toMediaItem().id, isNot(contains('temporary-token')));
    },
  );
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

  test(
    'Display title survives queue metadata without altering original title',
    () {
      const track = AudioTrack(
        id: '1',
        title: 'Original',
        artist: '',
        album: '',
        durationMs: 0,
        uri: 'content://media/external/audio/media/1',
      );
      final renamed = track.withDisplayTitle('Chosen name');
      final source = AudioSource.uri(
        Uri.parse(track.uri),
        tag: renamed.toMediaItem(),
      );
      final restored = audioTrackOf(source as IndexedAudioSource)!;
      expect(restored.title, 'Original');
      expect(restored.displayTitle, 'Chosen name');
      expect(restored.toMediaItem().title, 'Chosen name');
    },
  );

  test('An empty queue has no current track', () {
    expect(audioTrackOf(null), isNull);
  });
}
