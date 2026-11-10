// just_audio exposes custom streamed sources through this experimental API.
// ignore_for_file: experimental_member_use

import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import 'playback_cache.dart';

class CachedPlaybackSource extends StreamAudioSource {
  CachedPlaybackSource({
    required this.trackUri,
    required this.resolve,
    required this.cache,
    http.Client Function()? clientFactory,
    super.tag,
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final String trackUri;
  final Future<Uri> Function() resolve;
  final PlaybackCache cache;
  final http.Client Function() _clientFactory;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    PlaybackCacheRead? cached;
    try {
      cached = await cache.acquire(trackUri);
    } catch (_) {}
    if (cached != null) {
      final entry = cached;
      final length = await entry.file.length();
      final from = start ?? 0, to = end ?? length;
      if (from < 0 || from >= length || to < from || to > length) {
        await entry.release();
        throw const FormatException('Invalid range');
      }
      Stream<List<int>> bytes() async* {
        try {
          yield* entry.file.openRead(from, to);
        } finally {
          await entry.release();
        }
      }

      return StreamAudioResponse(
        sourceLength: start == null ? null : length,
        contentLength: to - from,
        offset: start,
        contentType: entry.mime,
        stream: bytes(),
      );
    }
    final remote = await resolve();
    final client = _clientFactory();
    try {
      final request = http.Request('GET', remote);
      if (start != null || end != null) {
        request.headers[HttpHeaders.rangeHeader] =
            'bytes=${start ?? 0}-${end == null ? '' : end - 1}';
      }
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 && response.statusCode != 206) {
        throw const FormatException('Stream unavailable');
      }
      int? total, actualStart;
      if (response.statusCode == 206) {
        final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
            .firstMatch(response.headers['content-range'] ?? '');
        if (match == null) throw const FormatException('Invalid content range');
        actualStart = int.parse(match[1]!);
        final last = int.parse(match[2]!);
        total = int.parse(match[3]!);
        if (actualStart != (start ?? 0) ||
            last < actualStart ||
            last >= total ||
            (end != null && last >= end) ||
            (response.contentLength != null &&
                response.contentLength != last - actualStart + 1)) {
          throw const FormatException('Invalid content range');
        }
      }
      final mime = (response.headers['content-type'] ?? 'audio/mpeg')
          .split(';')
          .first
          .trim();
      final expected = response.statusCode == 200
          ? response.contentLength
          : total;
      final whole =
          response.statusCode == 200 ||
          (actualStart == 0 &&
              expected != null &&
              response.contentLength == expected);
      PlaybackCacheWrite? reservation;
      final cacheableMime =
          mime.startsWith('audio/') ||
          mime == 'application/ogg' ||
          mime == 'application/octet-stream';
      if (whole && cacheableMime && expected != null && expected > 0) {
        try {
          reservation = await cache.begin(trackUri, expected);
        } catch (_) {}
      }
      final write = reservation;
      Stream<List<int>> bytes() async* {
        RandomAccessFile? file;
        var received = 0, complete = false, usable = write != null;
        try {
          if (write != null) {
            try {
              file = await write.file.open(mode: FileMode.write);
            } catch (_) {
              usable = false;
            }
          }
          await for (final chunk in response.stream) {
            received += chunk.length;
            if (usable && file != null) {
              if (received > write!.length) {
                usable = false;
              } else {
                try {
                  await file.writeFrom(chunk);
                } catch (_) {
                  usable = false;
                }
              }
            }
            yield chunk;
          }
          complete = true;
        } finally {
          try {
            await file?.close();
          } catch (_) {
            usable = false;
          }
          if (write != null) {
            if (complete && usable && received == write.length) {
              try {
                await write.finish(mime);
              } catch (_) {}
            } else {
              try {
                await write.abort();
              } catch (_) {}
            }
          }
          client.close();
        }
      }

      return StreamAudioResponse(
        rangeRequestsSupported:
            response.statusCode == 206 ||
            response.headers['accept-ranges'] == 'bytes',
        sourceLength: response.statusCode == 206 ? total : null,
        contentLength: response.contentLength,
        offset: response.statusCode == 206 ? actualStart : null,
        contentType: mime,
        stream: bytes(),
      );
    } catch (_) {
      client.close();
      rethrow;
    }
  }
}
