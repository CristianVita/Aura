import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aura/track_artwork.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.example.symphonium_clone/audio_library');
  final imageBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );
  Widget artwork(String id) => MaterialApp(
    home: TrackArtwork(
      uri: 'content://media/external/audio/media/$id',
      cacheKey: id,
      size: 46,
    ),
  );

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('displays embedded artwork and shares requests between views', (
    tester,
  ) async {
    var requests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          requests++;
          expect(call.method, 'loadArtwork');
          return imageBytes;
        });
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            const TrackArtwork(
              uri: 'content://media/external/audio/media/cover',
              cacheKey: 'cover',
              size: 46,
            ),
            const TrackArtwork(
              uri: 'content://media/external/audio/media/cover',
              cacheKey: 'cover',
              size: 220,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNWidgets(2));
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the fallback when artwork is unavailable', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
    await tester.pumpWidget(artwork('missing'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
    'a late result from the previous track cannot replace the new cover',
    (tester) async {
      final pending = Completer<Uint8List?>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            return (call.arguments as Map)['uri'].toString().endsWith('old')
                ? pending.future
                : null;
          });
      await tester.pumpWidget(artwork('old'));
      await tester.pump();
      await tester.pumpWidget(artwork('new'));
      await tester.pumpAndSettle();
      pending.complete(imageBytes);
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    },
  );
}
