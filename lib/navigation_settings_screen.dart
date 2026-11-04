import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'app_theme.dart';
import 'navigation_preferences.dart';
import 'navigation_ui.dart';
import 'saved_music.dart';

class NavigationSettingsScreen extends StatefulWidget {
  const NavigationSettingsScreen({super.key});
  @override
  State<NavigationSettingsScreen> createState() =>
      _NavigationSettingsScreenState();
}

class _NavigationSettingsScreenState extends State<NavigationSettingsScreen> {
  bool _busy = false;
  AppTab _preview = AppTab.home;
  Future<void> _save(NavigationPreferences next) async {
    final store = SavedMusicScope.of(context);
    setState(() => _busy = true);
    try {
      await store.setNavigation(next);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.appStrings.navigationSaveError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = SavedMusicScope.of(context);
    final preferences = store.data.navigation;
    final strings = context.appStrings;
    final enabled = store.ready && !_busy;
    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
            child: Text(
              title,
              style: TextStyle(color: context.auraAccent, fontSize: 16),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(strings.navigationTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          section(
            strings.navigationOrder,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.navigationHelp,
                  style: TextStyle(color: context.auraMuted),
                ),
                const SizedBox(height: 12),
                ReorderableListView(
                  shrinkWrap: true,
                  primary: false,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: (oldIndex, newIndex) {
                    if (enabled) _save(preferences.move(oldIndex, newIndex));
                  },
                  children: [
                    for (
                      var index = 0;
                      index < preferences.order.length;
                      index++
                    )
                      Builder(
                        key: ValueKey(preferences.order[index]),
                        builder: (context) {
                          final tab = preferences.order[index];
                          final required =
                              tab == AppTab.library || tab == AppTab.settings;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(appTabIcon(tab)),
                            title: Text(appTabLabel(context, tab)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (required)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Tooltip(
                                      message: strings.navigationRequired,
                                      child: const Icon(
                                        Icons.lock_outline,
                                        size: 20,
                                      ),
                                    ),
                                  )
                                else
                                  Switch(
                                    key: ValueKey('visible-${tab.name}'),
                                    value: !preferences.hidden.contains(tab),
                                    onChanged: enabled
                                        ? (visible) => _save(
                                            preferences.copy(
                                              hidden: visible
                                                  ? (preferences.hidden.toSet()
                                                      ..remove(tab))
                                                  : {
                                                      ...preferences.hidden,
                                                      tab,
                                                    },
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
              ],
            ),
          ),
          section(
            strings.navigationStart,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<AppTab>(
                  key: const ValueKey('navigation-start'),
                  isExpanded: true,
                  value: preferences.start,
                  items: [
                    for (final tab in preferences.visible)
                      DropdownMenuItem(
                        value: tab,
                        child: Text(appTabLabel(context, tab)),
                      ),
                  ],
                  onChanged: enabled
                      ? (tab) {
                          if (tab != null) _save(preferences.copy(start: tab));
                        }
                      : null,
                ),
                Text(
                  strings.navigationStartHelp,
                  style: TextStyle(color: context.auraMuted),
                ),
              ],
            ),
          ),
          section(
            strings.libraryLanding,
            DropdownButton<LibraryLanding>(
              key: const ValueKey('navigation-landing'),
              isExpanded: true,
              value: preferences.libraryLanding,
              items: [
                for (final landing in LibraryLanding.values)
                  DropdownMenuItem(
                    value: landing,
                    child: Text(switch (landing) {
                      LibraryLanding.categories => strings.landingCategories,
                      LibraryLanding.tracks => strings.landingTracks,
                      LibraryLanding.albums => strings.landingAlbums,
                      LibraryLanding.artists => strings.landingArtists,
                      LibraryLanding.playlists => strings.landingPlaylists,
                      LibraryLanding.favorites => strings.landingFavorites,
                    }),
                  ),
              ],
              onChanged: enabled
                  ? (landing) {
                      if (landing != null) {
                        _save(preferences.copy(libraryLanding: landing));
                      }
                    }
                  : null,
            ),
          ),
          section(
            strings.navigationLabels,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final labels in NavigationLabels.values)
                      ChoiceChip(
                        key: ValueKey('labels-${labels.name}'),
                        label: Text(switch (labels) {
                          NavigationLabels.adaptive => strings.labelsAdaptive,
                          NavigationLabels.hidden => strings.labelsHidden,
                          NavigationLabels.selected => strings.labelsSelected,
                          NavigationLabels.always => strings.labelsAlways,
                        }),
                        selected: preferences.labels == labels,
                        onSelected: enabled
                            ? (_) => _save(preferences.copy(labels: labels))
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  strings.labelsHelp,
                  style: TextStyle(color: context.auraMuted),
                ),
              ],
            ),
          ),
          section(
            strings.navigationPreview,
            AuraNavigation(
              preferences: preferences,
              selected: _preview,
              onSelected: (tab) => setState(() => _preview = tab),
            ),
          ),
          OutlinedButton.icon(
            onPressed: enabled ? () => _save(NavigationPreferences()) : null,
            icon: const Icon(Icons.restart_alt),
            label: Text(strings.resetNavigation),
          ),
        ],
      ),
    );
  }
}
