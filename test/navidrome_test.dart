import 'dart:convert';

import 'package:aura/navidrome.dart';
import 'package:aura/navidrome_ui.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class MemorySecrets implements NavidromeSecrets {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('disk');
    this.value = value;
  }
}

final server = NavidromeServer(
  url: 'https://music.example/test/',
  username: 'listener',
  password: 'test secret',
  name: 'Test music',
);
http.Response response(Map<String, Object?> body) => http.Response(
  jsonEncode({
    'subsonic-response': {'status': 'ok', ...body},
  }),
  200,
  headers: {'content-type': 'application/json'},
);

http.Client libraryClient({bool fail = false, List<Uri>? requests}) =>
    MockClient((request) async {
      requests?.add(request.url);
      final query = request.url.queryParameters;
      expect(query['p'], isNull);
      expect(query['u'], 'listener');
      expect(
        query['t'],
        md5.convert(utf8.encode('test secret${query['s']}')).toString(),
      );
      expect(request.followRedirects, isFalse);
      expect(request.url.path.startsWith('/test/rest/'), isTrue);
      if (fail) return http.Response('unavailable', 503);
      if (request.url.path.endsWith('ping.view')) return response({});
      if (request.url.path.endsWith('getAlbumList2.view')) {
        final offset = int.parse(query['offset']!);
        return response({
          'albumList2': {
            'album': offset < 2
                ? [
                    {'id': 'album-$offset'},
                  ]
                : [],
          },
        });
      }
      if (request.url.path.endsWith('getAlbum.view')) {
        return response({
          'album': {
            'name': 'Album',
            'year': 1998,
            'coverArt': 'cover-id',
            'song': [
              {
                'id': 'song/${query['id']}',
                'title': query['id'],
                'artist': 'Artist',
                'genre': 'Metal',
                'year': query['id'] == 'album-0' ? 2004 : 0,
                'duration': 123.5,
              },
              {'id': 'video', 'isVideo': true},
            ],
          },
        });
      }
      if (request.url.path.endsWith('getCoverArt.view')) {
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw StateError('Unexpected endpoint');
    });

void main() {
  test(
    'stream quality requests preserve original defaults and validate limits',
    () {
      final client = NavidromeClient(
        server,
        client: MockClient((_) async => http.Response('', 200)),
      );
      try {
        final original = client.stream('track/id').queryParameters;
        expect(original['id'], 'track/id');
        expect(original['format'], 'raw');
        expect(original.containsKey('maxBitRate'), isFalse);

        final explicitOriginal = client
            .stream(
              'track/id',
              quality: const NavidromeStreamQuality.original(),
            )
            .queryParameters;
        expect(explicitOriginal['format'], 'raw');
        expect(explicitOriginal.containsKey('maxBitRate'), isFalse);

        final limited = client
            .stream('track/id', quality: NavidromeStreamQuality.limited(128))
            .queryParameters;
        expect(limited['id'], 'track/id');
        expect(limited['maxBitRate'], '128');
        expect(limited.containsKey('format'), isFalse);
        expect(limited.containsKey('estimateContentLength'), isFalse);
        expect(limited['p'], isNull);
        expect(limited['t'], isNotEmpty);
        expect(limited['s'], isNotEmpty);

        expect(() => NavidromeStreamQuality.limited(0), throwsArgumentError);
        expect(() => NavidromeStreamQuality.limited(-1), throwsArgumentError);
      } finally {
        client.close();
      }
    },
  );

  test('offline download uses authenticated request without redirects and closes its client', () async {
    var requests = 0;
    final mock = MockClient((request) async {
      requests++;
      expect(request.followRedirects, isFalse);
      expect(request.url.path, '/test/rest/stream.view');
      expect(request.url.queryParameters['id'], 'song');
      expect(request.url.queryParameters['format'], 'raw');
      expect(request.url.queryParameters.containsKey('maxBitRate'), isFalse);
      expect(request.url.queryParameters['p'], isNull);
      expect(request.url.queryParameters['t'], isNotEmpty);
      return http.Response.bytes(
        [1, 2, 3],
        200,
        headers: {'content-type': 'audio/mpeg'},
      );
    });
    final secrets = MemorySecrets()..value = jsonEncode([server.toJson()]);
    final repository = NavidromeRepository(
      readCache: () async => null,
      writeCache: (_) async {},
      secrets: secrets,
      clientFactory: (value) => NavidromeClient(value, client: mock),
    );
    final uri = Uri.parse('aura://navidrome/${server.id}/song');
    final download = await repository.openDownload(uri);
    expect(await download.response.stream.toBytes(), [1, 2, 3]);
    download.close();
    expect(requests, 1);
  });

  test('URL validation preserves reverse proxy paths and rejects embedded credentials and insecure URLs', () {
    expect(
      navidromeBaseUrl(' https://music.example/test/rest/ ').toString(),
      'https://music.example/test',
    );
    for (final url in [
      'http://music.example',
      'ftp://music.example',
      'https://u:p@music.example',
      'https://music.example?q=secret',
      'https://music.example/#/app',
      'not a URL',
    ]) {
      expect(() => navidromeBaseUrl(url), throwsA(isA<NavidromeException>()));
    }
  });

  test('scan authenticates with fresh salt, pages albums and preserves logical IDs without credentials', () async {
    final requests = <Uri>[];
    final client = NavidromeClient(
      server,
      client: libraryClient(requests: requests),
      pageSize: 1,
    );
    final rows = await client.scan();
    expect(rows, hasLength(2));
    expect(rows.first['durationMs'], 123500);
    expect(rows.first['coverId'], 'cover-id');
    expect(rows.first['genre'], 'Metal');
    expect(rows.first['year'], 2004);
    expect(rows.last['year'], 1998);
    expect(
      requests.every(
        (uri) =>
            uri.path.contains('/rest/get') || uri.path.endsWith('/ping.view'),
      ),
      isTrue,
    );
    expect(
      Uri.parse(rows.first['uri'] as String).pathSegments.last,
      'song/album-0',
    );
    expect(jsonEncode(rows), isNot(contains('test secret')));
    expect(jsonEncode(rows), isNot(contains('https://')));
    expect(
      requests.map((uri) => uri.queryParameters['s']).toSet(),
      hasLength(requests.length),
    );
    expect(
      requests
          .where((uri) => uri.path.endsWith('getAlbumList2.view'))
          .map((uri) => uri.queryParameters['offset']),
      ['0', '1', '2'],
    );
    final stream = client.stream('song/a');
    expect(stream.queryParameters['id'], 'song/a');
    expect(stream.queryParameters['format'], 'raw');
    expect(await client.artwork('cover-id'), [1, 2, 3]);
    client.close();
  });

  test('network, authentication and invalid responses report errors without leaking URLs or secrets', () async {
    for (final client in [
      MockClient((_) async => http.Response('{invalid', 200)),
      MockClient(
        (_) async => http.Response(
          '{"subsonic-response":{"status":"failed","error":{"code":40,"message":"test secret"}}}',
          200,
        ),
      ),
      MockClient(
        (request) async => throw http.ClientException('private ${request.url}'),
      ),
      MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'https://other.example'},
        ),
      ),
    ]) {
      final api = NavidromeClient(server, client: client);
      try {
        await api.request('ping');
        fail('Expected a safe failure');
      } on NavidromeException catch (error) {
        expect(error.message, isNot(contains('test secret')));
        expect(error.message, isNot(contains('t=')));
      }
      api.close();
    }
  });

  test('connect, reload, stream resolution and disconnect retain other sources and failed refresh keeps cache', () async {
    final secrets = MemorySecrets();
    String? cache;
    var fail = false;
    NavidromeRepository repository() => NavidromeRepository(
      readCache: () async => cache,
      writeCache: (value) async {
        cache = value;
      },
      secrets: secrets,
      clientFactory: (server) => NavidromeClient(
        server,
        client: libraryClient(fail: fail),
        pageSize: 1,
      ),
    );
    final repo = repository();
    await repo.connect(server);
    expect((await repository().servers()).single.id, server.id);
    expect(await repository().cachedTracks(), hasLength(2));
    final uri = Uri.parse((await repo.cachedTracks()).first['uri'] as String);
    expect((await repo.resolve(uri)).queryParameters['id'], 'song/album-0');
    expect(cache, isNot(contains('test secret')));
    final previousCache = cache, previousSecrets = secrets.value;
    fail = true;
    await expectLater(repo.connect(server), throwsA(isA<NavidromeException>()));
    expect(cache, previousCache);
    expect(secrets.value, previousSecrets);
    await repo.remove(server.id);
    expect(await repo.servers(), isEmpty);
    expect(await repo.cachedTracks(), isEmpty);
    await expectLater(repo.resolve(uri), throwsA(isA<NavidromeException>()));
  });

  testWidgets(
    'connection form validates URL and password on a narrow display without contacting a server',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = NavidromeRepository(
        readCache: () async => null,
        writeCache: (_) async {},
        secrets: MemorySecrets(),
        clientFactory: (_) => throw StateError('Must not connect'),
      );
      await tester.pumpWidget(
        MaterialApp(home: NavidromeSourcesScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Adaugă server Navidrome'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Conectează'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Introdu adresa HTTPS'), findsOneWidget);
      final password = tester
          .widgetList<TextField>(find.byType(TextField))
          .last;
      expect(password.obscureText, isTrue);
      await tester.tap(find.text('Anulează'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
