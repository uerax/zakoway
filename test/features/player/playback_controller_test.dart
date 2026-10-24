import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/core/fsm/playback_event.dart';
import 'package:zakoway/features/player/core/fsm/playback_fsm_context.dart';
import 'package:zakoway/features/player/core/fsm/playback_side_effect.dart';
import 'package:zakoway/features/player/core/fsm/playback_transition.dart';
import 'package:zakoway/features/player/core/models/playback_state.dart' as core_state;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ZakowayPlaybackController 状态与控制测试', () {
    late ZakowayPlaybackController controller;

    setUp(() {
      controller = ZakowayPlaybackController();
    });

    tearDown(() async {
      await controller.dispose();
    });

    test('初始状态值校验', () {
      final core = controller.core.value;
      final timeline = controller.timeline.value;

      expect(core.playing, isFalse);
      expect(core.loading, isTrue);
      expect(core.buffering, isFalse);
      expect(core.playbackRate, equals(1.0));
      expect(core.volume, equals(0.5));
      expect(core.muted, isFalse);

      expect(timeline.position, equals(Duration.zero));
      expect(timeline.duration, equals(Duration.zero));
      expect(timeline.previewPosition, isNull);
    });

    test('拖拽 Seek 预览状态流转测试', () async {
      expect(controller.timeline.value.isSeekingPreview, isFalse);

      // 用户拖动滑块至 30 秒处
      controller.updateSeekPreview(const Duration(seconds: 30));

      expect(controller.timeline.value.isSeekingPreview, isTrue);
      expect(
        controller.timeline.value.displayPosition,
        equals(const Duration(seconds: 30)),
      );

      // 松开滑块，预览位置被重置，真实 position 被更新
      await controller.endSeekPreview();
      expect(controller.timeline.value.isSeekingPreview, isFalse);
      expect(
        controller.timeline.value.position,
        equals(const Duration(seconds: 30)),
      );
    });

    test('音量调整与静音切换测试', () async {
      expect(controller.core.value.muted, isFalse);
      expect(controller.core.value.volume, equals(0.5));

      // 设置音量为 80%
      await controller.setVolume(0.8);
      expect(controller.core.value.volume, equals(0.8));
      expect(controller.core.value.muted, isFalse);

      // 切换静音
      await controller.toggleMute();
      expect(controller.core.value.muted, isTrue);
      expect(controller.core.value.volume, equals(0.0));

      // 取消静音，恢复之前的 80% 音量
      await controller.toggleMute();
      expect(controller.core.value.muted, isFalse);
      expect(controller.core.value.volume, equals(0.8));
    });

    test('Seek 操作主动清除偶发错误状态', () async {
      // 模拟先前产生的偶发错误
      controller.core.value = controller.core.value.copyWith(
        errorMessage: 'Some transient network error',
      );
      expect(controller.core.value.hasError, isTrue);

      // 用户触发 Seek
      await controller.seek(const Duration(seconds: 45));

      // 验证错误已被清除
      expect(controller.core.value.hasError, isFalse);
      expect(controller.core.value.errorMessage, isNull);
    });

    test('自适应分级网络状态字段与拷贝流转测试', () {
      expect(controller.core.value.isMeteredNetwork, isFalse);

      controller.core.value = controller.core.value.copyWith(
        isMeteredNetwork: true,
      );
      expect(controller.core.value.isMeteredNetwork, isTrue);

      controller.core.value = controller.core.value.copyWith(
        isMeteredNetwork: false,
      );
      expect(controller.core.value.isMeteredNetwork, isFalse);
    });

    test('Seek 越界边界保护截断测试', () async {
      // 模拟视频总时长为 100 秒
      controller.timeline.value = controller.timeline.value.copyWith(
        duration: const Duration(seconds: 100),
      );

      // 用户拖到最右边 100 秒处
      await controller.seek(const Duration(seconds: 100));

      // 验证自动预留 500ms 截断保护，防止命中 EOF
      expect(
        controller.timeline.value.position,
        equals(const Duration(milliseconds: 99500)),
      );
    });

    test('首帧渲染状态流转与切集重置保护测试', () {
      // 1. 初始状态：首帧未渲染就绪
      expect(controller.core.value.firstFrameRendered, isFalse);

      // 2. 模拟新视频首帧渲染就绪
      controller.core.value = controller.core.value.copyWith(
        firstFrameRendered: true,
        loading: false,
      );
      expect(controller.core.value.firstFrameRendered, isTrue);
      expect(controller.core.value.loading, isFalse);

      // 3. 模拟切集：打开新视频流时，必须重新重置为 false，触发黑色遮罩防闪
      controller.core.value = controller.core.value.copyWith(
        loading: true,
        firstFrameRendered: false,
      );
      expect(controller.core.value.firstFrameRendered, isFalse);
      expect(controller.core.value.loading, isTrue);
    });

    test('控制器 stop 操作将播放器状态与时间线完全重置为空闲出画等待态', () async {
      // 模拟先前的播放状态：正在播放、首帧已出画、有进度
      controller.core.value = controller.core.value.copyWith(
        playing: true,
        loading: false,
        firstFrameRendered: true,
      );
      controller.timeline.value = controller.timeline.value.copyWith(
        position: const Duration(minutes: 12),
        duration: const Duration(minutes: 24),
      );

      // 调用 stop
      await controller.stop();

      // 验证状态重置为 loading 态且首帧出画标记为 false，时间线清空
      expect(controller.core.value.playing, isFalse);
      expect(controller.core.value.loading, isTrue);
      expect(controller.core.value.firstFrameRendered, isFalse);
      expect(controller.core.value.hasError, isFalse);
      expect(controller.timeline.value.position, equals(Duration.zero));
      expect(controller.timeline.value.duration, equals(Duration.zero));
    });

    test('控制器 dispose 后资源与定时器安全销毁', () async {
      await controller.dispose();
      expect(controller.isDisposed, isTrue);
    });

    test('状态机在 Error 状态下检测到物理出画时自愈迁移至 Playing 且清除错误', () {
      // 模拟先前进入 error 状态，但底层随后成功输出了物理画面尺寸与播放位移
      const context = PlaybackFsmContext(
        hasValidDimensions: true,
        hasPositionAdvanced: true,
        autoplay: true,
      );

      final result = evaluateTransition(
        currentState: core_state.PlaybackState.error,
        context: context,
        event: const FirstFrameRenderedEvent(),
      );

      expect(result.targetState, equals(core_state.PlaybackState.playing));
      expect(result.nextContext.firstFrameRendered, isTrue);
      expect(result.nextContext.lastFailure, isNull);
    });

    test('isPreResolved=true 直通跳过 resolving 状态直达 preparing 并触发底层 open', () {
      const context = PlaybackFsmContext();
      const event = LoadRequestEvent(
        uri: 'https://example.com/video.mp4',
        isPreResolved: true,
        autoplay: true,
      );

      final result = evaluateTransition(
        currentState: core_state.PlaybackState.idle,
        context: context,
        event: event,
      );

      // 验证直接流转至 preparing，且 sideEffects 包含 CallBackendOpenEffect
      expect(result.targetState, equals(core_state.PlaybackState.preparing));
      expect(result.nextContext.resolvedUrl, equals('https://example.com/video.mp4'));
      expect(
        result.sideEffects.any((e) => e is CallBackendOpenEffect),
        isTrue,
      );
    });
  });
}
