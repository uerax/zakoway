/// 状态机输入事件体系
///
/// 严格遵循 docs/player-rewrite/03-state-machine.md (v3.1) 第四节全矩阵定义
/// 涵盖 10 个外部控制事件与 9 个内部生命周期事件
library;

import '../models/backend_error.dart';

/// 状态机事件基类（使用 sealed 保证全覆盖无遗漏）
sealed class PlaybackEvent {
  const PlaybackEvent();
}

// =============================================================================
// 外部控制指令与底层基础属性变化事件 (03 第 4 节决策矩阵 10 大事件)
// =============================================================================

/// 用户发起加载/切集媒体请求 (LOAD_REQ)
class LoadRequestEvent extends PlaybackEvent {
  const LoadRequestEvent({
    required this.uri,
    this.startPosition,
    this.autoplay = true,
    this.headers,
    this.isPreResolved = false,
  });

  final String uri;
  final Duration? startPosition;
  final bool autoplay;
  final Map<String, String>? headers;

  /// 标记传入的 uri 是否已经为解析完成的可用直链
  /// 若为 true，状态机直接跳过 resolving 状态与二次网络请求，0ms 派发底层 open
  final bool isPreResolved;

  @override
  String toString() =>
      'LoadRequest(uri: $uri, start: $startPosition, autoplay: $autoplay, preResolved: $isPreResolved)';
}

/// 用户发起暂停请求 (PAUSE_REQ)
class PauseRequestEvent extends PlaybackEvent {
  const PauseRequestEvent();

  @override
  String toString() => 'PauseRequest';
}

/// 用户发起恢复播放请求 (PLAY_REQ)
class PlayRequestEvent extends PlaybackEvent {
  const PlayRequestEvent();

  @override
  String toString() => 'PlayRequest';
}

/// 用户发起寻道请求 (SEEK_REQ)
class SeekRequestEvent extends PlaybackEvent {
  const SeekRequestEvent(this.position);

  final Duration position;

  @override
  String toString() => 'SeekRequest(pos: $position)';
}

/// 底层派发致命错误事件 (FATAL_ERR)
class FatalErrorReceivedEvent extends PlaybackEvent {
  const FatalErrorReceivedEvent(this.error);

  final BackendError error;

  @override
  String toString() => 'FatalErrorReceived(${error.kind})';
}

/// 底层缓冲状态变为正在缓冲 (BUFF_TRUE)
class BufferingStartedEvent extends PlaybackEvent {
  const BufferingStartedEvent();

  @override
  String toString() => 'BufferingStarted';
}

/// 底层缓冲状态变为缓冲结束 (BUFF_FALSE)
class BufferingEndedEvent extends PlaybackEvent {
  const BufferingEndedEvent();

  @override
  String toString() => 'BufferingEnded';
}

/// 首帧物理出画或有证据超时放行事件 (FRAME_OK)
class FirstFrameRenderedEvent extends PlaybackEvent {
  const FirstFrameRenderedEvent();

  @override
  String toString() => 'FirstFrameRendered';
}

/// 收到播放完毕或 EOF 信号 (COMPLETED)
class CompletedReceivedEvent extends PlaybackEvent {
  const CompletedReceivedEvent({
    required this.currentPosition,
    required this.duration,
  });

  final Duration currentPosition;
  final Duration duration;

  @override
  String toString() =>
      'CompletedReceived(pos: $currentPosition, dur: $duration)';
}

/// 彻底销毁请求 (DISPOSE)
class DisposeRequestEvent extends PlaybackEvent {
  const DisposeRequestEvent();

  @override
  String toString() => 'DisposeRequest';
}

// =============================================================================
// 内部生命周期事件 (03 第 4.2 节内部事件矩阵 9 大事件)
// =============================================================================

/// 直链解析成功 (RESOLVE_OK)
class ResolveSuccessEvent extends PlaybackEvent {
  const ResolveSuccessEvent({
    required this.url,
    this.headers = const {},
  });

  final String url;
  final Map<String, String> headers;

  @override
  String toString() => 'ResolveSuccess(url: $url)';
}

/// 直链解析失败 (RESOLVE_FAIL)
class ResolveFailureEvent extends PlaybackEvent {
  const ResolveFailureEvent(this.error);

  final String error;

  @override
  String toString() => 'ResolveFailure($error)';
}

/// 底层 open IPC 派发成功 (BACKEND_OK)
class BackendDispatchedEvent extends PlaybackEvent {
  const BackendDispatchedEvent(this.generationId);

  final int generationId;

  @override
  String toString() => 'BackendDispatched(gen: $generationId)';
}

/// 首帧 12 秒硬上限超时 (FIRST_FRAME_TO)
class FirstFrameTimeoutEvent extends PlaybackEvent {
  const FirstFrameTimeoutEvent({required this.hasLivenessProof});

  /// 是否具备存活证据（纯音频或时钟已走）
  final bool hasLivenessProof;

  @override
  String toString() => 'FirstFrameTimeout(hasProof: $hasLivenessProof)';
}

/// 打开阶段解复用 12 秒看门狗熔断 (WATCHDOG_TO)
class OpenDemuxWatchdogTimeoutEvent extends PlaybackEvent {
  const OpenDemuxWatchdogTimeoutEvent();

  @override
  String toString() => 'OpenDemuxWatchdogTimeout';
}

/// 中途卡顿缓冲超时 (BUFFER_TO)
class BufferingTimeoutEvent extends PlaybackEvent {
  const BufferingTimeoutEvent();

  @override
  String toString() => 'BufferingTimeout';
}

/// 恢复状态 500ms 退避计时结束 (RECOVERY_TIMER)
class RecoveryTimerExpiredEvent extends PlaybackEvent {
  const RecoveryTimerExpiredEvent();

  @override
  String toString() => 'RecoveryTimerExpired';
}

/// 寻道出新帧完成 (SEEK_DONE)
class SeekAcknowledgedEvent extends PlaybackEvent {
  const SeekAcknowledgedEvent(this.newPosition);

  final Duration newPosition;

  @override
  String toString() => 'SeekAcknowledged(pos: $newPosition)';
}

/// 用户在错误或恢复界面点击重试 (RETRY_REQ)
class RetryRequestEvent extends PlaybackEvent {
  const RetryRequestEvent();

  @override
  String toString() => 'RetryRequest';
}
