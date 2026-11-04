import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'app_theme.dart';
import 'library_preferences.dart';
import 'saved_music.dart';

enum LibraryPageKind { library, albums, artists }

String librarySectionLabel(BuildContext context, LibrarySection section) =>
    switch (section) {
      LibrarySection.albums => context.appStrings.landingAlbums,
      LibrarySection.artists => context.appStrings.landingArtists,
      LibrarySection.tracks => context.appStrings.landingTracks,
      LibrarySection.playlists => context.appStrings.landingPlaylists,
      LibrarySection.favorites => context.appStrings.landingFavorites,
      LibrarySection.sources => context.appStrings.librarySources,
    };

class LibraryPageSettings extends StatefulWidget {
  const LibraryPageSettings({super.key, required this.page});
  final LibraryPageKind page;
  @override
  State<LibraryPageSettings> createState() => _LibraryPageSettingsState();
}

class _LibraryPageSettingsState extends State<LibraryPageSettings> {
  bool _busy = false;
  Future<void> _save(LibraryPagePreferences next) async {
    setState(() => _busy = true);
    try {
      await SavedMusicScope.of(context).setLibraryPages(next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.appStrings.pageSaveError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = SavedMusicScope.of(context);
    final prefs = store.data.libraryPages;
    final strings = context.appStrings;
    final enabled = store.ready && !_busy;
    final library = widget.page == LibraryPageKind.library;
    final group = widget.page == LibraryPageKind.artists
        ? prefs.artists
        : prefs.albums;
    void saveGroup(GroupPagePreferences value) => _save(
      widget.page == LibraryPageKind.artists
          ? prefs.copy(artists: value)
          : prefs.copy(albums: value),
    );
    Widget heading(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(8, 20, 8, 12),
      child: Text(
        title,
        style: TextStyle(color: context.auraAccent, fontSize: 16),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (widget.page) {
          LibraryPageKind.library => strings.libraryPageTitle,
          LibraryPageKind.albums => strings.albumPageTitle,
          LibraryPageKind.artists => strings.artistPageTitle,
        }),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (library) ...[
            heading(strings.categoryOrder),
            Text(strings.categoryHelp),
            ReorderableListView(
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (oldIndex, newIndex) {
                if (enabled) _save(prefs.move(oldIndex, newIndex));
              },
              children: [
                for (var index = 0; index < prefs.order.length; index++)
                  Builder(
                    key: ValueKey(prefs.order[index]),
                    builder: (context) {
                      final section = prefs.order[index];
                      final visible = !prefs.hidden.contains(section);
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(librarySectionLabel(context, section)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              key: ValueKey('category-${section.name}'),
                              value: visible,
                              onChanged:
                                  enabled &&
                                      (!visible || prefs.visible.length > 1)
                                  ? (value) => _save(
                                      prefs.copy(
                                        hidden: value
                                            ? (prefs.hidden.toSet()
                                                ..remove(section))
                                            : {...prefs.hidden, section},
                                      ),
                                    )
                                  : null,
                            ),
                            IgnorePointer(
                              ignoring: !enabled,
                              child: ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.drag_handle),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ] else ...[
            heading(strings.pageLayout),
            Wrap(
              spacing: 8,
              children: [
                for (final layout in GroupLayout.values)
                  ChoiceChip(
                    key: ValueKey('layout-${layout.name}'),
                    label: Text(
                      layout == GroupLayout.list
                          ? strings.layoutList
                          : strings.layoutGrid,
                    ),
                    selected: group.layout == layout,
                    onSelected: enabled
                        ? (_) => saveGroup(group.copy(layout: layout))
                        : null,
                  ),
              ],
            ),
            heading(strings.pageSort),
            DropdownButton<GroupSort>(
              key: const ValueKey('group-sort'),
              isExpanded: true,
              value: group.sort,
              items: [
                for (final sort in GroupSort.values)
                  DropdownMenuItem(
                    value: sort,
                    child: Text(switch (sort) {
                      GroupSort.name => strings.sortName,
                      GroupSort.nameDescending => strings.sortNameDescending,
                      GroupSort.trackCount => strings.sortTrackCount,
                    }),
                  ),
              ],
              onChanged: enabled
                  ? (sort) {
                      if (sort != null) saveGroup(group.copy(sort: sort));
                    }
                  : null,
            ),
          ],
          if (library || group.layout == GroupLayout.grid) ...[
            heading(strings.pageColumns),
            Wrap(
              spacing: 8,
              children: [
                for (final count in [2, 3, 4])
                  ChoiceChip(
                    key: ValueKey('columns-$count'),
                    label: Text('$count'),
                    selected:
                        (library ? prefs.columns : group.columns) == count,
                    onSelected: enabled
                        ? (_) {
                            if (library) {
                              _save(prefs.copy(columns: count));
                            } else {
                              saveGroup(group.copy(columns: count));
                            }
                          }
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              strings.pageColumnsHelp,
              style: TextStyle(color: context.auraMuted),
            ),
          ],
          if (!library) ...[
            const SizedBox(height: 16),
            SwitchListTile(
              key: const ValueKey('group-summary'),
              contentPadding: EdgeInsets.zero,
              title: Text(strings.pageSummary),
              subtitle: Text(strings.pageSummaryHelp),
              value: group.showSummary,
              onChanged: enabled
                  ? (value) => saveGroup(group.copy(showSummary: value))
                  : null,
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.restart_alt),
            label: Text(strings.pageReset),
            onPressed: enabled
                ? () {
                    if (library) {
                      _save(
                        prefs.copy(
                          order: LibrarySection.values,
                          hidden: [],
                          columns: 3,
                        ),
                      );
                    } else {
                      saveGroup(const GroupPagePreferences());
                    }
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
