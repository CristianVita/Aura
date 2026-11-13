import 'dart:async';

import 'package:aura/audio_track.dart';
import 'package:aura/background_downloads.dart';
import 'package:aura/background_downloads_ui.dart';
import 'package:aura/offline_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  Future<void> remove(String uri) async => throw StateError('not used');
  @override
  Future<void> download(AudioTrack track) async {
    await Future<void>.delayed(const Duration(seconds: 8));
  }
}

class SyntheticJob implements DownloadJobPersistence {
  String? data;
  @override
  Future<String?> read() async => data;
  @override
  Future<void> write(String value) async {
    data = value;
  }

  @override
  Future<void> clear() async {
    data = null;
  }
}

class SyntheticForeground implements DownloadForeground {
  @override
  void onCancel(void Function()? callback) {}
  @override
  Future<void> start({
    required String title,
    required String progress,
    required String stop,
    required int done,
    required int total,
  }) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> update(int done, int total) async {}
}

AudioTrack song(int i) => AudioTrack(
  id: '$i',
  title: 'Piesă sintetică $i',
  artist: 'Test',
  album: '',
  durationMs: 1000,
  uri: 'aura://navidrome/test/$i',
);
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Timer(const Duration(seconds: 55), () => SystemNavigator.pop());
  final job = BackgroundDownloads(
    store: SyntheticStore(),
    persistence: SyntheticJob(),
    foreground: SyntheticForeground(),
  );
  await job.create([song(1), song(2), song(3)]);
  runApp(
    MaterialApp(home: BackgroundDownloadsScreen(job: job, autoStart: true)),
  );
}
