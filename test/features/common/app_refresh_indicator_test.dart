import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/common/widgets/app_refresh_indicator.dart';

void main() {
  group('AppRefreshIndicator 防误触手势测试', () {
    testWidgets('轻度下拉（未触达 triggerDistance 物理阈值）松手不触发刷新', (tester) async {
      int refreshCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppRefreshIndicator(
              triggerDistance: 100.0,
              dragDamping: 0.70,
              onRefresh: () async {
                refreshCount++;
              },
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 50,
                itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
              ),
            ),
          ),
        ),
      );

      final listFinder = find.byType(ListView);
      expect(listFinder, findsOneWidget);

      // 模拟用户轻微下拉 50px（阻尼后 35px，远小于 100px 阈值）
      final gesture = await tester.startGesture(const Offset(100, 100));
      await gesture.moveBy(const Offset(0, 50));
      await tester.pump();

      // 用户松手，触发回弹/取消
      await gesture.up();
      await tester.pumpAndSettle();

      // 验证未误触刷新
      expect(refreshCount, equals(0));
    });

    testWidgets('大幅度主动下拉（超过 triggerDistance 物理阈值）松手正常触发刷新', (tester) async {
      int refreshCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppRefreshIndicator(
              triggerDistance: 100.0,
              dragDamping: 0.70,
              onRefresh: () async {
                refreshCount++;
              },
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: 50,
                itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
              ),
            ),
          ),
        ),
      );

      final listFinder = find.byType(ListView);
      expect(listFinder, findsOneWidget);

      // 模拟用户主动充分下拉 180px（阻尼 0.7 后为 126px > 100px 阈值）
      final gesture = await tester.startGesture(const Offset(100, 100));
      await gesture.moveBy(const Offset(0, 180));
      await tester.pump();

      // 松手
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // 验证刷新成功触发
      expect(refreshCount, equals(1));

      await tester.pumpAndSettle();
    });

    testWidgets('编程式 show() 正常触发 onRefresh', (tester) async {
      int refreshCount = 0;
      final key = GlobalKey<AppRefreshIndicatorState>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppRefreshIndicator(
              key: key,
              onRefresh: () async {
                refreshCount++;
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [Text('Hello')],
              ),
            ),
          ),
        ),
      );

      key.currentState?.show();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(refreshCount, equals(1));

      await tester.pumpAndSettle();
    });
  });
}
