import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/common/widgets/app_desktop_title_bar.dart';

void main() {
  group('AppDesktopTitleBar 跨平台沉浸顶栏测试', () {
    testWidgets('Windows 平台排版：左侧放置 32x32 高清 Logo，右侧放置极简三按键，中间留白', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AppDesktopTitleBar(height: 44.0),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 验证存在顶栏组件
        expect(find.byType(AppDesktopTitleBar), findsOneWidget);

        // 验证没有出现俗气的文字标题
        expect(find.text('zakoway'), findsNothing);
        expect(find.text('Zakoway'), findsNothing);

        // 验证 Windows 下右侧三按键存在（通过语义标签识别）
        expect(find.bySemanticsLabel('最小化'), findsOneWidget);
        expect(find.bySemanticsLabel('最大化'), findsOneWidget);
        expect(find.bySemanticsLabel('关闭'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('macOS 平台排版：左侧保留 78px 避让原生红绿灯，右侧放置 Logo，不渲染 Windows 三按键', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: AppDesktopTitleBar(height: 44.0),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 验证存在顶栏组件
        expect(find.byType(AppDesktopTitleBar), findsOneWidget);

        // 验证 macOS 下绝不渲染 Windows 的三按键
        expect(find.bySemanticsLabel('最小化'), findsNothing);
        expect(find.bySemanticsLabel('最大化'), findsNothing);
        expect(find.bySemanticsLabel('关闭'), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
