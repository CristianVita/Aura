import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'musicbrainz_gate.dart';

class CoverCandidate {
  const CoverCandidate({
    required this.id,
    required this.title,
    required this.artist,
    required this.date,
  });
  final String id, title, artist, date;
}

class CoverLookup {
  CoverLookup({
    http.Client Function()? clientFactory,
    MusicBrainzGate? gate,
    this.minimumInterval = const Duration(milliseconds: 1100),
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _gate =
           gate ??
           (clientFactory == null ? musicBrainzGate : MusicBrainzGate());
  final http.Client Function() _clientFactory;
  final Duration minimumInterval;
  final MusicBrainzGate _gate;
  static const _agent = 'Aura/1.0.0 (https://github.com/CristianVita/Aura)';
  static const maxImageBytes = 10 * 1024 * 1024;
  static final _idPattern = RegExp(
    r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
  );

  String _phrase(String value) => value.replaceAllMapped(
    RegExp(r'([+\-!(){}\[\]^"~*?:\\/]|&&|\|\|)'),
    (match) => '\\${match[0]}',
  );
  bool _valid(String s) =>
      s.length <= 200 && !s.contains(RegExp(r'[\x00-\x1f]'));
  String _text(Object? value) {
    if (value is! String) return '';
    final text = value.replaceAll(RegExp(r'[\x00-\x1f]'), '').trim();
    return text.length > 200 ? text.substring(0, 200) : text;
  }

  Future<Uint8List> _get(
    Uri uri, {
    required int limit,
    bool redirect = false,
  }) async {
    final client = _clientFactory();
    try {
      for (var i = 0; i < 6; i++) {
        final request = http.Request('GET', uri)..followRedirects = false;
        request.headers['User-Agent'] = _agent;
        final response = await client
            .send(request)
            .timeout(const Duration(seconds: 15));
        if (redirect &&
            response.statusCode >= 300 &&
            response.statusCode < 400) {
          final location = response.headers['location'];
          if (location == null) throw const FormatException('Missing redirect');
          var next = uri.resolve(location);
          final host = next.host.toLowerCase();
          if ((next.scheme != 'https' && next.scheme != 'http') ||
              next.userInfo.isNotEmpty ||
              (next.hasPort &&
                  next.port != (next.scheme == 'https' ? 443 : 80)) ||
              !(host == 'coverartarchive.org' ||
                  host == 'archive.org' ||
                  host.endsWith('.archive.org'))) {
            throw const FormatException('Invalid redirect');
          }
          if (next.scheme == 'http') {
            next = next.replace(scheme: 'https', port: 443);
          }
          uri = next;
          continue;
        }
        if (response.statusCode != 200 ||
            (response.contentLength != null &&
                response.contentLength! > limit)) {
          throw const FormatException('Unavailable or oversized response');
        }
        return await (() async {
          final builder = BytesBuilder(copy: false);
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 15),
          )) {
            if (builder.length + chunk.length > limit) {
              throw const FormatException('Oversized response');
            }
            builder.add(chunk);
          }
          return builder.takeBytes();
        })().timeout(const Duration(seconds: 30));
      }
      throw const FormatException('Too many redirects');
    } finally {
      client.close();
    }
  }

  Future<List<CoverCandidate>> search(String title, String artist) {
    title = title.trim();
    artist = artist.trim();
    if (title.isEmpty || !_valid(title) || !_valid(artist)) {
      return Future.error(const FormatException('Invalid query'));
    }
    final query =
        'release:"${_phrase(title)}"${artist.isEmpty ? '' : ' AND artistname:"${_phrase(artist)}"'}';
    return _gate.run(() async {
      final data = await _get(
        Uri.https('musicbrainz.org', '/ws/2/release/', {
          'query': query,
          'fmt': 'json',
          'limit': '10',
        }),
        limit: 1024 * 1024,
      );
      final root = jsonDecode(utf8.decode(data));
      if (root is! Map || root['releases'] is! List) {
        throw const FormatException('Invalid result');
      }
      final result = <CoverCandidate>[];
      for (final item in (root['releases'] as List).take(10)) {
        if (item is! Map) continue;
        final id = _text(item['id']), name = _text(item['title']);
        if (!_idPattern.hasMatch(id) || name.isEmpty) continue;
        final credit = item['artist-credit'];
        final artist = credit is List
            ? credit
                  .take(12)
                  .map(
                    (c) => c is Map
                        ? '${_text(c['name'])}${_text(c['joinphrase'])}'
                        : '',
                  )
                  .join(' ')
                  .trim()
            : '';
        result.add(
          CoverCandidate(
            id: id,
            title: name,
            artist: artist,
            date: _text(item['date']),
          ),
        );
      }
      return result;
    }, minimumInterval);
  }

  Future<Uint8List> front(String id) {
    if (!_idPattern.hasMatch(id)) {
      return Future.error(const FormatException('Invalid release'));
    }
    return _get(
      Uri.https('coverartarchive.org', '/release/$id/front-500'),
      limit: maxImageBytes,
      redirect: true,
    );
  }
}

final coverLookup = CoverLookup();
