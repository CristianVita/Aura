import 'package:aura/audio_track.dart';
import 'package:aura/playback_memory.dart';
import 'package:aura/playback_memory_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Storage implements PlaybackMemoryStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String json) async {
    value = json;
  }
}

const _tracks = [
  AudioTrack(
    id: '1',
    title: 'Song',
    artist: '',
    album: '',
    durationMs: 30000,
    uri: 'a',
    folder: 'Music/',
  ),
  AudioTrack(
    id: '2',
    title: 'Voice',
    artist: '',
    album: '',
    durationMs: 1000,
    uri: 'b',
    folder: 'WhatsApp Audio/',
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.symphonium_clone/audio_library');
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets(
    'filters preview counts and preserve queue/history while saving',
    (tester) async {
      final store = PlaybackMemoryStore(_Storage());
      await store.load();
      await store.record('a', DateTime(2026));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        LibraryFiltersScreen(store: store, tracks: _tracks),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('2 din 2 piese vor fi afișate.'), findsOneWidget);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      expect(find.text('1 din 2 piese vor fi afișate.'), findsOneWidget);
      await tester.tap(find.text('Salvează filtrele'));
      await tester.pumpAndSettle();
      expect(store.data.filters.hideMessaging, isTrue);
      expect(store.data.history.single.uri, 'a');
      expect(find.text('Open'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );

  testWidgets(
    'history plays available tracks in recency order and clears after confirmation',
    (tester) async {
      final store = PlaybackMemoryStore(_Storage());
      await store.load();
      await store.record('a', DateTime(2026));
      await store.record('missing', DateTime(2026));
      await store.record('b', DateTime(2026));
      List<AudioTrack>? queue;
      await tester.pumpWidget(
        MaterialApp(
          home: ListeningHistoryScreen(
            store: store,
            tracks: _tracks,
            onPlay: (tracks, index) async {
              queue = tracks;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Voice'));
      expect(queue?.map((t) => t.uri), ['b', 'a']);
      await tester.tap(find.byTooltip('Șterge istoricul'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anulează'));
      await tester.pumpAndSettle();
      expect(store.data.history.length, 3);
      await tester.tap(find.byTooltip('Șterge istoricul'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Șterge'));
      await tester.pumpAndSettle();
      expect(store.data.history, isEmpty);
      expect(find.text('Piesele ascultate vor apărea aici.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    },
  );
}
