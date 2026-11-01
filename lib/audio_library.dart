import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop_library_stub.dart' if (dart.library.io) 'desktop_library.dart';

/// Keeps the Android method-channel contract while providing Windows storage.
class AudioLibrary {
  const AudioLibrary();
  static const _channel = MethodChannel(
    'com.example.symphonium_clone/audio_library',
  );
  static final _desktop = DesktopLibrary();
  static bool get isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<T?> invokeMethod<T>(String method, [Object? arguments]) async {
    if (isWindows) return await _desktop.invoke(method, arguments) as T?;
    return _channel.invokeMethod<T>(method, arguments);
  }

  Future<List<T>?> invokeListMethod<T>(
    String method, [
    Object? arguments,
  ]) async => (await invokeMethod<List<Object?>>(method, arguments))?.cast<T>();
}
