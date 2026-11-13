import 'package:aura/player_skip_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'skip controls dispatch their direction and disable at queue ends',
    (tester) async {
      final requests = <bool>[];
      Future<void> skip(bool next) async => requests.add(next);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(
              children: [
                PlayerSkipButton(next: false, enabled: true, onSkip: skip),
                PlayerSkipButton(next: true, enabled: true, onSkip: skip),
                PlayerSkipButton(
                  key: const ValueKey('disabled-next'),
                  next: true,
                  enabled: false,
                  onSkip: skip,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      await tester.tap(find.byIcon(Icons.skip_next_rounded).first);
      await tester.tap(find.byKey(const ValueKey('disabled-next')));
      expect(requests, [false, true]);
      expect(find.byTooltip('Piesa anterioară'), findsOneWidget);
      expect(find.byTooltip('Piesa următoare'), findsNWidgets(2));
    },
  );
}
