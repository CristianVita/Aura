import 'package:flutter/widgets.dart';

import 'l10n/app_localizations.dart';

enum AppLanguage {
  system,
  ro,
  en,
  fr,
  de,
  es,
  it,
  pt,
  ru,
  uk,
  pl,
  nl,
  tr,
  ar,
  hi,
  zh,
  ja,
  ko,
  id,
  vi,
  th,
}

Locale resolveAuraLocale(AppLanguage language, Iterable<Locale> deviceLocales) {
  if (language != AppLanguage.system) return Locale(language.name);
  for (final locale in deviceLocales) {
    if (AppLocalizations.supportedLocales.any(
      (supported) => supported.languageCode == locale.languageCode,
    )) {
      return Locale(locale.languageCode);
    }
  }
  return const Locale('en');
}

// Background notifications and native file dialogs have no widget context.
abstract final class AppText {
  static final _locale = ValueNotifier<Locale>(const Locale('ro'));
  static Listenable get changes => _locale;
  static String get localeCode => _locale.value.toLanguageTag();
  static AppLocalizations get current => lookupAppLocalizations(_locale.value);
  static void useLocale(Locale locale) {
    _locale.value = locale;
  }
}
