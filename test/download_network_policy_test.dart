import 'dart:async';
import 'dart:io';

import 'package:aura/audio_track.dart';
import 'package:aura/download_network_policy.dart';
import 'package:aura/offline_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

const song = AudioTrack(
  id: '1',
  title: 'Synthetic',
  artist: 'Artist',
  album: 'Album',
  durationMs: 1,
  uri: 'aura://navidrome/test/1',
);

class FakeGuard implements DownloadNetworkGuard {
  bool permitted = false;
  final events = StreamController<bool>.broadcast(sync: true);
  @override
  Future<bool> allowed() async => permitted;
  @override
  Stream<bool> get changes => events.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('aura-network-test-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  test(
    'Wi-Fi-only is default, rejects mobile and unknown, and choice persists',
    () async {
      const channel = MethodChannel('dev.fluttercommunity.plus/connectivity');
      var state = ['mobile'];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => state);
      final p = DownloadNetworkPolicy(directory: () async => dir);
      await p.load();
      expect(p.mode, DownloadNetworkMode.wifiOnly);
      expect(await p.allowed(), isFalse);
      state = ['wifi'];
      expect(await p.allowed(), isTrue);
      state = ['wifi', 'other'];
      expect(await p.allowed(), isFalse);
      state = ['mobile'];
      await p.setMode(DownloadNetworkMode.anyNetwork);
      expect(await p.allowed(), isTrue);
      p.dispose();
      final restored = DownloadNetworkPolicy(directory: () async => dir);
      await restored.load();
      expect(restored.mode, DownloadNetworkMode.anyNetwork);
      expect(await restored.allowed(), isTrue);
      restored.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
  test('blocked network does not open a server connection', () async {
    final guard = FakeGuard();
    var calls = 0;
    final store = OfflineStore(
      directory: () async => dir,
      networkGuard: guard,
      open: (_) async {
        calls++;
        throw StateError('unexpected');
      },
    );
    await expectLater(
      store.download(song),
      throwsA(isA<DownloadNetworkException>()),
    );
    expect(calls, 0);
    expect(await store.localUri(song.uri), isNull);
    await guard.events.close();
    store.dispose();
  });
  test(
    'network change aborts the current transfer and removes the partial file',
    () async {
      final guard = FakeGuard()..permitted = true;
      final stream = StreamController<List<int>>();
      final opened = Completer<void>();
      var closes = 0;
      final store = OfflineStore(
        directory: () async => dir,
        networkGuard: guard,
        open: (_) async {
          opened.complete();
          return (
            response: http.StreamedResponse(
              stream.stream,
              200,
              headers: {'content-type': 'audio/mpeg'},
            ),
            close: () {
              closes++;
              if (!stream.isClosed) stream.close();
            },
          );
        },
      );
      final job = store.download(song);
      final check = expectLater(job, throwsA(isA<DownloadNetworkException>()));
      await opened.future;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      stream.add([1, 2, 3]);
      guard.permitted = false;
      guard.events.add(false);
      await check;
      expect(closes, greaterThan(0));
      expect(await store.localUri(song.uri), isNull);
      expect(
        dir.listSync().whereType<File>().where((f) => f.path.endsWith('.part')),
        isEmpty,
      );
      await guard.events.close();
      store.dispose();
    },
  );
}
