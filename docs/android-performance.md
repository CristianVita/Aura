# Android frame pacing verification — 2026-11-04

The high-refresh preference alone does not establish rendered UI performance. A display can report 120 Hz while an application presents fewer frames or misses deadlines.

Checked the normal Aura package on a OnePlus 8T, Android 14. Its display exposes 60 and 120 Hz; 144 Hz hardware was not available. SurfaceFlinger reported an active render rate of 120 Hz and no UID frame-rate overrides. The window requested 120 Hz; system peak refresh was 120 and battery saver was off. No system settings were changed.

Measured SurfaceFlinger presentation timestamp intervals for Aura's Flutter BLAST surface during 700 ms vertical swipes and their immediate continuation. The list remained populated with the user's existing library. No media, metadata or account contents are included here.

| Build | Frames in sample | Median interval | 90th percentile | Intervals over 12 ms |
| --- | ---: | ---: | ---: | ---: |
| Debug, folder list, up | 72 | 8.30 ms | 16.57 ms | 10 |
| Debug, folder list, down | 74 | 8.30 ms | 16.57 ms | 11 |
| Release, tracks list, down | 90 | 8.29 ms | 8.31 ms | 1 |
| Release, tracks list, up | 84 | 8.29 ms | 8.32 ms | 0 |

An 8.33 ms cadence corresponds to 120 presented frames per second. These short samples demonstrate 120 FPS presentation during the measured release scrolling; they do not guarantee that every screen, cold artwork load, thermal state or future interaction remains at that rate. The folder and full-track lists were not identical datasets, so this is a diagnostic check rather than a controlled performance benchmark. One intervening sample was discarded because ADB lost its server connection.

The optimized ARM64 release APK was built from commit `33bf0da`, verified to retain application ID `com.example.symphonium_clone`, and installed using `adb install -r`. Existing metadata was privately backed up before the update. The home and track list still showed all 153 tracks afterward. No application was uninstalled and no application data was cleared.

Build outside Documents if Controlled Folder Access prevents Flutter AOT/font-subsetting tools from writing generated files. Regenerate plugin registration for release by running `flutter build apk --release --target-platform android-arm64` without `--no-pub`; a stale debug registrant can reference the excluded integration-test plugin. No integration tests were run on the phone for this check.
