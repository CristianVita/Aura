import 'dart:convert';

import 'audio_library.dart';
import 'rename_filename.dart';
import 'saved_music.dart';

abstract class RenameTitleJournal {
  Future<String?> read();
  Future<void> write(String json);
  Future<String?> filename(String uri);
}

class DeviceRenameTitleJournal implements RenameTitleJournal {
  const DeviceRenameTitleJournal();
  static const _library = AudioLibrary();
  @override
  Future<String?> read() =>
      _library.invokeMethod<String>('loadRenameTitleJournal');
  @override
  Future<void> write(String json) =>
      _library.invokeMethod<void>('saveRenameTitleJournal', {'json': json});
  @override
  Future<String?> filename(String uri) =>
      _library.invokeMethod<String>('getAudioFileName', {'uri': uri});
}

enum RenameTitleRecoveryResult { none, unchanged, applied, deferred }

class RenameTitleRecovery {
  const RenameTitleRecovery({required this.journal, required this.saved});
  final RenameTitleJournal journal;
  final SavedMusicStore saved;
  static String get _complete =>
      jsonEncode({'version': 1, 'state': 'complete'});

  Future<void> prepare({
    required String uri,
    required String original,
    required String title,
  }) async {
    final recovered = await recover();
    if (recovered == RenameTitleRecoveryResult.deferred) {
      throw StateError('Previous rename requires recovery');
    }
    final target = renamedAudioFilename(original, title);
    final parsed = Uri.tryParse(uri);
    if (parsed == null ||
        parsed.scheme != 'content' ||
        parsed.authority != 'media' ||
        !uri.startsWith('content://media/external/audio/media/') ||
        original == target) {
      throw ArgumentError('Invalid rename');
    }
    await journal.write(
      jsonEncode({
        'version': 1,
        'state': 'pending',
        'uri': uri,
        'original': original,
        'target': target,
        'title': title.trim(),
      }),
    );
  }

  Future<void> complete() => journal.write(_complete);

  Future<RenameTitleRecoveryResult> recover() async {
    final raw = await journal.read();
    if (raw == null) return RenameTitleRecoveryResult.none;
    final record = jsonDecode(raw) as Map<String, dynamic>;
    if (record['version'] != 1) {
      throw const FormatException('Invalid rename journal');
    }
    if (record['state'] == 'complete') return RenameTitleRecoveryResult.none;
    if (record['state'] != 'pending') {
      throw const FormatException('Invalid rename journal');
    }
    final uri = record['uri'] as String;
    final original = record['original'] as String;
    final target = record['target'] as String;
    final title = record['title'] as String;
    final parsed = Uri.tryParse(uri);
    if (parsed == null ||
        parsed.scheme != 'content' ||
        parsed.authority != 'media' ||
        !uri.startsWith('content://media/external/audio/media/') ||
        renamedAudioFilename(original, title) != target ||
        original == target) {
      throw const FormatException('Invalid rename journal');
    }
    String? current;
    try {
      current = await journal.filename(uri);
    } catch (_) {
      return RenameTitleRecoveryResult.deferred;
    }
    if (current == target) {
      await saved.setTrackTitle(uri, title);
      await complete();
      return RenameTitleRecoveryResult.applied;
    }
    if (current == original) {
      await complete();
      return RenameTitleRecoveryResult.unchanged;
    }
    return RenameTitleRecoveryResult.deferred;
  }
}
