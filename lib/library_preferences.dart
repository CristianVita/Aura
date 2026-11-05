enum LibrarySection { albums, artists, tracks, playlists, favorites, sources }

enum GroupLayout { list, grid }

enum GroupSort { name, nameDescending, trackCount }

class GroupPagePreferences {
  const GroupPagePreferences({
    this.layout = GroupLayout.list,
    this.sort = GroupSort.name,
    this.columns = 2,
    this.showSummary = true,
  });
  final GroupLayout layout;
  final GroupSort sort;
  final int columns;
  final bool showSummary;
  GroupPagePreferences copy({
    GroupLayout? layout,
    GroupSort? sort,
    int? columns,
    bool? showSummary,
  }) => GroupPagePreferences(
    layout: layout ?? this.layout,
    sort: sort ?? this.sort,
    columns: columns ?? this.columns,
    showSummary: showSummary ?? this.showSummary,
  );
  Map<String, Object> toJson() => {
    'layout': layout.name,
    'sort': sort.name,
    'columns': columns,
    'showSummary': showSummary,
  };
  factory GroupPagePreferences.fromJson(Map<String, dynamic> json) {
    final columns = json['columns'] as int? ?? 2;
    if (columns < 2 || columns > 4) {
      throw const FormatException('Invalid group columns');
    }
    return GroupPagePreferences(
      layout: GroupLayout.values.byName(json['layout'] as String? ?? 'list'),
      sort: GroupSort.values.byName(json['sort'] as String? ?? 'name'),
      columns: columns,
      showSummary: json['showSummary'] as bool? ?? true,
    );
  }
}

class LibraryPagePreferences {
  LibraryPagePreferences({
    Iterable<LibrarySection> order = LibrarySection.values,
    Iterable<LibrarySection> hidden = const [],
    this.columns = 3,
    this.albums = const GroupPagePreferences(),
    this.artists = const GroupPagePreferences(),
    this.homeFavorites = true,
    this.homeRecent = true,
  }) : order = List.unmodifiable(order),
       hidden = Set.unmodifiable(hidden) {
    if (this.order.length != LibrarySection.values.length ||
        this.order.toSet().length != LibrarySection.values.length ||
        this.hidden.length == LibrarySection.values.length ||
        columns < 2 ||
        columns > 4) {
      throw ArgumentError('Invalid library preferences');
    }
  }
  final List<LibrarySection> order;
  final Set<LibrarySection> hidden;
  final int columns;
  final GroupPagePreferences albums;
  final GroupPagePreferences artists;
  final bool homeFavorites;
  final bool homeRecent;
  List<LibrarySection> get visible => order
      .where((section) => !hidden.contains(section))
      .toList(growable: false);
  LibraryPagePreferences copy({
    Iterable<LibrarySection>? order,
    Iterable<LibrarySection>? hidden,
    int? columns,
    GroupPagePreferences? albums,
    GroupPagePreferences? artists,
    bool? homeFavorites,
    bool? homeRecent,
  }) => LibraryPagePreferences(
    order: order ?? this.order,
    hidden: hidden ?? this.hidden,
    columns: columns ?? this.columns,
    albums: albums ?? this.albums,
    artists: artists ?? this.artists,
    homeFavorites: homeFavorites ?? this.homeFavorites,
    homeRecent: homeRecent ?? this.homeRecent,
  );
  LibraryPagePreferences move(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= order.length ||
        newIndex < 0 ||
        newIndex >= order.length) {
      throw RangeError('Invalid category move');
    }
    final next = order.toList();
    next.insert(newIndex, next.removeAt(oldIndex));
    return copy(order: next);
  }

  Map<String, Object> toJson() => {
    'order': order.map((value) => value.name).toList(),
    'hidden': hidden.map((value) => value.name).toList(),
    'columns': columns,
    'albums': albums.toJson(),
    'artists': artists.toJson(),
    'homeFavorites': homeFavorites,
    'homeRecent': homeRecent,
  };
  factory LibraryPagePreferences.fromJson(Map<String, dynamic> json) {
    try {
      return LibraryPagePreferences(
        order: json['order'] == null
            ? LibrarySection.values
            : (json['order'] as List).map(
                (value) => LibrarySection.values.byName(value as String),
              ),
        hidden: (json['hidden'] as List? ?? []).map(
          (value) => LibrarySection.values.byName(value as String),
        ),
        columns: json['columns'] as int? ?? 3,
        homeFavorites: json['homeFavorites'] as bool? ?? true,
        homeRecent: json['homeRecent'] as bool? ?? true,
        albums: GroupPagePreferences.fromJson(
          json['albums'] as Map<String, dynamic>? ?? {},
        ),
        artists: GroupPagePreferences.fromJson(
          json['artists'] as Map<String, dynamic>? ?? {},
        ),
      );
    } catch (_) {
      throw const FormatException('Invalid library preferences');
    }
  }
}
