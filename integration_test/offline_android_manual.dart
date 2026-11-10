import 'dart:io';
import 'dart:typed_data';

import 'package:aura/audio_library.dart';
import 'package:aura/audio_sources.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/navidrome.dart';
import 'package:aura/offline_store.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

class _NoSecrets implements NavidromeSecrets {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
}

void main() => runApp(const _TestApp());

class _TestApp extends StatefulWidget {
  const _TestApp();
  @override
  State<_TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<_TestApp> {
  String status = 'Starting offline test';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  Future<void> run() async {
    AudioPlayer? player;
    try {
      final bytes = ByteData(16044);
      void writeText(int offset, String value) {
        for (var i = 0; i < value.length; i++) {
          bytes.setUint8(offset + i, value.codeUnitAt(i));
        }
      }

      writeText(0, 'RIFF');
      bytes.setUint32(4, 16036, Endian.little);
      writeText(8, 'WAVEfmt ');
      bytes.setUint32(16, 16, Endian.little);
      bytes.setUint16(20, 1, Endian.little);
      bytes.setUint16(22, 1, Endian.little);
      bytes.setUint32(24, 8000, Endian.little);
      bytes.setUint32(28, 16000, Endian.little);
      bytes.setUint16(32, 2, Endian.little);
      bytes.setUint16(34, 16, Endian.little);
      writeText(36, 'data');
      bytes.setUint32(40, 16000, Endian.little);
      final data = bytes.buffer.asUint8List();
      final root = await Directory.systemTemp.createTemp(
        'aura-offline-synthetic-',
      );
      final offline = OfflineStore(
        directory: () async => root,
        open: (_) async => (
          response: http.StreamedResponse(
            Stream.value(data),
            200,
            contentLength: data.length,
            headers: {'content-type': 'audio/wav'},
          ),
          close: () {},
        ),
      );
      const track = AudioTrack(
        id: 'synthetic',
        title: 'Synthetic',
        artist: '',
        album: '',
        durationMs: 1000,
        uri: 'aura://navidrome/synthetic/song',
      );
      await offline.download(track);
      final repository = NavidromeRepository(
        readCache: () async => null,
        writeCache: (_) async {},
        secrets: _NoSecrets(),
      );
      final library = AudioLibrary(
        offlineStore: offline,
        navidromeRepository: repository,
        localInvoke: (_, _) async => <Object?>[],
      );
      final list = await library.invokeListMethod<Object?>('loadLibrary');
      if (list?.length != 1) throw StateError('Missing offline track');
      final source = await sourceForTrack(track, library: library);
      player = AudioPlayer();
      await player.setVolume(0);
      final duration = await player
          .setAudioSource(source)
          .timeout(const Duration(seconds: 15));
      if (duration == null || duration.inMilliseconds < 900) {
        throw StateError('Invalid duration');
      }
      await player.play().timeout(const Duration(seconds: 15));
      await player.dispose();
      player = null;
      await offline.remove(track.uri);
      if (await offline.hasRecord(track.uri)) throw StateError('Remove failed');
      offline.dispose();
      if (mounted) setState(() => status = 'OFFLINE TEST PASSED');
    } catch (error) {
      await player?.dispose();
      if (mounted) setState(() => status = 'OFFLINE TEST FAILED: $error');
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: Center(child: Text(status))),
  );
}
