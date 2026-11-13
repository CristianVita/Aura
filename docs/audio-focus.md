# Audio focus

Aura retains the audio session's normal music behavior by default. On Android, an optional setting under Playback → Audio focus requests a pause when another app requests a temporary interruption that would otherwise allow ducking. It is disabled by default and requires a complete Aura restart to apply. The existing player handles interruption end and may resume playback automatically; platform and app behavior can vary. Other platforms display the setting as unavailable.

The preference is stored with the other audio settings and participates in backups that include settings. Legacy data leaves it off. Unit and widget tests cover the default, serialization, session configuration and navigation. On a physical Android device, an isolated test APK using silent synthetic audio and a synthetic transient focus request verified that the opted-in player paused and resumed. A real phone call or notification, other devices, and interactions with crossfade have not been tested.
