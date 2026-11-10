import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'app_theme.dart';
import 'audio_track.dart';
import 'library_catalog.dart';
import 'library_preferences.dart';
import 'saved_music.dart';
import 'track_artwork.dart';

class AlbumSearchGroups extends StatefulWidget {
  const AlbumSearchGroups({
    super.key,
    required this.groups,
    required this.preferences,
    required this.controller,
    required this.onOpen,
    this.albums = const [],
    this.tracks = const [],
    this.onCreateAlbum,
    this.onOpenAlbum,
  });
  final Map<String, List<AudioTrack>> groups;
  final GroupPagePreferences preferences;
  final TextEditingController controller;
  final ValueChanged<String> onOpen;
  final List<MusicAlbum> albums;
  final List<AudioTrack> tracks;
  final VoidCallback? onCreateAlbum;
  final ValueChanged<MusicAlbum>? onOpenAlbum;

  @override
  State<AlbumSearchGroups> createState() => _AlbumSearchGroupsState();
}

class _AlbumSearchGroupsState extends State<AlbumSearchGroups> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(AlbumSearchGroups oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = widget.controller.text.trim().toLowerCase();
    final byUri = {for (final track in widget.tracks) track.uri: track};
    final personal = widget.albums
        .where(
          (album) =>
              query.isEmpty ||
              album.name.toLowerCase().contains(query) ||
              album.tracks.any(
                (uri) =>
                    byUri[uri]?.artist.toLowerCase().contains(query) ?? false,
              ),
        )
        .toList();
    final filtered = query.isEmpty
        ? widget.groups
        : Map<String, List<AudioTrack>>.fromEntries(
            widget.groups.entries.where((entry) {
              final album = entry.key.isEmpty
                  ? context.appStrings.unknownGroup
                  : entry.key;
              return album.toLowerCase().contains(query) ||
                  entry.value.any(
                    (track) => track.artist.toLowerCase().contains(query),
                  );
            }),
          );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('album-search'),
                  controller: widget.controller,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  decoration: InputDecoration(
                    hintText: context.appStrings.albumSearchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: widget.controller.text.isEmpty
                        ? null
                        : IconButton(
                            key: const ValueKey('clear-album-search'),
                            tooltip: context.appStrings.uiClearSearch,
                            icon: const Icon(Icons.close_rounded),
                            onPressed: widget.controller.clear,
                          ),
                    filled: true,
                    fillColor: context.auraAccent.withValues(alpha: .14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (widget.onCreateAlbum != null) ...[
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  key: const ValueKey('create-personal-album'),
                  tooltip: context.appStrings.customAlbumNew,
                  onPressed: widget.onCreateAlbum,
                  icon: const Icon(Icons.create_new_folder_outlined),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty && personal.isEmpty && query.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      context.appStrings.albumSearchEmpty,
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : LibraryGroups(
                  groups: filtered,
                  preferences: widget.preferences,
                  icon: Icons.album_rounded,
                  onOpen: (album) {
                    FocusScope.of(context).unfocus();
                    widget.onOpen(album);
                  },
                  albums: personal,
                  tracks: widget.tracks,
                  onOpenAlbum: widget.onOpenAlbum,
                ),
        ),
      ],
    );
  }
}

class LibraryGroups extends StatelessWidget {
  const LibraryGroups({
    super.key,
    required this.groups,
    required this.preferences,
    required this.icon,
    required this.onOpen,
    this.albums = const [],
    this.tracks = const [],
    this.onOpenAlbum,
  });
  final Map<String, List<AudioTrack>> groups;
  final GroupPagePreferences preferences;
  final IconData icon;
  final ValueChanged<String> onOpen;
  final List<MusicAlbum> albums;
  final List<AudioTrack> tracks;
  final ValueChanged<MusicAlbum>? onOpenAlbum;
  @override
  Widget build(BuildContext context) {
    final byUri = {for (final track in tracks) track.uri: track};
    final entries =
        <({String name, List<AudioTrack> tracks, MusicAlbum? album})>[
          for (final entry in groups.entries)
            (name: entry.key, tracks: entry.value, album: null),
          for (final album in albums)
            (
              name: album.name,
              tracks: [for (final uri in album.tracks) ?byUri[uri]],
              album: album,
            ),
        ];
    entries.sort((a, b) {
      final aCount = a.album?.tracks.length ?? a.tracks.length;
      final bCount = b.album?.tracks.length ?? b.tracks.length;
      final count = preferences.sort == GroupSort.trackCount
          ? bCount.compareTo(aCount)
          : 0;
      if (count != 0) return count;
      final folded = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      final name = folded == 0 ? a.name.compareTo(b.name) : folded;
      final result = preferences.sort == GroupSort.nameDescending
          ? -name
          : name;
      if (result != 0) return result;
      return (a.album?.id ?? '').compareTo(b.album?.id ?? '');
    });
    Widget tile(int index, double? coverSize) {
      final entry = entries[index];
      final first = entry.tracks.firstOrNull;
      final title = entry.name.isEmpty
          ? context.appStrings.unknownGroup
          : entry.name;
      final count = entry.album?.tracks.length ?? entry.tracks.length;
      final subtitle = entry.album == null
          ? context.appStrings.groupTracks(count)
          : '${context.appStrings.customAlbumLabel} · ${context.appStrings.groupTracks(count)}';
      final artwork = TrackArtwork(
        uri: first?.artworkUri.toString() ?? '',
        cacheKey: first?.artworkKey ?? 'personal:${entry.album?.id}',
        album: entry.album?.coverKey ?? first?.artworkAlbum ?? '',
        size: coverSize ?? 46,
        fallbackIcon: icon,
      );
      return Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: coverSize == null
            ? ListTile(
                onTap: () => entry.album == null
                    ? onOpen(entry.name)
                    : onOpenAlbum?.call(entry.album!),
                leading: artwork,
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(subtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
              )
            : InkWell(
                onTap: () => entry.album == null
                    ? onOpen(entry.name)
                    : onOpenAlbum?.call(entry.album!),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: artwork),
                      const SizedBox(height: 10),
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const Spacer(),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.auraMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      );
    }

    if (preferences.layout == GroupLayout.list) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
        itemCount: entries.length,
        separatorBuilder: (_, index) => const SizedBox(height: 2),
        itemBuilder: (_, index) => tile(index, null),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final columns = libraryGridColumns(
          constraints.maxWidth - 24,
          preferences.columns,
          scaler.scale(14) / 14,
        );
        final cell = (constraints.maxWidth - 24 - (columns - 1) * 8) / columns;
        final cover = (cell - 20).clamp(1.0, double.infinity);
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
          itemCount: entries.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            mainAxisExtent:
                cover + 42 + scaler.scale(14) * 3 + scaler.scale(12) * 1.5,
          ),
          itemBuilder: (_, index) => tile(index, cover),
        );
      },
    );
  }
}

class LibraryGroupSummary extends StatelessWidget {
  const LibraryGroupSummary({
    super.key,
    required this.tracks,
    required this.icon,
  });
  final List<AudioTrack> tracks;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    final first = tracks.first;
    final duration = tracks.fold<int>(
      0,
      (total, track) => total + track.durationMs,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
      child: Row(
        children: [
          TrackArtwork(
            uri: first.artworkUri.toString(),
            cacheKey: first.artworkKey,
            album: first.artworkAlbum,
            size: 72,
            fallbackIcon: icon,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.appStrings.groupTracks(tracks.length)),
                if (duration > 0)
                  Text(
                    context.appStrings.groupMinutes((duration / 60000).ceil()),
                    style: TextStyle(color: context.auraMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
