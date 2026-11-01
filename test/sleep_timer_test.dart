import 'package:aura/sleep_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late int pauses;
  late int errors;
  late bool playing;
  late SleepTimerController timer;
  setUp(() {
    now = DateTime(2026, 11, 2, 23, 59);
    pauses = 0;
    errors = 0;
    playing = true;
    timer = SleepTimerController(
      pause: () async {
        pauses++;
      },
      isPlaying: () => playing,
      onError: () => errors++,
      now: () => now,
      automaticTicks: false,
    );
  });
  tearDown(() => timer.dispose());
  test(
    'a delayed background tick expires by deadline across midnight only once',
    () {
      timer.start(const Duration(minutes: 5));
      now = now.add(const Duration(minutes: 8));
      timer.checkDeadline();
      timer.checkDeadline();
      expect(pauses, 1);
      expect(timer.active, isFalse);
    },
  );
  test('finish-track waits for a boundary and works with repeated tracks', () {
    timer.start(const Duration(minutes: 5), finishTrack: true);
    timer.onTrackEnded();
    expect(pauses, 0);
    now = now.add(const Duration(minutes: 5));
    timer.checkDeadline();
    expect(timer.waitingForTrack, isTrue);
    expect(pauses, 0);
    timer.onTrackEnded();
    expect(pauses, 1);
    expect(timer.active, isFalse);
  });
  test('a boundary can expire a timer before the next periodic tick', () {
    timer.start(const Duration(minutes: 5), finishTrack: true);
    now = now.add(const Duration(minutes: 6));
    timer.onTrackEnded();
    expect(pauses, 1);
  });
  test(
    'a paused player does not leave an expired finish-track timer pending',
    () {
      timer.start(const Duration(minutes: 5), finishTrack: true);
      playing = false;
      now = now.add(const Duration(minutes: 6));
      timer.checkDeadline();
      expect(timer.active, isFalse);
      expect(pauses, 1);
    },
  );
  test('cancel and replacement prevent the previous deadline from pausing', () {
    timer.start(const Duration(minutes: 5));
    timer.start(const Duration(minutes: 30));
    now = now.add(const Duration(minutes: 6));
    timer.checkDeadline();
    expect(pauses, 0);
    timer.cancel();
    now = now.add(const Duration(hours: 1));
    timer.checkDeadline();
    expect(pauses, 0);
    timer.stopAfterTrack();
    timer.onTrackEnded();
    expect(pauses, 1);
    expect(() => timer.start(Duration.zero), throwsArgumentError);
  });
  test(
    'failed pause reports an error without an unhandled async exception',
    () async {
      final failed = SleepTimerController(
        pause: () async => throw StateError('synthetic'),
        isPlaying: () => true,
        onError: () => errors++,
        automaticTicks: false,
      );
      failed.stopAfterTrack();
      failed.onTrackEnded();
      await Future<void>.delayed(Duration.zero);
      expect(errors, 1);
      expect(failed.active, isFalse);
      failed.dispose();
    },
  );
}
