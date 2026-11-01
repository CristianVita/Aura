import 'package:aura/audio_track.dart';
import 'package:aura/playback_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

class _Storage implements PlaybackMemoryStorage {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    if (fail) {
      fail = false;
      throw StateError('Disk unavailable');
    }
    value = json;
  }
}

AudioTrack track(
  String uri, {
  int durationMs = 30000,
  String folder = 'Music/',
}) => AudioTrack(
  id: uri,
  title: uri,
  artist: '',
  album: '',
  durationMs: durationMs,
  uri: uri,
  folder: folder,
);

PlaybackSession session({
  List<String> uris = const ['a', 'b', 'a'],
  int index = 2,
  List<int> order = const [2, 0, 1],
  bool shuffle = true,
  int position = 17000,
}) => PlaybackSession(
  uris: uris,
  index: index,
  positionMs: position,
  shuffle: shuffle,
  order: order,
  loop: LoopMode.all,
);

void main() {
  test('restore preserves duplicate queue entries, index, position and shuffle permutation', () {
    final restored = PlaybackSession.fromJson(session().toJson())
        .resolve([track('a'), track('b')]);
    expect(restored.tracks.map((t) => t.uri), ['a', 'b', 'a']);
    expect(restored.index, 2);
    expect(restored.positionMs, 17000);
    expect(restored.order, [2, 0, 1]);
    expect(restored.shuffle, isTrue);
    expect(restored.loop, LoopMode.all);
  });

  test(
    'missing current file advances in saved shuffle order and resets position',
    () {
      final saved = session(
        uris: ['gone', 'b', 'c'],
        index: 0,
        order: [0, 2, 1],
      );
      final restored = saved.resolve([track('b'), track('c')]);
      expect(restored.tracks.map((t) => t.uri), ['b', 'c']);
      expect(restored.index, 1);
      expect(restored.order, [1, 0]);
      expect(restored.positionMs, 0);
    },
  );

  test(
    'restore handles empty libraries and clamps position to changed duration',
    () {
      expect(session().resolve([]).tracks, isEmpty);
      expect(
        session().resolve([track('a', durationMs: 5000)]).positionMs,
        5000,
      );
      expect(
        () => PlaybackSession.fromJson({
          ...session().toJson(),
          'order': [0, 0, 1],
        }),
        throwsFormatException,
      );
    },
  );

  test('restored shuffle is applied once; later shuffle still works', () {
    final order = RestoredShuffleOrder([2, 0, 1]);
    order.insert(0, 3);
    order.shuffle(initialIndex: 0);
    expect(order.indices, [2, 0, 1]);
    order.shuffle(initialIndex: 1);
    expect(order.indices.first, 1);
    expect(order.indices.toSet(), {0, 1, 2});
    order.removeRange(0, 1);
    expect(order.indices.toSet(), {0, 1});
  });

  test('history uses actual listening time and ignores repeated ticks after qualification', () {
    final progress = ListeningProgress();
    expect(progress.advance('a', Duration.zero), isNull);
    expect(progress.advance('a', const Duration(seconds: 4)), isNull);
    expect(progress.advance('a', Duration.zero), isNull); // pause or seek
    expect(progress.advance('a', const Duration(seconds: 1)), 'a');
    expect(progress.advance('a', const Duration(seconds: 20)), isNull);
    expect(progress.advance('b', const Duration(seconds: 1)), isNull);
    progress.restart();
    expect(progress.advance('a', const Duration(seconds: 5)), 'a');
  });

  test(
    'short tracks qualify when heard through, but a brief skip does not',
    () {
      final progress = ListeningProgress();
      expect(
        progress.advance(
          'a',
          const Duration(milliseconds: 100),
          completed: true,
        ),
        isNull,
      );
      expect(
        progress.advance(
          'b',
          const Duration(milliseconds: 2900),
          durationMs: 3000,
        ),
        'b',
      );
    },
  );

  test('filters are opt-in and keep unknown durations', () {
    expect(
      const LibraryFilters().includes(
        track('a', durationMs: 2000, folder: 'WhatsApp Audio/'),
      ),
      isTrue,
    );
    const filters = LibraryFilters(minimumSeconds: 30, hideMessaging: true);
    expect(
      filters.includes(
        track('a', folder: 'Android/media/com.whatsapp/Media/WhatsApp Audio/'),
      ),
      isFalse,
    );
    expect(filters.includes(track('a', folder: 'TELEGRAM\\Audio')), isFalse);
    expect(filters.includes(track('a', durationMs: 29000)), isFalse);
    expect(filters.includes(track('a', durationMs: 30000)), isTrue);
    expect(filters.includes(track('a', durationMs: 0)), isTrue);
  });

  test(
    'interleaved session, filter and history writes survive reload',
    () async {
      final storage = _Storage();
      final store = PlaybackMemoryStore(storage);
      await store.load();
      await Future.wait([
        store.saveSession(session()),
        store.record('a', DateTime(2026, 11, 1)),
        store.setFilters(const LibraryFilters(minimumSeconds: 30)),
      ]);
      final restored = PlaybackMemoryStore(storage);
      await restored.load();
      expect(restored.data.session!.positionMs, 17000);
      expect(restored.data.history.single.uri, 'a');
      expect(restored.data.filters.minimumSeconds, 30);
      await restored.record('a', DateTime(2026, 11, 2));
      expect(restored.data.history.single.playCount, 2);
      await restored.clearHistory();
      expect(restored.data.history, isEmpty);
      expect(restored.data.session!.uris, ['a', 'b', 'a']);
      expect(restored.data.filters.minimumSeconds, 30);
      store.dispose();
      restored.dispose();
    },
  );

  test(
    'history stays bounded and sorts replays first without duplicate rows',
    () async {
      final store = PlaybackMemoryStore(_Storage());
      await store.load();
      for (var i = 0; i < 105; i++) {
        await store.record('$i', DateTime(2026));
      }
      await store.record('50', DateTime(2026));
      expect(store.data.history.length, 100);
      expect(store.data.history.first.uri, '50');
      expect(store.data.history.first.playCount, 2);
      expect(store.data.history.where((e) => e.uri == '50').length, 1);
      store.dispose();
    },
  );

  test(
    'write errors retain prior state and damaged files are protected',
    () async {
      final storage = _Storage();
      final store = PlaybackMemoryStore(storage);
      await store.load();
      await store.saveSession(session());
      storage.fail = true;
      await expectLater(store.clearHistory(), throwsStateError);
      expect(store.data.session!.positionMs, 17000);
      await store.record('a', DateTime(2026));
      expect(store.data.history.single.uri, 'a');
      storage.value = '{broken';
      final damaged = PlaybackMemoryStore(storage);
      await damaged.load();
      expect(damaged.failed, isTrue);
      expect(damaged.ready, isFalse);
      await expectLater(damaged.saveSession(session()), throwsStateError);
      expect(storage.value, '{broken');
      damaged.dispose();
      store.dispose();
    },
  );
}
