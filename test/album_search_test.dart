import 'package:aura/appearance_app.dart';
import 'package:aura/audio_track.dart';
import 'package:aura/library_groups.dart';
import 'package:aura/library_preferences.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

AudioTrack song(String album, String artist) => AudioTrack(
  id: album,
  title: 'Song',
  artist: artist,
  album: album,
  durationMs: 1000,
  uri: 'file:///test/${Uri.encodeComponent(album)}.mp3',
);

void main() {
  testWidgets('album search filters instantly, opens results, and clears', (
    tester,
  ) async {
    final saved = SavedMusicStore(MemorySavedMusicStorage());
    await saved.load();
    final controller = TextEditingController();
    String? opened;
    final groups = {
      'WhatsApp Audio': [song('WhatsApp Audio', 'Local')],
      'Other album': [song('Other album', 'Example Artist')],
    };
    await tester.pumpWidget(
      AuraAppearanceApp(
        store: saved,
        locale: const Locale('en'),
        home: Scaffold(
          body: AlbumSearchGroups(
            groups: groups,
            preferences: const GroupPagePreferences(),
            controller: controller,
            onOpen: (name) => opened = name,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('WhatsApp Audio'), findsOneWidget);
    expect(find.text('Other album'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('album-search')),
      'whATSapp',
    );
    await tester.pumpAndSettle();
    expect(find.text('WhatsApp Audio'), findsOneWidget);
    expect(find.text('Other album'), findsNothing);
    await tester.tap(find.text('WhatsApp Audio'));
    expect(opened, 'WhatsApp Audio');
    await tester.enterText(
      find.byKey(const ValueKey('album-search')),
      'example artist',
    );
    await tester.pumpAndSettle();
    expect(find.text('Other album'), findsOneWidget);
    expect(find.text('WhatsApp Audio'), findsNothing);
    await tester.enterText(
      find.byKey(const ValueKey('album-search')),
      'not present',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No albums found. Try a different search.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('clear-album-search')));
    await tester.pumpAndSettle();
    expect(controller.text, isEmpty);
    expect(find.text('WhatsApp Audio'), findsOneWidget);
    expect(find.text('Other album'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    saved.dispose();
  });

  testWidgets('search remains usable in a narrow RTL grid', (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final saved = SavedMusicStore(MemorySavedMusicStorage());
    await saved.load();
    final controller = TextEditingController(text: 'album');
    await tester.pumpWidget(
      AuraAppearanceApp(
        store: saved,
        locale: const Locale('ar'),
        home: Scaffold(
          body: AlbumSearchGroups(
            groups: {
              'Album': [song('Album', 'Artist')],
            },
            preferences: const GroupPagePreferences(layout: GroupLayout.grid),
            controller: controller,
            onOpen: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Album'), findsOneWidget);
    expect(find.byKey(const ValueKey('clear-album-search')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    saved.dispose();
  });
}
