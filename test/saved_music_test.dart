import 'package:aura/saved_music.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

void main() {
  late MemorySavedMusicStorage storage;
  late SavedMusicStore store;
  setUp(() async {
    storage = MemorySavedMusicStorage();
    store = SavedMusicStore(storage);
    await store.load();
  });
  tearDown(() => store.dispose());

  test(
    'favorites and ordered playlists survive reload with unavailable tracks',
    () async {
      await store.toggleFavorite('missing');
      final id = await store.createPlaylist(
        '  Seară 🎵  ',
        tracks: ['b', 'missing', 'a', 'b'],
      );
      await store.renamePlaylist(id, 'Edamame');
      final restored = SavedMusicStore(storage);
      await restored.load();
      expect(restored.data.favorites, {'missing'});
      expect(restored.data.playlists.single.name, 'Edamame');
      expect(restored.data.playlists.single.tracks, ['b', 'missing', 'a']);
      restored.dispose();
    },
  );

  test(
    'concurrent favorite and playlist edits do not overwrite each other',
    () async {
      final id = await store.createPlaylist('A');
      await Future.wait([
        store.toggleFavorite('a'),
        store.toggleFavorite('b'),
        store.addTrack(id, 'a'),
        store.addTrack(id, 'b'),
        store.addTrack(id, 'a'),
      ]);
      expect(store.data.favorites, {'a', 'b'});
      expect(store.data.playlists.single.tracks, ['a', 'b']);
    },
  );

  test(
    'failed writes keep the previous state and later edits still work',
    () async {
      await store.toggleFavorite('a');
      final saved = storage.value;
      storage.failNextWrite = true;
      await expectLater(store.toggleFavorite('b'), throwsStateError);
      expect(store.data.favorites, {'a'});
      expect(storage.value, saved);
      await store.toggleFavorite('c');
      expect(store.data.favorites, {'a', 'c'});
    },
  );

  test('removing tracks and deleting a playlist preserve favorites', () async {
    await store.toggleFavorite('a');
    final first = await store.createPlaylist('Same', tracks: ['a', 'b']);
    final second = await store.createPlaylist('Same', tracks: ['a']);
    expect(first, isNot(second));
    await store.removeTrack(first, 'a');
    expect(store.data.playlists.first.tracks, ['b']);
    await store.deletePlaylist(first);
    expect(store.data.playlists.single.id, second);
    expect(store.data.favorites, {'a'});
  });

  test('invalid names cannot create or rename playlists', () async {
    await expectLater(store.createPlaylist('   '), throwsArgumentError);
    final id = await store.createPlaylist('Valid');
    await expectLater(store.renamePlaylist(id, 'x' * 81), throwsArgumentError);
    expect(store.data.playlists.single.name, 'Valid');
  });

  test('damaged storage cannot silently be overwritten', () async {
    storage.value = '{damaged';
    await store.load();
    expect(store.ready, isFalse);
    expect(store.loadFailed, isTrue);
    await expectLater(store.toggleFavorite('a'), throwsStateError);
    expect(storage.value, '{damaged');
    expect(storage.writes, 0);
  });
}
