import 'dart:async';

import 'package:flutter/foundation.dart';

/// In-memory source artwork cache; it does not own album cover files.
class ArtworkMemoryCache extends ChangeNotifier {
  ArtworkMemoryCache({required this.read, this.limit = 64}) : assert(limit > 0);
  final Future<Uint8List?> Function(String uri) read;
  final int limit;
  final _entries = <String, Future<Uint8List?>>{};
  final _sizes = <String, int>{};
  bool _disposed = false, _queued = false;
  int get entryCount => _entries.length;
  int get byteCount => _sizes.values.fold(0, (total, size) => total + size);

  void _changed() {
    if (_queued || _disposed) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (!_disposed) notifyListeners();
    });
  }

  Future<Uint8List?> load(String uri, String key) {
    final existing = _entries.remove(key);
    if (existing != null) {
      _entries[key] = existing;
      return existing;
    }
    final request = read(uri);
    _entries[key] = request;
    _changed();
    request.then(
      (bytes) {
        if (identical(_entries[key], request)) {
          _sizes[key] = bytes?.length ?? 0;
          _changed();
        }
      },
      onError: (Object _, StackTrace stack) {
        if (identical(_entries[key], request)) {
          _sizes.remove(key);
          _changed();
        }
      },
    );
    while (_entries.length > limit) {
      final oldest = _entries.keys.first;
      _entries.remove(oldest);
      _sizes.remove(oldest);
    }
    return request;
  }

  void clear() {
    _entries.clear();
    _sizes.clear();
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
