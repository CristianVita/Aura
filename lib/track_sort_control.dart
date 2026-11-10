import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'app_theme.dart';
import 'library_preferences.dart';
import 'saved_music.dart';
import 'saved_music_ui.dart';

class TrackSortControl extends StatefulWidget {
  const TrackSortControl({super.key, required this.store});
  final SavedMusicStore store;
  @override
  State<TrackSortControl> createState() => _TrackSortControlState();
}

class _TrackSortControlState extends State<TrackSortControl> {
  bool busy = false;
  int revision = 0;
  Future<void> _select(TrackSort? value) async {
    if (value == null || busy) return;
    setState(() => busy = true);
    await saveMusicAction(
      context,
      () => widget.store.setLibraryPages(
        widget.store.data.libraryPages.copy(trackSort: value),
      ),
    );
    if (mounted) {
      setState(() {
        busy = false;
        revision++;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final strings = context.appStrings;
      final sort = widget.store.data.libraryPages.trackSort;
      String label(TrackSort value) => switch (value) {
        TrackSort.original => strings.trackSortOriginal,
        TrackSort.title => strings.uiTitle,
        TrackSort.year => strings.trackSortYear,
        TrackSort.artist => strings.uiArtist,
        TrackSort.album => strings.uiAlbum,
        TrackSort.genre => strings.trackSortGenre,
        TrackSort.duration => strings.uiDuration,
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyedSubtree(
            key: const ValueKey('track-sort'),
            child: DropdownButtonFormField<TrackSort>(
              key: ValueKey(revision),
              initialValue: sort,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: strings.trackSortLabel,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.sort_rounded),
              ),
              items: [
                for (final value in TrackSort.values)
                  DropdownMenuItem(
                    value: value,
                    child: Text(label(value), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: busy || !widget.store.ready ? null : _select,
            ),
          ),
          if (sort == TrackSort.year)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                strings.trackSortYearHelp,
                style: TextStyle(color: context.auraMuted, fontSize: 12),
              ),
            ),
          if (widget.store.data.ratingOrder != RatingOrder.original)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                strings.trackSortRatingPriority,
                style: TextStyle(color: context.auraMuted, fontSize: 12),
              ),
            ),
        ],
      );
    },
  );
}
