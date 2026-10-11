import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/controller/playback_state.dart';
import 'package:zakoway/features/player/widgets/controls/controls_bottom_bar.dart';
import 'package:zakoway/features/player/widgets/video_player_placeholder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('播放器断点续播与错误卡片防溢出测试', () {
    late ZakowayPlaybackController controller;

    setUp(() {
      controller = ZakowayPlaybackController();
    });

    tearDown(() async {
      await controller.dispose();
    });

    test('1. cleanErrorMessage 正确清洗提炼 Dio 403 异常文本', () {
      const raw403 =
          'DioException [bad response]: This exception was thrown because the response has a status code of 403 and RequestOptions.validateStatus was configured to throw for this status code. The status code of 403 has the following meaning: "Client error - the request contains bad syntax or cannot be fulfilled" Read more about status codes at https://developer.mozilla.org/en-US/docs/Web/HTTP/Status In order to resolve this exception you typically have either to verify and fix your request code or you have to fix the server code.';
      final cleaned = cleanErrorMessage(raw403, prefix: '播放解析失败');
      expect(cleaned.contains('https://'), isFalse);
      expect(cleaned.contains('RequestOptions'), isFalse);
      expect(cleaned, contains('播放解析失败: 视频源请求被拒绝 (HTTP 403)'));
    });

    testWidgets('2. 控制栏时间戳在视频未就绪(duration=0)时强制显示为 00:00 / 00:00',
        (tester) async {
      // 模拟断点续播 position 为 4分26秒，但底层媒体尚未就绪 (duration = 0)
      controller.timeline.value = const PlaybackTimelineState(
        position: Duration(minutes: 4, seconds: 26),
        duration: Duration.zero,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 200,
              child: PlayerControlsBottomBar(
                controller: controller,
                primaryColor: Colors.blue,
                onUserInteraction: () {},
                onToggleFullscreen: () {},
                onToggleSpeedPopup: () {},
                onToggleVolumeSlider: () {},
                onOpenSettingsPanel: () {},
                onOpenDanmakuPanel: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // 验证未就绪时不显示 04:26 / 00:00，而是防倒挂显示 00:00 / 00:00
      expect(find.text('04:26 / 00:00'), findsNothing);
      expect(find.text('00:00 / 00:00'), findsOneWidget);
    });

    testWidgets('3. 竖屏紧凑高度(220dp)下长错误文本不发生 RenderFlex 溢出且按钮可点击',
        (tester) async {
      bool retried = false;
      bool switched = false;

      final errors = <FlutterErrorDetails>[];
      final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details);

      const superLongError =
          'DioException [bad response]: This exception was thrown because the response has a status code of 403 and RequestOptions.validateStatus was configured to throw for this status code. The status code of 403 has the following meaning: "Client error - the request contains bad syntax or cannot be fulfilled" Read more about status codes at https://developer.mozilla.org/en-US/docs/Web/HTTP/Status In order to resolve this exception you typically have either to verify and fix your request code or you have to fix the server code. Extra padding text to simulate extreme long error message for overflow stress testing.';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 220, // 典型竖屏 16:9 紧凑播放器高度
              child: VideoPlayerResolveErrorCard(
                errorText: superLongError,
                primaryColor: Colors.cyan,
                onRetry: () => retried = true,
                onSwitchSource: () => switched = true,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      FlutterError.onError = oldHandler;
      // 验证绝无任何渲染溢出错误
      expect(errors, isEmpty);

      // 验证重试与切换视频源按钮完全可见且可点击
      final retryBtn = find.text('重试');
      final switchBtn = find.text('切换视频源');
      expect(retryBtn, findsOneWidget);
      expect(switchBtn, findsOneWidget);

      await tester.tap(retryBtn);
      await tester.pump();
      expect(retried, isTrue);

      await tester.tap(switchBtn);
      await tester.pump();
      expect(switched, isTrue);
    });
  });
}
