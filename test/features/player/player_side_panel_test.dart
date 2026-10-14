import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';
import 'package:zakoway/features/player/widgets/player_side_panel.dart';
import 'package:zakoway/features/player/widgets/video_source_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerSidePanel 全屏悬浮侧边抽屉测试', () {
    late DanmakuController danmakuController;

    setUp(() {
      danmakuController = DanmakuController();
    });

    tearDown(() {
      danmakuController.dispose();
    });

    final testSources = [
      const VideoSourceItem(
        id: 'xifan-next',
        name: '稀饭Next',
        description: '官方推荐主线',
        isDefault: true,
      ),
      const VideoSourceItem(
        id: 'girigiri',
        name: 'girigiri',
        description: '原画直连',
      ),
    ];

    testWidgets('1. 侧边抽屉展开、Tab 切换与选集测试', (tester) async {
      int? selectedEpisode;
      bool closed = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 700,
              child: PlayerSidePanel(
                isOpen: true,
                initialTab: PlayerSidePanelTab.episodes,
                onClose: () => closed = true,
                episodeCount: 12,
                currentEpisode: 1,
                roads: const ['主线线路', '备用线路'],
                activeRoadIndex: 0,
                episodeTitles: List.generate(12, (i) => '第 ${i + 1} 话'),
                onSelectEpisode: (ep) => selectedEpisode = ep,
                sources: testSources,
                selectedSourceId: 'xifan-next',
                onSourceSelected: (_) {},
                danmakuController: danmakuController,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 验证 3 个 Tab 按钮存在 (选集文字在 Tab 与 EpisodePicker 中均有出现)
      expect(find.text('选集'), findsNWidgets(2));
      expect(find.text('换源'), findsOneWidget);
      expect(find.text('弹幕'), findsOneWidget);

      // 验证选集列表呈现
      expect(find.text('第 1 话'), findsOneWidget);
      expect(find.text('第 2 话'), findsOneWidget);

      // 点选第 2 话
      await tester.tap(find.text('第 2 话'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(selectedEpisode, equals(2));

      // 切换到「换源」Tab
      await tester.tap(find.text('换源'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('稀饭Next'), findsOneWidget);
      expect(find.text('girigiri'), findsOneWidget);

      // 切换到「弹幕」Tab
      await tester.tap(find.text('弹幕'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 验证弹幕设置项呈现
      expect(find.text('显示弹幕'), findsOneWidget);
      expect(find.text('精简模式'), findsOneWidget);
      expect(find.text('屏蔽彩色弹幕'), findsOneWidget);
      expect(find.text('不透明度'), findsOneWidget);
      expect(find.text('弹幕字号'), findsOneWidget);
      expect(find.text('飞行速度'), findsOneWidget);

      // 点击右上角关闭按钮
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(closed, isTrue);
    });

    testWidgets('2. 弹幕高级设置状态双向联动测试', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 700,
              child: PlayerSidePanel(
                isOpen: true,
                initialTab: PlayerSidePanelTab.danmaku,
                onClose: () {},
                episodeCount: 12,
                onSelectEpisode: (_) {},
                sources: testSources,
                selectedSourceId: 'xifan-next',
                onSourceSelected: (_) {},
                danmakuController: danmakuController,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(danmakuController.settings.simplify, isFalse);

      // 点击“精简模式”Switch
      final simplifyTile = find.ancestor(
        of: find.text('精简模式'),
        matching: find.byType(Row),
      );
      await tester.tap(find.descendant(of: simplifyTile, matching: find.byType(CupertinoSwitch)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(danmakuController.settings.simplify, isTrue);
      // 等待 400ms 防抖落盘完成，清空 pending timer
      await tester.pump(const Duration(milliseconds: 100));
    });
  });
}
