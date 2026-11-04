import 'dart:async';

import 'package:flutter/material.dart';

import 'app_language.dart';
import 'app_strings.dart';
import 'l10n/app_localizations.dart';
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

Future<bool> confirmAuraLanguage(
  BuildContext context,
  AppLanguage language, {
  bool native = false,
}) async {
  final store = SavedMusicScope.of(context);
  final baseline = store.data.nativeLanguage == AppLanguage.system
      ? store.data.language
      : store.data.nativeLanguage;
  final strings = baseline == AppLanguage.system
      ? context.appStrings
      : lookupAppLocalizations(Locale(baseline.name));
  final direction = baseline == AppLanguage.system
      ? Directionality.of(context)
      : baseline == AppLanguage.ar
      ? TextDirection.rtl
      : TextDirection.ltr;
  var saved = false;
  try {
    store.previewLanguage(language);
    final confirmed = await showDialog<bool>(
      context: context,
      barrierLabel: strings.uiClose,
      builder: (_) =>
          _LanguageConfirmation(strings: strings, direction: direction),
    );
    if (confirmed == true && context.mounted) {
      if (native) {
        await store.setNativeLanguage(language);
      } else {
        await store.setLanguage(language);
      }
      saved = true;
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(strings.languageSaveError)));
    }
  } finally {
    if (saved) {
      store.previewLanguage(null);
    } else {
      // Keep a readable native-language UI even if persisting the revert fails.
      store.previewLanguage(baseline);
      try {
        if (store.data.language != baseline) await store.setLanguage(baseline);
        store.previewLanguage(null);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(strings.languageSaveError)));
        }
      }
    }
  }
  return saved;
}

class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key});
  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  bool _busy = false;
  Future<void> _save(AppLanguage language) async {
    if (_busy) return;
    final store = SavedMusicScope.of(context);
    if (language == store.effectiveLanguage) return;
    setState(() => _busy = true);
    try {
      await confirmAuraLanguage(context, language);
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
          ListTile(
            key: const ValueKey('native-language-change'),
            leading: const Icon(Icons.language),
            title: Text(context.appStrings.nativeLanguageTitle),
            subtitle: Text(languageName(store.data.nativeLanguage)),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy
                ? null
                : () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NativeLanguageSetup(change: true),
                    ),
                  ),
          ),
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
              selected: store.effectiveLanguage == language,
              trailing: store.effectiveLanguage == language
                  ? const Icon(Icons.check)
                  : null,
              onTap: store.ready && !_busy ? () => _save(language) : null,
            ),
        ],
      ),
    );
  }
}

class NativeLanguageGate extends StatelessWidget {
  const NativeLanguageGate({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final store = SavedMusicScope.of(context);
    return store.ready && store.data.nativeLanguage == AppLanguage.system
        ? const NativeLanguageSetup()
        : child;
  }
}

class NativeLanguageSetup extends StatefulWidget {
  const NativeLanguageSetup({super.key, this.change = false});
  final bool change;

  @override
  State<NativeLanguageSetup> createState() => _NativeLanguageSetupState();
}

class _NativeLanguageSetupState extends State<NativeLanguageSetup> {
  AppLanguage? _selected;
  bool _busy = false;

  Future<void> _continue() async {
    if (_selected == null || _busy) return;
    final store = SavedMusicScope.of(context);
    final strings = lookupAppLocalizations(Locale(_selected!.name));
    setState(() => _busy = true);
    try {
      if (widget.change) {
        if (await confirmAuraLanguage(context, _selected!, native: true) &&
            mounted) {
          Navigator.pop(context);
        }
      } else {
        await store.setNativeLanguage(_selected!);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(strings.languageSaveError)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = _selected == null
        ? context.appStrings
        : lookupAppLocalizations(Locale(_selected!.name));
    return PopScope(
      canPop: widget.change && !_busy,
      child: Directionality(
        textDirection: (_selected?.name ?? strings.localeName) == 'ar'
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: widget.change,
            title: Text(strings.nativeLanguageTitle),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(strings.nativeLanguageHelp),
              for (final language in AppLanguage.values.where(
                (language) => language != AppLanguage.system,
              ))
                ListTile(
                  key: ValueKey('native-language-${language.name}'),
                  title: Text(languageName(language)),
                  trailing: _selected == language
                      ? const Icon(Icons.check)
                      : null,
                  selected: _selected == language,
                  onTap: _busy
                      ? null
                      : () => setState(() => _selected = language),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: FilledButton.icon(
              key: const ValueKey('native-language-continue'),
              icon: const Icon(Icons.check),
              onPressed: _selected == null || _busy ? null : _continue,
              label: Text(strings.nativeLanguageContinue),
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageConfirmation extends StatefulWidget {
  const _LanguageConfirmation({required this.strings, required this.direction});
  final AppLocalizations strings;
  final TextDirection direction;

  @override
  State<_LanguageConfirmation> createState() => _LanguageConfirmationState();
}

class _LanguageConfirmationState extends State<_LanguageConfirmation>
    with WidgetsBindingObserver {
  late final Timer _deadline;
  late final Timer _countdown;
  int _seconds = 5;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _deadline = Timer(const Duration(seconds: 5), () => _finish(false));
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _seconds > 1) setState(() => _seconds--);
    });
  }

  void _finish(bool confirmed) {
    if (_finished || !mounted) return;
    _finished = true;
    _deadline.cancel();
    _countdown.cancel();
    final route = ModalRoute.of<bool>(context);
    if (route == null || !route.isActive) return;
    if (route.isCurrent) {
      Navigator.of(context).pop(confirmed);
    } else {
      Navigator.of(context).removeRoute(route, confirmed);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _finish(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _deadline.cancel();
    _countdown.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: widget.direction,
    child: AlertDialog(
      semanticLabel: widget.strings.languageConfirmTitle,
      title: Text(widget.strings.languageConfirmTitle),
      content: Text(widget.strings.languageConfirmMessage(_seconds)),
      actions: [
        TextButton(
          key: const ValueKey('language-confirm-no'),
          onPressed: () => _finish(false),
          child: Text(widget.strings.languageConfirmNo),
        ),
        FilledButton(
          key: const ValueKey('language-confirm-yes'),
          onPressed: () => _finish(true),
          child: Text(widget.strings.languageConfirmYes),
        ),
      ],
    ),
  );
}
