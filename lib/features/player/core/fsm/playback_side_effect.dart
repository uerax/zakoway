/// 状态机纯转移函数派发的副作用描述模型
///
/// 遵循 docs/player-rewrite/03-state-machine.md (v3.1)
/// 纯数据结构，描述状态机对外产生的操作意图，不含任何执行逻辑。
library;

import 'package:flutter/foundation.dart';
import '../models/playback_failure.dart';

/// 副作用意图基类
@immutable
sealed class PlaybackSideEffect {
  const PlaybackSideEffect();
}

/// 调用底层 open 接口
class CallBackendOpenEffect extends PlaybackSideEffect {
  const CallBackendOpenEffect({
    required this.url,
    this.start,
    this.autoplay = true,
    this.headers,
  });

  final String url;
  final Duration? start;
  final bool autoplay;
  final Map<String, String>? headers;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallBackendOpenEffect &&
          other.url == url &&
          other.start == start &&
          other.autoplay == autoplay &&
          mapEquals(other.headers, headers);

  @override
  int get hashCode => Object.hash(url, start, autoplay);

  @override
  String toString() =>
      'CallBackendOpen(url: $url, start: $start, autoplay: $autoplay)';
}

/// 调用底层 play 接口
class CallBackendPlayEffect extends PlaybackSideEffect {
  const CallBackendPlayEffect();

  @override
  bool operator ==(Object other) => other is CallBackendPlayEffect;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'CallBackendPlay';
}

/// 调用底层 pause 接口
class CallBackendPauseEffect extends PlaybackSideEffect {
  const CallBackendPauseEffect();

  @override
  bool operator ==(Object other) => other is CallBackendPauseEffect;

  @override
  int get hashCode => 2;

  @override
  String toString() => 'CallBackendPause';
}

/// 调用底层 seek 接口
class CallBackendSeekEffect extends PlaybackSideEffect {
  const CallBackendSeekEffect(this.position);

  final Duration position;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CallBackendSeekEffect && other.position == position;

  @override
  int get hashCode => position.hashCode;

  @override
  String toString() => 'CallBackendSeek(pos: $position)';
}

/// 调用底层 dispose 接口
class CallBackendDisposeEffect extends PlaybackSideEffect {
  const CallBackendDisposeEffect();

  @override
  bool operator ==(Object other) => other is CallBackendDisposeEffect;

  @override
  int get hashCode => 3;

  @override
  String toString() => 'CallBackendDispose';
}

/// 发起直链解析请求
class ResolveMediaEffect extends PlaybackSideEffect {
  const ResolveMediaEffect({required this.bypassCache});

  final bool bypassCache;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolveMediaEffect && other.bypassCache == bypassCache;

  @override
  int get hashCode => bypassCache.hashCode;

  @override
  String toString() => 'ResolveMedia(bypassCache: $bypassCache)';
}

/// 向选源层/UI层对外暴露失败事实与可用操作
class EmitFailureEffect extends PlaybackSideEffect {
  const EmitFailureEffect(this.failure);

  final PlaybackFailure failure;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmitFailureEffect && other.failure == failure;

  @override
  int get hashCode => failure.hashCode;

  @override
  String toString() => 'EmitFailure(${failure.kind})';
}

/// 取消所有进行中的定时器（首帧看门狗、退避定时器等）
class CancelTimersEffect extends PlaybackSideEffect {
  const CancelTimersEffect();

  @override
  bool operator ==(Object other) => other is CancelTimersEffect;

  @override
  int get hashCode => 4;

  @override
  String toString() => 'CancelTimers';
}
