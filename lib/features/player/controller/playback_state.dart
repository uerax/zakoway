import 'package:flutter/material.dart';

/// 动漫超分辨率画质增强模式 (基于 Anime4K 着色器)
enum SuperResolutionMode {
  off(
    storageValue: 1,
    label: '关闭',
    description: '原画输出',
  ),
  efficiency(
    storageValue: 2,
    label: '效率档',
    description: '轻度降噪与快速超分',
  ),
  quality(
    storageValue: 3,
    label: '质量档',
    description: '高质量 CNN 重建超分',
  );

  const SuperResolutionMode({
    required this.storageValue,
    required this.label,
    required this.description,
  });

  final int storageValue;
  final String label;
  final String description;

  static SuperResolutionMode fromStorageValue(int? value) {
    if (value == null) return SuperResolutionMode.off;
    return SuperResolutionMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => SuperResolutionMode.off,
    );
  }
}

/// 播放器低频核心状态（仅在宏观状态变化时触发更新）
@immutable
class PlaybackCoreState {
  const PlaybackCoreState({
    this.playing = false,
    this.loading = true,
    this.buffering = false,
    this.completed = false,
    this.firstFrameRendered = false,
    this.playbackRate = 1.0,
    this.volume = 0.5,
    this.muted = false,
    this.videoFit = BoxFit.contain,
    this.superResolution = SuperResolutionMode.off,
    this.isMeteredNetwork = false,
    this.errorMessage,
  });

  /// 是否正在播放
  final bool playing;

  /// 是否处于首次加载或切集加载状态
  final bool loading;

  /// 是否正在缓冲卡顿
  final bool buffering;

  /// 视频是否已播放完毕
  final bool completed;

  /// 新视频首帧是否已渲染就绪（用于切集时遮蔽前一集最后一帧画面，杜绝残影闪烁）
  final bool firstFrameRendered;

  /// 播放倍速 (0.5 ~ 3.0)
  final double playbackRate;

  /// 音量大小 (0.0 ~ 1.0)
  final double volume;

  /// 是否静音
  final bool muted;

  /// 画面缩放模式
  final BoxFit videoFit;

  /// 超分辨率画质模式
  final SuperResolutionMode superResolution;

  /// 当前是否处于移动蜂窝计费网络（对应 16MB 省流缓冲）
  final bool isMeteredNetwork;

  /// 错误提示信息
  final String? errorMessage;

  bool get hasError => errorMessage != null && errorMessage!.isNotEmpty;

  PlaybackCoreState copyWith({
    bool? playing,
    bool? loading,
    bool? buffering,
    bool? completed,
    bool? firstFrameRendered,
    double? playbackRate,
    double? volume,
    bool? muted,
    BoxFit? videoFit,
    SuperResolutionMode? superResolution,
    bool? isMeteredNetwork,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PlaybackCoreState(
      playing: playing ?? this.playing,
      loading: loading ?? this.loading,
      buffering: buffering ?? this.buffering,
      completed: completed ?? this.completed,
      firstFrameRendered: firstFrameRendered ?? this.firstFrameRendered,
      playbackRate: playbackRate ?? this.playbackRate,
      volume: volume ?? this.volume,
      muted: muted ?? this.muted,
      videoFit: videoFit ?? this.videoFit,
      superResolution: superResolution ?? this.superResolution,
      isMeteredNetwork: isMeteredNetwork ?? this.isMeteredNetwork,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 播放器高频时间线状态（250ms 节流触发，专供进度条、时间文字与弹幕时间轴监听）
@immutable
class PlaybackTimelineState {
  const PlaybackTimelineState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffer = Duration.zero,
    this.previewPosition,
  });

  /// 当前实际播放位置
  final Duration position;

  /// 视频总时长
  final Duration duration;

  /// 已缓冲位置
  final Duration buffer;

  /// 用户拖拽进度条时的预览目标位置（松手前不直接 seek 底层）
  final Duration? previewPosition;

  /// 是否正在拖拽 Seek 预览
  bool get isSeekingPreview => previewPosition != null;

  /// 进度条应该显示的最终位置（若在拖拽中优先展示 previewPosition）
  Duration get displayPosition => previewPosition ?? position;

  PlaybackTimelineState copyWith({
    Duration? position,
    Duration? duration,
    Duration? buffer,
    Duration? previewPosition,
    bool clearPreview = false,
  }) {
    return PlaybackTimelineState(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffer: buffer ?? this.buffer,
      previewPosition:
          clearPreview ? null : (previewPosition ?? this.previewPosition),
    );
  }
}
