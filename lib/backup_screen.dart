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
        _message('Backupul a fost salvat.');
      }
    } catch (_) {
      _message('Nu am putut salva backupul. Datele Aura nu au fost schimbate.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick() async {
    setState(() => _busy = true);
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
      _message(
        'Fișierul nu este un backup Aura valid, este deteriorat sau depășește 4 MB.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final plan = _plan;
    if (plan == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restaurare backup?'),
        content: SingleChildScrollView(
          child: Text(
            '${_replace ? 'Favoritele, ratingurile, playlisturile și istoricul actuale vor fi înlocuite.' : 'Datele vor fi combinate. Ratingurile și numele playlisturilor existente au prioritate.'}\n\n${_settings ? 'Vor fi importate și setările.' : 'Setările actuale rămân.'}\n\nRedarea va fi pusă pe pauză, iar temporizatorul va fi anulat. Coada curentă se păstrează.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Renunță'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _replace ? 'Înlocuiește și restaurează' : 'Restaurează',
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
      _message(
        'Backup restaurat. Piesele indisponibile rămân păstrate ca referințe.',
      );
    } catch (_) {
      _message(
        widget.service.recoveryRequired
            ? 'Recuperarea datelor trebuie încheiată înainte de a continua.'
            : 'Restaurarea a eșuat. Datele anterioare au fost păstrate.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recover() async {
    setState(() => _busy = true);
    try {
      await widget.service.recoverNow();
      _message('Datele anterioare au fost recuperate.');
    } catch (_) {
      _message(
        'Nu am putut recupera încă datele. Poți încerca din nou sau reporni Aura.',
      );
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
          title: const Text('Backup și restaurare'),
          automaticallyImplyLeading: !_busy && !widget.service.recoveryRequired,
        ),
        body: widget.service.recoveryRequired
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Text(
                      'Datele trebuie recuperate înainte de a continua. Aura a păstrat starea anterioară într-un jurnal local.',
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy ? null : _recover,
                      child: const Text('Încearcă recuperarea'),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Păstrează ce ai organizat',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Backupul include favoritele, ratingurile, playlisturile, istoricul, setările de redare și filtrele bibliotecii. Fișierele audio, sursele și folderele selectate nu sunt incluse; acestea se configurează separat.',
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: enabled ? _export : null,
                    icon: const Icon(Icons.file_upload_outlined),
                    label: const Text('Exportă backup'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: enabled ? _pick : null,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Alege un backup pentru restaurare'),
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
                              'Creat: ${plan.source.createdAt.toLocal().toString().split('.').first}',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${plan.source.saved.favorites.length} favorite · ${plan.source.saved.ratings.length} ratinguri\n${plan.source.saved.playlists.length} playlisturi · ${plan.source.memory.history.length} piese în istoric',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${plan.matched} referințe recunoscute · ${plan.remapped} reasociate\n${plan.unavailable} indisponibile sau ambigue',
                            ),
                            if (plan.unavailable > 0)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Referințele lipsă sunt păstrate, fără a lega ratinguri de alte melodii. Poți reimporta backupul după adăugarea surselor potrivite.',
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Înlocuiește datele actuale'),
                      subtitle: const Text(
                        'Oprit: combină datele și păstrează ratingurile existente.',
                      ),
                      value: _replace,
                      onChanged: enabled
                          ? (value) => setState(() => _replace = value)
                          : null,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Restabilește și setările'),
                      value: _settings,
                      onChanged: enabled
                          ? (value) => setState(() => _settings = value)
                          : null,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: enabled ? _restore : null,
                      child: const Text('Verifică și restaurează'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
