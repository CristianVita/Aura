# Playback reference inspection — 2026-11-02

Inspected the installed Symfonium interface through normal navigation. No reference application settings, ratings, accounts or media were changed. Screenshots and device library contents are not part of this repository.

Observed categories: output settings, playback, automatic actions, decoding/transcoding, transitions, audio focus, headset buttons, notification/media-session buttons and advanced settings. The player exposes a sleep timer and speed/pitch controls. Its timer supports finishing the last track; speed controls include fine adjustment and presets.

This Aura iteration implements player-specific volume, persistent playback speed, a deadline-based sleep timer with optional finish-current-track behavior, stop-at-track-end and quick access from the player. Saved preferences remain compatible with earlier Aura data. Sleep timers are deliberately not restored after process exit.

Further work: audio-focus policy, headset actions, notification button configuration, fade/crossfade, pitch controls, equalizer, decoding/transcoding settings and Android Auto. These have not been implemented by this iteration; each needs backend support and device validation.
