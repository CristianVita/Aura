import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/background_downloads.dart';
import 'package:aura/offline_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SyntheticStore extends OfflineStorage {
  @override
  bool busy(String uri) => false;
  @override
  Future<bool> hasRecord(String uri) async => false;
  @override
  Future<Uri?> localUri(String uri) async => null;
  @override
  Future<List<Map<String, Object?>>> cachedTracks() async => [];
  @override
  Future<void> remove(String uri) async => throw StateError('unexpected');
  @override
  Future<void> download(AudioTrack track) async {
    await Future<void>.delayed(const Duration(seconds: 10));
  }
}

AudioTrack synthetic(String id) => AudioTrack(
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
        body: Center(child: Text('Test Aura – se închide automat')),
      ),
    ),
  );
  final dir = Directory(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'synthetic-background-test',
    ),
  );
  debugPrint('AURA_SYNTHETIC_BOOT');
  final store = SyntheticStore();
  final persistence = DeviceDownloadJobPersistence(directory: () async => dir);
  final foreground = AndroidDownloadForeground();
  final job = BackgroundDownloads(
    store: store,
    persistence: persistence,
    foreground: foreground,
  );
  final watchdog = Timer(const Duration(seconds: 35), () {
    debugPrint('AURA_SYNTHETIC_WATCHDOG');
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
    debugPrint('AURA_SYNTHETIC_AUDIO_READY');
    await job.load();
    if (job.hasJob && !job.complete) {
      if (job.running) throw StateError('Job resumed without action');
      debugPrint('AURA_SYNTHETIC_RESTORED_PAUSED');
    } else {
      await job.create([synthetic('one'), synthetic('two')]);
    }
    var loggedCheckpoint = false;
    job.addListener(() {
      if (job.done == 1 && !loggedCheckpoint) {
        loggedCheckpoint = true;
        debugPrint('AURA_SYNTHETIC_BACKGROUND_CHECKPOINT');
      }
    });
    debugPrint('AURA_SYNTHETIC_BEFORE_START');
    await job.resume(
      title: 'Synthetic download',
      progress: 'Progress',
      stop: 'Stop',
    );
    debugPrint('AURA_SYNTHETIC_BACKGROUND_STARTED');
    await job.waitForCompletion().timeout(const Duration(seconds: 40));
    if (!job.complete || job.done != 2 || job.failed != 0) {
      throw StateError('Incomplete synthetic transfer');
    }
    final restored = BackgroundDownloads(
      store: store,
      persistence: persistence,
      foreground: foreground,
    );
    await restored.load();
    if (!restored.complete || restored.done != 2) {
      throw StateError('Progress not persisted');
    }
    restored.dispose();
    debugPrint('AURA_SYNTHETIC_BACKGROUND_PASS');
  } catch (error) {
    debugPrint('AURA_SYNTHETIC_BACKGROUND_FAIL: $error');
  } finally {
    watchdog.cancel();
    unawaited(SystemNavigator.pop());
    job.dispose();
    store.dispose();
  }
}
