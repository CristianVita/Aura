import 'dart:io';
import 'dart:typed_data';

import 'package:aura/cached_playback_source.dart';
import 'package:aura/playback_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';

Uint8List silentWav() {
  const sampleRate = 8000, sampleCount = sampleRate;
  final bytes = Uint8List(44 + sampleCount * 2);
  final data = ByteData.sublistView(bytes);
  void text(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  text(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  text(36, 'data');
  data.setUint32(40, sampleCount * 2, Endian.little);
  return bytes;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('synthetic audio plays and produces a verified cache entry', (
    tester,
  ) async {
    final dir = await Directory.systemTemp.createTemp(
      'aura-cache-integration-',
    );
    final cache = PlaybackCache(
      directory: () async => dir,
      maxBytes: 1024 * 1024,
    );
    final player = AudioPlayer();
    try {
      await cache.setEnabled(true);
      final wav = silentWav();
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
      final stored = await cache.acquire('aura://navidrome/synthetic/test');
      expect(stored, isNotNull);
      await stored!.release();
    } finally {
      await player.dispose();
      await cache.close();
      cache.dispose();
      await dir.delete(recursive: true);
    }
  });
}
