# Android Auto: preparation, not yet enabled

Aura already has an Android `MediaBrowserService` and media session supplied by `audio_service`, but its handler does not yet offer a browsable music library or playback by media ID. The manifest does not declare an Android Auto application. The settings entry must remain unavailable until a complete integration has been implemented and tested.

`CarMediaCatalog` is an isolated local snapshot for future integration. It creates bounded pages for tracks and favorites and maps opaque IDs back to local track objects without starting playback, accessing a server, exporting credentials or exposing raw file paths as IDs. Labels are provided by the caller, so a future handler must supply localized strings. A successful lookup is not permission to start playback: the handler still needs to validate current availability, resolve the source through Aura's existing playback path and report failures. The snapshot must be refreshed when the library, favorites or selected folders change; old IDs may no longer resolve.

The service is exported. In the installed `audio_service` dependency, `AudioService.onGetRoot` returns a browser root without checking the calling package, so wiring user data into browsing requires an appropriate host-validation design. Opaque IDs are not an authorization mechanism. The Android Auto media declaration should not be enabled until legitimate hosts can browse while untrusted callers are handled safely.

Before claiming support, implement and verify at least:

- A current, app-scoped library snapshot that can load when the service is started without the phone's library screen, without unexpectedly changing the user's Navidrome configuration or exposing authentication data.
- Browser children and playback by media ID in the authoritative audio handler, including unknown/stale IDs, unavailable/offline sources, queue changes, notifications, favorites and startup failures. Translate platform pagination correctly and bound requests.
- Android Auto metadata and icons, Android host validation, localizations and appropriate user-facing errors. Android Automotive OS is a separate distribution target and must not be assumed to follow the phone manifest.
- Tests with an isolated test APK and a simulated library, then the Android Auto Desktop Head Unit or a suitable real host. No such host test was performed in this preparation.

References: [Android for Cars media overview](https://developer.android.com/training/cars/media), [manifest configuration](https://developer.android.com/training/cars/media/configure-manifest), [content hierarchy](https://developer.android.com/training/cars/media/create-media-browser/content-hierarchy), and [Android Automotive OS support](https://developer.android.com/training/cars/media/automotive-os).
