import 'package:flutter/material.dart';

import 'album_artwork.dart';
import 'album_cover_ui.dart';
import 'app_strings.dart';
import 'audio_track.dart';
import 'saved_music.dart';
import 'track_artwork.dart';

class PersonalAlbumEditor extends StatefulWidget {
  const PersonalAlbumEditor({
    super.key,
    required this.store,
    required this.tracks,
    this.album,
  });
  final SavedMusicStore store;
  final List<AudioTrack> tracks;
  final MusicAlbum? album;
  @override
  State<PersonalAlbumEditor> createState() => _PersonalAlbumEditorState();
}

class _PersonalAlbumEditorState extends State<PersonalAlbumEditor> {
  late final TextEditingController name = TextEditingController(
    text: widget.album?.name ?? '',
  );
  final search = TextEditingController();
  late final Set<String> selected = {...?widget.album?.tracks};
  bool saving = false;
  @override
  void dispose() {
    name.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (saving || name.text.trim().isEmpty) return;
    setState(() => saving = true);
    try {
      final id = widget.album?.id;
      if (id == null) {
        final created = await widget.store.createAlbum(
          name.text,
          tracks: selected,
        );
        if (mounted) Navigator.pop(context, created);
      } else {
        await widget.store.updateAlbum(id, name: name.text, tracks: selected);
        if (mounted) Navigator.pop(context, id);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.appStrings.customAlbumFailure)),
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = search.text.trim().toLowerCase();
    final matches = widget.tracks
        .where(
          (track) =>
              query.isEmpty ||
              [
                track.displayTitle,
                track.artist,
                track.album,
              ].any((value) => value.toLowerCase().contains(query)),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.album == null
              ? context.appStrings.customAlbumNew
              : context.appStrings.customAlbumEdit,
        ),
        actions: [
          TextButton(
            onPressed: saving || name.text.trim().isEmpty ? null : save,
            child: Text(context.appStrings.uiSave),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              key: const ValueKey('personal-album-name'),
              controller: name,
              maxLength: 80,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: context.appStrings.customAlbumName,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              key: const ValueKey('personal-album-track-search'),
              controller: search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: context.appStrings.uiSearchYourMusic,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.appStrings.uiClearSearch,
                        onPressed: () => setState(search.clear),
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(context.appStrings.groupTracks(selected.length)),
            ),
          ),
          Expanded(
            child: matches.isEmpty
                ? Center(
                    child: Text(
                      query.isEmpty
                          ? context.appStrings.uiNoTracksFoundInTheLastScan
                          : context
                                .appStrings
                                .uiNoResultsMatchTheSelectedFilters,
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: matches.length,
                    itemBuilder: (context, index) {
                      final track = matches[index];
                      return CheckboxListTile(
                        key: ValueKey('personal-album-track:${track.uri}'),
                        title: Text(
                          track.displayTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          track.displayArtist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        value: selected.contains(track.uri),
                        onChanged: saving
                            ? null
                            : (value) => setState(() {
                                if (value == true) {
                                  selected.add(track.uri);
                                } else {
                                  selected.remove(track.uri);
                                }
                              }),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class PersonalAlbumScreen extends StatelessWidget {
  const PersonalAlbumScreen({
    super.key,
    required this.albumId,
    required this.store,
    required this.tracks,
    required this.onPlay,
    this.playerBar,
  });
  final String albumId;
  final SavedMusicStore store;
  final List<AudioTrack> tracks;
  final Future<void> Function(List<AudioTrack>, int) onPlay;
  final Widget? playerBar;

  Future<void> _delete(BuildContext context, MusicAlbum album) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.appStrings.customAlbumDelete),
        content: Text(context.appStrings.customAlbumDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.appStrings.uiCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.appStrings.uiDelete),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await store.deleteAlbum(album.id);
      try {
        await albumArtwork.remove(album.coverKey);
      } catch (_) {}
      if (context.mounted) Navigator.pop(context);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.appStrings.customAlbumFailure)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final album = store.data.albums.where((a) => a.id == albumId).firstOrNull;
      if (album == null) return const Scaffold(body: SizedBox.shrink());
      final byUri = {for (final track in tracks) track.uri: track};
      final queue = [
        for (final uri in album.tracks)
          if (byUri[uri] case final track?)
            track.withArtworkAlbum(album.coverKey),
      ];
      return Scaffold(
        bottomNavigationBar: playerBar == null
            ? null
            : SafeArea(top: false, child: playerBar!),
        appBar: AppBar(
          title: Text(album.name),
          actions: [
            AlbumCoverButton(album: album.coverKey, searchTitle: album.name),
            IconButton(
              tooltip: context.appStrings.customAlbumEdit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<String>(
                  builder: (_) => PersonalAlbumEditor(
                    store: store,
                    tracks: tracks,
                    album: album,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: context.appStrings.uiDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, album),
            ),
          ],
        ),
        body: queue.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    context.appStrings.customAlbumEmpty,
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                itemCount: queue.length,
                itemBuilder: (context, index) {
                  final track = queue[index];
                  return ListTile(
                    leading: TrackArtwork(
                      uri: track.artworkUri.toString(),
                      cacheKey: track.artworkKey,
                      album: track.artworkAlbum,
                      size: 46,
                    ),
                    title: Text(
                      track.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      track.displayArtist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => onPlay(queue, index),
                  );
                },
              ),
      );
    },
  );
}
