import 'offline_storage.dart';

import 'audio_track.dart';

class OfflineStore extends OfflineStorage {
  OfflineStore({required Object open, Object? networkGuard});
  @override
  bool busy(String uri) => false;
  @override
  Future<Uri?> localUri(String uri) async => null;
  @override
  Future<bool> hasRecord(String uri) async => false;
  @override
  Future<List<Map<String, Object?>>> cachedTracks() async => [];
  @override
  Future<OfflineMediaUsage> mediaUsage() async =>
      const OfflineMediaUsage(tracks: 0, bytes: 0);
  @override
  Future<void> download(AudioTrack track) async =>
      throw UnsupportedError('Unavailable');
  @override
  Future<void> remove(String uri) async =>
      throw UnsupportedError('Unavailable');
}
