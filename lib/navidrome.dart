import 'app_language.dart';
import 'audio_track.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

class NavidromeException implements Exception {
  const NavidromeException(this.message);
  final String message;
  @override
  String toString() => message;
}

Uri navidromeBaseUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw NavidromeException(
      AppText.current.uiEnterTheHTTPSServerAddressWithoutA,
    );
  }
  var path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  if (path.endsWith('/rest')) path = path.substring(0, path.length - 5);
  return uri.replace(path: path);
}

class NavidromeServer {
  NavidromeServer({
    required String url,
    required this.username,
    required this.password,
    required this.name,
  }) : base = navidromeBaseUrl(url) {
    if (username.trim().isEmpty || password.isEmpty || name.trim().isEmpty) {
      throw NavidromeException(
        AppText.current.uiEnterTheSourceNameUsernameAndPassword,
      );
    }
  }
  final Uri base;
  final String username, password, name;
  String get id => sha256
      .convert(utf8.encode('$base\n$username'))
      .toString()
      .substring(0, 24);
  Map<String, Object> toJson() => {
    'url': base.toString(),
    'username': username,
    'password': password,
    'name': name,
  };
  factory NavidromeServer.fromJson(Map<String, dynamic> value) =>
      NavidromeServer(
        url: value['url'] as String,
        username: value['username'] as String,
        password: value['password'] as String,
        name: value['name'] as String,
      );
}

/// Implements the read-only Subsonic endpoints supported by Navidrome.
class NavidromeClient {
  NavidromeClient(this.server, {http.Client? client, this.pageSize = 500})
    : _client = client ?? http.Client();
  final NavidromeServer server;
  final http.Client _client;
  final int pageSize;
  void close() => _client.close();
  Uri endpoint(String method, [Map<String, String> parameters = const {}]) {
    final random = Random.secure();
    final salt = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return server.base.replace(
      path: '${server.base.path}/rest/$method.view',
      queryParameters: {
        'u': server.username,
        's': salt,
        't': md5.convert(utf8.encode('${server.password}$salt')).toString(),
        'v': '1.16.1',
        'c': 'Aura',
        'f': 'json',
        ...parameters,
      },
    );
  }

  Future<Uint8List> _bytes(Uri uri, int limit) async {
    try {
      final request = http.Request('GET', uri)..followRedirects = false;
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw NavidromeException(
          AppText.current.uiTheServerDidNotRespondCorrectlyCheck,
        );
      }
      if (response.contentLength != null && response.contentLength! > limit) {
        throw NavidromeException(AppText.current.uiTheServerResponseIsTooLarge);
      }
      final output = BytesBuilder(copy: false);
      await for (final part in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        if (output.length + part.length > limit) {
          throw NavidromeException(
            AppText.current.uiTheServerResponseIsTooLarge,
          );
        }
        output.add(part);
      }
      return output.takeBytes();
    } on NavidromeException {
      rethrow;
    } catch (_) {
      // Network exceptions can contain an authenticated URL. Never display it.
      throw NavidromeException(
        AppText.current.uiCouldNotReachTheServerCheckYour,
      );
    }
  }

  Future<Map<String, dynamic>> request(
    String method, [
    Map<String, String> parameters = const {},
  ]) async {
    final bytes = await _bytes(endpoint(method, parameters), 16 * 1024 * 1024);
    try {
      final response =
          (jsonDecode(utf8.decode(bytes))
                  as Map<String, dynamic>)['subsonic-response']
              as Map<String, dynamic>;
      if (response['status'] != 'ok') {
        final code = (response['error'] as Map?)?['code'];
        throw NavidromeException(
          code == 40 || code == 41
              ? AppText
                    .current
                    .uiAuthenticationFailedCheckYourUsernameAndPassword
              : AppText.current.uiNavidromeRejectedTheRequestCheckTheAccounts,
        );
      }
      return response;
    } on NavidromeException {
      rethrow;
    } catch (_) {
      throw NavidromeException(AppText.current.uiTheAddressDidNotReturnAValid);
    }
  }

  Future<List<Map<String, Object?>>> scan() async {
    await request('ping');
    final songs = <String, Map<String, Object?>>{};
    final seenAlbums = <String>{};
    for (var offset = 0; ; offset += pageSize) {
      final page = await request('getAlbumList2', {
        'type': 'alphabeticalByName',
        'size': '$pageSize',
        'offset': '$offset',
      });
      final albums = ((page['albumList2'] as Map?)?['album'] as List?) ?? [];
      for (final entry in albums) {
        final id = (entry as Map)['id'] as String;
        if (!seenAlbums.add(id)) {
          throw NavidromeException(
            AppText.current.uiTheServerRepeatedAnAlbumPageYour,
          );
        }
        final album = (await request('getAlbum', {'id': id}))['album'] as Map;
        for (final value in (album['song'] as List? ?? [])) {
          final song = value as Map;
          if (song['isVideo'] == true) continue;
          final songId = song['id'] as String;
          final uri = Uri(
            scheme: 'aura',
            host: 'navidrome',
            pathSegments: [server.id, songId],
          ).toString();
          songs[songId] = {
            'id': songId,
            'uri': uri,
            'title': song['title'] as String? ?? '',
            'artist': song['artist'] as String? ?? '',
            'album': song['album'] as String? ?? album['name'] as String? ?? '',
            'genre': song['genre'] as String? ?? '',
            'year': metadataYear(song['year']) != 0
                ? metadataYear(song['year'])
                : metadataYear(album['year']),
            'coverId':
                song['coverArt'] as String? ??
                album['coverArt'] as String? ??
                '',
            'durationMs': ((song['duration'] as num? ?? 0) * 1000).round(),
            'folder': 'Navidrome · ${server.name}',
            'modifiedSeconds': 0,
          };
        }
      }
      if (albums.length < pageSize) break;
    }
    return songs.values.toList()..sort(
      (a, b) => (a['title'] as String).toLowerCase().compareTo(
        (b['title'] as String).toLowerCase(),
      ),
    );
  }

  Uri stream(String id) => endpoint('stream', {'id': id, 'format': 'raw'});
  Future<Uint8List> artwork(String id) => _bytes(
    endpoint('getCoverArt', {'id': id, 'size': '512'}),
    5 * 1024 * 1024,
  );
}

abstract class NavidromeSecrets {
  Future<String?> read();
  Future<void> write(String value);
}

class DeviceNavidromeSecrets implements NavidromeSecrets {
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read() => _storage.read(key: 'aura_navidrome_accounts_v1');
  @override
  Future<void> write(String value) =>
      _storage.write(key: 'aura_navidrome_accounts_v1', value: value);
}

class NavidromeRepository {
  NavidromeRepository({
    required this.readCache,
    required this.writeCache,
    NavidromeSecrets? secrets,
    NavidromeClient Function(NavidromeServer)? clientFactory,
  }) : secrets = secrets ?? DeviceNavidromeSecrets(),
       clientFactory = clientFactory ?? NavidromeClient.new;
  final Future<String?> Function() readCache;
  final Future<void> Function(String) writeCache;
  final NavidromeSecrets secrets;
  final NavidromeClient Function(NavidromeServer) clientFactory;
  Future<List<NavidromeServer>>? _accounts;
  Future<List<NavidromeServer>> servers() => _accounts ??= _readServers();
  Future<List<NavidromeServer>> _readServers() async {
    try {
      final saved = await secrets.read();
      return saved == null
          ? []
          : (jsonDecode(saved) as List)
                .map(
                  (row) =>
                      NavidromeServer.fromJson(row as Map<String, dynamic>),
                )
                .toList();
    } catch (_) {
      _accounts = null;
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> cachedTracks() async {
    final saved = await readCache();
    if (saved == null) return [];
    final root = jsonDecode(saved) as Map<String, dynamic>;
    if (root['version'] != 1) {
      throw const FormatException('Unsupported server cache');
    }
    return (root['tracks'] as List)
        .map((row) => Map<String, Object?>.from(row as Map))
        .toList();
  }

  Future<void> connect(NavidromeServer server) async {
    final client = clientFactory(server);
    try {
      final tracks = await client.scan();
      final accounts = await servers();
      final cached = await cachedTracks();
      final next = [
        ...cached.where(
          (row) =>
              Uri.parse(row['uri'] as String).pathSegments.first != server.id,
        ),
        ...tracks,
      ];
      await secrets.write(
        jsonEncode(
          [
            ...accounts.where((a) => a.id != server.id),
            server,
          ].map((a) => a.toJson()).toList(),
        ),
      );
      _accounts = null;
      await writeCache(jsonEncode({'version': 1, 'tracks': next}));
    } finally {
      client.close();
    }
  }

  Future<void> remove(String id) async {
    final accounts = await servers();
    final tracks = await cachedTracks();
    await writeCache(
      jsonEncode({
        'version': 1,
        'tracks': tracks
            .where(
              (row) => Uri.parse(row['uri'] as String).pathSegments.first != id,
            )
            .toList(),
      }),
    );
    await secrets.write(
      jsonEncode(
        accounts.where((a) => a.id != id).map((a) => a.toJson()).toList(),
      ),
    );
    _accounts = null;
  }

  Future<NavidromeServer> _server(Uri uri) async {
    if (uri.scheme != 'aura' ||
        uri.host != 'navidrome' ||
        uri.pathSegments.length != 2) {
      throw NavidromeException(AppText.current.uiInvalidServerTrack);
    }
    final accounts = await servers();
    for (final server in accounts) {
      if (server.id == uri.pathSegments.first) return server;
    }
    throw NavidromeException(
      AppText.current.uiReconnectTheNavidromeSourceToPlayThis,
    );
  }

  Future<Uri> resolve(Uri uri) async {
    final client = clientFactory(await _server(uri));
    try {
      return client.stream(uri.pathSegments.last);
    } finally {
      client.close();
    }
  }

  Future<({http.StreamedResponse response, void Function() close})>
  openDownload(Uri uri) async {
    final client = clientFactory(await _server(uri));
    try {
      final request = http.Request('GET', client.stream(uri.pathSegments.last))
        ..followRedirects = false;
      final response = await client._client
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw const NavidromeException('Download failed');
      }
      return (response: response, close: client.close);
    } catch (_) {
      client.close();
      throw const NavidromeException('Download failed');
    }
  }

  Future<Uint8List?> artwork(Uri uri) async {
    if (uri.pathSegments.last.isEmpty) return null;
    final client = clientFactory(await _server(uri));
    try {
      return await client.artwork(uri.pathSegments.last);
    } finally {
      client.close();
    }
  }
}
