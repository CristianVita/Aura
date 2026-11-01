# Working with Aura

- Never uninstall `com.example.symphonium_clone`, clear its data, or run Android integration tests under that application ID. It is the user's live installation.
- Android integration entrypoints must build as `com.example.symphonium_clone.integration`. The Gradle configuration derives this from the `target` integration-test path. Verify the built APK application ID before any on-device test installation.
- Keep device integration tests separate from normal user data. Use synthetic media, in-memory preferences, and uniquely named test storage keys.
- Before replacing an existing development APK, preserve a private backup of the app's library, saved music and playback-memory JSON outside the Git repository. Do not commit user metadata or credentials.
- Normal updates use `adb install -r` and retain the live application ID. After testing, verify that normal Aura is still installed.
