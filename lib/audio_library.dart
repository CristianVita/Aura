import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'navidrome.dart';
import 'offline_storage.dart';
import 'download_network_policy.dart';
import 'offline_store_stub.dart' if (dart.library.io) 'offline_store.dart';

import 'desktop_library_stub.dart' if (dart.library.io) 'desktop_library.dart';

/// Keeps the Android method-channel contract while providing Windows storage.
class AudioLibrary {
  const AudioLibrary({
    this.offlineStore,
    this.navidromeRepository,
    this.localInvoke,
  });
  final OfflineStorage? offlineStore;
  final NavidromeRepository? navidromeRepository;
  final Future<Object?> Function(String, Object?)? localInvoke;
  static const _channel = MethodChannel(
    'com.example.symphonium_clone/audio_library',
  );
  static final _desktop = DesktopLibrary();
  static final navidrome = NavidromeRepository(
    readCache: () async => await _local('loadServerCache', null) as String?,
    writeCache: (json) async {
      await _local('saveServerCache', {'json': json});
    },
  );
  static final downloadNetwork = DownloadNetworkPolicy();
  static final offline = OfflineStore(
    open: navidrome.openDownload,
    networkGuard: downloadNetwork,
  );
  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    final downloads = offlineStore ?? offline;
    final servers = navidromeRepository ?? navidrome;
    if (method == 'resolvePlaybackUri') {
      final uri = Uri.parse((arguments as Map)['uri'] as String);
      if (uri.scheme == 'aura') {
        // A damaged download must not silently use a metered connection.
        if (await downloads.hasRecord(uri.toString())) {
          final local = await downloads.localUri(uri.toString());
          if (local == null) throw StateError('Offline copy unavailable');
          return local.toString() as T;
        }
        final quality =
            (arguments['quality'] as NavidromeStreamQuality?) ??
            const NavidromeStreamQuality.original();
        return (await servers.resolve(uri, quality: quality)).toString() as T;
      }
      return uri.toString() as T;
    }
    if (method == 'loadArtwork') {
      final uri = Uri.parse((arguments as Map)['uri'] as String);
      if (uri.scheme == 'aura') return await servers.artwork(uri) as T?;
    }
    final local = await (localInvoke ?? _local)(method, arguments);
    if (method == 'loadLibrary' ||
        method == 'scanAudio' ||
        method == 'chooseAudioFolder' ||
        method == 'removeAudioFolder') {
      if (local == null && method == 'chooseAudioFolder') return null;
      final merged = <Object?>[...?local as List?];
      final seen = <String>{};
      try {
        for (final row in await servers.cachedTracks()) {
          final uri = row['uri'] as String?;
          if (uri != null && seen.add(uri)) merged.add(row);
        }
      } catch (_) {
        // A damaged server cache must not hide local music.
      }
      try {
        for (final row in await downloads.cachedTracks()) {
          final uri = row['uri'] as String?;
          if (uri != null && seen.add(uri)) merged.add(row);
        }
      } catch (_) {
        // A damaged offline cache must not hide the rest of the library.
      }
      return merged as T;
    }
    return local as T?;
  }

  static Future<Object?> _local(String method, Object? arguments) => isWindows
      ? _desktop.invoke(method, arguments)
      : _channel.invokeMethod<Object?>(method, arguments);

  Future<List<T>?> invokeListMethod<T>(
    String method, [
    Object? arguments,
  ]) async => (await invokeMethod<List<Object?>>(method, arguments))?.cast<T>();
}
