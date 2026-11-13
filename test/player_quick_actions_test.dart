import 'package:aura/playback_queue.dart';
import 'package:aura/player_quick_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

class _QueuePlayer extends Fake implements AudioPlayer {
  final state = SequenceState(
    sequence: [AudioSource.uri(Uri.parse('file:///synthetic.mp3'))],
    currentIndex: 0,
    shuffleIndices: [0],
    shuffleModeEnabled: false,
    loopMode: LoopMode.off,
  );
  LoopMode? requestedLoop;
  @override
  SequenceState get sequenceState => state;
  @override
  Stream<SequenceState> get sequenceStateStream => const Stream.empty();
  @override
  LoopMode get loopMode => LoopMode.off;
  @override
  Future<void> setLoopMode(LoopMode mode) async => requestedLoop = mode;
}

void main() {
  testWidgets('icon actions expose their purpose and preserve callbacks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: PlayerQuickActions(
            sleepLabel: '10:30',
            sleepTooltip: 'Temporizator: 10:30',
            sleepActive: true,
            speedLabel: '1,25×',
            speedTooltip: 'Viteză: 1,25×',
            equalizerTooltip: 'Egalizator',
            settingsTooltip: 'Setări',
            onSleep: () => calls.add('sleep'),
            onSpeed: () => calls.add('speed'),
            onEqualizer: () => calls.add('equalizer'),
            onSettings: () => calls.add('settings'),
          ),
        ),
      ),
    );
    expect(find.text('10:30'), findsOneWidget);
    expect(find.text('1,25×'), findsOneWidget);
    expect(find.byTooltip('Temporizator: 10:30'), findsOneWidget);
    expect(find.byTooltip('Viteză: 1,25×'), findsOneWidget);
    expect(find.byTooltip('Egalizator'), findsOneWidget);
    expect(find.byTooltip('Setări'), findsOneWidget);
    for (final name in ['sleep', 'speed', 'equalizer', 'settings']) {
      await tester.tap(find.byKey(ValueKey('player-$name')));
    }
    expect(calls, ['sleep', 'speed', 'equalizer', 'settings']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue button shows its count and repeat keeps its action', (
    tester,
  ) async {
    final player = _QueuePlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PlaybackOptions(player: player)),
      ),
    );
    expect(find.byTooltip('Coada · 1'), findsOneWidget);
    expect(find.byIcon(Icons.queue_music_rounded), findsOneWidget);
    await tester.tap(find.byTooltip('Repeat oprit'));
    await tester.pump();
    expect(player.requestedLoop, LoopMode.all);
    expect(tester.takeException(), isNull);
  });
}
