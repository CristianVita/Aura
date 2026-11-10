import 'app_strings.dart';
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
          title: Text(context.appStrings.uiListeningHistory),
          actions: [
            IconButton(
              tooltip: context.appStrings.uiClearHistory,
              icon: const Icon(Icons.delete_outline),
              onPressed: store.data.history.isEmpty
                  ? null
                  : () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(context.appStrings.uiClearHistory262),
                          content: Text(
                            context
                                .appStrings
                                .uiTracksFavoritesAndPlaylistsWillStaySaved,
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: Text(context.appStrings.uiCancel228),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: Text(context.appStrings.uiDelete),
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
                          ? context.appStrings.uiPlayedTracksWillAppearHere
                          : context.appStrings.uiTracksInYourHistoryAreHiddenBy,
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
                    final stamp = context.dateTime(when);
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
      appBar: AppBar(title: Text(context.appStrings.uiLibraryFilters)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              context.appStrings.visibleTracks(visible, widget.tracks.length),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<int>(
              initialValue: _minimum,
              decoration: InputDecoration(
                labelText: context.appStrings.uiMinimumDuration,
              ),
              items: [
                DropdownMenuItem(
                  value: 0,
                  child: Text(context.appStrings.uiAllDurations),
                ),
                DropdownMenuItem(
                  value: 10,
                  child: Text(context.appStrings.ui10Seconds),
                ),
                DropdownMenuItem(
                  value: 30,
                  child: Text(context.appStrings.ui30Seconds),
                ),
                DropdownMenuItem(
                  value: 60,
                  child: Text(context.appStrings.ui1Minute),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _minimum = value!),
            ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                context.appStrings.uiTracksWithUnknownDurationStayVisible,
                style: TextStyle(color: context.auraMuted, fontSize: 12),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(context.appStrings.uiHideWhatsAppAndTelegram),
              subtitle: Text(
                context.appStrings.uiHidesFilesFromTheseAppsFolders,
              ),
              value: _hideMessaging,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _hideMessaging = value),
            ),
            const SizedBox(height: 20),
            Text(context.appStrings.uiFiltersOnlyChangeWhatAppearsInYour),
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
              child: Text(
                _saving
                    ? context.appStrings.uiSaving
                    : context.appStrings.uiSaveFilters,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
