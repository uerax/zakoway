import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';
import 'package:zakoway/features/player/services/player_preferences_service.dart';
import 'package:zakoway/features/player/widgets/controls/danmaku_settings_icon.dart';
import 'package:zakoway/features/player/widgets/controls/popups/player_speed_popup.dart';
import 'package:zakoway/features/player/widgets/player_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerControls 底栏紧凑防溢出与自动连播测试', () {
    late ZakowayPlaybackController controller;
    late DanmakuController danmakuController;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PlayerPreferencesService.instance.resetForTest();
      danmakuController = DanmakuController();
      controller = ZakowayPlaybackController();
    });

    tearDown(() async {
      await controller.dispose();
      danmakuController.dispose();
    });

    testWidgets('1. 手机窄屏(360dp)下 1.25x 倍速且时长大于 1 小时，底栏不发生 RenderFlex 溢出',
        (tester) async {
      await controller.setPlaybackRate(1.25);
      controller.timeline.value = controller.timeline.value.copyWith(
        duration: const Duration(hours: 1, minutes: 15, seconds: 30),
        position: const Duration(minutes: 5, seconds: 20),
      );

      final errors = <FlutterErrorDetails>[];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 240,
              child: PlayerControls(
                controller: controller,
                title: '超长剧场版动画',
                danmakuController: danmakuController,
                isFullscreen: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      FlutterError.onError = oldHandler;
      expect(errors, isEmpty);

      // 验证控制栏呈现自绘弹幕图标与 1.25x 按钮
      expect(find.byType(DanmakuSettingsIcon), findsOneWidget);
      expect(find.text('1.25x'), findsOneWidget);

      // 验证时间戳正确按时分秒格式渲染
      expect(find.text('00:05:20 / 01:15:30'), findsOneWidget);

      // 验证上一集和下一集按钮已从控制栏移除
      expect(find.byIcon(Icons.skip_previous_rounded), findsNothing);
      expect(find.byIcon(Icons.skip_next_rounded), findsNothing);
    });

    testWidgets('2. 播放器设置面板中支持开关「自动播放下一集」并持久化', (tester) async {
      await PlayerPreferencesService.instance.initialize();
      final autoPlayNotifier = ValueNotifier<bool>(true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                autoPlayNextNotifier: autoPlayNotifier,
                isFullscreen: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 打开播放设置
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();

      // 验证「自动播放下一集」开关存在且初始为 true
      expect(find.text('自动播放下一集'), findsOneWidget);
      expect(autoPlayNotifier.value, isTrue);

      // 切换开关
      await tester.tap(find.text('自动播放下一集'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(autoPlayNotifier.value, isFalse);
      expect(PlayerPreferencesService.instance.autoPlayNext, isFalse);

      // 再次切换回开启
      await tester.tap(find.text('自动播放下一集'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(autoPlayNotifier.value, isTrue);
      expect(PlayerPreferencesService.instance.autoPlayNext, isTrue);

      autoPlayNotifier.dispose();
    });

    testWidgets('3. 验证底栏使用自绘 DanmakuToggleIcon 开关，点击切换开启与划线关闭状态',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                title: '测试动画',
                danmakuController: danmakuController,
                isFullscreen: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证存在自绘弹幕开关
      expect(find.byType(DanmakuToggleIcon), findsOneWidget);
      final initialIcon = tester.widget<DanmakuToggleIcon>(find.byType(DanmakuToggleIcon));
      expect(initialIcon.enabled, isTrue);

      // 点击弹幕开关关闭弹幕
      await tester.tap(find.byType(DanmakuToggleIcon));
      await tester.pumpAndSettle();

      expect(danmakuController.settings.enabled, isFalse);
      final toggledIcon = tester.widget<DanmakuToggleIcon>(find.byType(DanmakuToggleIcon));
      expect(toggledIcon.enabled, isFalse);
    });

    testWidgets('4. 播放设置面板支持切换「控制栏图标大小」并持久化偏好', (tester) async {
      await PlayerPreferencesService.instance.initialize();
      PlayerPreferencesService.instance.saveControlBarScale(PlayerControlBarScale.auto);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                isFullscreen: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 打开播放设置
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();

      expect(find.text('控制栏图标大小'), findsOneWidget);
      expect(find.text('自适应'), findsOneWidget);
      expect(find.text('标准'), findsOneWidget);

      // 滚动到底部并点击选择「大号」
      await tester.ensureVisible(find.text('大号'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('大号'));
      await tester.pumpAndSettle();

      expect(PlayerPreferencesService.instance.controlBarScale,
          equals(PlayerControlBarScale.large));
    });

    testWidgets('5. 窄屏 (360x220) 下展开倍速菜单，气泡动态自适应锚定于倍速按钮且无截断溢出',
        (tester) async {
      await PlayerPreferencesService.instance.initialize();
      await PlayerPreferencesService.instance.saveControlBarScale(PlayerControlBarScale.auto);

      final errors = <FlutterErrorDetails>[];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 220,
              child: PlayerControls(
                controller: controller,
                title: '窄屏动画测试',
                isFullscreen: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击展开倍速菜单 (1x)
      expect(find.text('1x'), findsOneWidget);
      await tester.tap(find.text('1x'));
      await tester.pumpAndSettle();

      FlutterError.onError = oldHandler;
      expect(errors, isEmpty);

      // 验证倍速气泡呈现且完整包含选项
      expect(find.byType(PlayerSpeedPopup), findsOneWidget);
      expect(find.text('2.0x'), findsOneWidget);
      expect(find.text('0.75x'), findsOneWidget);

      // 获取倍速按钮和倍速气泡的真实渲染矩形
      final speedButtonRect = tester.getRect(find.text('1x').first);
      final popupRect = tester.getRect(find.byType(PlayerSpeedPopup));

      // 验证气泡水平居中对齐倍速按钮（允许极窄屏幕下 clamp 保护边缘，且中心偏差极小）
      final speedBtnCenter = speedButtonRect.center.dx;
      final popupCenter = popupRect.center.dx;
      expect((speedBtnCenter - popupCenter).abs(), lessThan(10.0));

      // 验证气泡位于倍速按钮上方
      expect(popupRect.bottom, lessThanOrEqualTo(speedButtonRect.top));

      // 验证气泡完全位于播放器视口内（left >= 0, right <= 360, top >= 0）
      expect(popupRect.left, greaterThanOrEqualTo(0.0));
      expect(popupRect.right, lessThanOrEqualTo(360.0));
      expect(popupRect.top, greaterThanOrEqualTo(0.0));
    });

    testWidgets('6. 桌面端同时提供应用全屏与真全屏按钮，并能独立触发回调', (tester) async {
      bool appFullscreenToggled = false;
      bool trueFullscreenToggled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                title: '桌面端全屏测试',
                onToggleAppFullscreen: () => appFullscreenToggled = true,
                onToggleTrueFullscreen: () => trueFullscreenToggled = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证存在应用全屏图标与真全屏图标
      expect(find.byIcon(Icons.fit_screen_rounded), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);

      // 点击应用全屏按钮
      await tester.tap(find.byIcon(Icons.fit_screen_rounded));
      await tester.pump();
      expect(appFullscreenToggled, isTrue);

      // 点击真全屏按钮
      await tester.tap(find.byIcon(Icons.fullscreen_rounded));
      await tester.pump();
      expect(trueFullscreenToggled, isTrue);
    });
  });
}
