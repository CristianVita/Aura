import 'app_theme.dart';

import 'package:flutter/material.dart';

import 'audio_track.dart';
import 'playback_memory.dart';
import 'saved_music_ui.dart';
import 'track_artwork.dart';

class ListeningHistoryScreen extends StatelessWidget {
  const ListeningHistoryScreen({
    super.key,
    required this.store,
    required this.tracks,
    required this.onPlay,
  });
  final PlaybackMemoryStore store;
  final List<AudioTrack> tracks;
  final Future<void> Function(List<AudioTrack>, int) onPlay;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final byUri = {for (final track in tracks) track.uri: track};
      final entries = store.data.history
          .where((e) => byUri.containsKey(e.uri))
          .toList();
      final queue = entries.map((e) => byUri[e.uri]!).toList();
      return Scaffold(
        appBar: AppBar(
          title: const Text('Istoric de ascultare'),
          actions: [
            IconButton(
              tooltip: 'Șterge istoricul',
              icon: const Icon(Icons.delete_outline),
              onPressed: store.data.history.isEmpty
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Ștergi istoricul?'),
                          content: const Text(
                            'Piesele, favoritele și playlisturile rămân salvate.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Anulează'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Șterge'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true && context.mounted) {
                        await saveMusicAction(context, store.clearHistory);
                      }
                    },
            ),
          ],
        ),
        body: SafeArea(
          child: entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      store.data.history.isEmpty
                          ? 'Piesele ascultate vor apărea aici.'
                          : 'Piesele din istoric sunt ascunse de filtrele curente sau nu mai sunt disponibile.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final track = queue[index];
                    final when = DateTime.fromMillisecondsSinceEpoch(
                      entries[index].lastPlayedMs,
                    );
                    final stamp =
                        '${when.day.toString().padLeft(2, '0')}.${when.month.toString().padLeft(2, '0')}.${when.year} · '
                        '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
                    return ListTile(
                      leading: TrackArtwork(
                        uri: track.artworkUri.toString(),
                        cacheKey: track.artworkKey,
                        size: 46,
                      ),
                      title: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(stamp),
                      onTap: () => onPlay(queue, index),
                    );
                  },
                ),
        ),
      );
    },
  );
}

class LibraryFiltersScreen extends StatefulWidget {
  const LibraryFiltersScreen({
    super.key,
    required this.store,
    required this.tracks,
  });
  final PlaybackMemoryStore store;
  final List<AudioTrack> tracks;
  @override
  State<LibraryFiltersScreen> createState() => _LibraryFiltersScreenState();
}

class _LibraryFiltersScreenState extends State<LibraryFiltersScreen> {
  late int _minimum = widget.store.data.filters.minimumSeconds;
  late bool _hideMessaging = widget.store.data.filters.hideMessaging;
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final filters = LibraryFilters(
      minimumSeconds: _minimum,
      hideMessaging: _hideMessaging,
    );
    final visible = widget.tracks.where(filters.includes).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Filtre bibliotecă')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '$visible din ${widget.tracks.length} piese vor fi afișate.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<int>(
              initialValue: _minimum,
              decoration: const InputDecoration(labelText: 'Durata minimă'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('Toate duratele')),
                DropdownMenuItem(value: 10, child: Text('10 secunde')),
                DropdownMenuItem(value: 30, child: Text('30 de secunde')),
                DropdownMenuItem(value: 60, child: Text('1 minut')),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _minimum = value!),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Piesele cu durată necunoscută rămân vizibile.',
                style: TextStyle(color: context.auraMuted, fontSize: 12),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ascunde WhatsApp și Telegram'),
              subtitle: const Text(
                'Ascunde fișierele din folderele acestor aplicații.',
              ),
              value: _hideMessaging,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _hideMessaging = value),
            ),
            const SizedBox(height: 20),
            const Text(
              'Filtrele schimbă doar ce vezi în bibliotecă. Fișierele, playlisturile și coada curentă sunt păstrate.',
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving || !widget.store.ready
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      final saved = await saveMusicAction(
                        context,
                        () => widget.store.setFilters(filters),
                      );
                      if (!context.mounted) return;
                      if (saved) {
                        Navigator.pop(context);
                      } else {
                        setState(() => _saving = false);
                      }
                    },
              child: Text(_saving ? 'Se salvează...' : 'Salvează filtrele'),
            ),
          ],
        ),
      ),
    );
  }
}
