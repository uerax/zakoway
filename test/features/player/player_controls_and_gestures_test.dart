import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/controller/playback_state.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';
import 'package:zakoway/features/player/widgets/controls/danmaku_settings_icon.dart';
import 'package:zakoway/features/player/widgets/player_controls.dart';
import 'package:zakoway/features/player/widgets/player_indicators.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlayerControls 现代交互与控制增强测试', () {
    late ZakowayPlaybackController controller;
    late DanmakuController danmakuController;

    setUp(() {
      danmakuController = DanmakuController();
      controller = ZakowayPlaybackController();
    });

    tearDown(() async {
      await controller.dispose();
      danmakuController.dispose();
    });

    testWidgets('1. 基础 UI 元素完整呈现（快进快退10s、播放暂停、倍速、锁屏、选集）', (tester) async {
      bool fullscreenToggled = false;
      bool episodePickerOpened = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                title: '测试动画第01话',
                danmakuController: danmakuController,
                isFullscreen: true,
                onToggleFullscreen: () => fullscreenToggled = true,
                onOpenEpisodePicker: () => episodePickerOpened = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证标题呈现
      expect(find.text('测试动画第01话'), findsOneWidget);

      // 验证设置按钮与自绘弹幕面板设置图标 (DanmakuSettingsIcon)
      expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
      expect(find.byType(DanmakuSettingsIcon), findsOneWidget);

      // 验证控制栏上一集与下一集按钮已移除
      expect(find.byIcon(Icons.skip_previous_rounded), findsNothing);
      expect(find.byIcon(Icons.skip_next_rounded), findsNothing);

      // 验证存在播放按钮与中央暂停标识
      expect(find.byIcon(Icons.play_arrow_rounded), findsNWidgets(2));

      // 验证倍速按钮在控制栏存在，点击展开验证选项已精简（倒序排布且无 0.5x 与 3.0x）
      expect(find.text('1x'), findsOneWidget);
      await tester.tap(find.text('1x'));
      await tester.pumpAndSettle();
      expect(find.text('2.0x'), findsOneWidget);
      expect(find.text('0.5x'), findsNothing);
      expect(find.text('3.0x'), findsNothing);
      expect(find.text('3x'), findsNothing);
      await tester.tap(find.text('1.25x'));
      await tester.pumpAndSettle();
      expect(controller.core.value.playbackRate, 1.25);

      // 验证选集按钮存在
      expect(find.text('选集'), findsOneWidget);

      // 设置音量为 1.0 以验证满音量面板与图标状态
      await controller.setVolume(1.0);
      await tester.pumpAndSettle();

      // 验证音量调节面板展开与无多余小喇叭
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.volume_up_rounded));
      await tester.pumpAndSettle();
      expect(find.text('100'), findsOneWidget);
      // 面板底部小喇叭已按需求移除
      expect(find.byIcon(Icons.volume_down_rounded), findsNothing);

      // 验证垂直音量槽点击调节生效（点击中间位置瞬间调节音量）
      final volume100Pos = tester.getCenter(find.text('100'));
      await tester.tapAt(Offset(volume100Pos.dx, volume100Pos.dy + 45));
      await tester.pumpAndSettle();
      expect(controller.core.value.volume, lessThan(0.9));

      // 点击屏幕任意位置收起音量面板
      await tester.tapAt(const Offset(100, 100));
      await tester.pumpAndSettle();

      // 验证全屏下存在屏幕锁定浮动按钮
      expect(find.byType(PlayerLockFloatingButton), findsOneWidget);
      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);

      // 点击选集按钮
      await tester.tap(find.text('选集'));
      await tester.pumpAndSettle();
      expect(episodePickerOpened, isTrue);

      // 点击全屏按钮
      expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.fullscreen_exit_rounded));
      await tester.pumpAndSettle();
      expect(fullscreenToggled, isTrue);
    });

    testWidgets('2. 屏幕锁定交互测试（全屏显示锁定按钮，非全屏不显示；锁定后隐藏控制栏并屏蔽手势，解锁恢复）', (tester) async {
      // 1. 非全屏状态下验证锁按钮不显示
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                title: '非全屏锁测试',
                isFullscreen: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlayerLockFloatingButton), findsNothing);

      // 2. 全屏状态下验证锁按钮显示并可正常加锁/解锁
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                title: '锁屏测试',
                isFullscreen: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击屏幕锁按钮
      await tester.tap(find.byType(PlayerLockFloatingButton));
      await tester.pumpAndSettle();

      // 此时变为已锁定图标
      expect(find.byIcon(Icons.lock_rounded), findsOneWidget);

      // 控制栏顶部与底部应被隐藏/忽略指针交互
      final topText = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text('锁屏测试'),
          matching: find.byType(AnimatedOpacity),
        ).first,
      );
      expect(topText.opacity, equals(0.0));

      // 再次点击解锁
      await tester.tap(find.byType(PlayerLockFloatingButton));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.lock_open_rounded), findsOneWidget);
      final unlockedTopText = tester.widget<AnimatedOpacity>(
        find.ancestor(
          of: find.text('锁屏测试'),
          matching: find.byType(AnimatedOpacity),
        ).first,
      );
      expect(unlockedTopText.opacity, equals(1.0));
    });

    testWidgets('3. 桌面端键盘快捷键测试（Space 切换播放/暂停，ArrowLeft/Right 快退快进，M 静音）',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                title: '快捷键测试',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.core.value.playing, isFalse);

      // 按空格键 -> 切换播放
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(controller.core.value.playing, isTrue);

      // 再次按空格键 -> 暂停
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(controller.core.value.playing, isFalse);

      // 按 M 键 -> 静音切换
      expect(controller.core.value.muted, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(controller.core.value.muted, isTrue);

      // 再次按 M 键 -> 恢复声音
      await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
      await tester.pumpAndSettle();
      expect(controller.core.value.muted, isFalse);
    });

    testWidgets('4. HUD 指示器独立渲染与外观测试', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                const PlayerVerticalLevelIndicator(
                  value: 0.75,
                  isBrightness: true,
                  visible: true,
                ),
                PlayerSeekPreviewIndicator(
                  visible: true,
                  targetPosition: const Duration(minutes: 5, seconds: 20),
                  totalDuration: const Duration(minutes: 24, seconds: 10),
                  deltaSeconds: 30,
                ),
                const PlayerSpeedHoldIndicator(
                  visible: true,
                  speed: 2.0,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证亮度百分比
      expect(find.text('75%'), findsOneWidget);
      // 验证 Seek 目标时间与增量
      expect(find.text('+30s'), findsOneWidget);
      expect(find.text('05:20'), findsOneWidget);
      // 验证倍速提示
      expect(find.text('2.0x 极速播放中'), findsOneWidget);
    });

    testWidgets('5. 播放设置面板呼出与选项联动测试（画幅比例、超分辨率、片头片尾跳过）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                title: '设置面板测试',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击控制栏设置图标 (Icons.settings_rounded)
      expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pumpAndSettle();

      // 验证设置面板展示
      expect(find.text('播放设置'), findsOneWidget);
      expect(find.text('连播与跳过'), findsOneWidget);
      expect(find.text('自动播放下一集'), findsOneWidget);
      expect(find.text('自动跳过片头片尾'), findsOneWidget);
      expect(find.text('网络与解析'), findsOneWidget);
      expect(find.text('Animaku 服务端模式'), findsOneWidget);
      expect(find.text('播放速度'), findsOneWidget);
      expect(find.text('动漫超分辨率 (Anime4K)'), findsOneWidget);
      expect(find.text('画面填充比例'), findsOneWidget);
      expect(find.text('屏幕亮度'), findsOneWidget);
      expect(find.text('亮度调节'), findsOneWidget);

      // 点击切换超分辨率至效率档
      await tester.scrollUntilVisible(find.text('效率档'), 100);
      await tester.tap(find.text('效率档'));
      await tester.pumpAndSettle();
      expect(controller.core.value.superResolution, equals(SuperResolutionMode.efficiency));

      // 点击切换画幅比例至全屏拉伸
      await tester.scrollUntilVisible(find.text('全屏拉伸'), 100);
      await tester.tap(find.text('全屏拉伸'));
      await tester.pumpAndSettle();
      expect(controller.core.value.videoFit, equals(BoxFit.fill));

      // 滚动至亮度选项并点击暗室快捷档位
      await tester.scrollUntilVisible(find.text('暗室 (30%)'), 100);
      await tester.tap(find.text('暗室 (30%)'));
      await tester.pumpAndSettle();
      expect(find.text('30%'), findsOneWidget);
    });

    testWidgets('6. 弹幕面板呼出与配置测试（非全屏直接打开弹幕面板）', (tester) async {
      final danmaku = DanmakuController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                danmakuController: danmaku,
                isFullscreen: false,
                title: '弹幕面板测试',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点击自绘弹幕设置图标 (DanmakuSettingsIcon)
      expect(find.byType(DanmakuSettingsIcon), findsOneWidget);
      await tester.tap(find.byType(DanmakuSettingsIcon));
      await tester.pumpAndSettle();

      // 验证弹幕面板内容展现
      expect(find.text('弹幕设置'), findsOneWidget);
      expect(find.text('智能精简'), findsOneWidget);
      expect(find.text('屏蔽彩色弹幕'), findsOneWidget);
      expect(find.text('显示范围'), findsOneWidget);
    });
  });
}
