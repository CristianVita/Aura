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
- Windows local library: add music folders, rescan, select visible folders and remove sources without deleting files.
- Windows audio playback and a sidebar for wide windows; library, favorites and history are stored separately on each device.
- Original Aura icon for Android, Windows and web assets.

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

Thirty-one automated tests cover artwork, saved music, playback/session restoration, missing files, shuffle ordering, listening thresholds, library filters, concurrent writes, Windows scanning/storage and UI flows. Android behavior is also checked on a OnePlus 8T running Android 14.

For Windows development, install Visual Studio's **Desktop development with C++** workload, including C++ CMake tools and a Windows SDK. Build with:

```sh
flutter build windows --release
```

Distribute the entire `build/windows/x64/runner/Release` folder, including its DLLs and `data` folder. The target PC also needs the Microsoft Visual C++ runtime. This is an unsigned development build.

A Windows integration test generates a quiet WAV tone locally and verifies the native backend's play/pause, seek, next-track, shuffle and repeat controls:

```sh
flutter test integration_test/windows_playback_test.dart -d windows
```

Regenerate the code-drawn Aura icon with `./tool/generate_brand_assets.ps1` on Windows.

## Platform status and remaining work

Android is implemented and device-tested. Windows local scanning, persistence and playback are implemented; native playback is checked with WAV audio. File-format support depends on the Windows audio backend and installed codecs. Linux, macOS, web and iOS still need native library and playback integration. iOS is planned last.

Server/cloud music sources, synchronization between devices and further interface refinements remain future work. Closing the Windows window exits the player; tray playback and Windows media-key integration are not implemented yet.

Playback position is checkpointed about every three seconds while playing, and on pause, seek, queue changes and app lifecycle transitions. Abrupt process termination may lose the last few seconds. History records after five seconds of actual playback, or after hearing a shorter track through, and keeps the latest 100 distinct tracks. Folder and duration filters affect browsing without deleting media or saved playlist references.

## Local data

Audio files stay on the device. Library metadata, folder preferences and cached artwork are stored in the app's private storage. Device libraries, audio files, SDK paths, signing keys and generated builds are not part of this repository.
