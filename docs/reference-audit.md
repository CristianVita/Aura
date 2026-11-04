# Playback reference inspection — 2026-11-02

Inspected the installed Symfonium interface through normal navigation. No reference application settings, ratings, accounts or media were changed. Screenshots and device library contents are not part of this repository.

Observed categories: output settings, playback, automatic actions, decoding/transcoding, transitions, audio focus, headset buttons, notification/media-session buttons and advanced settings. The player exposes a sleep timer and speed/pitch controls. Its timer supports finishing the last track; speed controls include fine adjustment and presets.

This Aura iteration implements player-specific volume, persistent playback speed, a deadline-based sleep timer with optional finish-current-track behavior, stop-at-track-end and quick access from the player. Saved preferences remain compatible with earlier Aura data. Sleep timers are deliberately not restored after process exit.

## Second pass and implemented audio features

Aura now uses `audio_service` directly with an authoritative queue player and a second decoder for crossfade. Automatic transitions overlap the next track and hand its position back to the main queue. A discontinuity event carries the new index before just_audio updates its getters; handoff therefore uses the event index and waits for queue state to catch up. Manual seeks, skips, pause and buffering cancel an overlap. Crossfade defaults off, excludes repeat-one and very short tracks, and falls back to ordinary queue playback if preparation fails.

Added configurable play/pause fades, Android equalizer bands with Flat/Bass/Voice presets and gain headroom, notification previous/next versus ±10-second controls, optional Stop, headset skip-versus-seek actions and a keep-paused-on-skip preference. Windows does not expose an equalizer through the current backend, so its UI explicitly marks this capability as Android-only.

Native checks exercised overlap, handoff, seek, queue order, timer pause and media commands on Windows and Android, plus equalizer parameter application on Android. Remote-server transition quality still needs validation against a real Navidrome server and slow networks. No claim is made that crossfade is sample-accurate or supported for every codec/device.

The second UI inspection covered library categories, player actions and offline media/playback settings. Notable reference options: Wi-Fi-only downloads, original/transcoded download quality, automatic favorite downloads, parallel download limits, a separate playback cache, backup/restore and configurable page layouts.

Recommended next work, in order:

1. In-app backup/restore of preferences, ratings, playlists and history, with a preview before restoring — completed on 2026-11-04; see [backup behavior and validation](backup-restore.md).
2. Explicit offline downloads and a bounded playback cache, with Wi-Fi and storage controls.
3. Smart playlists built from rating, favorites, play count and recency.
4. Search by genre/year, configurable library categories and durable search history.
5. Lyrics, ReplayGain/loudness metadata, pitch controls, Android Auto and renderer integration.

These recommendations are a roadmap, not implemented features. Audio-focus customization and more advanced decoding/transcoding also remain future work.

## Device integration isolation

Flutter integration-test cleanup uninstalls its target package. Android integration targets now receive application ID `com.example.symphonium_clone.integration`; the normal ID remains `com.example.symphonium_clone`. The separate ID and launcher activity were verified from the built APK on the PC. Do not run device tests until that ID has been checked. Live device metadata backups remain private and outside this repository.
