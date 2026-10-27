import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/common/widgets/directional_tab_bar_view.dart';

void main() {
  group('DirectionalTabBarView 手势守卫测试', () {
    testWidgets('在每个 child 内部重置 touchSlop 为系统默认 18.0px，外层保持高阈值', (tester) async {
      double? innerSlop0;

      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              body: DirectionalTabBarView(
                horizontalTouchSlop: 48.0,
                disableDesktopDrag: false,
                children: [
                  Builder(
                    builder: (context) {
                      innerSlop0 = MediaQuery.maybeOf(context)?.gestureSettings.touchSlop;
                      return const Center(child: Text('Tab 0 Content'));
                    },
                  ),
                  const Center(child: Text('Tab 1 Content')),
                ],
              ),
            ),
          ),
        ),
      );

      // 验证当前已构建的 child 内层 touchSlop 恢复为系统标准 18.0 (kTouchSlop)
      expect(innerSlop0, equals(kTouchSlop));
      expect(find.text('Tab 0 Content'), findsOneWidget);
    });

    testWidgets('桌面端开启 disableDesktopDrag 时 physics 为 NeverScrollableScrollPhysics', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              body: DirectionalTabBarView(
                disableDesktopDrag: true,
                children: [
                  Center(child: Text('Tab 0')),
                  Center(child: Text('Tab 1')),
                ],
              ),
            ),
          ),
        ),
      );

      final tabBarViewFinder = find.byType(TabBarView);
      expect(tabBarViewFinder, findsOneWidget);
      final tabBarView = tester.widget<TabBarView>(tabBarViewFinder);
      expect(tabBarView.physics, isA<NeverScrollableScrollPhysics>());
    });

    testWidgets('斜向纵向滑动时，内层滚动组件不触发 TabBarView 左右切页', (tester) async {
      final scrollController = ScrollController();

      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              body: DirectionalTabBarView(
                horizontalTouchSlop: 48.0,
                disableDesktopDrag: false,
                children: [
                  ListView.builder(
                    controller: scrollController,
                    itemCount: 100,
                    itemBuilder: (context, index) => SizedBox(
                      height: 50,
                      child: Text('Item $index'),
                    ),
                  ),
                  const Center(child: Text('Tab 1 Content')),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('Tab 1 Content'), findsNothing);

      // 模拟一次带微小横向分量 (dx: -20, dy: -100) 的斜向滑动（偏角约 11.3°）
      // 横向位移 20px 超过默认的 18px，但低于 DirectionalTabBarView 的 48px
      // 纵向位移 100px 超过内层 18px 阈值，因此纵向 ListView 先胜出锁定
      await tester.drag(find.text('Item 0'), const Offset(-20, -100));
      await tester.pumpAndSettle();

      // 依然停留在 Tab 0，没有误切到 Tab 1
      expect(find.text('Tab 1 Content'), findsNothing);
      // 内层列表成功向上滚动
      expect(scrollController.offset, greaterThan(0));
    });

    testWidgets('大幅度纯水平横向滑动可以正常切换 Tab', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Scaffold(
              body: DirectionalTabBarView(
                horizontalTouchSlop: 48.0,
                disableDesktopDrag: false,
                children: [
                  Container(
                    color: Colors.red,
                    alignment: Alignment.center,
                    child: const Text('Tab 0 Content'),
                  ),
                  Container(
                    color: Colors.blue,
                    alignment: Alignment.center,
                    child: const Text('Tab 1 Content'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('Tab 0 Content'), findsOneWidget);

      // 纯水平大幅快速滑动
      await tester.fling(find.text('Tab 0 Content'), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      // 成功切到 Tab 1
      expect(find.text('Tab 1 Content'), findsOneWidget);
    });
  });
}
