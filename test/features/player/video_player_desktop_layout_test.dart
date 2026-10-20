import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/widgets/video_player_layouts.dart';

void main() {
  group('VideoPlayerDesktopLayout 桌面端黄金比例布局测试', () {
    testWidgets('1920x1080 桌面端右侧栏削减 15% 后锁定为 357px，左侧播放器分得 1563px 剩余空间', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const keyPlayer = Key('player_widget');
      const keyTab = Key('tab_section');

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerDesktopLayout(
            title: '测试桌面布局',
            onBackPressed: () {},
            playerWidget: const SizedBox(key: keyPlayer),
            tabSection: const SizedBox(key: keyTab),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tabBox = tester.getRect(find.byKey(keyTab));
      expect(tabBox.width, equals(357.0)); // 420.0 * 0.85 = 357.0

      // 验证左侧可用空间为 1920 - 357 = 1563
      // 内部播放器包含 16px padding，可用宽为 1563 - 32 = 1531
      final playerBox = tester.getRect(find.byKey(keyPlayer));
      expect(playerBox.width, closeTo(1531.0, 1.0));
      expect(playerBox.height, closeTo(1531.0 / (16 / 9), 1.0));
      // 验证播放器紧贴顶部 padding 16px（沉浸式无 AppBar），绝非垂直居中
      expect(playerBox.top, equals(16.0));
    });

    testWidgets('1000x800 中等窗口下右侧栏削减 15% 后触发 306px 保底下限', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const keyPlayer = Key('player_widget');
      const keyTab = Key('tab_section');

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerDesktopLayout(
            title: '测试桌面布局',
            onBackPressed: () {},
            playerWidget: const SizedBox(key: keyPlayer),
            tabSection: const SizedBox(key: keyTab),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tabBox = tester.getRect(find.byKey(keyTab));
      expect(tabBox.width, equals(306.0)); // 360.0 * 0.85 = 306.0
    });

    testWidgets('矮窗口 (1920x600) 下播放器按 16:9 Contain 自适应高度，绝对不产生溢出', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const keyPlayer = Key('player_widget');
      const keyTab = Key('tab_section');

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerDesktopLayout(
            title: '测试桌面布局',
            onBackPressed: () {},
            playerWidget: const SizedBox(key: keyPlayer),
            tabSection: const SizedBox(key: keyTab),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final playerBox = tester.getRect(find.byKey(keyPlayer));
      // 可用高度受限：高度小于宽度撑满时的 16:9
      expect(playerBox.height, lessThanOrEqualTo(600.0));
      expect(playerBox.width / playerBox.height, closeTo(16 / 9, 0.05));
    });

    testWidgets('全新桌面端架构布局：左侧播放器下依序排列简介与评论，右侧通过 [选集 | 视频源] 胶囊双 Tab 切换', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const keyPlayer = Key('player_widget');
      const keyIntro = Key('intro_section');
      const keyComments = Key('comments_section');
      const keySource = Key('source_view');
      const keyEpisodes = Key('episodes_picker');
      const keyRecommend = Key('recommend_section');

      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Builder(
              builder: (context) {
                return VideoPlayerDesktopLayout(
                  title: '全新桌面端布局番剧',
                  currentEpisode: 3,
                  onBackPressed: () {},
                  playerWidget: const SizedBox(key: keyPlayer),
                  introSection: const SizedBox(key: keyIntro),
                  commentsSection: const SizedBox(key: keyComments),
                  rightTabController: DefaultTabController.of(context),
                  episodePickerSection: const SizedBox(key: keyEpisodes),
                  sourceViewSection: const SizedBox(key: keySource),
                  recommendSection: const SizedBox(key: keyRecommend),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证全新沉浸式架构彻底移除外层横贯全屏的空白顶栏
      expect(find.byType(AppBar), findsNothing);

      // 验证右侧栏顶部呈现 [选集 | 视频源] 极简胶囊分段控制器
      expect(find.widgetWithText(Tab, '选集'), findsOneWidget);
      expect(find.widgetWithText(Tab, '视频源'), findsOneWidget);

      // 验证左栏组件垂直顺序：Player -> Intro -> Comments
      final playerTop = tester.getTopLeft(find.byKey(keyPlayer)).dy;
      final introTop = tester.getTopLeft(find.byKey(keyIntro)).dy;
      final commentsTop = tester.getTopLeft(find.byKey(keyComments)).dy;
      expect(playerTop, lessThan(introTop));
      expect(introTop, lessThan(commentsTop));

      // 默认聚焦 Tab 0「选集」，呈现选集与推荐
      expect(find.byKey(keyEpisodes), findsOneWidget);
      expect(find.byKey(keyRecommend), findsOneWidget);

      // 切换至 Tab 1「视频源」，呈现原本完整选源看板
      await tester.tap(find.widgetWithText(Tab, '视频源'));
      await tester.pumpAndSettle();
      expect(find.byKey(keySource), findsOneWidget);
    });

    testWidgets('桌面端常驻左下角半透明悬浮返回按钮，点击响应 onBackPressed', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var backPressedCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: VideoPlayerDesktopLayout(
            title: '测试返回按钮',
            onBackPressed: () => backPressedCount++,
            playerWidget: const SizedBox(),
            tabSection: const SizedBox(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证存在桌面端左下角悬浮返回按钮
      final backButtonFinder = find.byType(DesktopFloatingBackButton);
      expect(backButtonFinder, findsOneWidget);

      // 验证按钮位置在左下角 (left: 24, bottom: 24)
      final rect = tester.getRect(backButtonFinder);
      expect(rect.left, equals(24.0));
      expect(rect.bottom, equals(1080.0 - 24.0));

      // 验证点击触发返回回调
      await tester.tap(backButtonFinder);
      await tester.pumpAndSettle();
      expect(backPressedCount, equals(1));
    });

    testWidgets('剧场模式 (isTheaterMode: true)：播放器脱离分栏水平居中，下方双栏流式呈现', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const keyPlayer = Key('player_widget_theater');
      const keyIntro = Key('intro_section_theater');
      const keyComments = Key('comments_section_theater');
      const keyEpisodes = Key('episodes_picker_theater');
      const keyRecommend = Key('recommend_section_theater');

      await tester.pumpWidget(
        MaterialApp(
          home: DefaultTabController(
            length: 2,
            child: Builder(
              builder: (context) {
                return VideoPlayerDesktopLayout(
                  title: '剧场模式番剧',
                  currentEpisode: 1,
                  isTheaterMode: true,
                  onBackPressed: () {},
                  playerWidget: const SizedBox(key: keyPlayer),
                  introSection: const SizedBox(key: keyIntro),
                  commentsSection: const SizedBox(key: keyComments),
                  rightTabController: DefaultTabController.of(context),
                  episodePickerSection: const SizedBox(key: keyEpisodes),
                  recommendSection: const SizedBox(key: keyRecommend),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final playerBox = tester.getRect(find.byKey(keyPlayer));
      final introBox = tester.getRect(find.byKey(keyIntro));

      // 验证播放器水平中心对齐窗口中线 (1920 / 2 = 960)
      expect(playerBox.center.dx, closeTo(960.0, 1.0));

      // 验证播放器宽度远大于原分栏模式下的左侧可用宽度 (普通模式下约为 1531，剧场模式下接近 1563~1888 左右且自适应居中)
      expect(playerBox.width, greaterThan(1500.0));

      // 验证播放器高度受限于视口合理比例，绝不超出 1080 视口
      expect(playerBox.height, lessThan(1080.0));

      // 验证下方内容在播放器正下方：introTop > playerBottom
      expect(introBox.top, greaterThan(playerBox.bottom));

      // 验证下方右侧选集与推荐正常挂载
      expect(find.byKey(keyEpisodes), findsOneWidget);
      expect(find.byKey(keyRecommend), findsOneWidget);
    });
  });
}
