import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'app_strings.dart';
import 'audio_track.dart';
import 'aura_backup.dart';
import 'cover_backup_storage.dart';
import 'generated_files.dart';
import 'diagnostic_journal.dart';
import 'playback_memory.dart';
import 'saved_music.dart';

class GeneratedFilesScreen extends StatefulWidget {
  const GeneratedFilesScreen({
    super.key,
    required this.saved,
    required this.memory,
    required this.tracks,
    required this.covers,
    required this.onBackup,
    this.store,
  });
  final SavedMusicStore saved;
  final PlaybackMemoryStore memory;
  final List<AudioTrack> tracks;
  final CoverBackupStorage? covers;
  final VoidCallback? onBackup;
  final GeneratedFileStore? store;
  @override
  State<GeneratedFilesScreen> createState() => _GeneratedFilesScreenState();
}

class _GeneratedFilesScreenState extends State<GeneratedFilesScreen> {
  late final GeneratedFileStore store = widget.store ?? GeneratedFileStore();
  late Future<List<GeneratedEntry>> entries;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    entries = store.list();
  }

  void refresh() {
    setState(() {
      entries = store.list();
    });
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<bool> confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.appStrings.uiCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.appStrings.generatedCreate),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> createBackup() async {
    if (!widget.saved.ready || !widget.memory.ready) {
      message(context.appStrings.generatedUnavailable);
      return;
    }
    if (!await confirm(context.appStrings.generatedBackupNotice) || !mounted) {
      return;
    }
    setState(() => busy = true);
    try {
      await widget.saved.flush();
      await widget.memory.flush();
      final covers = await widget.covers?.snapshot();
      final bytes = AuraBackup.capture(
        widget.saved.data,
        widget.memory.data,
        widget.tracks,
        covers: covers,
      ).encode();
      await store.create(GeneratedKind.backup, bytes);
      if (mounted) {
        refresh();
        message(context.appStrings.generatedCreated);
      }
    } catch (_) {
      if (mounted) message(context.appStrings.generatedError);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> createPlaylist() async {
    if (!widget.saved.ready) {
      message(context.appStrings.generatedUnavailable);
      return;
    }
    final playlists = widget.saved.data.playlists;
    if (playlists.isEmpty) {
      message(context.appStrings.generatedNoPlaylists);
      return;
    }
    final playlist = await showDialog<MusicPlaylist>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.appStrings.generatedPickPlaylist),
        children: [
          for (final p in playlists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, p),
              child: Text(p.name),
            ),
        ],
      ),
    );
    if (playlist == null || !mounted) return;
    if (!await confirm(context.appStrings.generatedPlaylistNotice) ||
        !mounted) {
      return;
    }
    setState(() => busy = true);
    try {
      final byUri = {for (final track in widget.tracks) track.uri: track};
      final data = <String, Object?>{
        'format': 'aura.playlist',
        'version': 1,
        'name': playlist.name,
        'tracks': [
          for (final uri in playlist.tracks)
            {
              'uri': ?safePlaylistReference(uri),
              if (byUri[uri] case final track?) ...{
                'title': track.displayTitle,
                'artist': track.artist,
                'album': track.album,
              },
            },
        ],
      };
      await store.create(GeneratedKind.playlist, encodeGeneratedJson(data));
      if (mounted) {
        refresh();
        message(context.appStrings.generatedCreated);
      }
    } catch (_) {
      if (mounted) message(context.appStrings.generatedError);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> createDiagnostic() async {
    if (!await confirm(context.appStrings.generatedDiagnosticNotice) ||
        !mounted) {
      return;
    }
    setState(() => busy = true);
    try {
      final data = <String, Object?>{
        'format': 'aura.diagnostic',
        'version': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'appVersion': '1.0.0',
        'platform': Platform.operatingSystem,
        'savedMusicReady': widget.saved.ready,
        'playbackMemoryReady': widget.memory.ready,
        'libraryTrackCount': widget.tracks.length,
        'playlistCount': widget.saved.data.playlists.length,
        'savedMusicLoadFailed': widget.saved.loadFailed,
        'playbackMemoryLoadFailed': widget.memory.failed,
        'recordingActive': diagnosticJournal.active,
        'events': diagnosticJournal.events
            .map((event) => event.toJson())
            .toList(),
      };
      await store.create(GeneratedKind.diagnostic, encodeGeneratedJson(data));
      if (mounted) {
        refresh();
        message(context.appStrings.generatedCreated);
      }
    } catch (_) {
      if (mounted) message(context.appStrings.generatedError);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export(GeneratedEntry entry) async {
    setState(() => busy = true);
    try {
      final bytes = await store.read(entry.name);
      final result = await FilePicker.saveFile(
        fileName: entry.name,
        bytes: bytes,
        mimeType: 'application/json',
      );
      if (result != null && mounted) {
        message(context.appStrings.generatedExported);
      }
    } catch (_) {
      if (mounted) message(context.appStrings.generatedError);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(GeneratedEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(context.appStrings.generatedDeleteNotice),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.appStrings.uiCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.appStrings.generatedDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => busy = true);
    try {
      await store.remove(entry.name);
      if (mounted) refresh();
    } catch (_) {
      if (mounted) message(context.appStrings.generatedError);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.appStrings;
    String label(GeneratedKind kind) => switch (kind) {
      GeneratedKind.backup => s.generatedBackup,
      GeneratedKind.playlist => s.generatedPlaylist,
      GeneratedKind.diagnostic => s.generatedDiagnostic,
    };
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: Text(s.uiGeneratedFiles)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.generatedExplanation),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              key: const ValueKey('generate-backup'),
              onPressed: busy ? null : createBackup,
              icon: const Icon(Icons.backup_outlined),
              label: Text(s.generatedBackup),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('generate-playlist'),
              onPressed: busy ? null : createPlaylist,
              icon: const Icon(Icons.queue_music),
              label: Text(s.generatedPlaylist),
            ),
            FilledButton.tonalIcon(
              key: const ValueKey('generate-diagnostic'),
              onPressed: busy ? null : createDiagnostic,
              icon: const Icon(Icons.monitor_heart_outlined),
              label: Text(s.generatedDiagnostic),
            ),
            ListenableBuilder(
              listenable: diagnosticJournal,
              builder: (context, _) => Column(
                children: [
                  Text(
                    diagnosticJournal.active
                        ? s.generatedRecordingOn
                        : s.generatedRecordingOff,
                  ),
                  TextButton.icon(
                    key: const ValueKey('toggle-diagnostic-recording'),
                    onPressed: busy
                        ? null
                        : () {
                            if (diagnosticJournal.active) {
                              diagnosticJournal.stop();
                            } else {
                              diagnosticJournal.start();
                            }
                          },
                    icon: Icon(
                      diagnosticJournal.active
                          ? Icons.stop_circle_outlined
                          : Icons.fiber_manual_record_outlined,
                    ),
                    label: Text(
                      diagnosticJournal.active
                          ? s.generatedStopRecording
                          : s.generatedStartRecording,
                    ),
                  ),
                  Text(
                    '${s.generatedEvents}: ${diagnosticJournal.events.length}',
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: busy ? null : widget.onBackup,
              child: Text(s.generatedRestore),
            ),
            if (busy) const LinearProgressIndicator(),
            const SizedBox(height: 16),
            FutureBuilder<List<GeneratedEntry>>(
              future: entries,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) return Text(s.generatedError);
                final rows = snapshot.data ?? [];
                if (rows.isEmpty) return Text(s.generatedEmpty);
                return Column(
                  children: [
                    for (final entry in rows)
                      Card(
                        child: Column(
                          children: [
                            ListTile(
                              title: Text(
                                entry.displayName == null
                                    ? label(entry.kind)
                                    : '${label(entry.kind)} · ${entry.displayName}',
                              ),
                              subtitle: Text(
                                '${DateFormat.yMd(Localizations.localeOf(context).toString()).add_Hm().format(entry.modified.toLocal())} · ${NumberFormat.decimalPattern(Localizations.localeOf(context).toString()).format(entry.size)} B',
                              ),
                            ),
                            Wrap(
                              alignment: WrapAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: busy ? null : () => export(entry),
                                  icon: const Icon(Icons.save_alt),
                                  label: Text(s.generatedExport),
                                ),
                                TextButton.icon(
                                  onPressed: busy ? null : () => remove(entry),
                                  icon: const Icon(Icons.delete_outline),
                                  label: Text(s.generatedDelete),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
