/// 播放器宏观状态与核心视图状态模型
///
/// 遵循 docs/player-rewrite/03-state-machine.md (v3.1) 与 docs/player-rewrite/05-interfaces-and-contracts.md (v3)
library;

import 'package:flutter/foundation.dart';

/// 播放器宏观状态枚举
///
/// 严格由 11 个业务状态 + 1 个销毁终态（共 12 个互斥状态）组成
enum PlaybackState {
  /// 初始空闲态：无活跃媒体会话
  idle,

  /// 直链解析态：正在解析分集直链与鉴权头
  resolving,

  /// 底层初始化态：直链就绪，向底层发送 open 指令，等待底层完成 IPC 派发
  preparing,

  /// 首帧前初始缓冲态：底层建联拉流中，受 12 秒看门狗与 5 秒换线提示守护
  prebuffering,

  /// 正常播放态：物理首帧已渲染出画，播放时钟正常推进
  playing,

  /// 暂停态：画面定格在当前帧
  paused,

  /// 寻道态：已向底层发起 seek，等待底层重定位出新帧
  seeking,

  /// 中途卡顿缓冲态：首帧已出画，播放中网络波动导致解复用缓冲区水位过低
  rebuffering,

  /// 自动恢复态：发生可恢复异常，退避重试或刷新直链中
  recovering,

  /// 自然播放完毕：播放进度接近总时长且收到有效自然 EOF
  completed,

  /// 致命错误态：错误不可自动恢复或重试总预算耗尽，呈现错误卡片等待用户干预
  error,

  /// 终态：会话彻底销毁，拒绝响应除状态查询外的任何事件
  disposed;

  /// 该状态是否处于活跃播放会话中（非 idle 且非 disposed）
  bool get isActive => this != PlaybackState.idle && this != PlaybackState.disposed;

  /// 该状态是否为终态
  bool get isDisposed => this == PlaybackState.disposed;
}

/// 播放器低频核心状态（供 UI 层监听使用）
///
/// 依据修订要求，loading / playing / buffering / completed / hasError 统一由 [PlaybackState] 派生生成，杜绝独立存放。
@immutable
class PlaybackCoreState {
  const PlaybackCoreState({
    required this.state,
    this.firstFrameRendered = false,
    this.errorMessage,
  });

  /// 当前宏观状态枚举
  final PlaybackState state;

  /// 新视频首帧是否已渲染出画
  final bool firstFrameRendered;

  /// 错误提示文案（仅在 state == error 时非空）
  final String? errorMessage;

  /// 是否处于加载阶段 (resolving, preparing, recovering)
  bool get loading =>
      state == PlaybackState.resolving ||
      state == PlaybackState.preparing ||
      state == PlaybackState.recovering;

  /// 是否正在播放 (playing)
  bool get playing => state == PlaybackState.playing;

  /// 是否正在缓冲卡顿 (prebuffering, rebuffering, seeking)
  bool get buffering =>
      state == PlaybackState.prebuffering ||
      state == PlaybackState.rebuffering ||
      state == PlaybackState.seeking;

  /// 是否播放完毕 (completed)
  bool get completed => state == PlaybackState.completed;

  /// 是否发生错误 (error)
  bool get hasError => state == PlaybackState.error;

  /// 基于 PlaybackState 映射生成
  factory PlaybackCoreState.fromState(
    PlaybackState state, {
    bool firstFrameRendered = false,
    String? errorMessage,
  }) {
    return PlaybackCoreState(
      state: state,
      firstFrameRendered: firstFrameRendered,
      errorMessage: errorMessage,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaybackCoreState &&
        other.state == state &&
        other.firstFrameRendered == firstFrameRendered &&
        other.errorMessage == errorMessage;
  }

  @override
  int get hashCode => Object.hash(state, firstFrameRendered, errorMessage);

  @override
  String toString() =>
      'PlaybackCoreState(state: $state, loading: $loading, playing: $playing, buffering: $buffering, completed: $completed, firstFrameRendered: $firstFrameRendered, hasError: $hasError)';
}
