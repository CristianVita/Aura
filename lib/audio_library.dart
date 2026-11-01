import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'navidrome.dart';

import 'desktop_library_stub.dart' if (dart.library.io) 'desktop_library.dart';

/// Keeps the Android method-channel contract while providing Windows storage.
class AudioLibrary {
  const AudioLibrary();
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
  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    if (method == 'resolvePlaybackUri') {
      final uri = Uri.parse((arguments as Map)['uri'] as String);
      return (uri.scheme == 'aura' ? await navidrome.resolve(uri) : uri)
              .toString()
          as T;
    }
    if (method == 'loadArtwork') {
      final uri = Uri.parse((arguments as Map)['uri'] as String);
      if (uri.scheme == 'aura') return await navidrome.artwork(uri) as T?;
    }
    final local = await _local(method, arguments);
    if (method == 'loadLibrary' ||
        method == 'scanAudio' ||
        method == 'chooseAudioFolder' ||
        method == 'removeAudioFolder') {
      if (local == null && method == 'chooseAudioFolder') return null;
      try {
        final remote = await navidrome.cachedTracks();
        return [...?local as List?, ...remote] as T;
      } catch (_) {
        // A damaged server cache must not hide the local music library.
        return local as T?;
      }
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
