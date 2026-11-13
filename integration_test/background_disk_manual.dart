import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/background_downloads.dart';
import 'package:aura/offline_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

AudioTrack song(String id) => AudioTrack(
  id: id,
  title: 'Synthetic',
  artist: 'Synthetic',
  album: 'Synthetic',
  durationMs: 1,
  uri: 'aura://navidrome/synthetic/$id',
);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('Test Aura – ecranul poate fi stins')),
      ),
    ),
  );
  final dir = Directory(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'synthetic-background-disk',
    ),
  );
  final store = OfflineStore(
    directory: () async => Directory(p.join(dir.path, 'offline')),
    open: (_) async {
      Stream<List<int>> chunks() async* {
        for (var i = 0; i < 4; i++) {
          await Future<void>.delayed(const Duration(seconds: 2));
          yield Uint8List(16 * 1024);
        }
      }

      return (
        response: http.StreamedResponse(
          chunks(),
          200,
          headers: {'content-type': 'audio/mpeg'},
          contentLength: 4 * 16 * 1024,
        ),
        close: () {},
      );
    },
  );
  final job = BackgroundDownloads(
    store: store,
    persistence: DeviceDownloadJobPersistence(directory: () async => dir),
    foreground: AndroidDownloadForeground(),
  );
  final watchdog = Timer(const Duration(seconds: 55), () {
    debugPrint('AURA_SYNTHETIC_DISK_TIMEOUT');
    job.requestStop();
    unawaited(SystemNavigator.pop());
  });
  try {
    await AudioService.init(
      builder: () => BaseAudioHandler(),
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'aura.synthetic.playback',
        androidNotificationChannelName: 'Synthetic playback',
        androidNotificationIcon: 'drawable/ic_stat_audio',
      ),
    );
    await job.create([song('one'), song('two')]);
    await job.resume(title: 'Test Aura', progress: 'Progres', stop: 'Oprește');
    debugPrint('AURA_SYNTHETIC_DISK_STARTED');
    await job.waitForCompletion().timeout(const Duration(seconds: 45));
    if (!job.complete || job.failed != 0) throw StateError('Job incomplete');
    final one = await store.localUri(song('one').uri),
        two = await store.localUri(song('two').uri);
    if (one == null ||
        two == null ||
        await File.fromUri(one).length() != 4 * 16 * 1024 ||
        await File.fromUri(two).length() != 4 * 16 * 1024) {
      throw StateError('Synthetic files missing or invalid');
    }
    final restored = BackgroundDownloads(
      store: store,
      persistence: DeviceDownloadJobPersistence(directory: () async => dir),
      foreground: AndroidDownloadForeground(),
    );
    await restored.load();
    if (!restored.complete || restored.done != 2) {
      throw StateError('Progress not saved');
    }
    restored.dispose();
    debugPrint('AURA_SYNTHETIC_DISK_PASS');
  } catch (error) {
    debugPrint('AURA_SYNTHETIC_DISK_FAIL: $error');
  } finally {
    watchdog.cancel();
    unawaited(SystemNavigator.pop());
    job.dispose();
    store.dispose();
  }
}
