import 'app_language.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'audio_library.dart';
import 'audio_track.dart';
import 'cover_backup_storage.dart';
import 'playback_memory.dart';
import 'saved_music.dart';

const maxBackupBytes = 40 * 1024 * 1024;

class AuraBackup {
  AuraBackup({
    required this.createdAt,
    required this.saved,
    required this.memory,
    required this.catalog,
    this.covers,
  });
  final DateTime createdAt;
  final SavedMusicData saved;
  final PlaybackMemoryData memory;
  final Map<String, String> catalog;
  // Null denotes a legacy backup that contains no cover snapshot.
  final Map<String, Uint8List>? covers;
  static String identity(AudioTrack track) => jsonEncode([
    track.title.trim().toLowerCase(),
    track.artist.trim().toLowerCase(),
    track.album.trim().toLowerCase(),
    track.durationMs ~/ 1000,
  ]);
  Set<String> get references => {
    ...saved.favorites,
    ...saved.ratings.keys,
    ...saved.trackTitles.keys,
    for (final playlist in saved.playlists) ...playlist.tracks,
    for (final album in saved.albums) ...album.tracks,
    for (final entry in memory.history) entry.uri,
  };
  factory AuraBackup.capture(
    SavedMusicData saved,
    PlaybackMemoryData memory,
    List<AudioTrack> library, {
    DateTime? now,
    Map<String, Uint8List>? covers,
  }) {
    final backup = AuraBackup(
      createdAt: (now ?? DateTime.now()).toUtc(),
      saved: saved,
      memory: PlaybackMemoryData(
        history: memory.history,
        filters: memory.filters,
      ),
      catalog: {},
      covers: covers == null
          ? null
          : {
              for (final entry in covers.entries)
                entry.key: Uint8List.fromList(entry.value),
            },
    );
    final references = backup.references;
    for (final track in library) {
      if (references.contains(track.uri)) {
        backup.catalog[track.uri] = identity(track);
      }
    }
    return backup;
  }
  Uint8List encode() {
    if (covers != null) validateCoverBackupShape(covers!);
    final payload = {
      'createdAt': createdAt.toUtc().toIso8601String(),
      'savedMusic': jsonDecode(saved.encode()),
      'playback': jsonDecode(memory.encode()),
      'catalog': catalog,
      if (covers != null)
        'covers': {
          for (final entry in covers!.entries)
            entry.key: base64Encode(entry.value),
        },
    };
    final checksum = sha256
        .convert(utf8.encode(jsonEncode(payload)))
        .toString();
    final bytes = Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert({
          'format': 'aura.backup',
          'version': covers == null ? 1 : 2,
          'payload': payload,
          'checksum': checksum,
        }),
      ),
    );
    if (bytes.length > maxBackupBytes) {
      throw const FormatException('Backup too large');
    }
    return bytes;
  }

  factory AuraBackup.decode(List<int> bytes) {
    if (bytes.length > maxBackupBytes || bytes.isEmpty) {
      throw const FormatException('Invalid backup size');
    }
    try {
      final root = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      if (root['format'] != 'aura.backup' ||
          (root['version'] != 1 && root['version'] != 2)) {
        throw const FormatException();
      }
      final payload = root['payload'] as Map<String, dynamic>;
      if (root['checksum'] !=
          sha256.convert(utf8.encode(jsonEncode(payload))).toString()) {
        throw const FormatException('Checksum mismatch');
      }
      final saved = SavedMusicData.decode(jsonEncode(payload['savedMusic']));
      final memory = PlaybackMemoryData.decode(jsonEncode(payload['playback']));
      if (memory.session != null ||
          saved.playlists.length > 1000 ||
          saved.albums.length > 1000 ||
          saved.ratings.length > 50000 ||
          saved.trackTitles.length > 50000 ||
          saved.favorites.length > 50000 ||
          memory.history.length > 100) {
        throw const FormatException();
      }
      if (memory.history.map((e) => e.uri).toSet().length !=
              memory.history.length ||
          memory.history.any(
            (e) => e.uri.isEmpty || e.lastPlayedMs < 0 || e.playCount < 1,
          )) {
        throw const FormatException();
      }
      if (saved.playlists.any(
        (p) =>
            p.name.length > 80 || p.id.length > 200 || p.tracks.length > 10000,
      )) {
        throw const FormatException();
      }
      final catalog = (payload['catalog'] as Map<String, dynamic>).map(
        (uri, fingerprint) => MapEntry(uri, fingerprint as String),
      );
      Map<String, Uint8List>? covers;
      if (root['version'] == 2) {
        final rawCovers = payload['covers'] as Map<String, dynamic>;
        if (rawCovers.length > maxCoverBackupCount) {
          throw const FormatException();
        }
        covers = {};
        var total = 0;
        for (final entry in rawCovers.entries) {
          if (entry.value is! String ||
              (entry.value as String).length >
                  ((10 * 1024 * 1024 + 2) ~/ 3) * 4) {
            throw const FormatException();
          }
          final bytes = base64Decode(entry.value as String);
          total += bytes.length;
          if (total > maxCoverBackupBytes) throw const FormatException();
          covers[entry.key] = bytes;
        }
        validateCoverBackupShape(covers);
      }
      final backup = AuraBackup(
        createdAt: DateTime.parse(payload['createdAt'] as String).toUtc(),
        saved: saved,
        memory: memory,
        catalog: catalog,
        covers: covers,
      );
      if (backup.references.any((uri) => uri.isEmpty || uri.length > 8192) ||
          catalog.length > 50000 ||
          catalog.values.any((value) => value.length > 16384)) {
        throw const FormatException();
      }
      return backup;
    } catch (_) {
      throw FormatException(AppText.current.uiTheFileIsNotAValidAura);
    }
  }
}

class BackupPlan {
  BackupPlan(AuraBackup backup, List<AudioTrack> library) : source = backup {
    final byUri = {for (final track in library) track.uri: track};
    final byIdentity = <String, List<AudioTrack>>{};
    final sourceCounts = <String, int>{};
    for (final uri in backup.references) {
      final fingerprint = backup.catalog[uri];
      if (fingerprint != null) {
        sourceCounts.update(
          fingerprint,
          (count) => count + 1,
          ifAbsent: () => 1,
        );
      }
    }
    for (final track in library) {
      byIdentity.putIfAbsent(AuraBackup.identity(track), () => []).add(track);
    }
    for (final uri in backup.references) {
      final fingerprint = backup.catalog[uri];
      if (uri.startsWith('aura://navidrome/')) {
        mapping[uri] = uri;
        if (byUri.containsKey(uri)) {
          matched++;
        } else {
          unavailable++;
        }
      } else if (fingerprint != null &&
          byUri[uri] != null &&
          AuraBackup.identity(byUri[uri]!) == fingerprint) {
        mapping[uri] = uri;
        matched++;
      } else if (fingerprint != null &&
          sourceCounts[fingerprint] == 1 &&
          byIdentity[fingerprint]?.length == 1) {
        mapping[uri] = byIdentity[fingerprint]!.single.uri;
        matched++;
        remapped++;
      } else {
        // Never attach an old Android media ID to a different song.
        mapping[uri] =
            (uri.startsWith('aura://navidrome/') ||
                uri.startsWith('aura-backup://unavailable/'))
            ? uri
            : 'aura-backup://unavailable/${sha256.convert(utf8.encode('$uri\n$fingerprint'))}';
        unavailable++;
      }
    }
  }
  final AuraBackup source;
  final mapping = <String, String>{};
  int matched = 0, remapped = 0, unavailable = 0;
  String _uri(String uri) => mapping[uri]!;
  SavedMusicData savedResult(
    SavedMusicData current, {
    required bool replace,
    required bool settings,
  }) {
    final importedPlaylists = source.saved.playlists
        .map(
          (p) =>
              MusicPlaylist(id: p.id, name: p.name, tracks: p.tracks.map(_uri)),
        )
        .toList();
    final playlists = {
      if (!replace)
        for (final p in current.playlists) p.id: p,
    };
    for (final p in importedPlaylists) {
      final existing = playlists[p.id];
      playlists[p.id] = existing == null
          ? p
          : existing.copy(tracks: [...existing.tracks, ...p.tracks]);
    }
    final albums = <String, MusicAlbum>{
      if (!replace)
        for (final album in current.albums) album.id: album,
    };
    for (final album in source.saved.albums) {
      final mapped = MusicAlbum(
        id: album.id,
        name: album.name,
        tracks: album.tracks.map(_uri),
      );
      final existing = albums[album.id];
      albums[album.id] = existing == null
          ? mapped
          : existing.copy(tracks: [...existing.tracks, ...mapped.tracks]);
    }
    final ratings = <String, num>{
      for (final entry in source.saved.ratings.entries)
        _uri(entry.key): entry.value,
      if (!replace) ...current.ratings,
    };
    return (settings ? source.saved : current).copy(
      nativeLanguage: current.nativeLanguage,
      favorites: {
        if (!replace) ...current.favorites,
        ...source.saved.favorites.map(_uri),
      },
      playlists: playlists.values,
      albums: albums.values,
      ratings: ratings,
      trackTitles: {
        for (final entry in source.saved.trackTitles.entries)
          _uri(entry.key): entry.value,
        if (!replace) ...current.trackTitles,
      },
    );
  }

  PlaybackMemoryData memoryResult(
    PlaybackMemoryData current, {
    required bool replace,
    required bool settings,
  }) {
    final entries = <String, ListeningEntry>{
      if (!replace)
        for (final e in current.history) e.uri: e,
    };
    for (final entry in source.memory.history) {
      final uri = _uri(entry.uri), previous = entries[_uri(entry.uri)];
      entries[uri] = ListeningEntry(
        uri: uri,
        lastPlayedMs:
            previous != null && previous.lastPlayedMs > entry.lastPlayedMs
            ? previous.lastPlayedMs
            : entry.lastPlayedMs,
        playCount: previous != null && previous.playCount > entry.playCount
            ? previous.playCount
            : entry.playCount,
      );
    }
    final history = entries.values.toList()
      ..sort((a, b) => b.lastPlayedMs.compareTo(a.lastPlayedMs));
    return PlaybackMemoryData(
      session: current.session,
      filters: settings ? source.memory.filters : current.filters,
      history: history.take(100),
    );
  }
}

abstract class BackupJournal {
  Future<String?> read();
  Future<void> write(String json);
}

class DeviceBackupJournal implements BackupJournal {
  static const _channel = AudioLibrary();
  @override
  Future<String?> read() => _channel.invokeMethod<String>('loadBackupJournal');
  @override
  Future<void> write(String json) =>
      _channel.invokeMethod<void>('saveBackupJournal', {'json': json});
}

class BackupRestoreService {
  BackupRestoreService({
    required this.saved,
    required this.memory,
    required this.journal,
    this.beforeRestore,
    this.afterRestore,
    this.applyPreferences,
    this.covers,
  });
  final SavedMusicStore saved;
  final PlaybackMemoryStore memory;
  final BackupJournal journal;
  final CoverBackupStorage? covers;
  final Future<void> Function()? beforeRestore, applyPreferences;
  final void Function()? afterRestore;
  bool _busy = false;
  bool recoveryRequired = false;
  static String get _complete =>
      jsonEncode({'version': 1, 'state': 'complete'});
  static Future<bool> recover({
    required BackupJournal journal,
    required SavedMusicStorage saved,
    required PlaybackMemoryStorage memory,
    CoverBackupStorage? covers,
  }) async {
    final raw = await journal.read();
    if (raw == null) return false;
    final state = jsonDecode(raw) as Map<String, dynamic>;
    if (state['version'] != 1) {
      throw const FormatException('Invalid restore journal');
    }
    if (state['state'] == 'complete') return false;
    if (state['state'] != 'pending') {
      throw const FormatException('Invalid restore state');
    }
    final savedBefore = SavedMusicData.decode(state['savedBefore'] as String)
        .encode();
    final memoryBefore = PlaybackMemoryData.decode(
      state['memoryBefore'] as String,
    ).encode();
    final rawCovers = state['coversBefore'];
    if (rawCovers != null) {
      if (covers == null ||
          rawCovers is! Map<String, dynamic> ||
          rawCovers.length > maxCoverBackupCount) {
        throw const FormatException('Cover recovery unavailable');
      }
      final previous = <String, Uint8List>{};
      var total = 0;
      for (final entry in rawCovers.entries) {
        if (entry.value is! String ||
            (entry.value as String).length >
                ((10 * 1024 * 1024 + 2) ~/ 3) * 4) {
          throw const FormatException('Invalid cover journal');
        }
        final bytes = base64Decode(entry.value as String);
        total += bytes.length;
        if (total > maxCoverBackupBytes) {
          throw const FormatException('Invalid cover journal');
        }
        previous[entry.key] = bytes;
      }
      validateCoverBackupShape(previous);
      await covers.replaceSnapshot(previous);
    }
    await saved.write(savedBefore);
    await memory.write(memoryBefore);
    await journal.write(_complete);
    return true;
  }

  Future<void> restore(
    BackupPlan plan, {
    bool replace = false,
    bool settings = false,
  }) async {
    if (_busy || recoveryRequired || !saved.ready || !memory.ready) {
      throw StateError('Restore unavailable');
    }
    _busy = true;
    bool locked = false, pending = false, coversTouched = false;
    SavedMusicData? previousSaved;
    PlaybackMemoryData? previousMemory;
    Map<String, Uint8List>? previousCovers;
    Map<String, Uint8List>? nextCovers;
    try {
      final importedCovers = plan.source.covers;
      if (importedCovers != null) {
        if (covers == null) throw StateError('Cover restore unavailable');
        await covers!.validateSnapshot(importedCovers);
      }
      await beforeRestore?.call();
      locked = true;
      await saved.flush();
      await memory.flush();
      previousSaved = saved.data;
      previousMemory = memory.data;
      if (importedCovers != null) {
        previousCovers = await covers!.snapshot();
        nextCovers = {...importedCovers, if (!replace) ...previousCovers};
        validateCoverBackupShape(nextCovers);
      }
      final nextSaved = plan.savedResult(
        previousSaved,
        replace: replace,
        settings: settings,
      );
      final nextMemory = plan.memoryResult(
        previousMemory,
        replace: replace,
        settings: settings,
      );
      await journal.write(
        jsonEncode({
          'version': 1,
          'state': 'pending',
          'savedBefore': previousSaved.encode(),
          'memoryBefore': previousMemory.encode(),
          if (previousCovers != null)
            'coversBefore': {
              for (final entry in previousCovers.entries)
                entry.key: base64Encode(entry.value),
            },
        }),
      );
      pending = true;
      await saved.replaceData(nextSaved);
      await memory.replaceLibraryData(nextMemory);
      await applyPreferences?.call();
      if (nextCovers != null) {
        coversTouched = true;
        await covers!.replaceSnapshot(nextCovers);
      }
      await journal.write(_complete);
    } catch (_) {
      if (pending && previousSaved != null && previousMemory != null) {
        try {
          await saved.replaceData(previousSaved);
          await memory.replaceLibraryData(previousMemory);
          if (coversTouched && previousCovers != null) {
            await covers!.replaceSnapshot(previousCovers);
          }
          await applyPreferences?.call();
          await journal.write(_complete);
        } catch (_) {
          recoveryRequired = true;
          rethrow;
        }
      }
      rethrow;
    } finally {
      if (locked && !recoveryRequired) afterRestore?.call();
      _busy = false;
    }
  }

  Future<void> recoverNow() async {
    if (_busy || !recoveryRequired) throw StateError('Recovery unavailable');
    _busy = true;
    try {
      await recover(
        journal: journal,
        saved: saved.storage,
        memory: memory.storage,
        covers: covers,
      );
      await saved.load();
      await memory.load();
      if (!saved.ready || !memory.ready) {
        throw StateError('Recovery incomplete');
      }
      await applyPreferences?.call();
      recoveryRequired = false;
      afterRestore?.call();
    } finally {
      _busy = false;
    }
  }
}
