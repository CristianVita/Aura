# Working with Aura

- Never uninstall `com.example.symphonium_clone`, clear its data, or run Android integration tests under that application ID. It is the user's live installation.
- Android integration entrypoints must build as `com.example.symphonium_clone.integration`. Flutter can replace the integration-test target with a temporary `flutter_test_listener.*/listener.dart` bootstrap; the Gradle guard recognizes both forms. Verify the application ID of the exact APK that will be installed. If a command rebuilds it, verify the rebuilt APK too; never assume a previously checked APK is still the one being installed.
- Keep device integration tests separate from normal user data. Use synthetic media, in-memory preferences, and uniquely named test storage keys.
- Before replacing an existing development APK, preserve a private backup of the app's library, saved music and playback-memory JSON outside the Git repository. Do not commit user metadata or credentials.
- Normal updates use `adb install -r` and retain the live application ID. After testing, verify that normal Aura is still installed.
