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
- Per-track 0.5–5 star ratings, horizontal drag with live half-star preview, small/medium/large star sizes, clearing, local persistence, a minimum-rating filter and rating sort.
- Navidrome over HTTPS: connect with URL and credentials, load/refresh albums and songs, stream audio, display covers and disconnect sources.
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

Sixty automated tests cover artwork, saved music, rating gestures and legacy-data migration, playback/session restoration, missing files, shuffle ordering, listening thresholds, library filters, concurrent writes, Windows scanning/storage, the Navidrome protocol, audio preferences, sleep-timer deadlines and UI flows. Android behavior is also checked on a OnePlus 8T running Android 14.

Rate a track using the five stars below its details in the full player, or long-press a collection/search track to open its information. Long-press a track in favorites or a playlist to open the rating dialog. The clear button removes the rating. Collection rating filters and sorting are saved locally; unrated tracks appear last when sorting by rating. These preferences do not change an existing playback queue, playlist order or audio-file tags. Ratings currently belong to each device and are not synchronized.

Choose **Setări → Interfață → Dimensiunea stelelor → Mici / Medii / Mari** to change their size. Drag horizontally across the stars for 0.5-star steps; the preview changes while dragging and the final value is saved on release. Tapping a star still selects its whole-star value. Existing integer ratings remain valid.

Choose **Adaugă o sursă → Server Navidrome → Adaugă server Navidrome**. Enter the HTTPS server base URL (including a reverse-proxy subfolder, when applicable), username and password. Refresh or disconnect from the same source screen. Server tracks also appear in the collection and search. Refreshing a nonempty server collection updates its remote metadata; offline playback/downloads are not implemented.

Navidrome uses Subsonic token authentication with a fresh salt per request. Credentials use `flutter_secure_storage`; the library and playback history retain logical track IDs rather than authenticated stream URLs. Only read endpoints are used: ratings, favorites and playlists remain local to Aura. Server covers are displayed inside the app; notification artwork for remote tracks is not implemented. Automated tests use simulated HTTP responses; verification against the user's actual Navidrome server is pending its URL and account.

For Windows development, install Visual Studio's **Desktop development with C++** workload, including C++ CMake tools, C++ ATL and a Windows SDK. Build with:

```sh
flutter build windows --release
```

Distribute the entire `build/windows/x64/runner/Release` folder, including its DLLs and `data` folder. The target PC also needs the Microsoft Visual C++ runtime. This is an unsigned development build.

Native integration tests check a synthetic secure-storage roundtrip and generate a quiet WAV tone to verify play/pause, seek, next-track, shuffle, repeat, crossfade overlap/handoff, timer pause and configurable media commands. Android also checks the equalizer. Windows invocation:

```sh
flutter test integration_test/windows_playback_test.dart -d windows
```

Android integration entrypoints build with the separate application ID `com.example.symphonium_clone.integration`. Verify the APK ID before device tests; Flutter automatically uninstalls the test package afterward. Never target the user's live Aura application ID. See [AGENTS.md](AGENTS.md).

Playback settings include persistent speed/volume, sleep timer, crossfade (off by default), play/pause fades, Android equalizer presets/bands, and Android headset/notification controls. Windows supports crossfade and fades, while equalization remains Android-only. The current second-decoder crossfade hands back to the authoritative queue and is not advertised as sample-accurate; remote-server/network behavior needs real-server testing. See [the reference audit](docs/reference-audit.md) for validation and the next-feature roadmap.

Regenerate the code-drawn Aura icon with `./tool/generate_brand_assets.ps1` on Windows.

## Platform status and remaining work

Android is implemented and device-tested. Windows local scanning, persistence and playback are implemented; native playback is checked with WAV audio. File-format support depends on the Windows audio backend and installed codecs. Linux, macOS, web and iOS still need native library and playback integration. iOS is planned last.

Generic cloud sources, other server protocols, synchronization between devices and further interface refinements remain future work. Closing the Windows window exits the player; tray playback and Windows media-key integration are not implemented yet.

Playback position is checkpointed about every three seconds while playing, and on pause, seek, queue changes and app lifecycle transitions. Abrupt process termination may lose the last few seconds. History records after five seconds of actual playback, or after hearing a shorter track through, and keeps the latest 100 distinct tracks. Folder and duration filters affect browsing without deleting media or saved playlist references.

## Local data

Protocol reference: [OpenSubsonic authentication](https://opensubsonic.netlify.app/docs/api-reference/), [album pagination](https://opensubsonic.netlify.app/docs/endpoints/getalbumlist2/) and [album tracks](https://opensubsonic.netlify.app/docs/endpoints/getalbum/).

Audio files stay on the device. Library metadata, folder preferences and cached artwork are stored in the app's private storage. Device libraries, audio files, SDK paths, signing keys and generated builds are not part of this repository.
