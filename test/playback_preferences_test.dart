import 'dart:convert';

import 'package:aura/saved_music.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

void main() {
  test('legacy preferences default to normal speed and volume', () {
    final data = SavedMusicData.decode(
      '{"version":1,"favorites":["kept"],"playlists":[]}',
    );
    expect(data.playbackSpeed, 1);
    expect(data.playbackVolume, 1);
    expect(data.favorites, ['kept']);
  });
  test(
    'playback preferences survive favorite and rating edits and storage reload',
    () async {
      final storage = MemorySavedMusicStorage();
      final store = SavedMusicStore(storage);
      await store.load();
      await Future.wait([
        store.setPlaybackPreferences(speed: 1.25, volume: .6),
        store.toggleFavorite('song'),
        store.setRating('song', 4.5),
      ]);
      final loaded = SavedMusicData.decode(store.data.encode());
      expect(loaded.playbackSpeed, 1.25);
      expect(loaded.playbackVolume, .6);
      expect(loaded.favorites, ['song']);
      expect(loaded.ratingOf('song'), 4.5);
      storage.failNextWrite = true;
      await expectLater(
        store.setPlaybackPreferences(speed: 2),
        throwsStateError,
      );
      expect(store.data.playbackSpeed, 1.25);
      await store.setPlaybackPreferences(volume: .4);
      expect(store.data.playbackVolume, .4);
      store.dispose();
    },
  );
  test(
    'invalid playback preferences cannot enter or overwrite saved data',
    () async {
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      for (final speed in [0.0, 3.0, double.nan, double.infinity]) {
        await expectLater(
          store.setPlaybackPreferences(speed: speed),
          throwsArgumentError,
        );
      }
      for (final volume in [-1.0, 2.0, double.nan]) {
        await expectLater(
          store.setPlaybackPreferences(volume: volume),
          throwsArgumentError,
        );
      }
      for (final row in [
        {'playbackSpeed': 3},
        {'playbackVolume': -1},
        {'playbackSpeed': 'fast'},
      ]) {
        expect(
          () => SavedMusicData.decode(
            jsonEncode({
              'version': 1,
              'favorites': [],
              'playlists': [],
              ...row,
            }),
          ),
          throwsFormatException,
        );
      }
      expect(store.data.playbackSpeed, 1);
      store.dispose();
    },
  );
}
