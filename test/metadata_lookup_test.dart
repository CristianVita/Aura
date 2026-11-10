import 'dart:async';
import 'dart:convert';

import 'package:aura/appearance_app.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/metadata_lookup.dart';
import 'package:aura/metadata_lookup_screen.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/memory_saved_music_storage.dart';

const syntheticTrack = AudioTrack(
  id: '1',
  title: 'Synthetic',
  artist: 'Artist',
  album: 'Private album',
  durationMs: 12345,
  uri: 'content://media/external/audio/media/1',
  folder: '/private/folder',
);
Map<String, Object?> responseData() => {
  'recordings': [
    {
      'id': '12345678-1234-1234-1234-123456789abc',
      'title': 'Synthetic song',
      'first-release-date': '2001-05-01',
      'disambiguation': 'Live',
      'artist-credit': [
        {'name': 'Alpha', 'joinphrase': ' feat. '},
        {
          'artist': {'name': 'Beta'},
        },
      ],
      'releases': [
        {'title': 'Album A', 'date': '2001-05-01'},
        {'title': 'Album A', 'date': '2001-05-01'},
        {'title': 'Album B', 'date': '2002'},
      ],
    },
  ],
};
http.Response jsonResponse(Map<String, Object?> data) => http.Response(
  jsonEncode(data),
  200,
  headers: {'content-type': 'application/json'},
);

void main() {
  test(
    'request sends only opted-in fields to MusicBrainz and parses candidates',
    () async {
      var requests = 0;
      final lookup = MusicBrainzLookup(
        minimumInterval: Duration.zero,
        clientFactory: () => MockClient((request) async {
          requests++;
          expect(request.method, 'GET');
          expect(request.url.scheme, 'https');
          expect(request.url.host, 'musicbrainz.org');
          expect(request.url.path, '/ws/2/recording/');
          expect(request.followRedirects, isFalse);
          expect(request.headers['User-Agent'], contains('Aura/1.0.0'));
          expect(request.url.queryParameters['fmt'], 'json');
          expect(request.url.queryParameters['limit'], '10');
          final query = request.url.queryParameters['query']!;
          expect(query, contains(r'recording:"A \"quoted\" title"'));
          expect(query, contains('artist:"Someone"'));
          expect(request.url.toString(), isNot(contains('Private')));
          expect(request.url.toString(), isNot(contains('content%3A')));
          expect(request.url.toString(), isNot(contains('Navidrome')));
          return jsonResponse(responseData());
        }),
      );
      final candidates = await lookup.search(
        title: 'A "quoted" title',
        artist: 'Someone',
      );
      expect(requests, 1);
      expect(candidates.single.title, 'Synthetic song');
      expect(candidates.single.artist, 'Alpha feat. Beta');
      expect(candidates.single.firstReleaseDate, '2001-05-01');
      expect(candidates.single.releases.map((release) => release.title), [
        'Album A',
        'Album B',
      ]);
      expect(candidates.single.disambiguation, 'Live');
    },
  );

  test('invalid input, errors, redirects and oversized responses do not leak or retry', () async {
    var requests = 0;
    final lookup = MusicBrainzLookup(
      minimumInterval: Duration.zero,
      clientFactory: () => MockClient((request) async {
        requests++;
        final query = request.url.queryParameters['query']!;
        if (query.contains('busy')) return http.Response('', 503);
        if (query.contains('redirect')) {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://example.invalid/'},
          );
        }
        if (query.contains('malformed')) return http.Response('not json', 200);
        return http.Response(
          'x' * (MusicBrainzLookup.maxResponseBytes + 1),
          200,
        );
      }),
    );
    Future<void> fails(String query, MetadataLookupFailure reason) =>
        expectLater(
          lookup.search(title: query),
          throwsA(
            isA<MetadataLookupException>().having(
              (e) => e.reason,
              'reason',
              reason,
            ),
          ),
        );
    await fails('', MetadataLookupFailure.invalidQuery);
    await fails('bad\nline', MetadataLookupFailure.invalidQuery);
    expect(requests, 0);
    await fails('busy', MetadataLookupFailure.rateLimited);
    await fails('redirect', MetadataLookupFailure.unavailable);
    await fails('malformed', MetadataLookupFailure.invalidResponse);
    await fails('large', MetadataLookupFailure.invalidResponse);
    expect(requests, 4);
  });

  test(
    'concurrent searches are serialized and resume after a failed request',
    () async {
      final first = Completer<http.Response>();
      var calls = 0;
      final lookup = MusicBrainzLookup(
        minimumInterval: Duration.zero,
        clientFactory: () => MockClient((request) {
          calls++;
          if (calls == 1) return first.future;
          return Future.value(jsonResponse(responseData()));
        }),
      );
      final one = lookup.search(title: 'one');
      final two = lookup.search(title: 'two');
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      first.complete(http.Response('', 503));
      await expectLater(one, throwsA(isA<MetadataLookupException>()));
      expect(await two, hasLength(1));
      expect(calls, 2);
    },
  );

  testWidgets(
    'no lookup occurs before explicit tap; editable query and results are read-only',
    (tester) async {
      final saved = SavedMusicStore(MemorySavedMusicStorage());
      await saved.load();
      var requests = 0;
      final lookup = MusicBrainzLookup(
        minimumInterval: Duration.zero,
        clientFactory: () => MockClient((request) async {
          requests++;
          expect(
            request.url.queryParameters['query'],
            contains('recording:"Selected title"'),
          );
          expect(
            request.url.queryParameters['query'],
            contains('artist:"Selected artist"'),
          );
          return jsonResponse(responseData());
        }),
      );
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: saved,
          locale: const Locale('en'),
          home: MetadataLookupScreen(track: syntheticTrack, lookup: lookup),
        ),
      );
      await tester.pumpAndSettle();
      expect(requests, 0);
      expect(find.textContaining('your IP address'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('metadata-title')),
        'Selected title',
      );
      await tester.enterText(
        find.byKey(const ValueKey('metadata-artist')),
        'Selected artist',
      );
      await tester.ensureVisible(find.byKey(const ValueKey('metadata-search')));
      await tester.tap(find.byKey(const ValueKey('metadata-search')));
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      expect(requests, 1);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.text('Synthetic song'), findsOneWidget);
      expect(find.text('Alpha feat. Beta'), findsOneWidget);
      expect(find.textContaining('First release: 2001-05-01'), findsOneWidget);
      expect(saved.data.favorites, isEmpty);
      expect(syntheticTrack.title, 'Synthetic');
      await tester.pumpWidget(const SizedBox());
      saved.dispose();
    },
  );
}
