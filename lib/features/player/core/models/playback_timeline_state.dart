/// 播放器高频时间线状态模型
///
/// 遵循 docs/player-rewrite/05-interfaces-and-contracts.md (v3)
library;

import 'package:flutter/foundation.dart';

/// 播放器高频时间线只读状态（进度条、时长与拖拽预览）
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

  /// 已缓冲时长
  final Duration buffer;

  /// 用户拖拽进度条时的实时预览位置（手指未松开时非空）
  final Duration? previewPosition;

  /// 是否正在拖拽预览中
  bool get isSeekingPreview => previewPosition != null;

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

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaybackTimelineState &&
        other.position == position &&
        other.duration == duration &&
        other.buffer == buffer &&
        other.previewPosition == previewPosition;
  }

  @override
  int get hashCode => Object.hash(position, duration, buffer, previewPosition);

  @override
  String toString() =>
      'PlaybackTimelineState(pos: ${position.inSeconds}s, dur: ${duration.inSeconds}s, buf: ${buffer.inSeconds}s, preview: $previewPosition)';
}
