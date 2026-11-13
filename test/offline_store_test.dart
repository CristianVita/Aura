import 'dart:convert';
import 'dart:io';

import 'package:aura/audio_track.dart';
import 'package:aura/offline_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' show join;

String pJoin(String a, String b) => join(a, b);

const track = AudioTrack(
  id: 'song',
  title: 'Synthetic',
  artist: 'Artist',
  album: 'Album',
  year: 1998,
  durationMs: 1000,
  uri: 'aura://navidrome/server/song',
);

void main() {
  late Directory dir;
  setUp(
    () async =>
        dir = await Directory.systemTemp.createTemp('aura-offline-test-'),
  );
  tearDown(() async => dir.delete(recursive: true));
  test(
    'download survives restart and keeps logical metadata without credentials',
    () async {
      var calls = 0, closed = 0;
      final store = OfflineStore(
        directory: () async => dir,
        open: (uri) async {
          calls++;
          return (
            response: http.StreamedResponse(
              Stream.value([1, 2, 3, 4]),
              200,
              headers: {'content-type': 'audio/mpeg'},
              contentLength: 4,
            ),
            close: () => closed++,
          );
        },
      );
      await Future.wait([store.download(track), store.download(track)]);
      expect(calls, 1);
      expect(closed, 1);
      final restarted = OfflineStore(
        directory: () async => dir,
        open: (_) => throw StateError('offline'),
      );
      final path = await restarted.localUri(track.uri);
      expect(path, isNotNull);
      expect(await File.fromUri(path!).readAsBytes(), [1, 2, 3, 4]);
      expect((await restarted.cachedTracks()).single['uri'], track.uri);
      expect((await restarted.cachedTracks()).single['year'], 1998);
      final manifests = dir.listSync().whereType<File>().where(
        (f) => f.path.endsWith('.json'),
      );
      final text = await manifests.single.readAsString();
      expect(text, isNot(contains('password')));
      expect(text, isNot(contains('https://')));
      await restarted.remove(track.uri);
      expect(await restarted.localUri(track.uri), isNull);
      expect(await restarted.cachedTracks(), isEmpty);
      store.dispose();
      restarted.dispose();
    },
  );
  test('corrupt audio is never returned for playback', () async {
    final store = OfflineStore(
      directory: () async => dir,
      open: (_) async => (
        response: http.StreamedResponse(
          Stream.value([1, 2, 3]),
          200,
          headers: {'content-type': 'audio/wav'},
          contentLength: 3,
        ),
        close: () {},
      ),
    );
    await store.download(track);
    final uri = await store.localUri(track.uri);
    await File.fromUri(uri!).writeAsBytes([3, 2, 1]);
    expect(await store.localUri(track.uri), isNull);
    store.dispose();
  });
  test('failed, truncated, oversized or non-audio downloads leave no completed item', () async {
    for (final mode in ['status', 'short', 'large', 'json', 'stream']) {
      var closed = false;
      final store = OfflineStore(
        directory: () async => dir,
        maxBytes: 4,
        open: (_) async => (
          response: http.StreamedResponse(
            mode == 'stream'
                ? Stream<List<int>>.error(StateError('secret'))
                : Stream.value([1, 2, 3]),
            mode == 'status' ? 403 : 200,
            headers: {
              'content-type': mode == 'json'
                  ? 'application/json'
                  : 'audio/mpeg',
            },
            contentLength: mode == 'short'
                ? 4
                : mode == 'large'
                ? 9
                : null,
          ),
          close: () => closed = true,
        ),
      );
      await expectLater(store.download(track), throwsA(anything), reason: mode);
      expect(closed, isTrue);
      expect(await store.localUri(track.uri), isNull);
      expect(dir.listSync(), isEmpty, reason: mode);
      store.dispose();
    }
  });
  test('untrusted manifests cannot escape the offline directory', () async {
    final store = OfflineStore(
      directory: () async => dir,
      open: (_) => throw StateError('offline'),
    );
    await File('${dir.path}${Platform.pathSeparator}outside.txt')
        .writeAsString('personal');
    final digest = sha256.convert(utf8.encode(track.uri)).toString();
    await File('${dir.path}${Platform.pathSeparator}$digest.json')
        .writeAsString(
          jsonEncode({
            'version': 1,
            'uri': track.uri,
            'file': '../outside.txt',
            'length': 8,
            'sha256': 'a' * 64,
          }),
        );
    expect(await store.cachedTracks(), isEmpty);
    expect(await store.hasRecord(track.uri), isTrue);
    await store.remove(track.uri);
    expect(await store.hasRecord(track.uri), isFalse);
    expect(
      await File('${dir.path}${Platform.pathSeparator}outside.txt')
          .readAsString(),
      'personal',
    );
    store.dispose();
  });
  test('media usage counts registered files with matching size only', () async {
    final store = OfflineStore(
      directory: () async => dir,
      open: (_) async => (
        response: http.StreamedResponse(
          Stream.value([1, 2, 3, 4]),
          200,
          headers: {'content-type': 'audio/mpeg'},
          contentLength: 4,
        ),
        close: () {},
      ),
    );
    await store.download(track);
    await File('${dir.path}${Platform.pathSeparator}unrelated.part')
        .writeAsBytes(List.filled(100, 0));
    final usage = await store.mediaUsage();
    expect(usage.tracks, 1);
    expect(usage.bytes, 4);
    final uri = await store.localUri(track.uri);
    await File.fromUri(uri!).writeAsBytes([1]);
    final damaged = await store.mediaUsage();
    expect(damaged.tracks, 0);
    expect(damaged.bytes, 0);
    expect(
      await File('${dir.path}${Platform.pathSeparator}unrelated.part').length(),
      100,
    );
    store.dispose();
  });
  test(
    'retry removes only abandoned temporary files for the selected track',
    () async {
      final key = sha256.convert(utf8.encode(track.uri)).toString();
      final oldPart = File(pJoin(dir.path, '${key}_0123456789abcdef.mp3.part'));
      final oldManifest = File(
        pJoin(dir.path, '${key}_0123456789abcdef.json.part'),
      );
      final unrelated = File(pJoin(dir.path, 'unrelated.mp3.part'));
      await oldPart.writeAsBytes([1]);
      await oldManifest.writeAsBytes([1]);
      await unrelated.writeAsBytes([7]);
      final store = OfflineStore(
        directory: () async => dir,
        cleanupInterrupted: true,
        open: (_) async => (
          response: http.StreamedResponse(
            Stream.value([1, 2, 3]),
            200,
            headers: {'content-type': 'audio/mpeg'},
            contentLength: 3,
          ),
          close: () {},
        ),
      );
      await store.download(track);
      expect(await oldPart.exists(), false);
      expect(await oldManifest.exists(), false);
      expect(await unrelated.readAsBytes(), [7]);
      expect(await store.localUri(track.uri), isNotNull);
      store.dispose();
    },
  );
}
