import 'package:aura/appearance.dart';
import 'package:aura/appearance_app.dart';
import 'package:aura/appearance_settings_screen.dart';
import 'package:aura/app_theme.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

void main() {
  testWidgets(
    'changing appearance on a pushed route updates the app without resetting its home or navigation',
    (tester) async {
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      var starts = 0;
      await tester.pumpWidget(
        AuraAppearanceApp(
          locale: const Locale('ro'),
          store: store,
          home: _Home(onStart: () => starts++),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('theme-light')));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(AppearanceSettingsScreen)))
            .brightness,
        Brightness.light,
      );
      expect(find.byType(AppearanceSettingsScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('accent-violet')),
        100,
      );
      await tester.tap(find.byKey(const ValueKey('accent-violet')));
      await tester.pumpAndSettle();
      expect(store.data.appearance.accent, AppearanceAccent.violet);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('font-serif')),
        100,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('font-serif')));
      await tester.tap(find.byKey(const ValueKey('font-serif')));
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(AppearanceSettingsScreen)))
            .textTheme
            .bodyMedium!
            .fontFamily,
        'serif',
      );
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(starts, 1);
      expect(find.text('Open'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets('failed preference save leaves theme and selection unchanged', (
    tester,
  ) async {
    final storage = MemorySavedMusicStorage();
    final store = SavedMusicStore(storage);
    await store.load();
    await tester.pumpWidget(
      AuraAppearanceApp(
        locale: const Locale('ro'),
        store: store,
        home: const AppearanceSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();
    storage.failNextWrite = true;
    await tester.tap(find.byKey(const ValueKey('theme-light')));
    await tester.pumpAndSettle();
    expect(store.data.appearance.mode, AppearanceMode.dark);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const ValueKey('theme-dark')))
          .selected,
      isTrue,
    );
    expect(
      Theme.of(tester.element(find.byType(AppearanceSettingsScreen)))
          .brightness,
      Brightness.dark,
    );
    expect(
      find.text(
        'Nu am putut salva aspectul. Setările anterioare au fost păstrate.',
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
    'system appearance responds to device brightness and OLED remains black',
    (tester) async {
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      await store.setAppearance(
        const AppearancePreferences(mode: AppearanceMode.system),
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpWidget(
        AuraAppearanceApp(
          locale: const Locale('ro'),
          store: store,
          home: const AppearanceSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      BuildContext page() =>
          tester.element(find.byType(AppearanceSettingsScreen));
      expect(Theme.of(page()).brightness, Brightness.light);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(Theme.of(page()).brightness, Brightness.dark);
      await tester.tap(find.byKey(const ValueKey('theme-oled')));
      await tester.pumpAndSettle();
      expect(page().auraBackground, Colors.black);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'localized appearance controls fit a narrow screen with scaled text and reset safely',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = SavedMusicStore(MemorySavedMusicStorage());
      await store.load();
      await store.setAppearance(
        const AppearancePreferences(
          mode: AppearanceMode.light,
          font: AppearanceFont.monospace,
          textScale: 1.3,
        ),
      );
      await tester.pumpWidget(
        AuraAppearanceApp(
          store: store,
          locale: const Locale('en'),
          home: const AppearanceSettingsScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Theme, font and colors'), findsOneWidget);
      expect(
        MediaQuery.textScalerOf(
          tester.element(find.byType(AppearanceSettingsScreen)),
        ).scale(10),
        closeTo(15.6, .001),
      );
      await tester.scrollUntilVisible(
        find.text('Restore default appearance'),
        180,
      );
      await tester.ensureVisible(find.text('Restore default appearance'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore default appearance'));
      await tester.pumpAndSettle();
      expect(store.data.appearance, const AppearancePreferences());
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}

class _Home extends StatefulWidget {
  const _Home({required this.onStart});
  final VoidCallback onStart;
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  @override
  void initState() {
    super.initState();
    widget.onStart();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()),
        ),
        child: const Text('Open'),
      ),
    ),
  );
}
