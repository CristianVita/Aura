import 'dart:async';
import 'dart:typed_data';

import 'package:aura/appearance_app.dart';
import 'package:aura/artwork_cache_settings.dart';
import 'package:aura/artwork_memory_cache.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/memory_saved_music_storage.dart';

void main() {
  test(
    'shares requests, tracks size and evicts the least recently used entry',
    () async {
      var calls = 0;
      final cache = ArtworkMemoryCache(
        limit: 2,
        read: (uri) async {
          calls++;
          return Uint8List(uri.length);
        },
      );
      await cache.load('aaa', 'a');
      await cache.load('bb', 'b');
      expect(cache.entryCount, 2);
      expect(cache.byteCount, 5);
      await cache.load('aaa', 'a');
      expect(calls, 2);
      await cache.load('cccc', 'c');
      expect(cache.entryCount, 2);
      expect(cache.byteCount, 7);
      await cache.load('bb', 'b');
      expect(calls, 4);
      cache.dispose();
    },
  );
  test(
    'clearing an in-flight request does not add it back when it completes',
    () async {
      final pending = Completer<Uint8List?>();
      final cache = ArtworkMemoryCache(read: (_) => pending.future);
      final result = cache.load('synthetic', 'a');
      expect(cache.entryCount, 1);
      cache.clear();
      expect(cache.entryCount, 0);
      expect(cache.byteCount, 0);
      pending.complete(Uint8List(10));
      await result;
      await Future<void>.delayed(Duration.zero);
      expect(cache.entryCount, 0);
      expect(cache.byteCount, 0);
      cache.dispose();
    },
  );
  testWidgets('settings clear only temporary cache and show updated counts', (
    tester,
  ) async {
    final store = SavedMusicStore(MemorySavedMusicStorage());
    await store.load();
    final cache = ArtworkMemoryCache(read: (_) async => Uint8List(4));
    await cache.load('synthetic', 'a');
    await tester.pumpWidget(
      AuraAppearanceApp(
        store: store,
        locale: const Locale('en'),
        home: ArtworkCacheSettings(cache: cache),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(find.text('4 B'), findsOneWidget);
    expect(find.textContaining('Custom album covers'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('clear-artwork-memory')));
    await tester.pumpAndSettle();
    expect(cache.entryCount, 0);
    expect(cache.byteCount, 0);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('clear-artwork-memory')),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox());
    cache.dispose();
    store.dispose();
  });
}
