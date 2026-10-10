import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';

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

    test('控制器 dispose 后资源与定时器安全销毁', () async {
      await controller.dispose();
      expect(controller.isDisposed, isTrue);
    });
  });
}
