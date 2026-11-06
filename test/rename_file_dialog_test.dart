import 'package:aura/appearance_app.dart';
import 'package:aura/rename_file_dialog.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

void main() {
  testWidgets('rename dialog rejects invalid input and returns a valid stem', (
    tester,
  ) async {
    final store = SavedMusicStore(MemorySavedMusicStorage());
    await store.load();
    String? result;
    await tester.pumpWidget(
      AuraAppearanceApp(
        store: store,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showDialog<String>(
                  context: context,
                  builder: (_) =>
                      const RenameAudioDialog(filename: 'Original.MP3'),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('.MP3'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('rename-file-input')),
      '../bad',
    );
    await tester.tap(find.byKey(const ValueKey('rename-file-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(RenameAudioDialog), findsOneWidget);
    expect(result, isNull);
    await tester.enterText(
      find.byKey(const ValueKey('rename-file-input')),
      'New track',
    );
    await tester.tap(find.byKey(const ValueKey('rename-file-confirm')));
    await tester.pumpAndSettle();
    expect(result, 'New track');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
