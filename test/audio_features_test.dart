import 'package:aura/audio_features.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

void main() {
  test(
    'old saved libraries keep safe transition and media command defaults',
    () {
      final saved = SavedMusicData.decode(
        '{"version":1,"favorites":["kept"],"playlists":[]}',
      );
      expect(saved.audioFeatures.crossfadeSeconds, 0);
      expect(saved.audioFeatures.equalizerEnabled, isFalse);
      expect(saved.audioFeatures.keepPausedOnSkip, isTrue);
      expect(saved.audioFeatures.seekButtons, isFalse);
    },
  );
  test('audio features survive concurrent rating and favorite edits', () async {
    final store = SavedMusicStore(MemorySavedMusicStorage());
    await store.load();
    await Future.wait([
      store.setAudioFeatures(
        const AudioFeatures(
          crossfadeSeconds: 3,
          fadeMilliseconds: 500,
          equalizerEnabled: true,
          bandGains: [4, 2, 0, -1, 0],
          seekButtons: true,
          headsetSeek: true,
          showStop: false,
        ),
      ),
      store.toggleFavorite('song'),
      store.setRating('song', 4.5),
    ]);
    final saved = SavedMusicData.decode(store.data.encode());
    expect(saved.audioFeatures.crossfadeSeconds, 3);
    expect(saved.audioFeatures.fadeMilliseconds, 500);
    expect(saved.audioFeatures.bandGains, [4, 2, 0, -1, 0]);
    expect(saved.audioFeatures.headsetSeek, isTrue);
    expect(saved.audioFeatures.showStop, isFalse);
    expect(saved.favorites, ['song']);
    expect(saved.ratingOf('song'), 4.5);
    store.dispose();
  });
  test(
    'invalid transition durations and equalizer values cannot be saved',
    () async {
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      for (final invalid in [
        const AudioFeatures(crossfadeSeconds: -1),
        const AudioFeatures(crossfadeSeconds: 11),
        const AudioFeatures(fadeMilliseconds: 2500),
        const AudioFeatures(bandGains: [16]),
        AudioFeatures(bandGains: [double.nan]),
      ]) {
        await expectLater(
          store.setAudioFeatures(invalid),
          throwsFormatException,
        );
      }
      expect(store.data.audioFeatures.crossfadeSeconds, 0);
      store.dispose();
    },
  );
}
