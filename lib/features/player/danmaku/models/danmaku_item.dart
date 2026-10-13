import 'package:flutter/material.dart';

/// 弹幕显示类型
enum DanmakuMode {
  /// 从右向左滚动弹幕
  scroll,

  /// 顶部固定弹幕
  top,

  /// 底部固定弹幕
  bottom,
}

/// 原始弹幕数据项
class DanmakuItem {
  DanmakuItem({
    required this.text,
    required this.timeMs,
    this.mode = DanmakuMode.scroll,
    this.color = Colors.white,
    this.isSelf = false,
    this.source,
    this.senderHash,
  });

  /// 弹幕文本
  final String text;

  /// 弹幕在视频时间轴上的毫秒时刻
  final int timeMs;

  /// 弹幕显示模式
  final DanmakuMode mode;

  /// 弹幕颜色
  final Color color;

  /// 是否是当前用户自己发射的弹幕
  final bool isSelf;

  /// 弹幕来源标识 (如 dandan, bilibili, upload 等)
  final String? source;

  /// 发送者哈希特征 (用于多源跨站 O(1) 增量指纹去重)
  final String? senderHash;

  /// 时间轴秒数 (辅助转换)
  double get timeSeconds => timeMs / 1000.0;

  DanmakuItem copyWith({
    String? text,
    int? timeMs,
    DanmakuMode? mode,
    Color? color,
    bool? isSelf,
    String? source,
    String? senderHash,
  }) {
    return DanmakuItem(
      text: text ?? this.text,
      timeMs: timeMs ?? this.timeMs,
      mode: mode ?? this.mode,
      color: color ?? this.color,
      isSelf: isSelf ?? this.isSelf,
      source: source ?? this.source,
      senderHash: senderHash ?? this.senderHash,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'timeMs': timeMs,
        'mode': mode.name,
        'color': color.toARGB32(),
        'isSelf': isSelf,
        if (source != null) 'source': source,
        if (senderHash != null) 'senderHash': senderHash,
      };

  factory DanmakuItem.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode']?.toString();
    final mode = switch (modeName) {
      'top' => DanmakuMode.top,
      'bottom' => DanmakuMode.bottom,
      _ => DanmakuMode.scroll,
    };

    final colorVal = json['color'] as int? ?? 0xFFFFFFFF;

    return DanmakuItem(
      text: json['text']?.toString() ?? '',
      timeMs: json['timeMs'] as int? ?? 0,
      mode: mode,
      color: Color(colorVal),
      isSelf: json['isSelf'] as bool? ?? false,
      source: json['source']?.toString(),
      senderHash: json['senderHash']?.toString(),
    );
  }

  @override
  String toString() =>
      'DanmakuItem(text: $text, timeMs: $timeMs, mode: $mode, color: $color, source: $source)';
}

/// 弹幕配置参数
class DanmakuSettings {
  const DanmakuSettings({
    this.enabled = true,
    this.opacity = 0.85,
    this.fontSizeScale = 1.0,
    this.speed = 1.0,
    this.area = 0.75,
    this.strokeWidth = 2.0,
    this.simplify = false,
    this.hideScroll = false,
    this.hideTop = false,
    this.hideBottom = false,
    this.hideColor = false,
    this.filters = const <String>[],
  });

  /// 弹幕总开关
  final bool enabled;

  /// 不透明度 (0.1 ~ 1.0)
  final double opacity;

  /// 字号缩放倍率 (0.5 ~ 2.0)
  final double fontSizeScale;

  /// 飞行速度倍率 (0.5 ~ 2.0)
  final double speed;

  /// 弹幕显示区域占比 (0.25 ~ 1.0，如 0.75 表示占满屏幕上方 75% 区域)
  final double area;

  /// 文字描边宽度 (逻辑像素，推荐 1.5 ~ 2.5)
  final double strokeWidth;

  /// 精简模式：高密弹幕智能节流与降权
  final bool simplify;

  /// 是否隐藏滚动弹幕
  final bool hideScroll;

  /// 是否隐藏顶部固定弹幕
  final bool hideTop;

  /// 是否隐藏底部固定弹幕
  final bool hideBottom;

  /// 是否将彩色弹幕统一转为白色显示
  final bool hideColor;

  /// 屏蔽规则列表（支持纯字符串子串匹配或 "/pattern/flags" 正则表达式）
  final List<String> filters;

  DanmakuSettings copyWith({
    bool? enabled,
    double? opacity,
    double? fontSizeScale,
    double? speed,
    double? area,
    double? strokeWidth,
    bool? simplify,
    bool? hideScroll,
    bool? hideTop,
    bool? hideBottom,
    bool? hideColor,
    List<String>? filters,
  }) {
    return DanmakuSettings(
      enabled: enabled ?? this.enabled,
      opacity: opacity ?? this.opacity,
      fontSizeScale: fontSizeScale ?? this.fontSizeScale,
      speed: speed ?? this.speed,
      area: area ?? this.area,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      simplify: simplify ?? this.simplify,
      hideScroll: hideScroll ?? this.hideScroll,
      hideTop: hideTop ?? this.hideTop,
      hideBottom: hideBottom ?? this.hideBottom,
      hideColor: hideColor ?? this.hideColor,
      filters: filters ?? this.filters,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'opacity': opacity,
        'fontSizeScale': fontSizeScale,
        'speed': speed,
        'area': area,
        'strokeWidth': strokeWidth,
        'simplify': simplify,
        'hideScroll': hideScroll,
        'hideTop': hideTop,
        'hideBottom': hideBottom,
        'hideColor': hideColor,
        'filters': filters,
      };

  factory DanmakuSettings.fromJson(Map<String, dynamic> json) {
    return DanmakuSettings(
      enabled: json['enabled'] as bool? ?? true,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 0.85,
      fontSizeScale: (json['fontSizeScale'] as num?)?.toDouble() ?? 1.0,
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      area: (json['area'] as num?)?.toDouble() ?? 0.75,
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      simplify: json['simplify'] as bool? ?? false,
      hideScroll: json['hideScroll'] as bool? ?? false,
      hideTop: json['hideTop'] as bool? ?? false,
      hideBottom: json['hideBottom'] as bool? ?? false,
      hideColor: json['hideColor'] as bool? ?? false,
      filters: (json['filters'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
    );
  }
}
