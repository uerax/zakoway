import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/core/utils/adaptive_page_route.dart';
import 'package:zakoway/core/utils/instant_page_route.dart';

void main() {
  group('AdaptivePageRoute tests', () {
    testWidgets('returns InstantPageRoute on desktop platforms', (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;

        late Route<void> route;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                route = AdaptivePageRoute.build<void>(
                  context,
                  builder: (_) => const SizedBox(),
                );
                return const SizedBox();
              },
            ),
          ),
        );

        expect(route, isA<InstantPageRoute<void>>());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('returns MaterialPageRoute on iOS', (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

        late Route<void> route;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                route = AdaptivePageRoute.build<void>(
                  context,
                  builder: (_) => const SizedBox(),
                );
                return const SizedBox();
              },
            ),
          ),
        );

        expect(route, isA<MaterialPageRoute<void>>());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('returns MaterialPageRoute on Android compact screen (<600)', (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view.physicalSize = const Size(400, 800);
        tester.view.devicePixelRatio = 1.0;

        late Route<void> route;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                route = AdaptivePageRoute.build<void>(
                  context,
                  builder: (_) => const SizedBox(),
                );
                return const SizedBox();
              },
            ),
          ),
        );

        expect(route, isA<MaterialPageRoute<void>>());
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });

    testWidgets('returns PageRouteBuilder on Android medium tablet (600 - 839)', (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view.physicalSize = const Size(720, 1080);
        tester.view.devicePixelRatio = 1.0;

        late Route<void> route;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                route = AdaptivePageRoute.build<void>(
                  context,
                  builder: (_) => const SizedBox(),
                );
                return const SizedBox();
              },
            ),
          ),
        );

        expect(route, isA<PageRouteBuilder<void>>());
        expect(route, isNot(isA<InstantPageRoute<void>>()));
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });

    testWidgets('returns InstantPageRoute on Android large screen (>=840)', (tester) async {
      try {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view.physicalSize = const Size(1024, 768);
        tester.view.devicePixelRatio = 1.0;

        late Route<void> route;

        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) {
                route = AdaptivePageRoute.build<void>(
                  context,
                  builder: (_) => const SizedBox(),
                );
                return const SizedBox();
              },
            ),
          ),
        );

        expect(route, isA<InstantPageRoute<void>>());
      } finally {
        debugDefaultTargetPlatformOverride = null;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    });
  });
}
