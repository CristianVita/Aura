import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_strings.dart';
import 'saved_music.dart';

String languageName(AppLanguage language) => switch (language) {
  AppLanguage.system => '',
  AppLanguage.ro => 'Română',
  AppLanguage.en => 'English',
  AppLanguage.fr => 'Français',
  AppLanguage.de => 'Deutsch',
  AppLanguage.es => 'Español',
  AppLanguage.it => 'Italiano',
  AppLanguage.pt => 'Português',
  AppLanguage.ru => 'Русский',
  AppLanguage.uk => 'Українська',
  AppLanguage.pl => 'Polski',
  AppLanguage.nl => 'Nederlands',
  AppLanguage.tr => 'Türkçe',
  AppLanguage.ar => 'العربية',
  AppLanguage.hi => 'हिन्दी',
  AppLanguage.zh => '简体中文',
  AppLanguage.ja => '日本語',
  AppLanguage.ko => '한국어',
  AppLanguage.id => 'Bahasa Indonesia',
  AppLanguage.vi => 'Tiếng Việt',
  AppLanguage.th => 'ไทย',
};

class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key});
  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  bool _busy = false;
  Future<void> _save(AppLanguage language) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await SavedMusicScope.of(context).setLanguage(language);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.appStrings.languageSaveError)),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = SavedMusicScope.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.appStrings.languageTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(context.appStrings.languageHelp),
          ),
          for (final language in AppLanguage.values)
            ListTile(
              key: ValueKey('language-${language.name}'),
              title: Text(
                language == AppLanguage.system
                    ? context.appStrings.languageSystem
                    : languageName(language),
              ),
              selected: store.data.language == language,
              trailing: store.data.language == language
                  ? const Icon(Icons.check)
                  : null,
              onTap: store.ready && !_busy ? () => _save(language) : null,
            ),
        ],
      ),
    );
  }
}
