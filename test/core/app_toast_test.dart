import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/core/utils/app_toast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestHost({required Widget child}) {
    return MaterialApp(
      scaffoldMessengerKey: AppToast.scaffoldMessengerKey,
      home: Scaffold(body: child),
    );
  }

  group('AppToast unit and widget tests', () {
    testWidgets('AppToast.success displays floating capsule with check icon', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppToast.success('操作成功完成', context: ctx),
              child: const Text('Show Success'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Success'));
      await tester.pump(); // Start animation
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('操作成功完成'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    testWidgets('AppToast.error displays floating capsule with error icon', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppToast.error('发生网络错误', context: ctx),
              child: const Text('Show Error'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Error'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('发生网络错误'), findsOneWidget);
      expect(find.byIcon(Icons.error_rounded), findsOneWidget);
    });

    testWidgets('AppToast.warning displays warning amber icon', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppToast.warning('请检查输入项', context: ctx),
              child: const Text('Show Warning'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Warning'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('请检查输入项'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('AppToast.info works without context using root scaffoldMessengerKey', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: ElevatedButton(
            onPressed: () => AppToast.info('常规信息提示'),
            child: const Text('Show Info'),
          ),
        ),
      );

      await tester.tap(find.text('Show Info'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('常规信息提示'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    });

    testWidgets('Consecutive AppToast calls clear prior snackbar instantly (no queue delay)', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (ctx) => Column(
              children: [
                ElevatedButton(
                  onPressed: () => AppToast.info('第一条旧消息', context: ctx),
                  child: const Text('First'),
                ),
                ElevatedButton(
                  onPressed: () => AppToast.success('第二条新消息', context: ctx),
                  child: const Text('Second'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('First'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('第一条旧消息'), findsOneWidget);

      // Trigger second immediately
      await tester.tap(find.text('Second'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Old is cleared, new is visible
      expect(find.text('第一条旧消息'), findsNothing);
      expect(find.text('第二条新消息'), findsOneWidget);
    });

    testWidgets('Tapping toast capsule dismisses it immediately with haptic feedback', (tester) async {
      await tester.pumpWidget(
        buildTestHost(
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => AppToast.info('点击即可关闭我', context: ctx),
              child: const Text('Show Dismissible'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Dismissible'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('点击即可关闭我'), findsOneWidget);

      // Tap on the toast capsule itself
      await tester.tap(find.text('点击即可关闭我'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Toast is dismissed
      expect(find.text('点击即可关闭我'), findsNothing);
    });
  });
}
