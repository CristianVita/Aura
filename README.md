# Aura

An independent Flutter music player for your own music library.

## Current features

- Dark interface with home, collection, search and settings screens.
- Android audio scanning and persistent local library metadata.
- Source folder selection and browsing by song, album or artist.
- Local and background playback, seeking, previous/next controls and media notification.
- Embedded artwork and song information.
- Playback queue with selection, removal and drag reordering.
- Shuffle showing the actual playback order, and repeat off/all/one.
- Persistent favorites and playlists, with creation, renaming, deletion and track selection.
- Listening history with recent tracks and an option to clear it.
- Restored queue, current track, position, shuffle order and repeat mode; reopening stays paused.
- Optional minimum-duration and WhatsApp/Telegram folder filters.

## Development

Developed with Flutter 3.47.9 / Dart 3.13.7. Install Flutter, Android SDK Platform 36, Android SDK Command-line Tools and NDK 28.2.13676358. Connect an Android device with USB debugging enabled, then run:

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
```

Build a debug APK for an ARM64 Android device:

```sh
flutter build apk --debug --target-platform android-arm64
```

Run the tests:

```sh
flutter test
```

Twenty-six automated tests cover artwork, saved music, playback/session restoration, missing files, shuffle ordering, listening thresholds, library filters, concurrent writes and UI flows. Android behavior is also checked on a OnePlus 8T running Android 14.

## Platform status and remaining work

Android is currently implemented and device-tested. Flutter project scaffolding exists for Windows, Linux, macOS, web and iOS; native library integrations and playback support for those platforms still need work. iOS is planned last.

Server/cloud music sources and the other platforms remain future work. A dedicated Aura icon and further interface refinements are also planned.

Playback position is checkpointed about every three seconds while playing, and on pause, seek, queue changes and app lifecycle transitions. Abrupt process termination may lose the last few seconds. History records after five seconds of actual playback, or after hearing a shorter track through, and keeps the latest 100 distinct tracks. Folder and duration filters affect browsing without deleting media or saved playlist references.

## Local data

Audio files stay on the device. Library metadata, folder preferences and cached artwork are stored in the app's private storage. Device libraries, audio files, SDK paths, signing keys and generated builds are not part of this repository.
