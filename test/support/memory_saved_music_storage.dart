import 'package:aura/saved_music.dart';

class MemorySavedMusicStorage implements SavedMusicStorage {
  String? value;
  bool failNextWrite = false;
  int writes = 0;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('Disk unavailable');
    }
    writes++;
    value = json;
  }
}
