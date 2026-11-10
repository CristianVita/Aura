import 'dart:io';
import 'dart:typed_data';

import 'package:aura/cached_playback_source.dart';
import 'package:aura/playback_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'complete playback is cached and later ranges come from the cache',
    () async {
      final dir = await Directory.systemTemp.createTemp('aura-playback-test-');
      try {
        final cache = PlaybackCache(directory: () async => dir, maxBytes: 10);
        await cache.setEnabled(true);
        var requests = 0;
        final source = CachedPlaybackSource(
          trackUri: 'aura://navidrome/test/one',
          cache: cache,
          resolve: () async => Uri.parse('https://example.test/song'),
          clientFactory: () => MockClient((request) async {
            requests++;
            expect(request.headers['range'], 'bytes=0-');
            return http.Response.bytes(
              [1, 2, 3, 4],
              206,
              headers: {
                'content-range': 'bytes 0-3/4',
                'content-type': 'audio/mpeg',
              },
            );
          }),
        );
        final initial = await source.request(0);
        expect((await initial.stream.toList()).expand((x) => x), [1, 2, 3, 4]);
        final cached = await source.request(1, 3);
        expect((await cached.stream.toList()).expand((x) => x), [2, 3]);
        expect(requests, 1);
        await cache.close();
        cache.dispose();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('partial response is not stored as a complete track', () async {
    final dir = await Directory.systemTemp.createTemp('aura-playback-test-');
    try {
      final cache = PlaybackCache(directory: () async => dir, maxBytes: 10);
      await cache.setEnabled(true);
      final source = CachedPlaybackSource(
        trackUri: 'aura://navidrome/test/one',
        cache: cache,
        resolve: () async => Uri.parse('https://example.test/song'),
        clientFactory: () => MockClient(
          (_) async => http.Response.bytes(
            Uint8List.fromList([1, 2]),
            206,
            headers: {
              'content-range': 'bytes 0-1/4',
              'content-type': 'audio/mpeg',
            },
          ),
        ),
      );
      final response = await source.request(0, 2);
      await response.stream.drain<void>();
      expect(await cache.acquire('aura://navidrome/test/one'), isNull);
      await cache.close();
      cache.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test('cancelled playback removes the partial cache entry', () async {
    final dir = await Directory.systemTemp.createTemp('aura-playback-test-');
    try {
      final cache = PlaybackCache(directory: () async => dir, maxBytes: 10);
      await cache.setEnabled(true);
      final source = CachedPlaybackSource(
        trackUri: 'aura://navidrome/test/cancel',
        cache: cache,
        resolve: () async => Uri.parse('https://example.test/song'),
        clientFactory: () => MockClient(
          (_) async => http.Response.bytes(
            [1, 2, 3, 4],
            200,
            headers: {'content-type': 'audio/mpeg'},
          ),
        ),
      );
      final response = await source.request();
      await response.stream.take(1).toList();
      expect(await cache.acquire('aura://navidrome/test/cancel'), isNull);
      expect(
        dir.listSync().whereType<File>().where((f) => f.path.endsWith('.part')),
        isEmpty,
      );
      await cache.close();
      cache.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
