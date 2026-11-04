# Aura settings navigation

The settings hierarchy follows the supplied reference screenshots: Settings, Miscellaneous and About groups; an Interface submenu with collapsible sections; a Playback submenu with dedicated output, playback, automatic actions, transitions, headset and notification pages; and an Offline/cache/download category.

The layout uses compact outline icons, muted blue-gray grouped surfaces, separators and pale-blue section headings. Aura retains its name, assets and Romanian wording. Support/promotional cards from the reference application are not reproduced as Aura services.

Implemented destinations keep their existing behavior: player volume, speed, sleep timer, crossfade/fades, Android EQ, headset commands, media notification buttons, star size, library filters, source management and listening history. Output and playback pages expose their own controls; headset and notification settings no longer require opening a combined page.

Unavailable features are disabled and labeled `În pregătire`: theme/font customization, configurable page layouts, advanced decoding/audio focus, Android Auto, server downloads/cache, generated files, translations and store/support links. Backup/restore is optional in the menu API and remains disabled in this release until the separate restoration implementation is validated. Menu structure is not a claim that those capabilities are implemented.

The widget navigation test uses an in-memory music store and a fake audio player on a 320-pixel-wide display. It checks disabled actions, collapsible sections, access to star sizing, separate volume/speed pages, back navigation and the source-management callback. No test uses live phone data.
