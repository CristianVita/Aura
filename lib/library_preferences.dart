enum LibrarySection {
  albums,
  artists,
  tracks,
  playlists,
  favorites,
  sources,
  genres,
}

enum GroupLayout { list, grid }

enum GroupSort { name, nameDescending, trackCount }

enum SearchField { title, artist, album }

enum PlaylistSort { original, name, nameDescending, trackCount }

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
    this.genres = const GroupPagePreferences(),
    this.homeFavorites = true,
    this.homeRecent = true,
    Iterable<SearchField> searchFields = SearchField.values,
    this.searchFavoritesOnly = false,
    this.playlistSort = PlaylistSort.original,
    this.playlistShowCount = true,
  }) : order = List.unmodifiable(order),
       hidden = Set.unmodifiable(hidden),
       searchFields = Set.unmodifiable(searchFields) {
    if (this.order.length != LibrarySection.values.length ||
        this.order.toSet().length != LibrarySection.values.length ||
        this.hidden.length == LibrarySection.values.length ||
        this.searchFields.isEmpty ||
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
  final GroupPagePreferences genres;
  final bool homeFavorites;
  final bool homeRecent;
  final Set<SearchField> searchFields;
  final bool searchFavoritesOnly;
  final PlaylistSort playlistSort;
  final bool playlistShowCount;
  List<LibrarySection> get visible => order
      .where((section) => !hidden.contains(section))
      .toList(growable: false);
  LibraryPagePreferences copy({
    Iterable<LibrarySection>? order,
    Iterable<LibrarySection>? hidden,
    int? columns,
    GroupPagePreferences? albums,
    GroupPagePreferences? artists,
    GroupPagePreferences? genres,
    bool? homeFavorites,
    bool? homeRecent,
    Iterable<SearchField>? searchFields,
    bool? searchFavoritesOnly,
    PlaylistSort? playlistSort,
    bool? playlistShowCount,
  }) => LibraryPagePreferences(
    order: order ?? this.order,
    hidden: hidden ?? this.hidden,
    columns: columns ?? this.columns,
    albums: albums ?? this.albums,
    artists: artists ?? this.artists,
    genres: genres ?? this.genres,
    homeFavorites: homeFavorites ?? this.homeFavorites,
    homeRecent: homeRecent ?? this.homeRecent,
    searchFields: searchFields ?? this.searchFields,
    searchFavoritesOnly: searchFavoritesOnly ?? this.searchFavoritesOnly,
    playlistSort: playlistSort ?? this.playlistSort,
    playlistShowCount: playlistShowCount ?? this.playlistShowCount,
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
    'genres': genres.toJson(),
    'homeFavorites': homeFavorites,
    'homeRecent': homeRecent,
    'searchFields': searchFields.map((value) => value.name).toList(),
    'searchFavoritesOnly': searchFavoritesOnly,
    'playlistSort': playlistSort.name,
    'playlistShowCount': playlistShowCount,
  };
  factory LibraryPagePreferences.fromJson(Map<String, dynamic> json) {
    try {
      final order = json['order'] == null
          ? LibrarySection.values.toList()
          : (json['order'] as List)
                .map((value) => LibrarySection.values.byName(value as String))
                .toList();
      if (order.length == LibrarySection.values.length - 1 &&
          order.toSet().length == order.length &&
          !order.contains(LibrarySection.genres)) {
        order.add(LibrarySection.genres);
      }
      return LibraryPagePreferences(
        order: order,
        hidden: (json['hidden'] as List? ?? []).map(
          (value) => LibrarySection.values.byName(value as String),
        ),
        columns: json['columns'] as int? ?? 3,
        homeFavorites: json['homeFavorites'] as bool? ?? true,
        homeRecent: json['homeRecent'] as bool? ?? true,
        searchFields: json['searchFields'] == null
            ? SearchField.values
            : (json['searchFields'] as List).map(
                (value) => SearchField.values.byName(value as String),
              ),
        searchFavoritesOnly: json['searchFavoritesOnly'] as bool? ?? false,
        playlistSort: PlaylistSort.values.byName(
          json['playlistSort'] as String? ?? 'original',
        ),
        playlistShowCount: json['playlistShowCount'] as bool? ?? true,
        albums: GroupPagePreferences.fromJson(
          json['albums'] as Map<String, dynamic>? ?? {},
        ),
        artists: GroupPagePreferences.fromJson(
          json['artists'] as Map<String, dynamic>? ?? {},
        ),
        genres: GroupPagePreferences.fromJson(
          json['genres'] as Map<String, dynamic>? ?? {},
        ),
      );
    } catch (_) {
      throw const FormatException('Invalid library preferences');
    }
  }
}
