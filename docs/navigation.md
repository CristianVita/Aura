# Navigation and start screen

Interface → Navigation and start screen controls the order of the four tabs, optional Home/Search visibility, the next cold-start screen, and the library landing page (categories, tracks, albums, artists, playlists or favorites). Library and Settings stay visible to keep browsing and configuration reachable. Hiding the current/start tab falls back to Library.

Tabs use stable identities; reordering does not change which page a destination opens. A hidden Search tab remains accessible through Home's search button as a separate page. Start-screen changes apply on the next app launch; selecting Library applies its configured landing page. Explicit album/artist/favorite shortcuts still open their requested category.

Label modes are adaptive (phone icons, extended desktop rail), icons only, selected tab, and all labels. A preview is included. Preferences persist atomically alongside ratings and playlists and participate in backup's optional settings restoration. Older saved data and backups retain the original navigation defaults.

Unit/widget coverage checks validation, final-index drag order, stable callbacks on phone/desktop, saved-state failures, concurrent rating edits, backup opt-in, localized controls, visibility fallback and reset. Tests use in-memory data, never the live Android application.

Native verification: updated the live Android app with install -r after a private metadata backup; tested dragging Settings to the first position, starting in Library/Tracks after process restart, hiding Search, showing all labels, and resetting navigation. The library remained at 153 tracks; existing appearance preferences were retained. Android arm64 release and Windows x64 release builds passed.
