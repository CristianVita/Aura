import 'dart:async';

import 'package:aura/main.dart';
import 'package:aura/playback_settings_controller.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

import 'support/memory_saved_music_storage.dart';

class _Player extends Fake implements AudioPlayer {
  @override
  Stream<PositionDiscontinuity> get positionDiscontinuityStream =>
      const Stream.empty();
  @override
  Stream<ProcessingState> get processingStateStream => const Stream.empty();
  @override
  Future<void> setSpeed(double speed) async {}
  @override
  Future<void> setVolume(double volume) async {}
}

void main() {
  testWidgets(
    'settings retain nested navigation, collapse sections and disable unavailable features on a narrow screen',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final saved = SavedMusicStore(MemorySavedMusicStorage());
      await saved.load();
      final controls = PlaybackSettingsController(
        player: _Player(),
        store: saved,
        onError: () {},
      );
      var sources = 0;
      await tester.pumpWidget(
        SavedMusicScope(
          store: saved,
          child: MaterialApp(
            home: Scaffold(
              body: SettingsScreen(
                sourceSummary: 'Local',
                controls: controls,
                onFilters: () {},
                filtersReady: true,
                onHistory: () {},
                onManageSources: () => sources++,
                onScan: () {},
                isScanning: false,
              ),
            ),
          ),
        ),
      );
      expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Android Auto'))
            .onTap,
        isNull,
      );
      await tester.tap(find.text('Interfață'));
      await tester.pumpAndSettle();
      expect(find.text('Setări de interfață'), findsOneWidget);
      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();
      expect(find.text('Liste media'), findsNothing);
      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();
      expect(find.text('Liste media'), findsOneWidget);
      await tester.ensureVisible(find.text('Ecran de redare'));
      await tester.tap(find.text('Ecran de redare'));
      await tester.pumpAndSettle();
      expect(find.text('Ratingul pieselor'), findsOneWidget);
      expect(find.text('Mari'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Redare'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Setări de ieșire'));
      await tester.pumpAndSettle();
      expect(find.text('Volumul playerului: 100%'), findsOneWidget);
      expect(find.text('Viteză: 1.00×'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Redare'));
      await tester.pumpAndSettle();
      expect(find.text('Viteză: 1.00×'), findsOneWidget);
      expect(find.text('Volumul playerului: 100%'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Surse media'));
      await tester.tap(find.text('Surse media'));
      expect(sources, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      controls.dispose();
      saved.dispose();
    },
  );
}
