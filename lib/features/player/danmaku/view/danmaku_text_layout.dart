import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 工业级弹幕排版与双层渲染单元
/// 负责处理文字度量、圆角柔和描边与内容更新
class DanmakuTextLayout {
  DanmakuTextLayout({
    required this.text,
    required this.color,
    required this.fontSize,
    required this.strokeWidth,
    this.opacity = 1.0,
    this.fontFamily,
    this.isCached = false,
  }) {
    _layout();
  }

  String text;
  final Color color;
  final double fontSize;
  final double strokeWidth;
  final double opacity;
  final String? fontFamily;

  /// 是否由 DanmakuLayoutPool 缓存池托管
  final bool isCached;

  /// 当前被在屏弹幕引用的计数
  int refCount = 0;

  /// 是否已被 LRU 缓存池淘汰
  bool isEvicted = false;

  bool _isDisposed = false;

  late TextPainter _fillPainter;
  TextPainter? _strokePainter;
  Size _size = Size.zero;

  /// 测量出的完整弹幕尺寸
  Size get size => _size;

  void _layout() {
    final effectiveFontFamily = fontFamily ?? 'MiSans';
    // 黄金描边比例：约 1.2~1.4px，精致贴边，绝不侵蚀汉字内部笔画空间
    final effectiveStroke = strokeWidth > 0
        ? math.min(1.4, math.max(1.1, fontSize * 0.075))
        : 0.0;

    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      fontFamily: effectiveFontFamily,
      fontFamilyFallback: const [
        'MiSans',
        'Microsoft YaHei',
        'PingFang SC',
        'SimHei',
        'sans-serif',
      ],
      letterSpacing: 0.2,
      height: 1.18,
    );

    // 1. 底层描边绘制器（设置 StrokeJoin.round，彻底消除文字拐角尖刺毛刺）
    if (effectiveStroke > 0) {
      _strokePainter = TextPainter(
        text: TextSpan(
          text: text,
          style: style.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = effectiveStroke
              ..strokeJoin = StrokeJoin.round // 核心：消除折角尖刺
              ..strokeCap = StrokeCap.round
              // 0.85 柔和黑，按透明度级联，彻底消除全屏 4K saveLayer 显存带宽暴击
              ..color = const Color(0xD9000000).withValues(
                alpha: 0.85 * opacity.clamp(0.0, 1.0),
              ),
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
      )..layout();
    } else {
      _strokePainter = null;
    }

    // 2. 表层文字填充绘制器
    _fillPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(
          color: color.withValues(
            alpha: color.a * opacity.clamp(0.0, 1.0),
          ),
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout();

    _size = _fillPainter.size;
  }

  /// 飞行中动态合流（xN）时更新文本并重新计算尺寸
  void updateText(String newText) {
    if (text == newText) return;
    text = newText;
    _fillPainter.dispose();
    _strokePainter?.dispose();
    _layout();
  }

  /// 提交至 Canvas 绘制
  void paint(Canvas canvas, Offset offset) {
    _strokePainter?.paint(canvas, offset);
    _fillPainter.paint(canvas, offset);
  }

  /// 提交至 Canvas 绘制（避免外部高频分配 Offset 实例）
  void paintAt(Canvas canvas, double x, double y) {
    final offset = Offset(x, y);
    _strokePainter?.paint(canvas, offset);
    _fillPainter.paint(canvas, offset);
  }

  /// 资源回收（若由缓存池托管，仅在引用计数归零且被淘汰后才真正释放底层 TextPainter）
  void dispose() {
    if (isCached) {
      refCount--;
      if (refCount <= 0 && isEvicted) {
        _disposePainters();
      }
      return;
    }
    _disposePainters();
  }

  /// 标记被缓存池淘汰
  void evict() {
    isEvicted = true;
    if (refCount <= 0) {
      _disposePainters();
    }
  }

  void _disposePainters() {
    if (_isDisposed) return;
    _isDisposed = true;
    _fillPainter.dispose();
    _strokePainter?.dispose();
  }
}

/// 工业级高频弹幕文本排版 LRU 缓存池 (借鉴 animaku Glyph Cache 思想)
/// 对高频重复弹幕（如 "草"、"2333"、"前方高能" 等）直接复用已排版度量的 TextPainter，
/// 极大消除 Dart Eden 垃圾回收压力与 Skia/Impeller 布局度量开销
class DanmakuLayoutPool {
  DanmakuLayoutPool({this.maxEntries = 192});

  final int maxEntries;
  final Map<String, DanmakuTextLayout> _cache = {};

  DanmakuTextLayout acquire({
    required String text,
    required Color color,
    required double fontSize,
    required double strokeWidth,
    double opacity = 1.0,
    String? fontFamily,
    void Function()? onCacheMiss,
  }) {
    final effectiveFontFamily = fontFamily ?? 'MiSans';
    // 构造缓存 Key (含字号、颜色、描边宽、透明度、字族与文本)
    final key =
        '${fontSize.toStringAsFixed(1)}|${color.toARGB32()}|${strokeWidth.toStringAsFixed(1)}|${opacity.toStringAsFixed(2)}|$effectiveFontFamily|$text';

    final existing = _cache.remove(key);
    if (existing != null) {
      // LRU 命中：重新放回 LinkedHashMap 尾部保持活跃度
      _cache[key] = existing;
      existing.refCount++;
      return existing;
    }

    // 缓存未命中：新建并记录度量统计
    onCacheMiss?.call();
    final created = DanmakuTextLayout(
      text: text,
      color: color,
      fontSize: fontSize,
      strokeWidth: strokeWidth,
      opacity: opacity,
      fontFamily: fontFamily,
      isCached: true,
    );
    created.refCount++;
    _cache[key] = created;

    if (_cache.length > maxEntries) {
      final oldestKey = _cache.keys.first;
      final oldest = _cache.remove(oldestKey);
      oldest?.evict();
    }

    return created;
  }

  void clear() {
    for (final layout in _cache.values) {
      layout.evict();
    }
    _cache.clear();
  }
}
