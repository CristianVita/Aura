import 'app_strings.dart';

import 'package:flutter/material.dart';

import 'audio_track.dart';
import 'aura_backup.dart';
import 'backup_files.dart';
import 'playback_memory.dart';
import 'saved_music.dart';

class BackupScreen extends StatefulWidget {
  BackupScreen({
    super.key,
    required this.saved,
    required this.memory,
    required this.service,
    required this.tracks,
    BackupFiles? files,
  }) : files = files ?? DeviceBackupFiles();
  final SavedMusicStore saved;
  final PlaybackMemoryStore memory;
  final BackupRestoreService service;
  final List<AudioTrack> tracks;
  final BackupFiles files;
  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  bool _busy = false, _replace = false, _settings = false;
  BackupPlan? _plan;
  String? _name;
  void _message(String value) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));
    }
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    final strings = context.appStrings;
    try {
      await widget.saved.flush();
      await widget.memory.flush();
      final now = DateTime.now();
      final bytes = AuraBackup.capture(
        widget.saved.data,
        widget.memory.data,
        widget.tracks,
        now: now,
      ).encode();
      final stamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      if (await widget.files.save('Aura-backup-$stamp.json', bytes)) {
        _message(strings.uiBackupSaved);
      }
    } catch (_) {
      _message(strings.uiCouldNotSaveTheBackupAuraData);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
    final strings = context.appStrings;
    try {
      final file = await widget.files.pick();
      if (file != null) {
        final plan = BackupPlan(AuraBackup.decode(file.bytes), widget.tracks);
        if (mounted) {
          setState(() {
            _plan = plan;
            _name = file.name;
            _replace = false;
            _settings = false;
          });
        }
      }
    } catch (_) {
      _message(strings.uiTheFileIsNotAValidAura82);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final strings = context.appStrings;
    final plan = _plan;
    if (plan == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(strings.uiRestoreBackup),
        content: SingleChildScrollView(
          child: Text(
            strings.restoreConfirmation(
              _replace
                  ? strings.uiYourCurrentFavoritesRatingsPlaylistsAndHistory
                  : strings.uiDataWillBeMergedExistingRatingsAnd,
              _settings
                  ? strings.uiSettingsWillAlsoBeImported
                  : strings.uiYourCurrentSettingsWillBeKept,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(strings.uiCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _replace ? strings.uiReplaceAndRestore : strings.uiRestore,
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.service.restore(
        plan,
        replace: _replace,
        settings: _settings,
      );
      _message(strings.uiBackupRestoredUnavailableTracksAreKeptAs);
    } catch (_) {
      _message(
        widget.service.recoveryRequired
            ? strings.uiDataRecoveryMustFinishBeforeContinuing
            : strings.uiRestoreFailedYourPreviousDataWasKept,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    setState(() => _busy = true);
    final strings = context.appStrings;
    try {
      await widget.service.recoverNow();
      _message(strings.uiPreviousDataRecovered);
    } catch (_) {
      _message(strings.uiCouldNotRecoverTheDataYetTry);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final enabled = !_busy && widget.saved.ready && widget.memory.ready;
    return PopScope(
      canPop: !_busy && !widget.service.recoveryRequired,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.appStrings.uiBackupAndRestore),
          automaticallyImplyLeading: !_busy && !widget.service.recoveryRequired,
        ),
        body: widget.service.recoveryRequired
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Text(
                      context
                          .appStrings
                          .uiDataRecoveryIsRequiredBeforeContinuingAura,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _recover,
                      child: Text(context.appStrings.uiTryRecovery),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    context.appStrings.uiKeepWhatYouHaveOrganized,
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context
                        .appStrings
                        .uiBackupsIncludeFavoritesRatingsPlaylistsHistoryPlayback,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: enabled ? _export : null,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: Text(context.appStrings.uiExportBackup),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: enabled ? _pick : null,
                    icon: const Icon(Icons.file_download_outlined),
                    label: Text(context.appStrings.uiChooseABackupToRestore),
                  ),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: LinearProgressIndicator(),
                    ),
                  if (plan != null) ...[
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _name!,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              context.appStrings.backupCreated(
                                context.dateTime(
                                  plan.source.createdAt.toLocal(),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              context.appStrings.backupStats(
                                plan.source.saved.favorites.length,
                                plan.source.saved.ratings.length,
                                plan.source.saved.playlists.length,
                                plan.source.memory.history.length,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              context.appStrings.backupMatches(
                                plan.matched,
                                plan.remapped,
                                plan.unavailable,
                              ),
                            ),
                            if (plan.unavailable > 0)
                              Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  context
                                      .appStrings
                                      .uiMissingReferencesAreKeptWithoutAssigningRatings,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.appStrings.uiReplaceCurrentData),
                      subtitle: Text(
                        context.appStrings.uiOffMergeDataAndKeepExistingRatings,
                      ),
                      value: _replace,
                      onChanged: enabled
                          ? (value) => setState(() => _replace = value)
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.appStrings.uiRestoreSettingsToo),
                      value: _settings,
                      onChanged: enabled
                          ? (value) => setState(() => _settings = value)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: enabled ? _restore : null,
                      child: Text(context.appStrings.uiReviewAndRestore),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
