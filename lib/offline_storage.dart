import 'package:flutter/foundation.dart';

import 'audio_track.dart';

class OfflineMediaUsage {
  const OfflineMediaUsage({required this.tracks, required this.bytes});
  final int tracks;
  final int bytes;
}

abstract class OfflineStorage extends ChangeNotifier {
  bool busy(String uri);
  Future<bool> hasRecord(String uri);
  Future<Uri?> localUri(String uri);
  Future<List<Map<String, Object?>>> cachedTracks();
  Future<OfflineMediaUsage> mediaUsage() async =>
      throw UnsupportedError('Unavailable');
  Future<void> download(AudioTrack track);
  Future<void> remove(String uri);
}
