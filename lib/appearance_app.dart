import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'appearance.dart';
import 'app_language.dart';
import 'l10n/app_localizations.dart';
import 'saved_music.dart';

class AuraAppearanceApp extends StatefulWidget {
  const AuraAppearanceApp({
    super.key,
    required this.store,
    required this.home,
    this.locale,
  });
  final SavedMusicStore store;
  final Widget home;
  final Locale? locale;
  @override
  State<AuraAppearanceApp> createState() => _AuraAppearanceAppState();
}

class _AuraAppearanceAppState extends State<AuraAppearanceApp> {
  late AppearancePreferences _appearance;
  late AppLanguage _language;
  @override
  void initState() {
    super.initState();
    _appearance = widget.store.data.appearance;
    _language = widget.store.effectiveLanguage;
    widget.store.addListener(_changed);
  }

  void _changed() {
    if (_appearance != widget.store.data.appearance ||
        _language != widget.store.effectiveLanguage) {
      setState(() {
        _appearance = widget.store.data.appearance;
        _language = widget.store.effectiveLanguage;
      });
    }
  }

  @override
  void didUpdateWidget(AuraAppearanceApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_changed);
      widget.store.addListener(_changed);
      _appearance = widget.store.data.appearance;
      _language = widget.store.effectiveLanguage;
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SavedMusicScope(
    store: widget.store,
    child: MaterialApp(
      title: 'Aura',
      debugShowCheckedModeBanner: false,
      locale:
          widget.locale ??
          (_language == AppLanguage.system ? null : Locale(_language.name)),
      localeListResolutionCallback: (locales, supported) =>
          resolveAuraLocale(AppLanguage.system, locales ?? const []),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAuraTheme(_appearance, Brightness.light),
      darkTheme: buildAuraTheme(_appearance, Brightness.dark),
      themeMode: appearanceThemeMode(_appearance.mode),
      builder: (context, child) {
        AppText.useLocale(Localizations.localeOf(context));
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: AppearanceTextScaler(
              media.textScaler,
              _appearance.textScale,
            ),
          ),
          child: child!,
        );
      },
      home: widget.home,
    ),
  );
}
