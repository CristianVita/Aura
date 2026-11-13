import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:aura/audio_track.dart';
import 'package:aura/appearance_app.dart';
import 'package:aura/background_downloads_ui.dart';
import 'package:aura/saved_music.dart';
import 'package:flutter/material.dart';

import 'support/memory_saved_music_storage.dart';

import 'package:aura/background_downloads.dart';
import 'package:aura/download_network_policy.dart';
import 'package:aura/offline_storage.dart';
import 'package:aura/offline_store.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_test/flutter_test.dart';

AudioTrack track(String id) => AudioTrack(
  id: id,
  title: id,
  artist: 'Synthetic',
  album: 'Synthetic',
  durationMs: 1,
  uri: 'aura://navidrome/source/$id',
);

class MemoryJob implements DownloadJobPersistence {
  String? content;
  bool failWrites = false;
  Completer<void>? writeWait;
  @override
  Future<String?> read() async => content;
  @override
  Future<void> write(String value) async {
    if (failWrites) throw StateError('synthetic disk failure');
    if (writeWait != null) await writeWait!.future;
    content = value;
  }

  @override
  Future<void> clear() async {
    content = null;
  }
}

class FakeForeground implements DownloadForeground {
  bool fail = false;
  Completer<void>? startWait;
  int starts = 0, stops = 0;
  void Function()? cancel;
  @override
  void onCancel(void Function()? value) {
    cancel = value;
  }

  @override
  Future<void> start({
    required String title,
    required String progress,
    required String stop,
    required int done,
    required int total,
  }) async {
    starts++;
    if (fail) throw StateError('denied');
    if (startWait != null) await startWait!.future;
  }

  @override
  Future<void> update(int done, int total) async {}
  @override
  Future<void> stop() async {
    stops++;
  }
}

class FakeStore extends OfflineStorage {
  final seen = <String>[];
  Completer<void>? wait;
  String? networkError, failure;
  @override
  bool busy(String uri) => false;
  @override
  Future<bool> hasRecord(String uri) async => false;
  @override
  Future<Uri?> localUri(String uri) async => null;
  @override
  Future<List<Map<String, Object?>>> cachedTracks() async => [];
  @override
  Future<void> remove(String uri) async {
    throw StateError('unexpected remove');
  }

  @override
  Future<void> download(AudioTrack t) async {
    seen.add(t.id);
    if (wait != null) await wait!.future;
    if (t.id == networkError) throw const DownloadNetworkException();
    if (t.id == failure) throw StateError('synthetic failure');
  }
}

Future<void> start(BackgroundDownloads job) =>
    job.resume(title: 'Downloads', progress: 'Progress', stop: 'Stop');
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'permission prompt is not cancelled by the service startup timeout',
    (tester) async {
      final permission = Completer<bool>();
      var starts = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidDownloadForeground.channel, (
            call,
          ) async {
            if (call.method == 'permission') return permission.future;
            if (call.method == 'start') {
              starts++;
              return null;
            }
            return null;
          });
      var finished = false;
      final operation = AndroidDownloadForeground()
          .start(
            title: 'Downloads',
            progress: 'Progress',
            stop: 'Stop',
            done: 0,
            total: 1,
          )
          .then((_) => finished = true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 20));
      expect(finished, false);
      expect(starts, 0);
      permission.complete(true);
      await tester.pump();
      await tester.pump();
      await operation;
      expect(finished, true);
      expect(starts, 1);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AndroidDownloadForeground.channel, null);
    },
  );

  test('stop after current track preserves progress and a new instance resumes manually', () async {
    final persistence = MemoryJob(),
        foreground = FakeForeground(),
        store = FakeStore()..wait = Completer<void>();
    final job = BackgroundDownloads(
      store: store,
      persistence: persistence,
      foreground: foreground,
    );
    await job.create([track('one'), track('one'), track('two')]);
    await start(job);
    expect(store.seen, ['one']);
    foreground.cancel!();
    store.wait!.complete();
    await job.waitForCompletion();
    expect(job.done, 1);
    expect(job.running, false);
    expect(foreground.stops, 1);
    final restoredStore = FakeStore();
    final restored = BackgroundDownloads(
      store: restoredStore,
      persistence: persistence,
      foreground: FakeForeground(),
    );
    await restored.load();
    expect(restored.done, 1);
    expect(restored.running, false);
    await start(restored);
    await restored.waitForCompletion();
    expect(restoredStore.seen, ['two']);
    expect(restored.complete, true);
    job.dispose();
    restored.dispose();
    store.dispose();
    restoredStore.dispose();
  });
  test('blocked network keeps the same track and no job runs if service start fails', () async {
    final persistence = MemoryJob(),
        foreground = FakeForeground()..fail = true,
        store = FakeStore()..networkError = 'one';
    final job = BackgroundDownloads(
      store: store,
      persistence: persistence,
      foreground: foreground,
    );
    await job.create([track('one')]);
    await expectLater(start(job), throwsStateError);
    expect(store.seen, isEmpty);
    expect(job.running, false);
    foreground.fail = false;
    await start(job);
    await job.waitForCompletion();
    expect(job.done, 0);
    expect(job.networkBlocked, true);
    store.networkError = null;
    await start(job);
    await job.waitForCompletion();
    expect(job.complete, true);
    job.dispose();
    store.dispose();
  });
  test(
    'failed track counted, and paused jobs cannot be silently replaced',
    () async {
      final persistence = MemoryJob(), store = FakeStore()..failure = 'one';
      final job = BackgroundDownloads(
        store: store,
        persistence: persistence,
        foreground: FakeForeground(),
      );
      await job.create([track('one'), track('two')]);
      await expectLater(job.create([track('three')]), throwsStateError);
      await start(job);
      await job.waitForCompletion();
      expect(job.done, 2);
      expect(job.failed, 1);
      await job.discard();
      expect(persistence.content, isNull);
      job.dispose();
      store.dispose();
    },
  );
  testWidgets('progress screen can stop and resume a saved job', (
    tester,
  ) async {
    final memory = MemoryJob(),
        foreground = FakeForeground(),
        store = FakeStore()..wait = Completer<void>();
    final job = BackgroundDownloads(
      store: store,
      persistence: memory,
      foreground: foreground,
    );
    final saved = SavedMusicStore(MemorySavedMusicStorage());
    await saved.load();
    await job.create([track('one'), track('two')]);
    await tester.pumpWidget(
      AuraAppearanceApp(
        store: saved,
        locale: const Locale('en'),
        home: BackgroundDownloadsScreen(job: job),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('background-resume')));
    await tester.pump();
    expect(job.running, true);
    expect(find.text('one'), findsOneWidget);
    expect(find.textContaining('Downloading'), findsWidgets);
    expect(find.textContaining('Waiting'), findsWidgets);
    expect(store.seen, ['one']);
    await tester.tap(find.byKey(const ValueKey('background-stop')));
    await tester.pump();
    expect(job.stopping, true);
    store.wait!.complete();
    await tester.pumpAndSettle();
    expect(job.done, 1);
    expect(job.running, false);
    expect(find.textContaining('Completed'), findsWidgets);
    expect(find.byKey(const ValueKey('background-resume')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    job.dispose();
    store.dispose();
    saved.dispose();
  });
  test(
    'failed persistence cannot start a transfer or overwrite a saved job',
    () async {
      final storage = MemoryJob()..failWrites = true;
      final store = FakeStore();
      final foreground = FakeForeground();
      final job = BackgroundDownloads(
        store: store,
        persistence: storage,
        foreground: foreground,
      );
      await expectLater(job.create([track('one')]), throwsStateError);
      expect(job.hasJob, false);
      expect(foreground.starts, 0);
      expect(store.seen, isEmpty);
      job.dispose();
      store.dispose();
    },
  );
  test('simultaneous starts are rejected and cancellation during startup is respected', () async {
    final storage = MemoryJob();
    final store = FakeStore();
    final foreground = FakeForeground()..startWait = Completer<void>();
    final job = BackgroundDownloads(
      store: store,
      persistence: storage,
      foreground: foreground,
    );
    await job.create([track('one')]);
    final first = start(job);
    await Future<void>.delayed(Duration.zero);
    await expectLater(start(job), throwsStateError);
    foreground.cancel!();
    foreground.startWait!.complete();
    await first;
    await job.waitForCompletion();
    expect(store.seen, isEmpty);
    expect(job.done, 0);
    expect(foreground.starts, 1);
    job.dispose();
    store.dispose();
  });
  test(
    'durable job has no credentials and restores only after explicit resume',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'aura-background-test-',
      );
      final store = FakeStore()..wait = Completer<void>();
      final first = BackgroundDownloads(
        store: store,
        persistence: DeviceDownloadJobPersistence(directory: () async => dir),
        foreground: FakeForeground(),
      );
      try {
        await first.create([track('one'), track('two')]);
        await start(first);
        first.requestStop();
        store.wait!.complete();
        await first.waitForCompletion();
        final file = File(p.join(dir.path, 'background_download_job.json'));
        final text = await file.readAsString();
        expect(text, isNot(contains('password')));
        expect(text, isNot(contains('https://')));
        final resumedStore = FakeStore();
        final restored = BackgroundDownloads(
          store: resumedStore,
          persistence: DeviceDownloadJobPersistence(directory: () async => dir),
          foreground: FakeForeground(),
        );
        await restored.load();
        expect(restored.done, 1);
        expect(restored.running, false);
        expect(resumedStore.seen, isEmpty);
        await start(restored);
        await restored.waitForCompletion();
        expect(resumedStore.seen, ['two']);
        restored.dispose();
        resumedStore.dispose();
      } finally {
        first.dispose();
        store.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test('offline files and progress survive a network interruption and manual resume', () async {
    final dir = await Directory.systemTemp.createTemp('aura-background-e2e-');
    var blocked = true;
    final store = OfflineStore(
      directory: () async => Directory(p.join(dir.path, 'offline')),
      open: (uri) async {
        if (uri.pathSegments.last == 'two' && blocked) {
          throw const DownloadNetworkException();
        }
        return (
          response: http.StreamedResponse(
            Stream.value([1, 2, 3]),
            200,
            headers: {'content-type': 'audio/mpeg'},
            contentLength: 3,
          ),
          close: () {},
        );
      },
    );
    final persistence = DeviceDownloadJobPersistence(
      directory: () async => dir,
    );
    final first = BackgroundDownloads(
      store: store,
      persistence: persistence,
      foreground: FakeForeground(),
    );
    try {
      await first.create([track('one'), track('two')]);
      await start(first);
      await first.waitForCompletion();
      expect(first.done, 1);
      expect(first.networkBlocked, true);
      expect(await store.localUri(track('one').uri), isNotNull);
      expect(await store.localUri(track('two').uri), isNull);
      blocked = false;
      final second = BackgroundDownloads(
        store: store,
        persistence: persistence,
        foreground: FakeForeground(),
      );
      await second.load();
      expect(second.done, 1);
      expect(second.running, false);
      await start(second);
      await second.waitForCompletion();
      expect(second.complete, true);
      expect(await store.localUri(track('two').uri), isNotNull);
      second.dispose();
    } finally {
      first.dispose();
      store.dispose();
      await dir.delete(recursive: true);
    }
  });
  test(
    'a job cannot start or be discarded before its initial state is saved',
    () async {
      final storage = MemoryJob()..writeWait = Completer<void>();
      final store = FakeStore();
      final foreground = FakeForeground();
      final job = BackgroundDownloads(
        store: store,
        persistence: storage,
        foreground: foreground,
      );
      final creating = job.create([track('one')]);
      await Future<void>.delayed(Duration.zero);
      expect(job.saving, true);
      await expectLater(start(job), throwsStateError);
      await expectLater(job.discard(), throwsStateError);
      expect(foreground.starts, 0);
      expect(store.seen, isEmpty);
      storage.writeWait!.complete();
      await creating;
      expect(job.saving, false);
      expect(storage.content, isNotNull);
      job.dispose();
      store.dispose();
    },
  );
  test(
    'legacy mixed outcomes stay unknown and new results survive restart',
    () async {
      final persistence = MemoryJob();
      final oldStore = FakeStore()
        ..failure = 'one'
        ..wait = Completer<void>();
      final oldJob = BackgroundDownloads(
        store: oldStore,
        persistence: persistence,
        foreground: FakeForeground(),
      );
      await oldJob.create([track('one'), track('two')]);
      await start(oldJob);
      oldJob.requestStop();
      oldStore.wait!.complete();
      await oldJob.waitForCompletion();
      final legacy = jsonDecode(persistence.content!) as Map<String, dynamic>;
      legacy.remove('outcomes');
      persistence.content = jsonEncode(legacy);
      final newStore = FakeStore();
      final restored = BackgroundDownloads(
        store: newStore,
        persistence: persistence,
        foreground: FakeForeground(),
      );
      await restored.load();
      expect(restored.outcomes, [0]);
      expect(restored.failed, 1);
      expect(restored.running, false);
      await start(restored);
      await restored.waitForCompletion();
      expect(restored.outcomes, [0, 1]);
      expect(restored.failed, 1);
      final again = BackgroundDownloads(
        store: newStore,
        persistence: persistence,
        foreground: FakeForeground(),
      );
      await again.load();
      expect(again.outcomes, [0, 1]);
      expect(again.failed, 1);
      oldJob.dispose();
      restored.dispose();
      again.dispose();
      oldStore.dispose();
      newStore.dispose();
    },
  );

  test('individual outcomes identify failed tracks after reload', () async {
    final persistence = MemoryJob();
    final store = FakeStore()..failure = 'one';
    final job = BackgroundDownloads(
      store: store,
      persistence: persistence,
      foreground: FakeForeground(),
    );
    await job.create([track('one'), track('two')]);
    await start(job);
    await job.waitForCompletion();
    expect(job.outcomes, [2, 1]);
    final restored = BackgroundDownloads(
      store: store,
      persistence: persistence,
      foreground: FakeForeground(),
    );
    await restored.load();
    expect(restored.outcomes, [2, 1]);
    expect(restored.failed, 1);
    job.dispose();
    restored.dispose();
    store.dispose();
  });

  test('manual retry prepares only failed tracks and restores them without auto-start', () async {
    final persistence = MemoryJob();
    final store = FakeStore()..failure = 'one';
    final foreground = FakeForeground();
    final job = BackgroundDownloads(
      store: store,
      persistence: persistence,
      foreground: foreground,
    );
    await job.create([track('one'), track('two')]);
    await start(job);
    await job.waitForCompletion();
    expect(job.outcomes, [2, 1]);
    await job.retryFailures();
    expect(job.tracks.map((t) => t.id), ['one']);
    expect(job.done, 0);
    expect(job.running, false);
    expect(foreground.starts, 1);
    final restored = BackgroundDownloads(
      store: store,
      persistence: persistence,
      foreground: FakeForeground(),
    );
    await restored.load();
    expect(restored.tracks.map((t) => t.id), ['one']);
    expect(restored.running, false);
    store.failure = null;
    await start(restored);
    await restored.waitForCompletion();
    expect(restored.outcomes, [1]);
    expect(store.seen, ['one', 'two', 'one']);
    job.dispose();
    restored.dispose();
    store.dispose();
  });

  test('retry preserves completed job when persistence fails and rejects an empty retry', () async {
    final persistence = MemoryJob();
    final store = FakeStore()..failure = 'one';
    final job = BackgroundDownloads(
      store: store,
      persistence: persistence,
      foreground: FakeForeground(),
    );
    await job.create([track('one'), track('two')]);
    await start(job);
    await job.waitForCompletion();
    final saved = persistence.content;
    persistence.failWrites = true;
    await expectLater(job.retryFailures(), throwsStateError);
    expect(job.tracks.map((t) => t.id), ['one', 'two']);
    expect(job.outcomes, [2, 1]);
    expect(job.done, 2);
    expect(persistence.content, saved);
    persistence.failWrites = false;
    await job.retryFailures();
    store.failure = null;
    await start(job);
    await job.waitForCompletion();
    await expectLater(job.retryFailures(), throwsStateError);
    job.dispose();
    store.dispose();
  });

  test('retry includes unknown legacy results because the failures cannot be identified', () async {
    final persistence = MemoryJob();
    final store = FakeStore()..failure = 'one';
    final job = BackgroundDownloads(
      store: store,
      persistence: persistence,
      foreground: FakeForeground(),
    );
    await job.create([track('one'), track('two')]);
    await start(job);
    await job.waitForCompletion();
    final legacy = jsonDecode(persistence.content!) as Map<String, dynamic>;
    legacy.remove('outcomes');
    persistence.content = jsonEncode(legacy);
    final restored = BackgroundDownloads(
      store: store,
      persistence: persistence,
      foreground: FakeForeground(),
    );
    await restored.load();
    expect(restored.outcomes, [0, 0]);
    await restored.retryFailures();
    expect(restored.tracks.map((t) => t.id), ['one', 'two']);
    expect(restored.running, false);
    job.dispose();
    restored.dispose();
    store.dispose();
  });

  testWidgets('retry button explicitly restarts only failed downloads', (
    tester,
  ) async {
    final persistence = MemoryJob();
    final store = FakeStore()..failure = 'one';
    final foreground = FakeForeground();
    final job = BackgroundDownloads(
      store: store,
      persistence: persistence,
      foreground: foreground,
    );
    final saved = SavedMusicStore(MemorySavedMusicStorage());
    await saved.load();
    await job.create([track('one'), track('two')]);
    await start(job);
    await job.waitForCompletion();
    store.failure = null;
    await tester.pumpWidget(
      AuraAppearanceApp(
        store: saved,
        locale: const Locale('en'),
        home: BackgroundDownloadsScreen(job: job),
      ),
    );
    await tester.pumpAndSettle();
    final retry = find.byKey(const ValueKey('background-retry-failures'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(store.seen, ['one', 'two', 'one']);
    expect(job.failed, 0);
    expect(job.complete, true);
    await tester.pumpWidget(const SizedBox());
    job.dispose();
    store.dispose();
    saved.dispose();
  });
}
