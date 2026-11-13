import 'dart:async';

import 'package:aura/audio_track.dart';
import 'package:aura/offline_storage.dart';
import 'package:aura/offline_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const song = AudioTrack(
  id: 'test',
  title: 'Piesă sintetică test',
  artist: 'Test',
  album: '',
  durationMs: 1000,
  uri: 'aura://navidrome/test/test',
);

class TestStore extends OfflineStorage {
  bool exists = true;
  @override
  bool busy(String uri) => false;
  @override
  Future<bool> hasRecord(String uri) async => exists;
  @override
  Future<Uri?> localUri(String uri) async => null;
  @override
  Future<void> download(AudioTrack track) async =>
      throw StateError('no network');
  @override
  Future<void> remove(String uri) async {
    exists = false;
    notifyListeners();
  }

  @override
  Future<List<Map<String, Object?>>> cachedTracks() async => exists
      ? [
          {
            'id': song.id,
            'uri': song.uri,
            'title': song.title,
            'artist': song.artist,
            'album': song.album,
            'durationMs': song.durationMs,
          },
        ]
      : [];
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Timer(const Duration(seconds: 45), () => SystemNavigator.pop());
  runApp(
    MaterialApp(
      home: OfflineDownloadsScreen(
        store: TestStore(),
        canRemove: (_) => true,
        onPlay: (_, _) async {},
      ),
    ),
  );
}
