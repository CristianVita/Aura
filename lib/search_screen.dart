part of 'main.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
    required this.tracks,
    required this.isScanning,
    required this.onAddSource,
    required this.onTrackSelected,
    this.recentQueries,
  });
  final List<AudioTrack> tracks;
  final bool isScanning;
  final VoidCallback onAddSource;
  final Future<void> Function(List<AudioTrack>, int) onTrackSelected;
  final List<String>? recentQueries;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _localRecent = <String>[];
  Set<SearchField> _fields = SearchField.values.toSet();
  bool _favoritesOnly = false;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = SavedMusicScope.of(context);
    if (!_initialized && store.ready) {
      final prefs = store.data.libraryPages;
      _fields = prefs.searchFields.toSet();
      _favoritesOnly = prefs.searchFavoritesOnly;
      _initialized = true;
    }
  }

  List<String> get _recent => widget.recentQueries ?? _localRecent;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _remember() {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _recent.removeWhere((old) => old.toLowerCase() == query.toLowerCase());
      _recent.insert(0, query);
      if (_recent.length > 12) _recent.removeRange(12, _recent.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final saved = SavedMusicScope.of(context).data;
    final matches = widget.tracks
        .where((track) {
          if (query.isEmpty ||
              (_favoritesOnly && !saved.favorites.contains(track.uri))) {
            return false;
          }
          return [
            if (_fields.contains(SearchField.title)) track.displayTitle,
            if (_fields.contains(SearchField.artist)) track.artist,
            if (_fields.contains(SearchField.album)) track.album,
          ].any((value) => value.toLowerCase().contains(query));
        })
        .toList(growable: false);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: TextField(
            controller: _controller,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _remember(),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: context.appStrings.uiSearchYourMusic,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: context.appStrings.uiClearSearch,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(_controller.clear),
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
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(context.appStrings.labelsAlways),
                  selected: _fields.length == 3,
                  onSelected: (_) => setState(() {
                    _fields.addAll(SearchField.values);
                  }),
                ),
              ),
              for (final field in SearchField.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(switch (field) {
                      SearchField.title => context.appStrings.uiTitle,
                      SearchField.artist => context.appStrings.uiArtist,
                      _ => context.appStrings.uiAlbum,
                    }),
                    selected: _fields.contains(field),
                    onSelected: (selected) => setState(() {
                      if (selected) {
                        _fields.add(field);
                      } else if (_fields.length > 1) {
                        _fields.remove(field);
                      }
                    }),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Switch(
                value: _favoritesOnly,
                onChanged: (value) => setState(() => _favoritesOnly = value),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  context.appStrings.uiFavoritesOnly,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (query.isNotEmpty)
                Text(
                  context.appStrings.searchResultCount(matches.length),
                  style: TextStyle(color: context.auraMuted, fontSize: 12),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: widget.tracks.isEmpty
              ? _SimplePage(
                  eyebrow: context.appStrings.uiYOURLIBRARYISEMPTY,
                  title: context.appStrings.uiAddMusic,
                  message:
                      context.appStrings.uiAddASourceToSearchYourCollection,
                  icon: Icons.library_music_outlined,
                  actionLabel: widget.isScanning
                      ? context.appStrings.uiScanning
                      : context.appStrings.uiAddASource,
                  onAction: widget.isScanning ? null : widget.onAddSource,
                )
              : query.isEmpty
              ? ListView(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  children: [
                    Center(
                      child: Text(
                        context.appStrings.uiRecentSearches,
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_recent.isEmpty)
                      Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          context.appStrings.uiSearchForATitleArtistOrAlbum,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: context.auraMuted),
                        ),
                      ),
                    for (final recent in List<String>.of(_recent))
                      ListTile(
                        leading: const Icon(Icons.history_rounded, size: 21),
                        title: Text(recent),
                        onTap: () => setState(() => _controller.text = recent),
                        trailing: IconButton(
                          tooltip: context.appStrings.removeRecentSearch(
                            recent,
                          ),
                          icon: const Icon(Icons.close_rounded, size: 20),
                          onPressed: () =>
                              setState(() => _recent.remove(recent)),
                        ),
                      ),
                  ],
                )
              : matches.isEmpty
              ? Center(
                  child: Text(
                    context.appStrings.uiNoResultsMatchTheSelectedFilters,
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
                  itemCount: matches.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 2),
                  itemBuilder: (context, index) => _AudioTrackTile(
                    track: matches[index],
                    onTap: () {
                      _remember();
                      widget.onTrackSelected(matches, index);
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
