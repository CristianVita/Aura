import 'dart:convert';

import 'package:aura/rename_title_recovery.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

class FakeJournal implements RenameTitleJournal {
  String? value;
  String? current = 'original.mp3';
  bool cannotRead = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    value = json;
  }

  @override
  Future<String?> filename(String uri) async {
    if (cannotRead) throw StateError('permission');
    return current;
  }
}

void main() {
  const uri = 'content://media/external/audio/media/123';
  test('recovers a completed rename and persists the display title', () async {
    final storage = MemorySavedMusicStorage();
    final saved = SavedMusicStore(storage);
    await saved.load();
    final journal = FakeJournal();
    final recovery = RenameTitleRecovery(journal: journal, saved: saved);
    await recovery.prepare(
      uri: uri,
      original: 'original.mp3',
      title: 'New title',
    );
    journal.current = 'New title.mp3';
    expect(await recovery.recover(), RenameTitleRecoveryResult.applied);
    expect(saved.data.trackTitles[uri], 'New title');
    expect(SavedMusicData.decode(storage.value!).trackTitles[uri], 'New title');
    expect(jsonDecode(journal.value!)['state'], 'complete');
    expect(await recovery.recover(), RenameTitleRecoveryResult.none);
    saved.dispose();
  });
  test(
    'cancellation never changes title and uncertain state stays pending',
    () async {
      final saved = SavedMusicStore(MemorySavedMusicStorage());
      await saved.load();
      final journal = FakeJournal();
      final recovery = RenameTitleRecovery(journal: journal, saved: saved);
      await recovery.prepare(
        uri: uri,
        original: 'original.mp3',
        title: 'New title',
      );
      journal.cannotRead = true;
      expect(await recovery.recover(), RenameTitleRecoveryResult.deferred);
      expect(jsonDecode(journal.value!)['state'], 'pending');
      await expectLater(
        recovery.prepare(uri: uri, original: 'original.mp3', title: 'Other'),
        throwsStateError,
      );
      journal.cannotRead = false;
      expect(await recovery.recover(), RenameTitleRecoveryResult.unchanged);
      expect(saved.data.trackTitles, isEmpty);
      saved.dispose();
    },
  );
  test('a failed title write keeps journal for retry', () async {
    final storage = MemorySavedMusicStorage();
    final saved = SavedMusicStore(storage);
    await saved.load();
    final journal = FakeJournal();
    final recovery = RenameTitleRecovery(journal: journal, saved: saved);
    await recovery.prepare(
      uri: uri,
      original: 'original.mp3',
      title: 'New title',
    );
    journal.current = 'New title.mp3';
    storage.failNextWrite = true;
    await expectLater(recovery.recover(), throwsStateError);
    expect(jsonDecode(journal.value!)['state'], 'pending');
    expect(saved.data.trackTitles, isEmpty);
    expect(await recovery.recover(), RenameTitleRecoveryResult.applied);
    expect(saved.data.trackTitles[uri], 'New title');
    saved.dispose();
  });
}
