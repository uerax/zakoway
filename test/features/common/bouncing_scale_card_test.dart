import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/common/widgets/bouncing_scale_card.dart';

void main() {
  group('BouncingScaleCard micro-interaction & delay tests', () {
    testWidgets('Triggers onTap after tapDelayMs delay by default', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BouncingScaleCard(
                onTap: () => tapCount++,
                child: const SizedBox(
                  width: 100,
                  height: 100,
                  child: Text('Card'),
                ),
              ),
            ),
          ),
        ),
      );

      final cardFinder = find.text('Card');
      expect(cardFinder, findsOneWidget);

      final gesture = await tester.startGesture(tester.getCenter(cardFinder));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();

      // At 0ms after up, onTap should NOT have been invoked yet (waiting for micro-delay window)
      await tester.pump();
      expect(tapCount, 0);

      // Advance through part of the delay (e.g. 30ms)
      await tester.pump(const Duration(milliseconds: 30));
      expect(tapCount, 0);

      // Advance through remaining minHold + tapDelay (45ms + 70ms = 115ms total)
      await tester.pump(const Duration(milliseconds: 90));
      expect(tapCount, 1);
    });

    testWidgets('Zero tapDelayMs triggers onTap immediately on tapUp', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BouncingScaleCard(
                tapDelayMs: 0,
                minHoldMs: 0,
                onTap: () => tapCount++,
                child: const SizedBox(
                  width: 100,
                  height: 100,
                  child: Text('ZeroDelayCard'),
                ),
              ),
            ),
          ),
        ),
      );

      final cardFinder = find.text('ZeroDelayCard');
      final gesture = await tester.startGesture(tester.getCenter(cardFinder));
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();

      // With tapDelayMs: 0 and minHoldMs: 0, onTap triggers on tapUp frame
      await tester.pump();
      expect(tapCount, 1);
    });

    testWidgets('Gesture cancellation during press does not trigger onTap', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: BouncingScaleCard(
                onTap: () => tapCount++,
                child: const SizedBox(
                  width: 100,
                  height: 100,
                  child: Text('CancelCard'),
                ),
              ),
            ),
          ),
        ),
      );

      final cardFinder = find.text('CancelCard');
      final gesture = await tester.startGesture(tester.getCenter(cardFinder));
      await tester.pump(const Duration(milliseconds: 30));
      await gesture.cancel();

      // Advance past any potential hold & delay
      await tester.pump(const Duration(milliseconds: 200));
      expect(tapCount, 0);
    });
  });
}
