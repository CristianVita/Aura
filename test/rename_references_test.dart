import 'package:aura/playback_memory.dart';
import 'package:aura/rename_references.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  test('remaps every reference and preserves queue order and position', () {
    final saved = SavedMusicData(
      favorites: ['old'],
      ratings: {'old': 4.5},
      playlists: [
        MusicPlaylist(id: 'p', name: 'P', tracks: ['old', 'other']),
      ],
    );
    final memory = PlaybackMemoryData(
      history: [
        const ListeningEntry(uri: 'old', lastPlayedMs: 23, playCount: 3),
      ],
      session: PlaybackSession(
        uris: ['old', 'other', 'old'],
        index: 2,
        positionMs: 123,
        shuffle: true,
        order: [2, 1, 0],
        loop: LoopMode.all,
      ),
    );
    final result = remapRenamedTrack(
      saved: saved,
      memory: memory,
      oldUri: 'old',
      newUri: 'new',
    );
    expect(result.saved.favorites, {'new'});
    expect(result.saved.ratings, {'new': 4.5});
    expect(result.saved.playlists.single.tracks, ['new', 'other']);
    expect(result.memory.history.single.uri, 'new');
    expect(result.memory.history.single.playCount, 3);
    expect(result.memory.session!.uris, ['new', 'other', 'new']);
    expect(result.memory.session!.order, [2, 1, 0]);
    expect(result.memory.session!.positionMs, 123);
    expect(saved.playlists.single.tracks, ['old', 'other']);
  });
  test('rejects a destination already referenced by other data', () {
    expect(
      () => remapRenamedTrack(
        saved: SavedMusicData(favorites: ['new']),
        memory: PlaybackMemoryData(),
        oldUri: 'old',
        newUri: 'new',
      ),
      throwsStateError,
    );
  });
}
