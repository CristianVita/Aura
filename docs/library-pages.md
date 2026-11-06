# Library, album and artist page preferences

Open **Setări → Interfață → Setări pagini**. The Home, Library, Album, Artist, Genre, Playlist and Search entries are available.

- Home: independently show or hide favorite tracks and recently played. Reset restores both without changing other pages. Core browsing and source shortcuts remain available.
- Playlist: sort the playlist list by its original order, name or track count, and show or hide track counts. Sorting never changes stored playlists or the tracks and playback order within them. Reset affects only these options.
- Search: select the default searchable fields (title, artist, album) and whether to search favorites only. At least one field stays enabled. Search screen filters can still be changed for the current session; resetting the page restores all fields and disables the favorites filter.
- Library: reorder seven categories, hide/show them, and choose 2–4 phone columns. At least one category stays visible. Hidden categories remain reachable from other shortcuts and hiding does not delete music.
- Album, Artist and Genre: independent list/cover-grid layouts, 2–4 preferred phone columns, name ascending/descending or track-count sorting, and an optional artwork/duration/track-count summary when opening a group.
- Wider windows add columns automatically. Large text reduces the column count for readability. Group headers scroll with their content on short screens.
- Reset restores only the selected page. Album resets leave Artist and Library preferences intact.

Artwork comes from the existing first-track artwork provider, with an icon fallback. Artist grids use representative track/album artwork, not downloaded artist portraits. Custom cover import remains separate future work. Group identity and playback queues retain existing behavior; sorting groups does not reorder a track queue or change ratings.

Settings are validated and stored in saved music. Backup settings restoration includes them only when opted in; old saved data and backups receive defaults. Defaults are the six library categories in the existing order, three library columns, two group columns, list layout, alphabetical group order and enabled summaries. Labels use the application's twenty ARB language catalogs.

Unit/widget tests cover legacy data, invalid settings, immutable category order, visibility constraints, deterministic sorting, stable group callbacks, large text/narrow grids, independent page reset, failed writes, concurrent rating edits and backup settings opt-in. Device tests never use live Android integration entrypoints.

Validation: all 97 unit/widget tests and analysis passed. Android arm64 and Windows x64 release builds succeeded. On OnePlus 8T, the album grid with three columns and count sorting survived process restart, group detail/summary opened correctly, category drag/hiding and two-column browsing worked, and the Artist settings page opened independently. Test preferences were reset afterward. The live installation retained its 153-track library and existing paused queue after private metadata backup and install -r.

Genre browsing groups tracks by their stored genre and includes an unknown group when it is absent. A rescan is required to add genres to existing local caches; refresh Navidrome sources to update cached server tracks. Android 11 and later use the MediaStore genre column; earlier Android versions currently leave local genres unknown. Windows reads the first genre tag and Navidrome uses the server-provided genre. Multiple genre tags are not split into separate groups. Genre metadata and names are personal media data and are not translated.
