import 'dart:convert';
import 'dart:typed_data';

import 'package:aura/appearance_app.dart';
import 'package:aura/cover_lookup.dart';
import 'package:aura/cover_lookup_screen.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/memory_saved_music_storage.dart';

const id = '12345678-1234-1234-1234-123456789abc';
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
http.Response releaseResponse() => http.Response(
  jsonEncode({
    'releases': [
      {
        'id': id,
        'title': 'Synthetic album',
        'date': '2020',
        'artist-credit': [
          {'name': 'Synthetic artist'},
        ],
      },
      {'id': 'invalid', 'title': 'ignored'},
    ],
  }),
  200,
);

void main() {
  test('search only sends requested fields, escapes query and validates release IDs', () async {
    final lookup = CoverLookup(
      minimumInterval: Duration.zero,
      clientFactory: () => MockClient((request) async {
        expect(request.url.host, 'musicbrainz.org');
        expect(request.url.path, '/ws/2/release/');
        expect(request.followRedirects, isFalse);
        expect(request.headers['User-Agent'], contains('Aura/1.0.0'));
        expect(
          request.url.queryParameters['query'],
          contains(r'release:"A \"title\""'),
        );
        expect(
          request.url.queryParameters['query'],
          contains('artistname:"Artist"'),
        );
        return releaseResponse();
      }),
    );
    final result = await lookup.search('A "title"', 'Artist');
    expect(result.single.id, id);
    expect(result.single.artist, 'Synthetic artist');
    await expectLater(lookup.search('', ''), throwsFormatException);
    await expectLater(lookup.front('../invalid'), throwsFormatException);
  });
  test('rejects untrusted redirects and oversized covers', () async {
    final badRedirect = CoverLookup(
      clientFactory: () => MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://evil.example/image'},
        ),
      ),
    );
    await expectLater(badRedirect.front(id), throwsFormatException);
    final tooLarge = CoverLookup(
      clientFactory: () => MockClient(
        (_) async =>
            http.Response.bytes(Uint8List(CoverLookup.maxImageBytes + 1), 200),
      ),
    );
    await expectLater(tooLarge.front(id), throwsFormatException);
  });
  test('upgrades archive redirect to HTTPS', () async {
    var requests = 0;
    final lookup = CoverLookup(
      clientFactory: () => MockClient((request) async {
        requests++;
        if (requests == 1) {
          return http.Response(
            '',
            307,
            headers: {'location': 'http://archive.org/download/test/image.jpg'},
          );
        }
        expect(request.url.scheme, 'https');
        expect(request.url.host, 'archive.org');
        return http.Response.bytes(png, 200);
      }),
    );
    expect(await lookup.front(id), png);
    expect(requests, 2);
  });
  testWidgets(
    'cover is fetched only on selection and saved only after confirmation',
    (tester) async {
      var searches = 0, images = 0, saves = 0;
      final lookup = CoverLookup(
        minimumInterval: Duration.zero,
        clientFactory: () => MockClient((request) async {
          if (request.url.host == 'musicbrainz.org') {
            searches++;
            return releaseResponse();
          }
          images++;
          expect(request.url.host, 'coverartarchive.org');
          return http.Response.bytes(png, 200);
        }),
      );
      final saved = SavedMusicStore(MemorySavedMusicStorage());
      await saved.load();
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: saved,
          locale: const Locale('en'),
          home: CoverLookupScreen(
            albumKey: 'private-cover-key',
            initialTitle: 'Synthetic album',
            lookup: lookup,
            save: (key, Uint8List bytes) async {
              expect(key, 'private-cover-key');
              expect(bytes, png);
              saves++;
            },
          ),
        ),
      );
      expect(searches, 0);
      await tester.tap(find.byKey(const ValueKey('cover-online-search')));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(searches, 1);
      expect(images, 0);
      expect(saves, 0);
      await tester.tap(find.text('Synthetic album').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(images, 1);
      expect(saves, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      await tester.tap(find.text('Synthetic album').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('cover-online-confirm')));
      await tester.pumpAndSettle();
      expect(saves, 1);
      await tester.pumpWidget(const SizedBox());
      saved.dispose();
    },
  );
}
