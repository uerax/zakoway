import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zakoway/features/common/widgets/app_desktop_title_bar.dart';
import 'package:zakoway/features/player/constants/player_ui_constants.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/widgets/controls/controls_top_bar.dart';
import 'package:zakoway/features/player/widgets/controls/popups/player_speed_popup.dart';
import 'package:zakoway/features/player/widgets/controls/popups/player_vertical_volume_popup.dart';
import 'package:zakoway/features/player/widgets/desktop/desktop_player_controls.dart';
import 'package:zakoway/features/player/widgets/desktop/desktop_player_gesture_layer.dart';
import 'package:zakoway/features/player/widgets/desktop/desktop_shortcut_help_dialog.dart';
import 'package:zakoway/features/player/widgets/player_progress_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ZakowayPlaybackController controller;

  setUp(() {
    controller = ZakowayPlaybackController();
  });

  tearDown(() {
    controller.dispose();
  });

  group('DesktopPlayerControls 桌面端专属控制与手势测试', () {
    testWidgets('DesktopPlayerGestureLayer: 单击即刻触发播放/暂停（无双击延迟判定）',
        (tester) async {
      bool activityReported = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: DesktopPlayerGestureLayer(
                controller: controller,
                onUserActivity: () => activityReported = true,
                onHideControls: () {},
                isControlsVisible: true,
              ),
            ),
          ),
        ),
      );

      expect(controller.core.value.playing, isFalse);
      await tester.tap(find.byType(DesktopPlayerGestureLayer));
      // 无双击等待计时器，微任务/单帧即刻触发播放
      await tester.pump();
      expect(controller.core.value.playing, isTrue);
      expect(activityReported, isTrue);
    });

    testWidgets('DesktopPlayerControls: 鼠标移入音量键悬停展开，移入面板后保持展开不消失，且滚轮调节音量',
        (tester) async {
      controller.setVolume(0.5);

      await tester.binding.setSurfaceSize(const Size(1000, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1000,
              height: 600,
              child: DesktopPlayerControls(
                controller: controller,
                title: '测试音量悬停',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.core.value.volume, equals(0.5));
      // 初始未悬停时，垂直音量滑槽面板不存在
      expect(find.byType(VerticalVolumeBar), findsNothing);

      // 1. 模拟鼠标移入音量图标按钮
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);

      final volumeBtnFinder = find.byIcon(Icons.volume_down_rounded);
      expect(volumeBtnFinder, findsOneWidget);

      await gesture.moveTo(tester.getCenter(volumeBtnFinder));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 2. 悬停展开后，垂直音量滑槽面板出现
      expect(find.byType(VerticalVolumeBar), findsOneWidget);

      // 3. 模拟鼠标向上移动进入垂直音量滑槽面板（验证绝对不消失）
      final barFinder = find.byType(VerticalVolumeBar);
      await gesture.moveTo(tester.getCenter(barFinder));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 面板依然健在，绝不消失
      expect(find.byType(VerticalVolumeBar), findsOneWidget);

      // 4. 在音量面板内部向上滚轮：音量增加 0.05 -> 0.55
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(barFinder),
          scrollDelta: const Offset(0, -100), // 向上滚
        ),
      );
      await tester.pump();
      expect(controller.core.value.volume, closeTo(0.55, 0.001));

      // 5. 在音量面板内部向下滚轮：音量减少 0.05 -> 0.50
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(barFinder),
          scrollDelta: const Offset(0, 100), // 向下滚
        ),
      );
      await tester.pump();
      expect(controller.core.value.volume, closeTo(0.50, 0.001));
    });

    testWidgets('DesktopShortcutHelpDialog: 快捷键帮助对话框正常渲染且包含常用说明', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DesktopShortcutHelpDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('键盘快捷键指南'), findsOneWidget);
      expect(find.text('Space / K'), findsOneWidget);
      expect(find.text('播放 / 暂停'), findsOneWidget);
      expect(find.text('F'), findsOneWidget);
      expect(find.text('切换全屏'), findsOneWidget);
    });

    testWidgets('DesktopPlayerControls: 基础渲染无锁屏按钮，键盘快捷键正常响应', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      bool fullscreenToggled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopPlayerControls(
              controller: controller,
              title: '测试桌面控制层',
              onToggleTrueFullscreen: () => fullscreenToggled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock_open_rounded), findsNothing);
      expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);

      expect(controller.core.value.playing, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(controller.core.value.playing, isTrue);

      expect(controller.core.value.muted, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pump();
      expect(controller.core.value.muted, isTrue);

      // 验证快捷键 Enter 不触发全屏，仅 F 键触发全屏
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(fullscreenToggled, isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.pump();
      expect(fullscreenToggled, isTrue);
    });

    testWidgets('DesktopPlayerControls: 小窗口 (448px) 与极窄窗口 (380px) 渲染零 overflow 溢出',
        (tester) async {
      // 模拟用户日志中报错的 448px 甚至更窄的 380px 小窗口
      for (final width in [448.0, 380.0, 350.0]) {
        await tester.binding.setSurfaceSize(Size(width, width * (9 / 16)));

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: width,
                height: width * (9 / 16),
                child: DesktopPlayerControls(
                  controller: controller,
                  title: '小窗口自适应测试',
                  onPrevEpisode: () {},
                  onNextEpisode: () {},
                  onToggleAppFullscreen: () {},
                  onToggleTrueFullscreen: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 验证没有抛出任何 RenderFlex overflow 异常
        expect(tester.takeException(), isNull);
      }
      addTearDown(() => tester.binding.setSurfaceSize(null));
    });

    testWidgets('DesktopPlayerControls: 窗口模式下点击播放设置呼出桌面模态弹窗，全屏下展示右下角悬浮卡片',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 1. 窗口模式 (isFullscreen: false)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopPlayerControls(
              controller: controller,
              title: '窗口设置测试',
              isFullscreen: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final settingsBtn = find.byIcon(Icons.tune_rounded);
      expect(settingsBtn, findsOneWidget);
      // 验证控制条已移除快捷键指南按钮
      expect(find.byTooltip('快捷键指南 (?)'), findsNothing);

      await tester.tap(settingsBtn);
      await tester.pumpAndSettle();

      // 验证桌面模态弹窗正常打开且包含「播放设置」与「快捷键指南」
      expect(find.text('播放设置'), findsOneWidget);
      expect(find.text('自动播放下一集'), findsOneWidget);
      expect(find.text('快捷键指南'), findsOneWidget);

      // 点击快捷键指南可唤起桌面快捷键说明对话框
      await tester.scrollUntilVisible(find.text('快捷键指南'), 100);
      await tester.tap(find.text('快捷键指南'));
      await tester.pumpAndSettle();
      expect(find.text('键盘快捷键指南'), findsOneWidget);

      // 关闭快捷键对话框
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();
      expect(find.text('键盘快捷键指南'), findsNothing);

      // 关闭设置弹窗
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();
      expect(find.text('自动播放下一集'), findsNothing);
    });

    testWidgets('DesktopPlayerControls: 左右快捷键静默快进后退触发 seek，弹窗关闭后依然灵敏响应',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      controller.timeline.value = controller.timeline.value.copyWith(
        position: const Duration(seconds: 30),
        duration: const Duration(minutes: 24),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopPlayerControls(
              controller: controller,
              title: '快捷键保活测试',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 左键快退 5 秒（静默生效，不展示 Toast 气泡）
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(controller.timeline.value.position, const Duration(seconds: 25));
      expect(find.text('快退 5 秒'), findsNothing);

      // 2. 右键快进 5 秒（静默生效，不展示 Toast 气泡）
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.timeline.value.position, const Duration(seconds: 30));
      expect(find.text('快进 5 秒'), findsNothing);

      // 3. 打开播放设置弹窗
      final settingsBtn = find.byIcon(Icons.tune_rounded);
      await tester.tap(settingsBtn);
      await tester.pumpAndSettle();
      expect(find.text('播放设置'), findsOneWidget);

      // 4. 关闭弹窗后，测试焦点自动恢复，继续响应左右键
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(controller.timeline.value.position, const Duration(seconds: 35));
      expect(find.text('快进 5 秒'), findsNothing);
    });

    testWidgets('DesktopPlayerControls: 点击底部控制条按钮间隙与空白区域不触发播放/暂停',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // 设置播放状态为正在播放
      controller.play();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopPlayerControls(
              controller: controller,
              title: '控制条间隙防误触测试',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(controller.core.value.playing, isTrue);

      // 1. 找到底部控制条内部的按钮 Row（与 PlayerProgressBar 处于同一个 Column）
      final bottomRowFinder = find.descendant(
        of: find.ancestor(
          of: find.byType(PlayerProgressBar),
          matching: find.byType(Column),
        ),
        matching: find.byType(Row),
      );
      expect(bottomRowFinder, findsOneWidget);
      final center = tester.getCenter(bottomRowFinder);

      // 2. 点击底部控制条中间空白占位 Spacer 区域
      await tester.tapAt(center);
      await tester.pump();

      // 验证：点击控制条按钮间隙/空白处被整块拦截，视频依然在播放，绝不暂停
      expect(controller.core.value.playing, isTrue);

      // 3. 点击控制条按钮下方 padding 边距区域 (Y=595 处)
      await tester.tapAt(const Offset(300, 595));
      await tester.pump();
      expect(controller.core.value.playing, isTrue);

      // 4. 点击控制条上方真正的视频画面区域 (例如 Y=200 处)
      await tester.tapAt(const Offset(500, 200));
      await tester.pump();

      // 验证：点击视频画面依然能正常触发播放/暂停
      expect(controller.core.value.playing, isFalse);
    });

    testWidgets('DesktopPlayerControls: 倍速气泡浮层展开时与倍速按钮水平中心精准对齐',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopPlayerControls(
              controller: controller,
              title: '倍速居中对齐测试',
            ),
          ),
        ),
      );
      await tester.pump();

      // 找到倍速按钮
      final speedBtnFinder = find.text('倍速');
      expect(speedBtnFinder, findsOneWidget);
      final speedBtnCenter = tester.getCenter(speedBtnFinder);

      // 点击展开倍速选择气泡
      await tester.tap(speedBtnFinder);
      await tester.pump();

      // 验证倍速气泡展开
      final popupFinder = find.byType(PlayerSpeedPopup);
      expect(popupFinder, findsOneWidget);
      final popupCenter = tester.getCenter(popupFinder);

      // 验证：气泡中心 X 坐标与倍速按钮中心 X 坐标精准对齐（误差 < 1px）
      expect(popupCenter.dx, closeTo(speedBtnCenter.dx, 1.0));
      // 验证：气泡位于倍速按钮上方
      expect(popupCenter.dy, lessThan(speedBtnCenter.dy));

      // 点击选择 1.5x
      await tester.tap(find.text('1.5x'));
      await tester.pump();

      expect(controller.core.value.playbackRate, equals(1.5));
      expect(find.byType(PlayerSpeedPopup), findsNothing);
    });

    testWidgets('DesktopPlayerControls: 剧场模式按钮渲染且点击/按T键响应 onToggleTheaterMode',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var theaterToggleCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopPlayerControls(
              controller: controller,
              title: '剧场模式按键测试',
              isTheaterMode: false,
              onToggleTheaterMode: () => theaterToggleCount++,
            ),
          ),
        ),
      );
      await tester.pump();

      // 验证剧场模式图标存在（非剧场模式时为 rectangle_outlined）
      final theaterBtnFinder = find.byIcon(Icons.rectangle_outlined);
      expect(theaterBtnFinder, findsOneWidget);

      // 点击剧场模式按钮
      await tester.tap(theaterBtnFinder);
      await tester.pump();
      expect(theaterToggleCount, equals(1));

      // 按下键盘 T 键
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pump();
      expect(theaterToggleCount, equals(2));
    });

    testWidgets('DesktopTitleBarManager: 联动隐藏桌面窗口顶栏并更新顶内边距',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: AppDesktopWindowFrame(
              child: Builder(
                builder: (context) {
                  final topPad = MediaQuery.of(context).padding.top;
                  return Center(
                    child: Text('TopPadding: $topPad'),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 默认状态下：存在桌面沉浸顶栏，且向下注入 44px top padding
        expect(find.byType(AppDesktopTitleBar), findsOneWidget);
        expect(find.text('TopPadding: 44.0'), findsOneWidget);

        // 进入播放器全屏状态：顶栏收缩隐藏，全局 MediaQuery 保持绝对稳定不重排
        DesktopTitleBarManager.instance.setPlayerFullscreen(true);
        await tester.pumpAndSettle();

        expect(find.byType(AppDesktopTitleBar), findsNothing);
        expect(find.text('TopPadding: 44.0'), findsOneWidget);

        // 退出播放器全屏：顶栏平滑恢复
        DesktopTitleBarManager.instance.setPlayerFullscreen(false);
        await tester.pumpAndSettle();

        expect(find.byType(AppDesktopTitleBar), findsOneWidget);
        expect(find.text('TopPadding: 44.0'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        DesktopTitleBarManager.instance.setPlayerFullscreen(false);
      }
    });

    testWidgets('DesktopPlayerControls: 全屏播放状态下播放中 2 秒自动隐藏顶部控制栏与底部条',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopPlayerControls(
              controller: controller,
              title: '全屏播放顶栏测试',
              isFullscreen: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // 验证全屏下顶部控制栏存在
      expect(find.byType(PlayerControlsTopBar), findsOneWidget);

      // 开始播放
      await controller.play();
      await tester.pump();

      // 验证控制栏此时仍然可见（opacity: 1.0）
      final animatedOpacityFinder = find.byWidgetPredicate(
        (w) => w is AnimatedOpacity && w.duration == const Duration(milliseconds: 220),
      );
      expect(animatedOpacityFinder, findsOneWidget);
      var opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, equals(1.0));

      // 等待自动隐藏定时器触发并完成 220ms 动画
      await tester.pump(PlayerUiConstants.desktopControlsAutoHideDelay + const Duration(milliseconds: 300));

      opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, equals(0.0));

      // 模拟鼠标移动唤醒控制栏
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(400, 300));
      addTearDown(gesture.removePointer);
      await tester.pump();

      await gesture.moveTo(const Offset(450, 350));
      await tester.pump();

      opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, equals(1.0));
    });

    testWidgets('DesktopPlayerControls: 视频暂停状态下静止依然会自动隐藏控制栏，鼠标移动后恢复可见',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopPlayerControls(
              controller: controller,
              title: '暂停状态自动隐藏测试',
              isFullscreen: true,
            ),
          ),
        ),
      );
      await tester.pump();

      // 处于未播放/暂停状态
      expect(controller.core.value.playing, isFalse);

      final animatedOpacityFinder = find.byWidgetPredicate(
        (w) => w is AnimatedOpacity && w.duration == const Duration(milliseconds: 220),
      );
      expect(animatedOpacityFinder, findsOneWidget);
      var opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, equals(1.0));

      // 等待自动隐藏定时器触发并完成动画
      await tester.pump(PlayerUiConstants.desktopControlsAutoHideDelay + const Duration(milliseconds: 300));

      opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, equals(0.0));

      // 模拟鼠标移动唤醒控制栏
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(400, 300));
      addTearDown(gesture.removePointer);
      await tester.pump();

      await gesture.moveTo(const Offset(450, 350));
      await tester.pump();

      opacityWidget = tester.widget<AnimatedOpacity>(animatedOpacityFinder);
      expect(opacityWidget.opacity, equals(1.0));
    });

    testWidgets('PlayerControlsTopBar: 桌面端顶部控制栏配置 DragToMoveArea 支持窗口拖拽与双击最大化',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerControlsTopBar(
                title: '测试可拖拽标题',
                isFullscreen: true,
                onBackPressed: () {},
                onOpenEpisodePicker: () {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DragToMoveArea), findsWidgets);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
