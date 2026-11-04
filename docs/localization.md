# Languages

Aura includes twenty offline catalogs: Romanian, English, French, German, Spanish, Italian, Portuguese, Russian, Ukrainian, Polish, Dutch, Turkish, Arabic, Hindi, Simplified Chinese, Japanese, Korean, Indonesian, Vietnamese and Thai.

Choose **Settings → Languages** (Romanian: **Setări → Traduceri**). Changes apply immediately, including routes already open, without rebuilding the library or restarting playback. The setting is saved locally and included when restoring settings from an Aura backup.

New installations follow the system language; existing data without a language preference keeps Romanian. System selection matches supported language codes, including regional variants such as `fr-CA`, and falls back to English when none of the device's preferred languages is supported. Arabic uses right-to-left layout, including rating gestures.

App screens, dialogs, greetings, accessibility labels, errors and playback controls use ARB resources. Counts use ICU plurals, and dates and decimal numbers follow the selected locale. Song titles, artist names, playlist names, file paths and other user content are preserved. System-owned dialogs and Android notification-channel settings can follow the operating system's own language and lifecycle.

The additional fourteen language catalogs started as machine-assisted drafts generated locally using [Argos Translate models](https://github.com/argosopentech/argospm-index), followed by manual reviews of core navigation, playback actions, greetings and plural rules. Native-speaker review of extended wording remains welcome. Completeness checks do not guarantee idiomatic wording in every language. Translation models and development tools are not included in the app; no translation service is contacted at runtime.

## Maintenance and validation

Edit the matching `lib/l10n/app_*.arb` resources, preserving message keys, ICU syntax, placeholders and placeholder metadata. Run `flutter pub get` or `flutter gen-l10n` to regenerate the ignored Dart localization files, then run `flutter analyze` and `flutter test`.

Localization tests check catalog parity, placeholders, plural examples, persistence and failed saves, backup opt-in, system-language fallback, immediate changes on existing routes, all twenty locales on a narrow screen, Arabic rating gestures and unchanged music metadata. Device checks complement these tests; they do not replace native-speaker review.
