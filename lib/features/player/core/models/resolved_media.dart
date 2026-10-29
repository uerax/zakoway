/// 直链解析产出实体
///
/// 遵循 docs/player-rewrite/05-interfaces-and-contracts.md (v3) 第三节
library;

import 'package:flutter/foundation.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';

/// 包含视频真实直链与必要鉴权 HTTP 请求头及外挂字幕轨的解析结果对象
@immutable
class ResolvedMedia {
  const ResolvedMedia({
    required this.url,
    this.headers = const {},
    this.subtitles = const [],
  });

  /// 视频播放直链 URL
  final String url;

  /// 附加 HTTP 请求头（如 Referer、User-Agent 等）
  final Map<String, String> headers;

  /// 外挂字幕轨列表
  final List<SourceSubtitleTrack> subtitles;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ResolvedMedia &&
        other.url == url &&
        mapEquals(other.headers, headers) &&
        listEquals(other.subtitles, subtitles);
  }

  @override
  int get hashCode => Object.hash(
        url,
        Object.hashAll(headers.entries),
        Object.hashAll(subtitles),
      );

  @override
  String toString() =>
      'ResolvedMedia(url: $url, headers: $headers, subtitles: $subtitles)';
}
