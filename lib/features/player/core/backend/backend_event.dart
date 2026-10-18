/// 携带代际分界与重置标记的原生底层事件包装
///
/// 遵循 docs/player-rewrite/03-state-machine.md (v3.1) 第六节与 docs/player-rewrite/05-interfaces-and-contracts.md (v3)
library;

import 'package:flutter/foundation.dart';

/// 携带底层 open 物理代际标记的事件包装器
@immutable
class BackendEvent<T> {
  const BackendEvent(
    this.data, {
    required this.generationId,
    this.isResetMarker = false,
  });

  /// 事件承载的数据实体
  final T data;

  /// 本次事件归属的底层 open 物理代际自增 ID
  final int generationId;

  /// 该事件是否为底层针对全新 open 同步发射的初始重置标记值
  ///
  /// 实测事实（08 事实 8）：在每次 open 后的 6~7ms 内，
  /// playing/position/duration/buffer/buffering/videoParams/width/height 会同步发射重置标记。
  final bool isResetMarker;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BackendEvent<T> &&
        other.data == data &&
        other.generationId == generationId &&
        other.isResetMarker == isResetMarker;
  }

  @override
  int get hashCode => Object.hash(data, generationId, isResetMarker);

  @override
  String toString() =>
      'BackendEvent(data: $data, gen: $generationId, isReset: $isResetMarker)';
}

/// 原生底层日志消息实体
@immutable
class PlayerLogMessage {
  const PlayerLogMessage({
    required this.prefix,
    required this.level,
    required this.text,
    required this.timestamp,
    required this.generationId,
  });

  final String prefix;
  final String level;
  final String text;
  final DateTime timestamp;
  final int generationId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlayerLogMessage &&
        other.prefix == prefix &&
        other.level == level &&
        other.text == text &&
        other.timestamp == timestamp &&
        other.generationId == generationId;
  }

  @override
  int get hashCode => Object.hash(prefix, level, text, timestamp, generationId);

  @override
  String toString() =>
      '[$prefix] ($level) $text (gen: $generationId, time: $timestamp)';
}

/// 视频画面物理尺寸模型
@immutable
class VideoDimensions {
  const VideoDimensions(this.width, this.height);
  final int? width;
  final int? height;

  /// 是否具备大于 0 的有效渲染尺寸
  bool get hasValidSize => (width ?? 0) > 0 && (height ?? 0) > 0;

  /// 宽高比
  double get aspectRatio {
    if (width == null || height == null || height == 0) {
      return 16 / 9;
    }
    return width! / height!;
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VideoDimensions &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'VideoDimensions(${width}x$height)';
}
