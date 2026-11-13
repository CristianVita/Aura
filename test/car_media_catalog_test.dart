import 'package:aura/audio_track.dart';
import 'package:aura/car_media_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

AudioTrack song(String id, String uri) => AudioTrack(
  id: id,
  title: 'Track $id',
  artist: 'Synthetic artist',
  album: 'Synthetic album',
  durationMs: 1234,
  uri: uri,
);

void main() {
  test('browsable roots and favorites expose opaque IDs with no paths', () {
    final one = song('one', 'aura://navidrome/private-server/one');
    final two = song('two', 'file:///private/audio/two.mp3');
    final catalog = CarMediaCatalog(
      tracks: [one, two, one],
      favoriteUris: {two.uri, 'missing'},
      allTracksLabel: 'Tracks',
      favoritesLabel: 'Favorites',
    );
    final root = catalog.children(CarMediaCatalog.rootId);
    expect(root.map((item) => item.title), ['Tracks', 'Favorites']);
    expect(root.every((item) => item.playable == false), isTrue);
    final tracks = catalog.children(CarMediaCatalog.allTracksId);
    expect(tracks.length, 2);
    expect(tracks.every((item) => item.playable == true), isTrue);
    expect(tracks.first.id, isNot(contains('private-server')));
    expect(tracks.last.id, isNot(contains('private/audio')));
    expect(tracks.first.duration, const Duration(milliseconds: 1234));
    expect(catalog.trackForId(tracks.first.id), same(one));
    expect(catalog.trackForId(one.uri), isNull);
    final favorites = catalog.children(CarMediaCatalog.favoritesId);
    expect(favorites.map((item) => item.id), [tracks.last.id]);
    expect(favorites.single.artUri, isNull);
  });

  test(
    'pages are bounded, deterministic and invalid IDs return no entries',
    () {
      final catalog = CarMediaCatalog(
        tracks: List.generate(125, (i) => song('$i', 'aura://navidrome/s/$i')),
        favoriteUris: {},
        allTracksLabel: 'Tracks',
        favoritesLabel: 'Favorites',
      );
      final first = catalog.children(CarMediaCatalog.allTracksId, limit: 100);
      final last = catalog.children(
        CarMediaCatalog.allTracksId,
        offset: 100,
        limit: 100,
      );
      expect(first.length, 100);
      expect(last.length, 25);
      expect(first.last.id, isNot(last.first.id));
      expect(
        catalog.children(CarMediaCatalog.allTracksId, offset: 500),
        isEmpty,
      );
      expect(catalog.children('unknown'), isEmpty);
      expect(() => catalog.children('root', offset: -1), throwsRangeError);
      expect(() => catalog.children('root', limit: 101), throwsRangeError);
    },
  );
}
