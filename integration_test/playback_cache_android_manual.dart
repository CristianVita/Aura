import 'dart:io';
import 'dart:typed_data';

import 'package:aura/cached_playback_source.dart';
import 'package:aura/playback_cache.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio/just_audio.dart';

Uint8List wavData() {
  const rate = 8000;
  final bytes = Uint8List(44 + rate * 2), data = ByteData(44 + rate * 2);
  void put(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  void u16(int offset, int value) {
    data.setUint16(offset, value, Endian.little);
    bytes.setRange(offset, offset + 2, data.buffer.asUint8List(offset, 2));
  }

  void u32(int offset, int value) {
    data.setUint32(offset, value, Endian.little);
    bytes.setRange(offset, offset + 4, data.buffer.asUint8List(offset, 4));
  }

  put(0, 'RIFF');
  u32(4, bytes.length - 8);
  put(8, 'WAVE');
  put(12, 'fmt ');
  u32(16, 16);
  u16(20, 1);
  u16(22, 1);
  u32(24, rate);
  u32(28, rate * 2);
  u16(32, 2);
  u16(34, 16);
  put(36, 'data');
  u32(40, rate * 2);
  return bytes;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Synthetic test'))),
    ),
  );
  final dir = await Directory.systemTemp.createTemp('aura-cache-isolated-');
  final cache = PlaybackCache(
    directory: () async => dir,
    maxBytes: 1024 * 1024,
  );
  final player = AudioPlayer();
  try {
    await cache.setEnabled(true);
    final wav = wavData();
    final source = CachedPlaybackSource(
      trackUri: 'aura://navidrome/synthetic/test',
      cache: cache,
      resolve: () async => Uri.parse('https://example.test/stream'),
      clientFactory: () => MockClient((request) async {
        final range = request.headers['range'];
        if (range == null) {
          return http.Response.bytes(
            wav,
            200,
            headers: {'content-type': 'audio/wav', 'accept-ranges': 'bytes'},
          );
        }
        final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range)!;
        final start = int.parse(match[1]!);
        final end = match[2]!.isEmpty
            ? wav.length - 1
            : int.parse(match[2]!).clamp(0, wav.length - 1);
        return http.Response.bytes(
          wav.sublist(start, end + 1),
          206,
          headers: {
            'content-type': 'audio/wav',
            'content-range': 'bytes $start-$end/${wav.length}',
          },
        );
      }),
    );
    await player.setAudioSource(source).timeout(const Duration(seconds: 30));
    await player.play().timeout(const Duration(seconds: 30));
    final entry = await cache.acquire('aura://navidrome/synthetic/test');
    if (entry == null) throw StateError('Cache entry absent');
    await entry.release();
    debugPrint('AURA_SYNTHETIC_CACHE_PASS');
  } catch (error) {
    debugPrint('AURA_SYNTHETIC_CACHE_FAIL: $error');
  } finally {
    await player.dispose();
    await cache.close();
    cache.dispose();
    await dir.delete(recursive: true);
  }
}
