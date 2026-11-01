class DesktopLibrary {
  Future<Object?> invoke(String method, Object? arguments) async =>
      throw UnsupportedError(
        'Desktop library is unavailable on this platform.',
      );
}
