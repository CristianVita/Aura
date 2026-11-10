import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'musicbrainz_gate.dart';

class MetadataRelease {
  const MetadataRelease({required this.title, required this.date});
  final String title;
  final String date;
}

class MetadataCandidate {
  const MetadataCandidate({
    required this.id,
    required this.title,
    required this.artist,
    required this.firstReleaseDate,
    required this.releases,
    required this.disambiguation,
  });
  final String id;
  final String title;
  final String artist;
  final String firstReleaseDate;
  final List<MetadataRelease> releases;
  final String disambiguation;
}

enum MetadataLookupFailure {
  invalidQuery,
  unavailable,
  rateLimited,
  invalidResponse,
}

class MetadataLookupException implements Exception {
  const MetadataLookupException(this.reason);
  final MetadataLookupFailure reason;
}

class MusicBrainzLookup {
  MusicBrainzLookup({
    http.Client Function()? clientFactory,
    MusicBrainzGate? gate,
    this.minimumInterval = const Duration(milliseconds: 1100),
    this.timeout = const Duration(seconds: 15),
  }) : _clientFactory = clientFactory ?? http.Client.new,
       _gate =
           gate ??
           (clientFactory == null ? musicBrainzGate : MusicBrainzGate());
  final http.Client Function() _clientFactory;
  final Duration minimumInterval;
  final Duration timeout;
  final MusicBrainzGate _gate;
  static const maxResponseBytes = 1024 * 1024;
  static const maxQueryLength = 200;
  static const _userAgent = 'Aura/1.0.0 (https://github.com/CristianVita/Aura)';

  String _phrase(String value) => value.replaceAllMapped(
    RegExp(r'([+\-!(){}\[\]^"~*?:\\/]|&&|\|\|)'),
    (match) => '\\${match[0]}',
  );

  Future<List<MetadataCandidate>> search({
    required String title,
    String artist = '',
  }) {
    final cleanTitle = title.trim();
    final cleanArtist = artist.trim();
    if (cleanTitle.isEmpty ||
        cleanTitle.length > maxQueryLength ||
        cleanArtist.length > maxQueryLength ||
        cleanTitle.contains(RegExp(r'[\r\n\x00-\x1f]')) ||
        cleanArtist.contains(RegExp(r'[\r\n\x00-\x1f]'))) {
      return Future.error(
        const MetadataLookupException(MetadataLookupFailure.invalidQuery),
      );
    }
    final query =
        'recording:"${_phrase(cleanTitle)}"${cleanArtist.isEmpty ? '' : ' AND artist:"${_phrase(cleanArtist)}"'}';
    return _gate.run(() async {
      final client = _clientFactory();
      try {
        final request =
            http.Request(
                'GET',
                Uri.https('musicbrainz.org', '/ws/2/recording/', {
                  'query': query,
                  'fmt': 'json',
                  'limit': '10',
                }),
              )
              ..followRedirects = false
              ..headers['User-Agent'] = _userAgent
              ..headers['Accept'] = 'application/json';
        final response = await client.send(request).timeout(timeout);
        if (response.statusCode == 429 || response.statusCode == 503) {
          throw const MetadataLookupException(
            MetadataLookupFailure.rateLimited,
          );
        }
        if (response.statusCode != 200) {
          throw const MetadataLookupException(
            MetadataLookupFailure.unavailable,
          );
        }
        if (response.contentLength != null &&
            response.contentLength! > maxResponseBytes) {
          throw const MetadataLookupException(
            MetadataLookupFailure.invalidResponse,
          );
        }
        final bytes = await (() async {
          final collected = <int>[];
          await for (final chunk in response.stream.timeout(timeout)) {
            if (collected.length + chunk.length > maxResponseBytes) {
              throw const MetadataLookupException(
                MetadataLookupFailure.invalidResponse,
              );
            }
            collected.addAll(chunk);
          }
          return collected;
        })().timeout(timeout);
        final root = jsonDecode(utf8.decode(bytes));
        if (root is! Map || root['recordings'] is! List) {
          throw const MetadataLookupException(
            MetadataLookupFailure.invalidResponse,
          );
        }
        return _parse(root['recordings'] as List);
      } on MetadataLookupException {
        rethrow;
      } on FormatException {
        throw const MetadataLookupException(
          MetadataLookupFailure.invalidResponse,
        );
      } catch (_) {
        throw const MetadataLookupException(MetadataLookupFailure.unavailable);
      } finally {
        client.close();
      }
    }, minimumInterval);
  }

  List<MetadataCandidate> _parse(List<dynamic> rows) {
    String clean(Object? value, [int limit = 300]) {
      if (value is! String) return '';
      final text = value.trim();
      return text.length > limit ? text.substring(0, limit) : text;
    }

    String date(Object? value) {
      final text = value is String ? value.trim() : '';
      return RegExp(r'^\d{4}(?:-\d{2}(?:-\d{2})?)?$').hasMatch(text)
          ? text
          : '';
    }

    final result = <MetadataCandidate>[];
    for (final item in rows.take(10)) {
      if (item is! Map) continue;
      final id = clean(item['id'], 36);
      final title = clean(item['title']);
      if (!RegExp(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')
              .hasMatch(id) ||
          title.isEmpty) {
        continue;
      }
      final credits = item['artist-credit'];
      final artist = credits is List
          ? credits
                .take(12)
                .map((entry) {
                  if (entry is! Map) return '';
                  final nested = entry['artist'];
                  final join = entry['joinphrase'];
                  final safeJoin = join is String
                      ? join.replaceAll(RegExp(r'[\x00-\x1f]'), '')
                      : '';
                  final separator = safeJoin.length > 30
                      ? safeJoin.substring(0, 30)
                      : safeJoin;
                  return '${clean(entry['name'] ?? (nested is Map ? nested['name'] : null))}$separator';
                })
                .join()
                .trim()
          : '';
      final releases = <MetadataRelease>[];
      final seen = <String>{};
      final rawReleases = item['releases'];
      if (rawReleases is List) {
        for (final release in rawReleases.take(50)) {
          if (release is! Map) continue;
          final name = clean(release['title']);
          final when = date(release['date']);
          if (name.isNotEmpty && seen.add('$name\u0000$when')) {
            releases.add(MetadataRelease(title: name, date: when));
          }
          if (releases.length == 6) break;
        }
      }
      result.add(
        MetadataCandidate(
          id: id,
          title: title,
          artist: artist,
          firstReleaseDate: date(item['first-release-date']),
          releases: List.unmodifiable(releases),
          disambiguation: clean(item['disambiguation']),
        ),
      );
    }
    return List.unmodifiable(result);
  }
}

final musicBrainzLookup = MusicBrainzLookup();
