import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/widgets/controls/popups/player_vertical_volume_popup.dart';
import 'package:zakoway/features/player/widgets/desktop/desktop_player_controls.dart';
import 'package:zakoway/features/player/widgets/desktop/desktop_player_gesture_layer.dart';
import 'package:zakoway/features/player/widgets/desktop/desktop_shortcut_help_dialog.dart';

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
    testWidgets('DesktopPlayerGestureLayer: 单击触发播放/暂停', (tester) async {
      bool activityReported = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: DesktopPlayerGestureLayer(
                controller: controller,
                onToggleFullscreen: () {},
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
      await tester.pump(const Duration(milliseconds: 350));
      expect(controller.core.value.playing, isTrue);
      expect(activityReported, isTrue);
    });

    testWidgets('DesktopPlayerGestureLayer: 双击触发全屏', (tester) async {
      bool fullscreenToggled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: DesktopPlayerGestureLayer(
                controller: controller,
                onToggleFullscreen: () => fullscreenToggled = true,
                onUserActivity: () {},
                onHideControls: () {},
                isControlsVisible: true,
              ),
            ),
          ),
        ),
      );

      final finder = find.byType(DesktopPlayerGestureLayer);
      await tester.tap(finder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(fullscreenToggled, isTrue);
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

      final volumeBtnFinder = find.byTooltip('静音 (M) / 悬停调音量');
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
      expect(find.text('F / Enter'), findsOneWidget);
      expect(find.text('切换全屏'), findsOneWidget);
    });

    testWidgets('DesktopPlayerControls: 基础渲染无锁屏按钮，键盘快捷键正常响应', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopPlayerControls(
              controller: controller,
              title: '测试桌面控制层',
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

      final settingsBtn = find.byTooltip('播放设置');
      expect(settingsBtn, findsOneWidget);
      await tester.tap(settingsBtn);
      await tester.pumpAndSettle();

      // 验证桌面模态弹窗正常打开且标题为「播放设置」
      expect(find.text('播放设置'), findsOneWidget);
      expect(find.text('自动播放下一集'), findsOneWidget);

      // 关闭弹窗
      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await tester.pumpAndSettle();
      expect(find.text('自动播放下一集'), findsNothing);
    });
  });
}
