import 'package:aura/rename_title_recovery.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';

class MemoryStorage implements SavedMusicStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    value = json;
  }
}

class SyntheticJournal implements RenameTitleJournal {
  final device = const DeviceRenameTitleJournal();
  String current = 'original.wav';
  @override
  Future<String?> read() => device.read();
  @override
  Future<void> write(String json) => device.write(json);
  @override
  Future<String?> filename(String uri) async => current;
}

void main() => runApp(const TestApp());

class TestApp extends StatefulWidget {
  const TestApp({super.key});
  @override
  State<TestApp> createState() => _TestState();
}

class _TestState extends State<TestApp> {
  String status = 'Running';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  Future<void> run() async {
    try {
      const uri = 'content://media/external/audio/media/123';
      final storage = MemoryStorage();
      final saved = SavedMusicStore(storage);
      await saved.load();
      final journal = SyntheticJournal();
      final recovery = RenameTitleRecovery(journal: journal, saved: saved);
      await recovery.complete();
      await recovery.prepare(
        uri: uri,
        original: 'original.wav',
        title: 'New title',
      );
      journal.current = 'New title.wav';
      final result = await recovery.recover();
      if (result != RenameTitleRecoveryResult.applied ||
          SavedMusicData.decode(storage.value!).trackTitles[uri] !=
              'New title') {
        throw StateError('Recovery failed');
      }
      saved.dispose();
      if (mounted) setState(() => status = 'RENAME TEST PASSED');
    } catch (e) {
      if (mounted) setState(() => status = 'RENAME TEST FAILED: $e');
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(body: Center(child: Text(status))),
  );
}
