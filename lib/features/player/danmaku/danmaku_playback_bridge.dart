import 'dart:async';

import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/danmaku/core/danmaku_controller.dart';

/// 播放器内核与弹幕状态机的单向响应式解耦同步桥接器
///
/// 架构设计说明：
/// 1. 彻底解耦 ZakowayPlaybackController 与 DanmakuController，播放控制器不再直接持有弹幕实例；
/// 2. 单向监听 ZakowayPlaybackController 的 core、timeline 与 onSeek 事件流，按需驱动弹幕时钟、寻道与启停；
/// 3. 随宿主生命周期销毁（优先于 Controller 销毁）：在 dispose() 中立即解除所有监听，
///    从根本上阻断任何后台异步 IPC / 微任务对已销毁弹幕控制器的非法反冲调用。
class DanmakuPlaybackBridge {
  DanmakuPlaybackBridge({
    required this.playbackController,
    required this.danmakuController,
  }) {
    playbackController.core.addListener(_onCoreChanged);
    playbackController.timeline.addListener(_onTimelineChanged);
    _seekSubscription = playbackController.onSeek.listen(_onSeek);

    // 初始状态同步
    danmakuController.setPlaybackRate(playbackController.core.value.playbackRate);
    _syncDanmakuRunningState();
  }

  final ZakowayPlaybackController playbackController;
  final DanmakuController danmakuController;
  StreamSubscription<Duration>? _seekSubscription;
  bool _disposed = false;

  bool get isDisposed => _disposed;

  void _onSeek(Duration target) {
    if (_disposed) return;
    danmakuController.seek(target);
  }

  void _onCoreChanged() {
    if (_disposed) return;
    danmakuController.setPlaybackRate(playbackController.core.value.playbackRate);
    _syncDanmakuRunningState();
  }

  void _onTimelineChanged() {
    if (_disposed) return;
    danmakuController.syncTime(playbackController.extrapolatedPosition);
  }

  void _syncDanmakuRunningState() {
    if (_disposed) return;
    final core = playbackController.core.value;
    final shouldRun = core.playing &&
        core.firstFrameRendered &&
        !core.loading &&
        !core.buffering &&
        !core.completed;

    if (shouldRun) {
      danmakuController.resume();
    } else {
      danmakuController.pause();
    }
  }

  /// 立即注销监听器并切断同步通道
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _seekSubscription?.cancel();
    _seekSubscription = null;
    playbackController.core.removeListener(_onCoreChanged);
    playbackController.timeline.removeListener(_onTimelineChanged);
  }
}
