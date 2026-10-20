/// 状态机上下文模型（不可变数据容器）
///
/// 遵循 docs/player-rewrite/03-state-machine.md (v3.1)
library;

import 'package:flutter/foundation.dart';
import '../models/playback_failure.dart';
import '../models/playback_state.dart';

/// 状态机运行上下文
@immutable
class PlaybackFsmContext {
  const PlaybackFsmContext({
    this.attemptId = 0,
    this.generationId = 0,
    this.currentUri,
    this.resolvedUrl,
    this.headers,
    this.initialResumePosition,
    this.currentPosition = Duration.zero,
    this.totalDuration = Duration.zero,
    this.autoplay = true,
    this.targetPhaseAfterFirstFrame,
    this.phaseBeforeSeeking = PlaybackState.playing,
    this.pendingSeekPosition,
    this.realVideoTrackCount = 1,
    this.recoveryAttempts = 0,
    this.lastEofPosition,
    this.eofRecoveryCount = 0,
    this.lastFailure,
    this.firstFrameRendered = false,
    this.hasValidDimensions = false,
    this.hasPositionAdvanced = false,
  });

  /// Dart 异步调度 Attempt ID
  final int attemptId;

  /// 底层物理代际 ID
  final int generationId;

  /// 请求播放的逻辑 URI（如番剧播放页地址或直链）
  final String? currentUri;

  /// 真实解析出的媒体直链
  final String? resolvedUrl;

  /// 媒体请求头
  final Map<String, String>? headers;

  /// 初始续播/断点位置
  final Duration? initialResumePosition;

  /// 当前播放进度位置
  final Duration currentPosition;

  /// 当前视频总时长
  final Duration totalDuration;

  /// 用户初始起播意图（是否自动起播）
  final bool autoplay;

  /// prebuffering 阶段排队的起播目标态（若收到 PauseRequest，首帧后应转 paused）
  final PlaybackState? targetPhaseAfterFirstFrame;

  /// 进入 seeking 之前的基态 (playing 或 paused)
  final PlaybackState phaseBeforeSeeking;

  /// prebuffering / recovering 期间排队的 Seek 目标位置
  final Duration? pendingSeekPosition;

  /// 真实视频轨数（适配层已排除 auto/no 伪轨），== 0 为纯音频
  final int realVideoTrackCount;

  /// 当前已重试自愈次数
  final int recoveryAttempts;

  /// 上一次记录的异常 EOF 位置
  final Duration? lastEofPosition;

  /// 异常 EOF 已自愈次数
  final int eofRecoveryCount;

  /// 最近一次派发的失败实体
  final PlaybackFailure? lastFailure;

  /// 首帧是否已出画
  final bool firstFrameRendered;

  /// 底层画面尺寸是否有效 (width > 0 && height > 0)
  final bool hasValidDimensions;

  /// 底层播放进度是否已推进 (position > 0)
  final bool hasPositionAdvanced;

  /// 是否为纯音频媒体
  bool get isAudioOnly => realVideoTrackCount == 0;

  PlaybackFsmContext copyWith({
    int? attemptId,
    int? generationId,
    String? currentUri,
    String? resolvedUrl,
    Map<String, String>? headers,
    Duration? initialResumePosition,
    Duration? currentPosition,
    Duration? totalDuration,
    bool? autoplay,
    PlaybackState? targetPhaseAfterFirstFrame,
    bool clearTargetPhaseAfterFirstFrame = false,
    PlaybackState? phaseBeforeSeeking,
    Duration? pendingSeekPosition,
    bool clearPendingSeekPosition = false,
    int? realVideoTrackCount,
    int? recoveryAttempts,
    Duration? lastEofPosition,
    int? eofRecoveryCount,
    PlaybackFailure? lastFailure,
    bool? firstFrameRendered,
    bool? hasValidDimensions,
    bool? hasPositionAdvanced,
  }) {
    return PlaybackFsmContext(
      attemptId: attemptId ?? this.attemptId,
      generationId: generationId ?? this.generationId,
      currentUri: currentUri ?? this.currentUri,
      resolvedUrl: resolvedUrl ?? this.resolvedUrl,
      headers: headers ?? this.headers,
      initialResumePosition:
          initialResumePosition ?? this.initialResumePosition,
      currentPosition: currentPosition ?? this.currentPosition,
      totalDuration: totalDuration ?? this.totalDuration,
      autoplay: autoplay ?? this.autoplay,
      targetPhaseAfterFirstFrame: clearTargetPhaseAfterFirstFrame
          ? null
          : (targetPhaseAfterFirstFrame ?? this.targetPhaseAfterFirstFrame),
      phaseBeforeSeeking: phaseBeforeSeeking ?? this.phaseBeforeSeeking,
      pendingSeekPosition: clearPendingSeekPosition
          ? null
          : (pendingSeekPosition ?? this.pendingSeekPosition),
      realVideoTrackCount: realVideoTrackCount ?? this.realVideoTrackCount,
      recoveryAttempts: recoveryAttempts ?? this.recoveryAttempts,
      lastEofPosition: lastEofPosition ?? this.lastEofPosition,
      eofRecoveryCount: eofRecoveryCount ?? this.eofRecoveryCount,
      lastFailure: lastFailure ?? this.lastFailure,
      firstFrameRendered: firstFrameRendered ?? this.firstFrameRendered,
      hasValidDimensions: hasValidDimensions ?? this.hasValidDimensions,
      hasPositionAdvanced: hasPositionAdvanced ?? this.hasPositionAdvanced,
    );
  }

  /// 创建初始上下文
  static const PlaybackFsmContext initial = PlaybackFsmContext();
}
