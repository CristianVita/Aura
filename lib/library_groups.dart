import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'app_theme.dart';
import 'audio_track.dart';
import 'library_catalog.dart';
import 'library_preferences.dart';
import 'track_artwork.dart';

class LibraryGroups extends StatelessWidget {
  const LibraryGroups({
    super.key,
    required this.groups,
    required this.preferences,
    required this.icon,
    required this.onOpen,
  });
  final Map<String, List<AudioTrack>> groups;
  final GroupPagePreferences preferences;
  final IconData icon;
  final ValueChanged<String> onOpen;
  @override
  Widget build(BuildContext context) {
    final entries = orderedLibraryGroups(groups, preferences.sort);
    Widget tile(int index, double? coverSize) {
      final entry = entries[index];
      final first = entry.value.first;
      final title = entry.key.isEmpty
          ? context.appStrings.unknownGroup
          : entry.key;
      final subtitle = context.appStrings.groupTracks(entry.value.length);
      final artwork = TrackArtwork(
        uri: first.artworkUri.toString(),
        cacheKey: first.artworkKey,
        size: coverSize ?? 46,
        fallbackIcon: icon,
      );
      return Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: coverSize == null
            ? ListTile(
                onTap: () => onOpen(entry.key),
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
                onTap: () => onOpen(entry.key),
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
