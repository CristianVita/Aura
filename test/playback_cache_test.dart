import 'dart:io';

import 'package:aura/playback_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('disabled by default; quota evicts oldest completed cache without touching unrelated files', () async {
    final dir = await Directory.systemTemp.createTemp('aura-cache-test-');
    try {
      final cache = PlaybackCache(directory: () async => dir, maxBytes: 6);
      await cache.load();
      expect(cache.enabled, false);
      expect(await cache.begin('one', 3), isNull);
      await cache.setEnabled(true);
      final unrelated = File('${dir.path}/manual-download');
      await unrelated.writeAsBytes([9]);
      final one = (await cache.begin('one', 3))!;
      await one.file.writeAsBytes([1, 2, 3]);
      await one.finish('audio/mpeg');
      final first = (await cache.acquire('one'))!;
      expect(await first.file.readAsBytes(), [1, 2, 3]);
      await first.release();
      await first.file.setLastModified(DateTime(2020));
      final two = (await cache.begin('two', 3))!;
      await two.file.writeAsBytes([4, 5, 6]);
      await two.finish('audio/mpeg');
      final three = (await cache.begin('three', 3))!;
      await three.file.writeAsBytes([7, 8, 9]);
      await three.finish('audio/mpeg');
      expect(await cache.acquire('one'), isNull);
      final cachedTwo = (await cache.acquire('two'))!;
      await cachedTwo.release();
      expect(await unrelated.readAsBytes(), [9]);
      await cache.close();
      final persisted = PlaybackCache(directory: () async => dir, maxBytes: 6);
      await persisted.load();
      expect(persisted.enabled, true);
      await persisted.setEnabled(false);
      expect(persisted.enabled, false);
      await persisted.close();
      final restored = PlaybackCache(directory: () async => dir, maxBytes: 6);
      await restored.load();
      expect(restored.enabled, false);
      await restored.close();
      restored.dispose();
      persisted.dispose();
      await cache.close();
      cache.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });
  test(
    'reservations, pins, aborted and incomplete writes preserve the quota',
    () async {
      final dir = await Directory.systemTemp.createTemp('aura-cache-test-');
      try {
        final cache = PlaybackCache(directory: () async => dir, maxBytes: 4);
        await cache.setEnabled(true);
        final one = (await cache.begin('one', 4))!;
        expect(await cache.begin('two', 1), isNull);
        await one.file.writeAsBytes([1, 2, 3]);
        await expectLater(one.finish('audio/mpeg'), throwsFormatException);
        expect(await cache.acquire('one'), isNull);
        final two = (await cache.begin('two', 4))!;
        await two.file.writeAsBytes([1, 2, 3, 4]);
        await two.finish('audio/mpeg');
        final pinned = (await cache.acquire('two'))!;
        expect(await cache.begin('three', 4), isNull);
        await pinned.release();
        final three = (await cache.begin('three', 4))!;
        await three.file.writeAsBytes([1]);
        await three.abort();
        expect(await three.file.exists(), false);
        await cache.close();
        cache.dispose();
      } finally {
        await dir.delete(recursive: true);
      }
    },
  );
  test('corrupt cached data is not used as audio', () async {
    final dir = await Directory.systemTemp.createTemp('aura-cache-test-');
    try {
      final cache = PlaybackCache(directory: () async => dir, maxBytes: 10);
      await cache.setEnabled(true);
      final write = (await cache.begin('one', 3))!;
      await write.file.writeAsBytes([1, 2, 3]);
      await write.finish('audio/mpeg');
      final read = (await cache.acquire('one'))!;
      await read.file.writeAsBytes([3, 2, 1]);
      await read.release();
      expect(await cache.acquire('one'), isNull);
      expect(await read.file.exists(), false);
      await cache.close();
      cache.dispose();
    } finally {
      await dir.delete(recursive: true);
    }
  });
  if (Platform.isWindows) {
    test('a second instance cannot modify an in-use cache', () async {
      final dir = await Directory.systemTemp.createTemp('aura-cache-lock-');
      final first = PlaybackCache(directory: () async => dir, maxBytes: 10);
      final second = PlaybackCache(directory: () async => dir, maxBytes: 10);
      try {
        await first.setEnabled(true);
        final write = (await first.begin('one', 3))!;
        await write.file.writeAsBytes([1, 2, 3]);
        await second.load();
        expect(second.available, false);
        await expectLater(second.setEnabled(true), throwsStateError);
        expect(await write.file.exists(), true);
        await write.finish('audio/mpeg');
        final read = (await first.acquire('one'))!;
        await read.release();
      } finally {
        await second.close();
        second.dispose();
        await first.close();
        first.dispose();
        await dir.delete(recursive: true);
      }
    });
  }
  test(
    'clear removes only unused cache files and preserves active entries',
    () async {
      final dir = await Directory.systemTemp.createTemp('aura-cache-clear-');
      final cache = PlaybackCache(directory: () async => dir, maxBytes: 20);
      try {
        await cache.setEnabled(true);
        for (final uri in ['active', 'unused']) {
          final write = (await cache.begin(uri, 3))!;
          await write.file.writeAsBytes([1, 2, 3]);
          await write.finish('audio/mpeg');
        }
        final other = File('${dir.path}/manual-download');
        await other.writeAsBytes([9]);
        final pinned = (await cache.acquire('active'))!;
        expect(await cache.clear(), 1);
        expect(await cache.acquire('unused'), isNull);
        expect(await pinned.file.exists(), true);
        expect(await other.readAsBytes(), [9]);
        await pinned.release();
        expect(await cache.clear(), 0);
        expect(await cache.acquire('active'), isNull);
      } finally {
        await cache.close();
        cache.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
