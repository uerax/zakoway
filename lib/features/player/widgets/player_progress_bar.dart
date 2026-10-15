import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:zakoway/core/services/bangumi_oped_service.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';

/// 复合型多功能流体播放进度条
/// 整合了：
/// 1. 弹幕高能雾光波形图 (Danmaku Heatmap Mist)
/// 2. OP 片头 (薄荷绿 #65D1C5) 与 ED 片尾 (暖橙色 #F2BA72) 彩色区间刻度
/// 3. 网络分级预读缓冲进度
/// 4. 现代流体交互感知（常态纤细收敛，悬停/拖拽丝滑膨胀与滑块弹出）
class PlayerProgressBar extends StatefulWidget {
  const PlayerProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffer,
    this.opedSegment,
    this.officialDurationSeconds,
    this.danmakuItems,
    this.primaryColor,
    required this.onChangeStart,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final Duration position;
  final Duration duration;
  final Duration buffer;
  final EpisodeOpedSegment? opedSegment;
  final int? officialDurationSeconds;
  final List<DanmakuItem>? danmakuItems;
  final Color? primaryColor;

  final ValueChanged<Duration> onChangeStart;
  final ValueChanged<Duration> onChanged;
  final ValueChanged<Duration> onChangeEnd;

  @override
  State<PlayerProgressBar> createState() => _PlayerProgressBarState();
}

class _PlayerProgressBarState extends State<PlayerProgressBar> {
  bool _isDragging = false;
  bool _isHovered = false;
  double _dragRatio = 0.0;

  List<double>? _cachedHeatmap;
  int _lastDanmakuCount = -1;
  int _lastDurationMs = -1;

  @override
  void didUpdateWidget(covariant PlayerProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final curCount = widget.danmakuItems?.length ?? 0;
    final curDur = widget.duration.inMilliseconds;
    if (curCount != _lastDanmakuCount || curDur != _lastDurationMs) {
      _recomputeHeatmap();
    }
  }

  void _recomputeHeatmap() {
    final items = widget.danmakuItems;
    final durMs = widget.duration.inMilliseconds;
    _lastDanmakuCount = items?.length ?? 0;
    _lastDurationMs = durMs;

    if (items == null || items.length < 5 || durMs <= 0) {
      _cachedHeatmap = null;
      return;
    }

    const numBuckets = 60;
    final buckets = List<double>.filled(numBuckets, 0.0);

    for (final item in items) {
      if (item.timeMs >= 0 && item.timeMs <= durMs) {
        final idx = ((item.timeMs / durMs) * numBuckets).floor().clamp(0, numBuckets - 1);
        buckets[idx] += 1.0;
      }
    }

    final maxVal = buckets.reduce(math.max);
    if (maxVal <= 1.0) {
      _cachedHeatmap = null;
      return;
    }

    // 3点滑动平均平滑算法 (3-point moving average)
    final smoothed = List<double>.generate(numBuckets, (i) {
      final prev = i > 0 ? buckets[i - 1] : buckets[i];
      final next = i < numBuckets - 1 ? buckets[i + 1] : buckets[i];
      return (prev + buckets[i] * 2 + next) / 4.0;
    });

    final smoothedMax = smoothed.reduce(math.max);
    if (smoothedMax <= 0) {
      _cachedHeatmap = null;
      return;
    }

    // 归一化为 0.0 ~ 1.0
    _cachedHeatmap = smoothed.map((v) => (v / smoothedMax).clamp(0.0, 1.0)).toList();
  }

  double _getRatioFromPosition(double localX, double totalWidth) {
    if (totalWidth <= 0) return 0.0;
    return (localX / totalWidth).clamp(0.0, 1.0);
  }

  Duration _getDurationFromRatio(double ratio) {
    final totalMs = widget.duration.inMilliseconds;
    return Duration(milliseconds: (totalMs * ratio).round());
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primaryColor ?? Theme.of(context).colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final totalMs = widget.duration.inMilliseconds.toDouble();

        final currentRatio = _isDragging
            ? _dragRatio
            : (totalMs > 0
                ? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0)
                : 0.0);

        final bufferRatio = totalMs > 0
            ? (widget.buffer.inMilliseconds / totalMs).clamp(0.0, 1.0)
            : 0.0;

        final isInteracting = _isDragging || _isHovered;
        final trackHeight = isInteracting ? 4.5 : 2.5;

        return MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (details) {
              setState(() {
                _isDragging = true;
                _dragRatio = _getRatioFromPosition(details.localPosition.dx, totalWidth);
              });
              widget.onChangeStart(_getDurationFromRatio(_dragRatio));
            },
            onHorizontalDragUpdate: (details) {
              setState(() {
                _dragRatio = _getRatioFromPosition(details.localPosition.dx, totalWidth);
              });
              widget.onChanged(_getDurationFromRatio(_dragRatio));
            },
            onHorizontalDragEnd: (details) {
              final finalRatio = _dragRatio;
              setState(() => _isDragging = false);
              widget.onChangeEnd(_getDurationFromRatio(finalRatio));
            },
            onTapDown: (details) {
              final tapRatio = _getRatioFromPosition(details.localPosition.dx, totalWidth);
              final target = _getDurationFromRatio(tapRatio);
              widget.onChangeStart(target);
              widget.onChangeEnd(target);
            },
            child: SizedBox(
              height: 22,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.bottomLeft,
                children: [
                  // 1. 弹幕高能波形图 (轻盈银白雾光微光波形，告别浓艳青色色块)
                  if (_cachedHeatmap != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 4.5,
                      height: 12,
                      child: CustomPaint(
                        painter: _DanmakuHeatmapPainter(
                          heatmap: _cachedHeatmap!,
                          isInteracting: isInteracting,
                        ),
                      ),
                    ),

                  // 2. 底层未播放底轨（常态 2.5px，交互态膨胀至 4.5px）
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 2,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutCubic,
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                  ),

                  // 3. 网络缓冲进度轨
                  if (bufferRatio > 0)
                    Positioned(
                      left: 0,
                      bottom: 2,
                      width: totalWidth * bufferRatio,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOutCubic,
                        height: trackHeight,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                      ),
                    ),

                  // 4. OP / ED 彩色区间高亮刻度
                  if (widget.opedSegment != null && totalMs > 0)
                    ..._buildOpedMarkers(totalWidth, totalMs, trackHeight),

                  // 5. 当前播放进度轨
                  Positioned(
                    left: 0,
                    bottom: 2,
                    width: totalWidth * currentRatio,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutCubic,
                      height: trackHeight,
                      decoration: BoxDecoration(
                        color: primary,
                        borderRadius: BorderRadius.circular(2.5),
                        boxShadow: isInteracting
                            ? [
                                BoxShadow(
                                  color: primary.withValues(alpha: 0.45),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),

                  // 6. 可拖动滑块 Thumb（常态完全收缩隐藏，悬停/拖拽时丝滑弹出）
                  Positioned(
                    bottom: _isDragging ? -3.0 : -2.0,
                    left: (totalWidth * currentRatio - (_isDragging ? 7.0 : 5.5)).clamp(
                      0.0,
                      math.max(0.0, totalWidth - (_isDragging ? 14.0 : 11.0)),
                    ),
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOutBack,
                      scale: isInteracting ? 1.0 : 0.0,
                      child: Container(
                        width: _isDragging ? 14.0 : 11.0,
                        height: _isDragging ? 14.0 : 11.0,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.35),
                              blurRadius: _isDragging ? 5.0 : 3.0,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildOpedMarkers(double totalWidth, double totalMs, double trackHeight) {
    final seg = widget.opedSegment!;
    final totalSec = totalMs / 1000.0;
    if (totalSec <= 0) return const [];

    // 容灾检查：当前视频总时长与 Bangumi 官方片长差距超过 10 秒，熔断不绘制
    final officialSec = widget.officialDurationSeconds ?? 0;
    if (officialSec > 0 && (totalSec.round() - officialSec).abs() > 10) {
      return const [];
    }

    final widgets = <Widget>[];

    // OP 片头高亮 (薄荷青色 #65D1C5)
    if (seg.hasOp && seg.opEnd! <= totalSec) {
      final startRatio = (seg.opStart! / totalSec).clamp(0.0, 1.0);
      final endRatio = (seg.opEnd! / totalSec).clamp(0.0, 1.0);
      final left = totalWidth * startRatio;
      final width = (totalWidth * (endRatio - startRatio)).clamp(2.0, totalWidth);

      widgets.add(
        Positioned(
          left: left,
          bottom: 2,
          width: width,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            height: trackHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF65D1C5).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
        ),
      );
    }

    // ED 片尾高亮 (暖淡橙色 #F2BA72)
    if (seg.hasEd && seg.edStart! < totalSec) {
      final startRatio = (seg.edStart! / totalSec).clamp(0.0, 1.0);
      final endRatio = (seg.edEnd! / totalSec).clamp(0.0, 1.0);
      final left = totalWidth * startRatio;
      final width = (totalWidth * (endRatio - startRatio)).clamp(2.0, totalWidth);

      widgets.add(
        Positioned(
          left: left,
          bottom: 2,
          width: width,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            height: trackHeight,
            decoration: BoxDecoration(
              color: const Color(0xFFF2BA72).withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(2.5),
            ),
          ),
        ),
      );
    }

    return widgets;
  }
}

/// 弹幕高能波形图绘制器（银白微光通透雾态波形）
class _DanmakuHeatmapPainter extends CustomPainter {
  const _DanmakuHeatmapPainter({
    required this.heatmap,
    required this.isInteracting,
  });

  final List<double> heatmap;
  final bool isInteracting;

  @override
  void paint(Canvas canvas, Size size) {
    if (heatmap.length < 2) return;

    final h = size.height;
    final w = size.width;

    // 半透明极度轻盈优雅的银白雾光渐变，绝不遮蔽视频画面与字幕
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: isInteracting ? 0.20 : 0.09),
          Colors.white.withValues(alpha: 0.01),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    // 波形脊线极细微光勾勒
    final strokePaint = Paint()
      ..color = Colors.white.withValues(alpha: isInteracting ? 0.32 : 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final path = Path();
    final topCurvePath = Path();
    final count = heatmap.length;
    final stepX = w / (count - 1);

    path.moveTo(0, h);

    // 绘制波形曲线
    for (int i = 0; i < count; i++) {
      final x = i * stepX;
      final normalized = math.pow(heatmap[i], 0.85).toDouble();
      final y = h - normalized * (h - 2.0);

      if (i == 0) {
        path.lineTo(x, y);
        topCurvePath.moveTo(x, y);
      } else {
        final prevX = (i - 1) * stepX;
        final prevNorm = math.pow(heatmap[i - 1], 0.85).toDouble();
        final prevY = h - prevNorm * (h - 2.0);
        final cx = (prevX + x) / 2.0;
        path.cubicTo(cx, prevY, cx, y, x, y);
        topCurvePath.cubicTo(cx, prevY, cx, y, x, y);
      }
    }

    path.lineTo(w, h);
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(topCurvePath, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _DanmakuHeatmapPainter oldDelegate) {
    return oldDelegate.heatmap != heatmap || oldDelegate.isInteracting != isInteracting;
  }
}
