# Languages

Aura includes twenty offline catalogs: Romanian, English, French, German, Spanish, Italian, Portuguese, Russian, Ukrainian, Polish, Dutch, Turkish, Arabic, Hindi, Simplified Chinese, Japanese, Korean, Indonesian, Vietnamese and Thai.

At first launch, choose your native language from the twenty endonyms and press Continue. Installations upgraded without a native-language choice also show this setup once. It is saved separately from the current interface language. The system language helps display setup, but cannot be selected as the native safety language.

Choose **Settings → Languages** (Romanian: **Setări → Traduceri**) to change the interface language or update your native language. Selecting a different interface language previews it immediately without rebuilding the library or restarting playback. The five-second Yes/No confirmation always uses the saved native language and its text direction. Only Yes keeps the selection. No, expiry, Back, tapping outside the dialog or backgrounding Aura restores the native language, even if the previous interface language was something else. Native-language changes also require confirmation in the existing native language.

Unconfirmed previews stay in memory and are excluded from concurrent music saves and backups; restarting the app keeps the previous saved choice. Canceling a preview persists the native interface language. If that write fails, Aura keeps the readable native language for the current session and shows an error; a restart can still load the last successfully saved interface language. Confirmed interface settings can be restored from backups, but imports always preserve this device's native safety language. Old backups lacking that field do not remove a configured native language.

After native-language setup, the interface can still follow the system if explicitly selected. System selection matches supported language codes, including regional variants such as `fr-CA`, and falls back to English when none of the device's preferred languages is supported. Arabic uses right-to-left layout, including rating gestures.

App screens, dialogs, greetings, accessibility labels, errors and playback controls use ARB resources. Counts use ICU plurals, and dates and decimal numbers follow the selected locale. Song titles, artist names, playlist names, file paths and other user content are preserved. System-owned dialogs and Android notification-channel settings can follow the operating system's own language and lifecycle.

The additional fourteen language catalogs started as machine-assisted drafts generated locally using [Argos Translate models](https://github.com/argosopentech/argospm-index), followed by manual reviews of core navigation, playback actions, greetings and plural rules. Native-speaker review of extended wording remains welcome. Completeness checks do not guarantee idiomatic wording in every language. Translation models and development tools are not included in the app; no translation service is contacted at runtime.

## Maintenance and validation

Edit the matching `lib/l10n/app_*.arb` resources, preserving message keys, ICU syntax, placeholders and placeholder metadata. Run `flutter pub get` or `flutter gen-l10n` to regenerate the ignored Dart localization files, then run `flutter analyze` and `flutter test`.

Localization tests check catalog parity, placeholders, plural examples, absence of tokenizer artifacts, persistence and failed saves, backup opt-in, system-language fallback, immediate changes on existing routes, all twenty locales on a narrow screen, Arabic rating gestures and unchanged music metadata. Safety tests cover first-run setup, native-language persistence and change confirmation, five-second expiry, Yes/No, dismissal near expiry, background/resume, RTL prompts, concurrent saves/restart during a preview and Japanese → Korean → native Romanian. Device checks complement these tests; they do not replace native-speaker review.
