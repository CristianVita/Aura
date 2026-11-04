# Library, album and artist page preferences

Open **Setări → Interfață → Setări pagini**. The Library, Album and Artist entries are available.

- Library: reorder six categories, hide/show them, and choose 2–4 phone columns. At least one category stays visible. Hidden categories remain reachable from other shortcuts and hiding does not delete music.
- Album and Artist: independent list/cover-grid layouts, 2–4 preferred phone columns, name ascending/descending or track-count sorting, and an optional artwork/duration/track-count summary when opening a group.
- Wider windows add columns automatically. Large text reduces the column count for readability. Group headers scroll with their content on short screens.
- Reset restores only the selected page. Album resets leave Artist and Library preferences intact.

Artwork comes from the existing first-track artwork provider, with an icon fallback. Artist grids use representative track/album artwork, not downloaded artist portraits. Custom cover import remains separate future work. Group identity and playback queues retain existing behavior; sorting groups does not reorder a track queue or change ratings.

Settings are validated and stored in saved music. Backup settings restoration includes them only when opted in; old saved data and backups receive defaults. Defaults are the six library categories in the existing order, three library columns, two group columns, list layout, alphabetical group order and enabled summaries. Labels for the new controls use Romanian/English ARB resources.

Unit/widget tests cover legacy data, invalid settings, immutable category order, visibility constraints, deterministic sorting, stable group callbacks, large text/narrow grids, independent page reset, failed writes, concurrent rating edits and backup settings opt-in. Device tests never use live Android integration entrypoints.

Validation: all 97 unit/widget tests and analysis passed. Android arm64 and Windows x64 release builds succeeded. On OnePlus 8T, the album grid with three columns and count sorting survived process restart, group detail/summary opened correctly, category drag/hiding and two-column browsing worked, and the Artist settings page opened independently. Test preferences were reset afterward. The live installation retained its 153-track library and existing paused queue after private metadata backup and install -r.
