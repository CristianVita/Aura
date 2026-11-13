import 'dart:io';
import 'dart:convert';

import 'package:aura/audio_library.dart';
import 'package:aura/audio_sources.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/cached_playback_source.dart';
import 'package:aura/navidrome.dart';
import 'package:aura/offline_store.dart';
import 'package:aura/playback_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

class EmptySecrets implements NavidromeSecrets {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
}

class TestSecrets implements NavidromeSecrets {
  TestSecrets(this.value);
  final String value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async =>
      throw StateError('Unexpected write');
}

void main() {
  test(
    'downloaded track remains browseable and playable after source removal',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'aura-offline-resolve-',
      );
      try {
        const track = AudioTrack(
          id: 'song',
          title: 'Track',
          artist: 'Artist',
          album: 'Album',
          durationMs: 1000,
          uri: 'aura://navidrome/server/song',
        );
        var downloads = 0;
        final offline = OfflineStore(
          directory: () async => dir,
          open: (_) async {
            downloads++;
            return (
              response: http.StreamedResponse(
                Stream.value([10, 20, 30]),
                200,
                headers: {'content-type': 'audio/mpeg'},
                contentLength: 3,
              ),
              close: () {},
            );
          },
        );
        await offline.download(track);
        final servers = NavidromeRepository(
          readCache: () async => null,
          writeCache: (_) async {},
          secrets: EmptySecrets(),
        );
        final library = AudioLibrary(
          offlineStore: offline,
          navidromeRepository: servers,
          localInvoke: (_, _) async => <Object?>[],
        );
        final rows = await library.invokeListMethod<Object?>('loadLibrary');
        expect(rows, hasLength(1));
        expect((rows!.single as Map)['uri'], track.uri);
        final cache = PlaybackCache(
          directory: () async => Directory('${dir.path}/playback-cache'),
          maxBytes: 100,
        );
        await cache.setEnabled(true);
        final audioSource = await sourceForTrack(
          track,
          library: library,
          cache: cache,
        ) as UriAudioSource;
        expect(audioSource.uri.scheme, 'file');
        expect(await File.fromUri(audioSource.uri).readAsBytes(), [10, 20, 30]);
        final limitedSource = await sourceForTrack(
          track,
          library: library,
          cache: cache,
          quality: NavidromeStreamQuality.limited(128),
        ) as UriAudioSource;
        expect(limitedSource.uri.scheme, 'file');
        expect(await File.fromUri(limitedSource.uri).readAsBytes(), [
          10,
          20,
          30,
        ]);
        expect(audioTrackOf(audioSource)!.uri, track.uri);
        expect(downloads, 1);
        await File.fromUri(audioSource.uri).writeAsBytes([30, 20, 10]);
        await expectLater(
          library.invokeMethod<String>('resolvePlaybackUri', {
            'uri': track.uri,
          }),
          throwsStateError,
        );
        await cache.close();
        cache.dispose();
        offline.dispose();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'limited streams bypass the original playback cache without changing it',
    () async {
      final dir = await Directory.systemTemp.createTemp('aura-quality-test-');
      final server = NavidromeServer(
        url: 'https://music.example',
        username: 'test',
        password: 'secret',
        name: 'Test',
      );
      final track = AudioTrack(
        id: 'song',
        title: 'Track',
        artist: 'Artist',
        album: '',
        durationMs: 1,
        uri: 'aura://navidrome/${server.id}/song',
      );
      final cache = PlaybackCache(
        directory: () async => Directory('${dir.path}/cache'),
        maxBytes: 100,
      );
      final offline = OfflineStore(
        directory: () async => Directory('${dir.path}/offline'),
        open: (_) => throw StateError('Unexpected download'),
      );
      try {
        await cache.setEnabled(true);
        final write = (await cache.begin(track.uri, 3))!;
        await write.file.writeAsBytes([1, 2, 3]);
        await write.finish('audio/mpeg');
        final repository = NavidromeRepository(
          readCache: () async => null,
          writeCache: (_) async => throw StateError('Unexpected write'),
          secrets: TestSecrets(jsonEncode([server.toJson()])),
        );
        final library = AudioLibrary(
          offlineStore: offline,
          navidromeRepository: repository,
        );
        final original = await sourceForTrack(
          track,
          library: library,
          cache: cache,
        );
        expect(original, isA<CachedPlaybackSource>());
        final limited = await sourceForTrack(
          track,
          library: library,
          cache: cache,
          quality: NavidromeStreamQuality.limited(128),
        ) as UriAudioSource;
        expect(limited.uri.queryParameters['maxBitRate'], '128');
        expect(limited.uri.queryParameters.containsKey('format'), isFalse);
        final stillCached = (await cache.acquire(track.uri))!;
        expect(await stillCached.file.readAsBytes(), [1, 2, 3]);
        await stillCached.release();
      } finally {
        await cache.close();
        cache.dispose();
        offline.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
