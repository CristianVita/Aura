import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:aura/audio_features.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/aura_backup.dart';
import 'package:aura/playback_memory.dart';
import 'package:aura/saved_music.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'support/memory_saved_music_storage.dart';

AudioTrack track(String uri, [String title = 'Song']) => AudioTrack(
  id: uri,
  uri: uri,
  title: title,
  artist: 'Artist',
  album: 'Album',
  durationMs: 90000,
);

class BackupMemoryStorage implements PlaybackMemoryStorage {
  String? value;
  bool failNext = false;
  int writes = 0;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    writes++;
    if (failNext) {
      failNext = false;
      throw StateError('Disk failure');
    }
    value = json;
  }
}

class MemoryJournal implements BackupJournal {
  String? value;
  final failAt = <int>{};
  int attempts = 0;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    if (failAt.contains(++attempts)) throw StateError('Journal failure');
    value = json;
  }
}

class FailingSavedStorage extends MemorySavedMusicStorage {
  int attempts = 0;
  final failAt = <int>{};
  @override
  Future<void> write(String json) async {
    if (failAt.contains(++attempts)) throw StateError('Saved failure');
    await super.write(json);
  }
}

class DelayedSavedStorage extends MemorySavedMusicStorage {
  Future<void>? gate;
  @override
  Future<void> write(String json) async {
    await gate;
    await super.write(json);
  }
}

AuraBackup sampleBackup() => AuraBackup.capture(
  SavedMusicData(
    favorites: ['old'],
    ratings: {'old': 4.5},
    playlists: [
      MusicPlaylist(id: 'mix', name: 'Imported', tracks: ['old']),
    ],
    starSize: RatingStarSize.large,
    playbackSpeed: 1.5,
    audioFeatures: const AudioFeatures(
      crossfadeSeconds: 3,
      pauseWhenDucked: true,
    ),
  ),
  PlaybackMemoryData(
    history: const [
      ListeningEntry(uri: 'old', lastPlayedMs: 2000, playCount: 3),
    ],
    filters: const LibraryFilters(minimumSeconds: 30),
  ),
  [track('old')],
  now: DateTime.utc(2026, 11, 4),
);

Uint8List changedPayload(
  AuraBackup backup,
  void Function(Map<String, dynamic>) change,
) {
  final root = jsonDecode(utf8.decode(backup.encode())) as Map<String, dynamic>;
  final payload = root['payload'] as Map<String, dynamic>;
  change(payload);
  root['checksum'] = sha256
      .convert(utf8.encode(jsonEncode(payload)))
      .toString();
  return Uint8List.fromList(utf8.encode(jsonEncode(root)));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('restore waits for queued edits, commits both stores and preserves the live session', () async {
    final disk = DelayedSavedStorage();
    final saved = SavedMusicStore(disk);
    final memory = PlaybackMemoryStore(BackupMemoryStorage());
    await saved.load();
    await memory.load();
    final session = PlaybackSession(
      uris: ['current'],
      index: 0,
      positionMs: 1800,
      shuffle: true,
      order: [0],
      loop: LoopMode.all,
    );
    await memory.saveSession(session);
    final gate = Completer<void>();
    disk.gate = gate.future;
    final queued = saved.setRating('queued', 3.5);
    final journal = MemoryJournal();
    var applied = false;
    final service = BackupRestoreService(
      saved: saved,
      memory: memory,
      journal: journal,
      applyPreferences: () async {
        expect(saved.data.playbackSpeed, 1.5);
        expect(memory.data.filters.minimumSeconds, 30);
        applied = true;
      },
    );
    final operation = service.restore(
      BackupPlan(sampleBackup(), [track('new')]),
      settings: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(journal.value, isNull);
    gate.complete();
    await queued;
    await operation;
    expect(saved.data.ratings, {'new': 4.5, 'queued': 3.5});
    expect(memory.data.session!.toJson(), session.toJson());
    expect(applied, isTrue);
    expect(jsonDecode(journal.value!)['state'], 'complete');
    saved.dispose();
    memory.dispose();
  });
  test('backup roundtrip includes organization and settings but excludes queue session', () {
    final session = PlaybackSession(
      uris: ['old'],
      index: 0,
      positionMs: 1500,
      shuffle: false,
      order: [0],
      loop: LoopMode.off,
    );
    final backup = AuraBackup.capture(
      sampleBackup().saved,
      PlaybackMemoryData(
        history: sampleBackup().memory.history,
        session: session,
      ),
      [track('old')],
    );
    final restored = AuraBackup.decode(backup.encode());
    expect(restored.saved.ratings['old'], 4.5);
    expect(restored.saved.audioFeatures.crossfadeSeconds, 3);
    expect(restored.saved.audioFeatures.pauseWhenDucked, isTrue);
    expect(restored.saved.starSize, RatingStarSize.large);
    expect(restored.memory.history.single.playCount, 3);
    expect(restored.memory.session, isNull);
    expect(restored.catalog['old'], AuraBackup.identity(track('old')));
    expect(
      (jsonDecode(utf8.decode(backup.encode()))['payload'] as Map).keys.toSet(),
      {'createdAt', 'savedMusic', 'playback', 'catalog'},
    );
  });

  test('invalid checksum, version, size and semantically invalid content are rejected', () {
    final backup = sampleBackup();
    final damaged =
        jsonDecode(utf8.decode(backup.encode())) as Map<String, dynamic>;
    damaged['payload']['savedMusic']['ratings']['old'] = 5;
    expect(
      () => AuraBackup.decode(utf8.encode(jsonEncode(damaged))),
      throwsFormatException,
    );
    damaged['version'] = 99;
    expect(
      () => AuraBackup.decode(utf8.encode(jsonEncode(damaged))),
      throwsFormatException,
    );
    expect(
      () => AuraBackup.decode(Uint8List(maxBackupBytes + 1)),
      throwsFormatException,
    );
    expect(() => AuraBackup.decode([]), throwsFormatException);
    expect(
      () => AuraBackup.decode(
        changedPayload(backup, (p) => p['savedMusic']['ratings']['old'] = 4.25),
      ),
      throwsFormatException,
    );
    expect(
      () => AuraBackup.decode(
        changedPayload(
          backup,
          (p) => p['playback']['history'][0]['playCount'] = -1,
        ),
      ),
      throwsFormatException,
    );
    expect(
      () => AuraBackup.decode(
        changedPayload(
          backup,
          (p) => p['savedMusic']['playlists'][0]['name'] = '',
        ),
      ),
      throwsFormatException,
    );
  });

  test('local ID collisions remap by unique metadata and ambiguous songs remain unavailable', () {
    final plan = BackupPlan(sampleBackup(), [
      track('old', 'Different song'),
      track('new'),
    ]);
    expect(plan.mapping['old'], 'new');
    expect(plan.remapped, 1);
    final ambiguous = BackupPlan(sampleBackup(), [
      track('new'),
      track('duplicate'),
    ]);
    expect(ambiguous.matched, 0);
    expect(ambiguous.mapping['old'], startsWith('aura-backup://unavailable/'));
    expect(BackupPlan(sampleBackup(), []).mapping, ambiguous.mapping);
    final duplicateSource = AuraBackup.capture(
      SavedMusicData(ratings: {'one': 2, 'two': 5}),
      PlaybackMemoryData(),
      [track('one'), track('two')],
    );
    final manyToOne = BackupPlan(duplicateSource, [track('new')]);
    expect(manyToOne.matched, 0);
    expect(manyToOne.unavailable, 2);
  });

  test('Navidrome logical IDs remain stable when metadata changes or source is disconnected', () {
    const uri = 'aura://navidrome/server/song';
    final backup = AuraBackup.capture(
      SavedMusicData(ratings: {uri: 5}),
      PlaybackMemoryData(),
      [track(uri)],
    );
    final plan = BackupPlan(backup, [track(uri, 'Renamed'), track('local')]);
    expect(plan.mapping[uri], uri);
    expect(plan.matched, 1);
    final missing = BackupPlan(backup, []);
    expect(missing.mapping[uri], uri);
    expect(missing.unavailable, 1);
  });

  test('title-only backup matches the original metadata and preserves current titles on merge', () {
    final backup = AuraBackup.capture(
      SavedMusicData(trackTitles: {'old': 'Chosen title'}),
      PlaybackMemoryData(),
      [track('old', 'Original tag')],
    );
    final plan = BackupPlan(backup, [track('new', 'Original tag')]);
    expect(plan.mapping['old'], 'new');
    expect(
      plan
          .savedResult(SavedMusicData(), replace: true, settings: false)
          .trackTitles['new'],
      'Chosen title',
    );
    expect(
      plan
          .savedResult(
            SavedMusicData(trackTitles: {'new': 'Current'}),
            replace: false,
            settings: false,
          )
          .trackTitles['new'],
      'Current',
    );
  });

  test('merge is idempotent, keeps current ratings and playlist names; settings are opt-in', () {
    final plan = BackupPlan(sampleBackup(), [track('new')]);
    final current = SavedMusicData(
      favorites: ['kept'],
      ratings: {'new': 2},
      playlists: [
        MusicPlaylist(id: 'mix', name: 'Current', tracks: ['kept']),
      ],
    );
    final merged = plan.savedResult(current, replace: false, settings: false);
    expect(merged.favorites, {'kept', 'new'});
    expect(merged.ratings['new'], 2);
    expect(merged.playlists.single.name, 'Current');
    expect(merged.playlists.single.tracks, ['kept', 'new']);
    expect(merged.starSize, RatingStarSize.medium);
    expect(merged.playbackSpeed, 1);
    expect(merged.audioFeatures.pauseWhenDucked, isFalse);
    expect(
      plan.savedResult(merged, replace: false, settings: false).encode(),
      merged.encode(),
    );
    final replaced = plan.savedResult(current, replace: true, settings: true);
    expect(replaced.favorites, {'new'});
    expect(replaced.ratings['new'], 4.5);
    expect(replaced.playlists.single.name, 'Imported');
    expect(replaced.starSize, RatingStarSize.large);
    expect(replaced.playbackSpeed, 1.5);
    expect(replaced.audioFeatures.pauseWhenDucked, isTrue);
  });

  test('history merge keeps latest timestamp/max count and preserves the current queue', () {
    final session = PlaybackSession(
      uris: ['kept'],
      index: 0,
      positionMs: 4000,
      shuffle: false,
      order: [0],
      loop: LoopMode.one,
    );
    final current = PlaybackMemoryData(
      session: session,
      history: const [
        ListeningEntry(uri: 'new', lastPlayedMs: 4000, playCount: 2),
      ],
    );
    final plan = BackupPlan(sampleBackup(), [track('new')]);
    final merged = plan.memoryResult(current, replace: false, settings: false);
    expect(merged.history.single.playCount, 3);
    expect(merged.history.single.lastPlayedMs, 4000);
    expect(identical(merged.session, session), isTrue);
    expect(merged.filters.minimumSeconds, 0);
    expect(
      plan.memoryResult(merged, replace: false, settings: false).encode(),
      merged.encode(),
    );
    final replaced = plan.memoryResult(current, replace: true, settings: true);
    expect(identical(replaced.session, session), isTrue);
    expect(replaced.filters.minimumSeconds, 30);
  });

  test(
    'second-store failure rolls back first store and unlocks the player',
    () async {
      final savedStorage = MemorySavedMusicStorage()
        ..value = SavedMusicData(favorites: ['kept']).encode();
      final memoryStorage = BackupMemoryStorage();
      final saved = SavedMusicStore(savedStorage),
          memory = PlaybackMemoryStore(memoryStorage);
      await saved.load();
      await memory.load();
      final beforeSaved = saved.data.encode(),
          beforeMemory = memory.data.encode();
      final journal = MemoryJournal();
      var locks = 0, unlocks = 0;
      final service = BackupRestoreService(
        saved: saved,
        memory: memory,
        journal: journal,
        beforeRestore: () async {
          locks++;
        },
        afterRestore: () {
          unlocks++;
        },
      );
      memoryStorage.failNext = true;
      await expectLater(
        service.restore(
          BackupPlan(sampleBackup(), [track('new')]),
          replace: true,
        ),
        throwsStateError,
      );
      expect(saved.data.encode(), beforeSaved);
      expect(memory.data.encode(), beforeMemory);
      expect(savedStorage.value, beforeSaved);
      expect(jsonDecode(journal.value!)['state'], 'complete');
      expect([locks, unlocks], [1, 1]);
      expect(service.recoveryRequired, isFalse);
      saved.dispose();
      memory.dispose();
    },
  );

  test('failed rollback locks restoration and can recover from its durable journal', () async {
    final savedStorage = FailingSavedStorage()
      ..value = SavedMusicData(favorites: ['kept']).encode();
    final memoryStorage = BackupMemoryStorage();
    final saved = SavedMusicStore(savedStorage),
        memory = PlaybackMemoryStore(memoryStorage);
    await saved.load();
    await memory.load();
    final before = saved.data.encode();
    final journal = MemoryJournal();
    var unlocks = 0;
    final service = BackupRestoreService(
      saved: saved,
      memory: memory,
      journal: journal,
      afterRestore: () {
        unlocks++;
      },
    );
    savedStorage.failAt.add(2);
    memoryStorage.failNext = true;
    final plan = BackupPlan(sampleBackup(), [track('new')]);
    await expectLater(service.restore(plan, replace: true), throwsStateError);
    expect(service.recoveryRequired, isTrue);
    expect(unlocks, 0);
    expect(jsonDecode(journal.value!)['state'], 'pending');
    await expectLater(service.restore(plan), throwsStateError);
    await service.recoverNow();
    expect(service.recoveryRequired, isFalse);
    expect(saved.data.encode(), before);
    expect(unlocks, 1);
    saved.dispose();
    memory.dispose();
  });

  test('startup recovery restores both snapshots after an interrupted import and is repeatable', () async {
    final oldSaved = SavedMusicData(favorites: ['before']).encode();
    final oldMemory = PlaybackMemoryData(
      history: const [
        ListeningEntry(uri: 'before', lastPlayedMs: 100, playCount: 1),
      ],
    ).encode();
    final journal = MemoryJournal()
      ..value = jsonEncode({
        'version': 1,
        'state': 'pending',
        'savedBefore': oldSaved,
        'memoryBefore': oldMemory,
      });
    final saved = MemorySavedMusicStorage()
      ..value = sampleBackup().saved.encode();
    final memory = BackupMemoryStorage()..failNext = true;
    await expectLater(
      BackupRestoreService.recover(
        journal: journal,
        saved: saved,
        memory: memory,
      ),
      throwsStateError,
    );
    expect(jsonDecode(journal.value!)['state'], 'pending');
    expect(
      await BackupRestoreService.recover(
        journal: journal,
        saved: saved,
        memory: memory,
      ),
      isTrue,
    );
    expect(saved.value, oldSaved);
    expect(memory.value, oldMemory);
    expect(
      await BackupRestoreService.recover(
        journal: journal,
        saved: saved,
        memory: memory,
      ),
      isFalse,
    );
  });

  test(
    'journal commit and playback-application failures revert imported data',
    () async {
      for (final failCommit in [true, false]) {
        final saved = SavedMusicStore(MemorySavedMusicStorage());
        final memory = PlaybackMemoryStore(BackupMemoryStorage());
        await saved.load();
        await memory.load();
        final journal = MemoryJournal();
        if (failCommit) journal.failAt.add(2);
        var applications = 0;
        final service = BackupRestoreService(
          saved: saved,
          memory: memory,
          journal: journal,
          applyPreferences: () async {
            if (!failCommit && ++applications == 1) {
              throw StateError('Player failure');
            }
          },
        );
        await expectLater(
          service.restore(
            BackupPlan(sampleBackup(), [track('new')]),
            settings: true,
          ),
          throwsStateError,
        );
        expect(saved.data.ratings, isEmpty);
        expect(memory.data.history, isEmpty);
        expect(service.recoveryRequired, isFalse);
        saved.dispose();
        memory.dispose();
      }
    },
  );
}
