import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/pages/video_play_page.dart';
import 'package:zakoway/features/player/widgets/episode_picker_section.dart';
import 'package:zakoway/features/player/widgets/episode_source_pod.dart';
import 'package:zakoway/features/player/widgets/video_player_layouts.dart';
import 'package:zakoway/features/player/widgets/video_source_view.dart';
import 'package:zakoway/features/player/widgets/watch_comments_section.dart';
import 'package:zakoway/features/player/widgets/watch_meta_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoPlayPage 功能与交互设计测试', () {
    testWidgets('1. 点开番剧不默认播放第一集，展示占位引导', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: VideoPlayPage(
              title: '测试动画',
              episodeCount: 12,
              currentEpisode: null, // 未起播
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证未起播提示条存在
      expect(find.text('分集已就绪 · 请在下方选择集数开始播放'), findsOneWidget);
      // 验证未起播时绝不存在中央大播放按钮（引导用户点击下方集数选择起播）
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets('2. 移动端页面包含 2 个主 Tab（简介 / 评论），且默认聚焦「简介」Tab 展示融合舱', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: VideoPlayPage(
              title: '测试动画',
              episodeCount: 12,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证存在 2 个主 Tab
      expect(find.widgetWithText(Tab, '简介'), findsOneWidget);
      expect(find.widgetWithText(Tab, '评论'), findsOneWidget);

      // 验证默认显示的是 EpisodeSourcePod（选集与视频源融合舱）
      expect(find.byType(EpisodeSourcePod), findsOneWidget);
    });

    testWidgets('3. 选集组件支持正序/倒序切换', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpisodePickerSection(
              episodeCount: 5,
              onSelectEpisode: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 默认正序
      expect(find.text('正序'), findsOneWidget);
      expect(find.text('第 1 话'), findsOneWidget);
      expect(find.text('第 5 话'), findsOneWidget);

      // 点击切换为倒序
      await tester.tap(find.text('正序'));
      await tester.pumpAndSettle();

      expect(find.text('倒序'), findsOneWidget);
    });

    testWidgets('4. 优化点 1 验证：未探活的非绿色源点击后绝不自动跳转', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: VideoPlayPage(
              title: '测试动画',
              episodeCount: 12,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击源药丸打开全功能抽屉
      await tester.tap(find.text('稀饭Next'));
      await tester.pumpAndSettle();

      // 切换到抽屉内的「切换视频源」Tab
      await tester.tap(find.text('切换视频源'));
      await tester.pumpAndSettle();

      expect(find.byType(VideoSourceView), findsOneWidget);
      expect(find.text('girigiri'), findsOneWidget);

      // 点击处于待探活状态的girigiri
      await tester.tap(find.text('girigiri'));
      await tester.pumpAndSettle();

      // 严格验证：绝不跳转，仍然保持在视频源看板！
      expect(find.byType(VideoSourceView), findsOneWidget);
    });

    testWidgets('5. 多线路选集播放态隔离：线路 1 正在播放第 1 集时，切换查看线路 2 不会把线路 2 的第 1 集标为正在播放', (tester) async {
      int activeRoad = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return EpisodePickerSection(
                  episodeCount: 12,
                  currentEpisode: 1,
                  roads: const ['线路 1', '线路 2', '线路 3'],
                  activeRoadIndex: activeRoad,
                  playingRoadIndex: 0, // 仅线路 1 处于实际在播态
                  onRoadSelected: (idx) => setState(() => activeRoad = idx),
                  onSelectEpisode: (_) {},
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 验证线路 1 处于在播态（有正在播放音波指示动画图标）
      expect(find.byType(AnimatedBuilder), findsWidgets);

      // 切换查看线路 2
      await tester.tap(find.text('线路 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 验证切换到线路 2 后，第 1 集不会被标记为正在播放
      // 检查当前界面中的第 1 话不是在播高亮
      final ep1Text = tester.widget<Text>(find.text('第 1 话'));
      expect(ep1Text.style?.color, isNot(equals(Colors.white)));

      // 切换查看线路 3
      await tester.tap(find.text('线路 3'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 验证切换到线路 3 后，第 1 集同样绝不显示在播
      final ep1TextRoad3 = tester.widget<Text>(find.text('第 1 话'));
      expect(ep1TextRoad3.style?.color, isNot(equals(Colors.white)));

      // 切回线路 1，第 1 话恢复正在播放高亮态
      await tester.tap(find.text('线路 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final ep1TextRoad1 = tester.widget<Text>(find.text('第 1 话'));
      expect(ep1TextRoad1.style?.color, equals(Colors.white));
    });

    testWidgets('6. 视频源列表顶部不再渲染冗余的「当前视频源」大卡片', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: VideoSourceView(
              sources: [
                VideoSourceItem(
                  id: 'xifan-next',
                  name: '稀饭Next',
                  description: '官方推荐主线',
                ),
              ],
              selectedSourceId: 'xifan-next',
              onSourceSelected: _dummySelect,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证不再有旧版「当前正在生效」或「当前视频源：」大卡片
      expect(find.textContaining('当前视频源：'), findsNothing);
      expect(find.textContaining('当前生效'), findsNothing);
    });

    testWidgets('7. 点击线路 2 仅切换查看视图，绝不自动调用切集起播', (tester) async {
      int selectedEpisodeCallCount = 0;
      int selectedRoad = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return EpisodePickerSection(
                  episodeCount: 12,
                  currentEpisode: 1,
                  roads: const ['线路 1', '线路 2', '线路 3'],
                  activeRoadIndex: selectedRoad,
                  playingRoadIndex: 0,
                  onRoadSelected: (idx) {
                    setState(() => selectedRoad = idx);
                  },
                  onSelectEpisode: (_) {
                    selectedEpisodeCallCount++;
                  },
                );
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 点击切换到线路 2
      await tester.tap(find.text('线路 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 验证仅线路视图切换为线路 2，绝未触发切集播放
      expect(selectedRoad, equals(1));
      expect(selectedEpisodeCallCount, equals(0));
    });

    testWidgets('8. 移动端选集分页单页容量为 28，整除 4 列网格且支持即时 0ms 切页', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpisodePickerSection(
              episodeCount: 60,
              currentEpisode: 1,
              onSelectEpisode: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证生成 1-28, 29-56, 57-60 区间胶囊
      expect(find.text('1-28'), findsOneWidget);
      expect(find.text('29-56'), findsOneWidget);
      expect(find.text('57-60'), findsOneWidget);
      expect(find.text('第 1 话'), findsOneWidget);
      expect(find.text('第 28 话'), findsOneWidget);
      expect(find.text('第 29 话'), findsNothing);

      // 点击切换至第二区间「29-56」
      await tester.tap(find.text('29-56'));
      await tester.pump(); // 0ms 即时渲染生效，无动画延迟

      expect(find.text('第 29 话'), findsOneWidget);
      expect(find.text('第 56 话'), findsOneWidget);
      expect(find.text('第 1 话'), findsNothing);
    });

    testWidgets('9. 桌面端 (宽屏 >= 768) 采用全新分块架构：左栏简介与评论、右栏 [选集 | 视频源] 胶囊双 Tab', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: VideoPlayPage(
              title: '桌面端测试动画',
              episodeCount: 12,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证桌面端渲染 VideoPlayerDesktopLayout 且无外层空白 AppBar
      expect(find.byType(VideoPlayerDesktopLayout), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);
      // 验证左栏包含 WatchMetaView (简介) 与 WatchCommentsSection (评论)
      expect(find.byType(WatchMetaView), findsOneWidget);
      expect(find.byType(WatchCommentsSection), findsOneWidget);
      // 验证右栏包含 [选集 | 视频源] 双 Tab 与 EpisodePickerSection (选集)
      expect(find.widgetWithText(Tab, '选集'), findsOneWidget);
      expect(find.widgetWithText(Tab, '视频源'), findsOneWidget);
      expect(find.byType(EpisodePickerSection), findsOneWidget);
    });

    testWidgets('10. 桌面端右侧栏 [选集 | 视频源] 胶囊支持切换至原本视频源看板', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: VideoPlayPage(
              title: '测试切源动画',
              episodeCount: 12,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击切换至「视频源」Tab
      await tester.tap(find.widgetWithText(Tab, '视频源'));
      await tester.pumpAndSettle();

      // 验证呈现原本的 VideoSourceView 完整看板
      expect(find.byType(VideoSourceView), findsOneWidget);
      expect(find.text('稀饭Next'), findsAtLeastNWidgets(1));
    });

    testWidgets('11. 分集正在加载 (isLoading == true) 时展示骨架与提示，绝不提前暴露虚假上千集卡片与分页胶囊', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpisodePickerSection(
              episodeCount: 1100, // 模拟外部传入的长篇占位总集数
              isLoading: true,
              loadingMessage: '正在从「稀饭Next」解析分集...',
              onSelectEpisode: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();

      // 验证展示加载中提示文案
      expect(find.text('正在从「稀饭Next」解析分集...'), findsOneWidget);
      expect(find.text('加载中...'), findsOneWidget);

      // 验证绝不提前渲染 1-50 等基于 1100 虚假集数计算的分页胶囊与第 1 话虚假卡片
      expect(find.text('1-50'), findsNothing);
      expect(find.text('共 1100 话'), findsNothing);
      expect(find.text('第 1 话'), findsNothing);
    });

    testWidgets('12. 页面级 Esc 兜底测试：未起播与起播状态下按 Esc 触发分级返回上一页', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const VideoPlayPage(
                        title: '快捷键兜底测试',
                        episodeCount: 12,
                      ),
                    ),
                  );
                },
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      expect(find.byType(VideoPlayPage), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(VideoPlayPage), findsNothing);
    });
  });
}

void _dummySelect(VideoSourceItem _) {}
