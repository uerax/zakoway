import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/core/theme/m3_expressive_theme.dart';
import 'package:zakoway/core/utils/smooth_page_transitions_builder.dart';

void main() {
  group('SmoothCupertinoPageTransitionsBuilder tests', () {
    test('default durations are tuned for 120Hz high refresh rate', () {
      const builder = SmoothCupertinoPageTransitionsBuilder();

      expect(builder.transitionDuration, const Duration(milliseconds: 280));
      expect(builder.reverseTransitionDuration, const Duration(milliseconds: 240));
      expect(builder.delegatedTransition, isNotNull);
    });

    testWidgets('buildTransitions wraps child with RepaintBoundary for GPU layer caching during navigation', (tester) async {
      final theme = ThemeData(
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: SmoothCupertinoPageTransitionsBuilder(),
          },
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          body: Text('Target Page Content'),
                        ),
                      ),
                    );
                  },
                  child: const Text('Go to Detail'),
                );
              },
            ),
          ),
        ),
      );

      // Trigger navigation
      await tester.tap(find.text('Go to Detail'));
      // Pump halfway through transition (140ms)
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));

      // Verify that RepaintBoundary wraps the target content during animation
      expect(find.text('Target Page Content'), findsOneWidget);
      final repaintBoundaries = tester.widgetList<RepaintBoundary>(
        find.ancestor(
          of: find.text('Target Page Content'),
          matching: find.byType(RepaintBoundary),
        ),
      );
      expect(repaintBoundaries, isNotEmpty);

      // Complete transition
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(find.text('Target Page Content'), findsOneWidget);
    });

    testWidgets('M3ExpressiveTheme configures SmoothCupertinoPageTransitionsBuilder across platforms', (tester) async {
      final theme = M3ExpressiveTheme.build(
        primaryColor: const Color(0xFF6750A4),
        brightness: Brightness.light,
        currentFont: null,
        fontFallback: const ['Microsoft YaHei UI', 'Segoe UI'],
      );

      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        final transitionBuilder = theme.pageTransitionsTheme.builders[platform];
        expect(
          transitionBuilder,
          isA<SmoothCupertinoPageTransitionsBuilder>(),
          reason: 'Platform $platform should use SmoothCupertinoPageTransitionsBuilder',
        );
        expect(
          transitionBuilder?.transitionDuration,
          const Duration(milliseconds: 280),
        );
      }
    });
  });
}
