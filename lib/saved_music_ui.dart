import 'package:flutter/material.dart';

import 'audio_track.dart';
import 'saved_music.dart';
import 'track_artwork.dart';

const _mint = Color(0xFF8BE0C0);

String _trackCount(int count) => '$count ${count == 1 ? 'piesă' : 'piese'}';

Future<bool> saveMusicAction(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nu am putut salva modificarea. Încearcă din nou.'),
        ),
      );
    }
    return false;
  }
}

Future<String?> _askName(BuildContext context, {String? initial}) =>
    showDialog<String>(
      context: context,
      builder: (_) => _PlaylistNameDialog(initial: initial),
    );

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog({this.initial});
  final String? initial;
  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  late final controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial == null ? 'Playlist nou' : 'Redenumește playlistul',
    ),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: 'Numele playlistului'),
      onSubmitted: (value) {
        if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Anulează'),
      ),
      ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => FilledButton(
          onPressed: value.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context, value.text.trim()),
          child: const Text('Salvează'),
        ),
      ),
    ],
  );
}

class SavedTrackActions extends StatelessWidget {
  const SavedTrackActions({
    super.key,
    required this.track,
    this.showPlaylist = true,
  });
  final AudioTrack track;
  final bool showPlaylist;

  @override
  Widget build(BuildContext context) {
    final store = SavedMusicScope.of(context);
    final favorite = store.data.favorites.contains(track.uri);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: favorite ? 'Elimină din favorite' : 'Adaugă la favorite',
          icon: Icon(
            favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: favorite ? _mint : Colors.white54,
            size: 22,
          ),
          onPressed: !store.ready
              ? null
              : () => saveMusicAction(
                  context,
                  () => store.toggleFavorite(track.uri),
                ),
        ),
        if (showPlaylist)
          IconButton(
            tooltip: 'Adaugă în playlist',
            icon: const Icon(Icons.playlist_add_rounded, size: 22),
            onPressed: !store.ready
                ? null
                : () => _addToPlaylist(context, store, track),
          ),
      ],
    );
  }
}

Future<void> _addToPlaylist(
  BuildContext context,
  SavedMusicStore store,
  AudioTrack track,
) async {
  final selected = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Adaugă în playlist',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Închide',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Playlist nou'),
              onTap: () => Navigator.pop(context, 'new'),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final p in store.data.playlists)
                    ListTile(
                      leading: const Icon(Icons.queue_music),
                      title: Text(p.name),
                      subtitle: Text(
                        p.tracks.contains(track.uri)
                            ? 'Piesa este deja în playlist'
                            : _trackCount(p.tracks.length),
                      ),
                      enabled: !p.tracks.contains(track.uri),
                      onTap: () => Navigator.pop(context, p.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (selected == null || !context.mounted) return;
  bool saved;
  if (selected == 'new') {
    final name = await _askName(context);
    if (name == null || !context.mounted) return;
    saved = await saveMusicAction(context, () async {
      await store.createPlaylist(name, tracks: [track.uri]);
    });
  } else {
    saved = await saveMusicAction(
      context,
      () => store.addTrack(selected, track.uri),
    );
  }
  if (saved && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Piesă adăugată în playlist.')),
    );
  }
}

class SavedMusicScreen extends StatefulWidget {
  const SavedMusicScreen({
    super.key,
    required this.tracks,
    required this.onPlay,
    this.initialFavorites = false,
  });
  final List<AudioTrack> tracks;
  final Future<void> Function(List<AudioTrack>, int) onPlay;
  final bool initialFavorites;
  @override
  State<SavedMusicScreen> createState() => _SavedMusicScreenState();
}

class _SavedMusicScreenState extends State<SavedMusicScreen> {
  String? _selectedId;
  late bool _favorites = widget.initialFavorites;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await saveMusicAction(context, action);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _create(SavedMusicStore store) async {
    final name = await _askName(context);
    if (name == null || !mounted) return;
    await _run(() async {
      final id = await store.createPlaylist(name);
      if (mounted) {
        setState(() {
          _selectedId = id;
          _favorites = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = SavedMusicScope.of(context);
    if (!store.ready) {
      return Center(
        child: store.loadFailed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Nu am putut încărca favoritele și playlisturile.',
                  ),
                  TextButton(
                    onPressed: store.load,
                    child: const Text('Încearcă din nou'),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      );
    }
    final playlists = store.data.playlists;
    final selected = playlists.where((p) => p.id == _selectedId).firstOrNull;
    final detail = _favorites || selected != null;
    final uris = _favorites
        ? store.data.favorites.toList()
        : selected?.tracks ?? <String>[];
    final byUri = {for (final track in widget.tracks) track.uri: track};
    final tracks = uris
        .map((uri) => byUri[uri])
        .whereType<AudioTrack>()
        .toList();
    final missing = uris.length - tracks.length;
    return PopScope(
      canPop: !detail || widget.initialFavorites,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && detail) {
          setState(() {
            _selectedId = null;
            _favorites = false;
          });
        }
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 8),
            child: Row(
              children: [
                if (detail && !widget.initialFavorites)
                  IconButton(
                    tooltip: 'Înapoi la playlisturi',
                    onPressed: () => setState(() {
                      _selectedId = null;
                      _favorites = false;
                    }),
                    icon: const Icon(Icons.arrow_back),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Text(
                      _favorites ? 'Favorite' : selected?.name ?? 'Playlisturi',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (!detail)
                  IconButton(
                    tooltip: 'Playlist nou',
                    onPressed: _busy ? null : () => _create(store),
                    icon: const Icon(Icons.add),
                  ),
                if (selected != null)
                  PopupMenuButton<String>(
                    tooltip: 'Opțiuni playlist',
                    enabled: !_busy,
                    onSelected: (action) async {
                      if (action == 'rename') {
                        final name = await _askName(
                          context,
                          initial: selected.name,
                        );
                        if (name != null && mounted) {
                          await _run(
                            () => store.renamePlaylist(selected.id, name),
                          );
                        }
                      } else {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Ștergi playlistul?'),
                            content: const Text(
                              'Fișierele audio rămân pe telefon.',
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
                        if (confirmed == true && mounted) {
                          await _run(() async {
                            await store.deletePlaylist(selected.id);
                            if (mounted) setState(() => _selectedId = null);
                          });
                        }
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'rename',
                        child: Text('Redenumește'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text('Șterge playlistul'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          if (!detail)
            Expanded(
              child: ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.favorite, color: _mint),
                    title: const Text('Favorite'),
                    subtitle: Text(
                      '${_trackCount(store.data.favorites.length)} ${store.data.favorites.length == 1 ? 'salvată' : 'salvate'}',
                    ),
                    onTap: () => setState(() => _favorites = true),
                  ),
                  const Divider(),
                  if (playlists.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Creează primul playlist cu + sau din meniul unei piese.',
                      ),
                    ),
                  for (final p in playlists)
                    ListTile(
                      leading: const Icon(Icons.queue_music, color: _mint),
                      title: Text(p.name),
                      subtitle: Text(_trackCount(p.tracks.length)),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => setState(() => _selectedId = p.id),
                    ),
                ],
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_trackCount(tracks.length)} ${tracks.length == 1 ? 'disponibilă' : 'disponibile'}',
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ),
                  if (selected != null)
                    TextButton.icon(
                      icon: const Icon(Icons.playlist_add),
                      label: const Text('Adaugă piese'),
                      onPressed: _busy
                          ? null
                          : () async {
                              final picked = await Navigator.push<Set<String>>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => _TrackPicker(
                                    tracks: widget.tracks,
                                    selected: selected.tracks.toSet(),
                                  ),
                                ),
                              );
                              if (picked != null && mounted) {
                                await _run(
                                  () => store.setTracks(selected.id, picked),
                                );
                              }
                            },
                    ),
                ],
              ),
            ),
            if (missing > 0)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  missing == 1
                      ? 'O piesă nu este în folderele selectate sau nu mai este disponibilă. Referința ei este păstrată.'
                      : '$missing piese nu sunt în folderele selectate sau nu mai sunt disponibile. Referințele lor sunt păstrate.',
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ),
            if (tracks.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Redă toate'),
                    onPressed: () => widget.onPlay(tracks, 0),
                  ),
                ),
              ),
            Expanded(
              child: tracks.isEmpty
                  ? Center(
                      child: Text(
                        _favorites
                            ? 'Apasă inima unei piese pentru a o salva aici.'
                            : 'Adaugă piese în acest playlist.',
                      ),
                    )
                  : ListView.builder(
                      itemCount: tracks.length,
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        return ListTile(
                          leading: TrackArtwork(
                            uri: track.artworkUri.toString(),
                            cacheKey: track.artworkKey,
                            size: 42,
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            track.artist.isEmpty
                                ? 'Artist necunoscut'
                                : track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => widget.onPlay(tracks, index),
                          trailing: selected == null
                              ? SavedTrackActions(track: track)
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SavedTrackActions(
                                      track: track,
                                      showPlaylist: false,
                                    ),
                                    IconButton(
                                      tooltip: 'Elimină din playlist',
                                      icon: const Icon(
                                        Icons.remove_circle_outline,
                                      ),
                                      onPressed: _busy
                                          ? null
                                          : () => _run(
                                              () => store.removeTrack(
                                                selected.id,
                                                track.uri,
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrackPicker extends StatefulWidget {
  const _TrackPicker({required this.tracks, required this.selected});
  final List<AudioTrack> tracks;
  final Set<String> selected;
  @override
  State<_TrackPicker> createState() => _TrackPickerState();
}

class _TrackPickerState extends State<_TrackPicker> {
  late final _selected = {...widget.selected};
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final matches = widget.tracks
        .where(
          (t) => '${t.title} ${t.artist} ${t.album}'.toLowerCase().contains(
            _query,
          ),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Adaugă piese'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _selected),
            child: const Text('Salvează'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                decoration: const InputDecoration(
                  labelText: 'Caută o piesă',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (query) =>
                    setState(() => _query = query.trim().toLowerCase()),
              ),
            ),
            Text(
              '${_trackCount(_selected.length)} ${_selected.length == 1 ? 'selectată' : 'selectate'}',
            ),
            Expanded(
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final track = matches[index];
                  return CheckboxListTile(
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: _selected.contains(track.uri),
                    onChanged: (checked) => setState(() {
                      if (checked == true) {
                        _selected.add(track.uri);
                      } else {
                        _selected.remove(track.uri);
                      }
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
