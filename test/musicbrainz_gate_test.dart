import 'dart:async';

import 'package:aura/musicbrainz_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'serializes concurrent requests and continues after a failure',
    () async {
      final gate = MusicBrainzGate();
      final blocker = Completer<void>();
      final order = <String>[];
      final first = gate.run(() async {
        order.add('first');
        await blocker.future;
        throw StateError('synthetic');
      }, Duration.zero);
      final second = gate.run(() async {
        order.add('second');
        return 2;
      }, Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(order, ['first']);
      final failure = expectLater(first, throwsStateError);
      blocker.complete();
      await failure;
      expect(await second, 2);
      expect(order, ['first', 'second']);
    },
  );
}
