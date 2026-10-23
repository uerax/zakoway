import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DanmakuPlaybackBridge 解耦响应式同步测试', () {
    late ZakowayPlaybackController playback;
    late DanmakuController danmaku;
    late DanmakuPlaybackBridge bridge;

    setUp(() {
      playback = ZakowayPlaybackController();
      danmaku = DanmakuController();
      bridge = DanmakuPlaybackBridge(
        playbackController: playback,
        danmakuController: danmaku,
      );
    });

    tearDown(() async {
      bridge.dispose();
      await playback.dispose();
      danmaku.dispose();
    });

    test('初始倍速与状态正常同步', () {
      expect(danmaku.playbackRate, equals(1.0));
      expect(danmaku.playing, isFalse);
    });

    test('倍速变更通过 core 自动同步至弹幕', () async {
      await playback.setPlaybackRate(1.5);
      expect(danmaku.playbackRate, equals(1.5));
    });

    test('播放与首帧就绪状态流转驱动弹幕 resume / pause', () {
      // 仅 playing 为 true 但未出首帧：弹幕不启动
      playback.core.value = playback.core.value.copyWith(
        playing: true,
        firstFrameRendered: false,
        loading: false,
        buffering: false,
      );
      expect(danmaku.playing, isFalse);

      // 首帧已就绪且播放中：弹幕正常起跑
      playback.core.value = playback.core.value.copyWith(
        firstFrameRendered: true,
      );
      expect(danmaku.playing, isTrue);

      // 缓冲卡顿：弹幕暂停
      playback.core.value = playback.core.value.copyWith(
        buffering: true,
      );
      expect(danmaku.playing, isFalse);

      // 缓冲恢复：弹幕恢复
      playback.core.value = playback.core.value.copyWith(
        buffering: false,
      );
      expect(danmaku.playing, isTrue);
    });

    test('播放器 seek 显式联动弹幕 seek', () async {
      Duration? seekTarget;
      danmaku.attach(_MockDanmakuListener(onSeek: (pos) => seekTarget = pos));

      await playback.seek(const Duration(seconds: 45));
      expect(seekTarget, equals(const Duration(seconds: 45)));
    });

    test('bridge.dispose() 后彻底切断同步，即便 playback 后续状态突变也绝不调用 danmaku', () async {
      // 先确认正常联动
      playback.core.value = playback.core.value.copyWith(
        playing: true,
        firstFrameRendered: true,
        loading: false,
        buffering: false,
      );
      expect(danmaku.playing, isTrue);

      // 销毁桥接器
      bridge.dispose();
      expect(bridge.isDisposed, isTrue);

      // 模拟页面退出：danmaku 已经 dispose
      danmaku.dispose();
      expect(danmaku.isDisposed, isTrue);

      // 此时无论 playback 触发暂停、seek、倍速还是继续抛流事件，桥接器都已注销，danmaku 绝不被调用
      await playback.setPlaybackRate(2.0);
      await playback.pause();
      playback.core.value = playback.core.value.copyWith(playing: false);
      playback.timeline.value = playback.timeline.value.copyWith(
        position: const Duration(seconds: 100),
      );

      // 没有抛出 FlutterError: A DanmakuController was used after being disposed
      expect(true, isTrue);
    });
  });
}

class _MockDanmakuListener implements DanmakuListener {
  _MockDanmakuListener({this.onSeek});

  final void Function(Duration pos)? onSeek;

  @override
  void onDanmakuTimeSync(Duration position) {}

  @override
  void onDanmakuSeek(Duration position) {
    onSeek?.call(position);
  }

  @override
  void onDanmakuPlaybackRateChanged(double rate) {}

  @override
  void onDanmakuItemsChanged() {}

  @override
  void onDanmakuInject(DanmakuItem item) {}

  @override
  void onDanmakuSettingsChanged(DanmakuSettings next, DanmakuSettings previous) {}

  @override
  void onDanmakuPause() {}

  @override
  void onDanmakuResume() {}

  @override
  void onDanmakuReset() {}
}
