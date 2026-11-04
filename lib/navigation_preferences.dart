enum AppTab { home, library, search, settings }

enum NavigationLabels { adaptive, hidden, selected, always }

enum LibraryLanding {
  categories,
  tracks,
  albums,
  artists,
  playlists,
  favorites,
}

class NavigationPreferences {
  NavigationPreferences({
    Iterable<AppTab> order = AppTab.values,
    Iterable<AppTab> hidden = const [],
    this.start = AppTab.home,
    this.labels = NavigationLabels.adaptive,
    this.libraryLanding = LibraryLanding.categories,
  }) : order = List.unmodifiable(order),
       hidden = Set.unmodifiable(hidden) {
    if (this.order.length != AppTab.values.length ||
        this.order.toSet().length != AppTab.values.length ||
        this.hidden.any(
          (tab) => tab == AppTab.library || tab == AppTab.settings,
        ) ||
        this.hidden.contains(start)) {
      throw ArgumentError('Invalid navigation preferences');
    }
  }
  final List<AppTab> order;
  final Set<AppTab> hidden;
  final AppTab start;
  final NavigationLabels labels;
  final LibraryLanding libraryLanding;
  List<AppTab> get visible =>
      order.where((tab) => !hidden.contains(tab)).toList(growable: false);
  AppTab resolve(AppTab selected) =>
      hidden.contains(selected) ? AppTab.library : selected;
  NavigationPreferences copy({
    Iterable<AppTab>? order,
    Iterable<AppTab>? hidden,
    AppTab? start,
    NavigationLabels? labels,
    LibraryLanding? libraryLanding,
  }) {
    final hiddenTabs = (hidden ?? this.hidden).toSet();
    final requestedStart = start ?? this.start;
    return NavigationPreferences(
      order: order ?? this.order,
      hidden: hiddenTabs,
      start: hiddenTabs.contains(requestedStart)
          ? AppTab.library
          : requestedStart,
      labels: labels ?? this.labels,
      libraryLanding: libraryLanding ?? this.libraryLanding,
    );
  }

  NavigationPreferences move(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= order.length ||
        newIndex < 0 ||
        newIndex >= order.length) {
      throw RangeError('Invalid navigation move');
    }
    final next = order.toList();
    next.insert(newIndex, next.removeAt(oldIndex));
    return copy(order: next);
  }

  Map<String, Object> toJson() => {
    'order': order.map((tab) => tab.name).toList(),
    'hidden': hidden.map((tab) => tab.name).toList(),
    'start': start.name,
    'labels': labels.name,
    'libraryLanding': libraryLanding.name,
  };
  factory NavigationPreferences.fromJson(Map<String, dynamic> json) {
    try {
      return NavigationPreferences(
        order: json['order'] == null
            ? AppTab.values
            : (json['order'] as List).map(
                (value) => AppTab.values.byName(value as String),
              ),
        hidden: (json['hidden'] as List? ?? []).map(
          (value) => AppTab.values.byName(value as String),
        ),
        start: AppTab.values.byName(json['start'] as String? ?? 'home'),
        labels: NavigationLabels.values.byName(
          json['labels'] as String? ?? 'adaptive',
        ),
        libraryLanding: LibraryLanding.values.byName(
          json['libraryLanding'] as String? ?? 'categories',
        ),
      );
    } catch (_) {
      throw const FormatException('Invalid navigation preferences');
    }
  }
}
