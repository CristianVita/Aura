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

Fourteen automated tests cover artwork loading, queue metadata, saved music persistence, concurrent edits, failed writes and playlist UI flows. Android behavior is also checked on a OnePlus 8T running Android 14.

## Platform status and remaining work

Android is currently implemented and device-tested. Flutter project scaffolding exists for Windows, Linux, macOS, web and iOS; native library integrations and playback support for those platforms still need work. iOS is planned last.

Listening history, server/cloud music sources and restoring the playback queue after restarting the app are not implemented yet.

## Local data

Audio files stay on the device. Library metadata, folder preferences and cached artwork are stored in the app's private storage. Device libraries, audio files, SDK paths, signing keys and generated builds are not part of this repository.
