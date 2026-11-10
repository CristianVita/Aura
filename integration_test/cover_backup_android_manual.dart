import 'dart:convert';
import 'dart:io';

import 'package:aura/album_artwork.dart';
import 'package:aura/aura_backup.dart';
import 'package:aura/playback_memory.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';

class MemorySaved implements SavedMusicStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    value = json;
  }
}

class MemoryPlayback implements PlaybackMemoryStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    value = json;
  }
}

class MemoryJournal implements BackupJournal {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    value = json;
  }
}

void main() => runApp(const TestApp());

class TestApp extends StatefulWidget {
  const TestApp({super.key});
  @override
  State<TestApp> createState() => TestState();
}

class TestState extends State<TestApp> {
  String status = 'Starting backup test';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  Future<void> run() async {
    Directory? root;
    AlbumArtworkStore? artwork;
    SavedMusicStore? saved;
    PlaybackMemoryStore? playback;
    try {
      root = await Directory.systemTemp.createTemp(
        'aura-cover-backup-synthetic-',
      );
      final testRoot = root;
      artwork = AlbumArtworkStore(directory: () async => testRoot);
      final savedDisk = MemorySaved();
      final memoryDisk = MemoryPlayback();
      saved = SavedMusicStore(savedDisk);
      playback = PlaybackMemoryStore(memoryDisk);
      await saved.load();
      await playback.load();
      final png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      await artwork.set('Synthetic album', png);
      final original = await artwork.snapshot();
      final backup = AuraBackup.decode(
        AuraBackup.capture(
          saved.data,
          playback.data,
          [],
          covers: original,
        ).encode(),
      );
      await artwork.remove('Synthetic album');
      await artwork.set('Synthetic other', png);
      final journal = MemoryJournal();
      final service = BackupRestoreService(
        saved: saved,
        memory: playback,
        journal: journal,
        covers: artwork,
      );
      await service.restore(BackupPlan(backup, []), replace: true);
      final restored = await artwork.snapshot();
      if (restored.length != 1 ||
          !restored.containsKey(original.keys.single) ||
          await artwork.read('Synthetic other') != null) {
        throw StateError('Restore mismatch');
      }
      if (mounted) setState(() => status = 'COVER BACKUP TEST PASSED');
    } catch (error) {
      if (mounted) setState(() => status = 'COVER BACKUP TEST FAILED: $error');
    } finally {
      saved?.dispose();
      playback?.dispose();
      artwork?.dispose();
      if (root != null && await root.exists()) {
        await root.delete(recursive: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: Center(child: Text(status))),
  );
}
