import 'package:flutter/material.dart';

import 'appearance.dart';
import 'app_theme.dart';
import 'app_strings.dart';
import 'saved_music.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});
  @override
  State<AppearanceSettingsScreen> createState() =>
      _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  bool _busy = false;
  double? _scale;
  Future<void> _save(AppearancePreferences value) async {
    final store = SavedMusicScope.of(context);
    setState(() => _busy = true);
    try {
      await store.setAppearance(value);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.appStrings.appearanceSaveError)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _scale = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = SavedMusicScope.of(context);
    final appearance = store.data.appearance;
    final enabled = store.ready && !_busy;
    final strings = context.appStrings;
    Widget section(String title, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 10),
            child: Text(
              title,
              style: TextStyle(color: context.auraAccent, fontSize: 16),
            ),
          ),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(padding: const EdgeInsets.all(16), child: child),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: Text(strings.appearanceTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          section(
            strings.themeLabel,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final mode in AppearanceMode.values)
                  ChoiceChip(
                    key: ValueKey('theme-${mode.name}'),
                    label: Text(switch (mode) {
                      AppearanceMode.system => strings.themeSystem,
                      AppearanceMode.light => strings.themeLight,
                      AppearanceMode.dark => strings.themeDark,
                      AppearanceMode.oled => strings.themeOled,
                    }),
                    selected: appearance.mode == mode,
                    onSelected: enabled
                        ? (_) => _save(appearance.copy(mode: mode))
                        : null,
                  ),
              ],
            ),
          ),
          section(
            strings.accentLabel,
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final accent in AppearanceAccent.values)
                  ChoiceChip(
                    key: ValueKey('accent-${accent.name}'),
                    avatar: DecoratedBox(
                      decoration: BoxDecoration(
                        color: accentSeed(accent),
                        shape: BoxShape.circle,
                        border: Border.all(color: context.auraMuted),
                      ),
                      child: const SizedBox.square(dimension: 20),
                    ),
                    label: Text(switch (accent) {
                      AppearanceAccent.mint => strings.accentMint,
                      AppearanceAccent.blue => strings.accentBlue,
                      AppearanceAccent.violet => strings.accentViolet,
                      AppearanceAccent.rose => strings.accentRose,
                      AppearanceAccent.amber => strings.accentAmber,
                      AppearanceAccent.teal => strings.accentTeal,
                    }),
                    selected: appearance.accent == accent,
                    onSelected: enabled
                        ? (_) => _save(appearance.copy(accent: accent))
                        : null,
                  ),
              ],
            ),
          ),
          section(
            strings.fontLabel,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final font in AppearanceFont.values)
                      ChoiceChip(
                        key: ValueKey('font-${font.name}'),
                        label: Text(
                          switch (font) {
                            AppearanceFont.system => strings.fontSystem,
                            AppearanceFont.serif => strings.fontSerif,
                            AppearanceFont.monospace => strings.fontMonospace,
                          },
                          style: TextStyle(
                            fontFamily: appearanceFontFamily(
                              font,
                              Theme.of(context).platform,
                            ),
                          ),
                        ),
                        selected: appearance.font == font,
                        onSelected: enabled
                            ? (_) => _save(appearance.copy(font: font))
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  strings.fontDescription,
                  style: TextStyle(color: context.auraMuted),
                ),
              ],
            ),
          ),
          section(
            strings.textSizeLabel,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.percentValue(
                    ((_scale ?? appearance.textScale) * 100).round(),
                  ),
                ),
                Slider(
                  key: const ValueKey('appearance-text-size'),
                  min: .85,
                  max: 1.3,
                  divisions: 9,
                  label: strings.percentValue(
                    ((_scale ?? appearance.textScale) * 100).round(),
                  ),
                  value: _scale ?? appearance.textScale,
                  onChanged: enabled
                      ? (value) => setState(() => _scale = value)
                      : null,
                  onChangeEnd: enabled
                      ? (value) => _save(
                          appearance.copy(
                            textScale: (value * 100).round() / 100,
                          ),
                        )
                      : null,
                ),
                Text(
                  strings.textSizeDescription,
                  style: TextStyle(color: context.auraMuted),
                ),
              ],
            ),
          ),
          section(
            strings.previewLabel,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  strings.previewTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  strings.previewSubtitle,
                  style: TextStyle(color: context.auraMuted),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: null,
                  style: FilledButton.styleFrom(
                    disabledBackgroundColor: context.auraAccent,
                    disabledForegroundColor: context.auraOnAccent,
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(strings.previewButton),
                ),
              ],
            ),
          ),
          Text(
            strings.appearanceHelp,
            style: TextStyle(color: context.auraMuted),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: enabled
                ? () => _save(const AppearancePreferences())
                : null,
            icon: const Icon(Icons.restart_alt),
            label: Text(strings.resetAppearance),
          ),
        ],
      ),
    );
  }
}
