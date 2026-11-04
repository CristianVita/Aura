import 'package:flutter/material.dart';

import 'app_strings.dart';
import 'app_theme.dart';
import 'navigation_preferences.dart';

String appTabLabel(BuildContext context, AppTab tab) => switch (tab) {
  AppTab.home => context.appStrings.navigationHome,
  AppTab.library => context.appStrings.navigationLibrary,
  AppTab.search => context.appStrings.navigationSearch,
  AppTab.settings => context.appStrings.navigationSettings,
};

IconData appTabIcon(AppTab tab, {bool selected = false}) => switch (tab) {
  AppTab.home => selected ? Icons.home_rounded : Icons.home_outlined,
  AppTab.library =>
    selected ? Icons.library_music_rounded : Icons.library_music_outlined,
  AppTab.search => Icons.search_rounded,
  AppTab.settings => Icons.tune_rounded,
};

class AuraNavigation extends StatelessWidget {
  const AuraNavigation({
    super.key,
    required this.preferences,
    required this.selected,
    required this.onSelected,
    this.rail = false,
    this.leading,
  });
  final NavigationPreferences preferences;
  final AppTab selected;
  final ValueChanged<AppTab> onSelected;
  final bool rail;
  final Widget? leading;
  @override
  Widget build(BuildContext context) {
    final tabs = preferences.visible;
    final index = tabs.indexOf(preferences.resolve(selected));
    final extended =
        preferences.labels == NavigationLabels.adaptive ||
        preferences.labels == NavigationLabels.always;
    if (rail) {
      return NavigationRail(
        extended: extended,
        labelType: !extended && preferences.labels == NavigationLabels.selected
            ? NavigationRailLabelType.selected
            : NavigationRailLabelType.none,
        backgroundColor: context.auraSurface,
        leading: leading,
        selectedIndex: index,
        onDestinationSelected: (index) => onSelected(tabs[index]),
        destinations: [
          for (final tab in tabs)
            NavigationRailDestination(
              icon: Icon(appTabIcon(tab)),
              selectedIcon: Icon(appTabIcon(tab, selected: true)),
              label: Text(appTabLabel(context, tab)),
            ),
        ],
      );
    }
    final labels = switch (preferences.labels) {
      NavigationLabels.adaptive ||
      NavigationLabels.hidden => NavigationDestinationLabelBehavior.alwaysHide,
      NavigationLabels.selected =>
        NavigationDestinationLabelBehavior.onlyShowSelected,
      NavigationLabels.always => NavigationDestinationLabelBehavior.alwaysShow,
    };
    return NavigationBar(
      height: labels == NavigationDestinationLabelBehavior.alwaysHide ? 56 : 80,
      labelBehavior: labels,
      backgroundColor: context.auraSurface,
      indicatorColor: context.auraAccent.withValues(alpha: .16),
      selectedIndex: index,
      onDestinationSelected: (index) => onSelected(tabs[index]),
      destinations: [
        for (final tab in tabs)
          NavigationDestination(
            icon: Icon(appTabIcon(tab)),
            selectedIcon: Icon(appTabIcon(tab, selected: true)),
            label: appTabLabel(context, tab),
          ),
      ],
    );
  }
}
