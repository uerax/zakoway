import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:zakoway/features/player/danmaku/core/danmaku_controller.dart';
import 'package:zakoway/features/player/danmaku/core/danmaku_entry.dart';
import 'package:zakoway/features/player/danmaku/core/danmaku_perf_stats.dart';
import 'package:zakoway/features/player/danmaku/core/danmaku_scroll_track.dart';
import 'package:zakoway/features/player/danmaku/models/danmaku_item.dart';
import 'package:zakoway/features/player/danmaku/utils/danmaku_text_normalizer.dart';
import 'package:zakoway/features/player/danmaku/view/danmaku_text_layout.dart';

const double _kTrackSpacing = 1.16;
const double _kTopDurationMs = 5000.0;
const double _kBottomDurationMs = 5000.0;
/// 移动端窄屏滚动弹幕基准穿越耗时 (7.5s)
const double _kScrollBaseDurationMs = 7500.0;

/// 特殊处理说明：
/// 分级时钟漂移治理模型 (Tiered Drift Policy)：
/// 1. 正负对称死区 (|drift| <= 40ms)：吸收 24/30fps 视频解码步进 (约 33~42ms) 与硬件采样抖动，
///    完全不干预，保证弹幕匀速单调前进，杜绝微小拉扯抖动；
/// 2. 平滑微调 (40ms < |drift| <= 600ms)：采用一阶 EMA 低通滤波 (alpha = 0.15)，
///    正负双向温和吸收漂移，数秒内平稳追平进度且消除向后快退死锁；
/// 3. 硬寻道 (|drift| > 600ms)：超过 600ms 视为 Seek 跳转，触发时钟重置、清屏与重定位游标。
const double _kSeekThresholdMs = 600.0;
const double _kSyncDeadbandMs = 40.0;
const double _kSyncEmaAlpha = 0.15;

/// 高性能纯 Flutter Canvas 弹幕渲染组件
/// 支持飞行中动态吸收合流 (xN)、微秒级时钟插值、防追尾轨道算法与智能休眠节电
class DanmakuView extends StatefulWidget {
  const DanmakuView({
    super.key,
    required this.controller,
    this.fontFamily,
  });

  final DanmakuController controller;
  final String? fontFamily;

  @override
  State<DanmakuView> createState() => _DanmakuViewState();
}

class _DanmakuViewState extends State<DanmakuView>
    with SingleTickerProviderStateMixin
    implements DanmakuListener {
  late final Ticker _ticker;
  final ValueNotifier<int> _repaintNotifier = ValueNotifier<int>(0);
  final DanmakuPerfStats _perfStats = DanmakuPerfStats();

  final List<DanmakuEntry> _activeEntries = <DanmakuEntry>[];
  final DanmakuLayoutPool _layoutPool = DanmakuLayoutPool();
  List<DanmakuScrollTrack> _scrollTracks = const [];
  List<double> _topBusyUntil = const [];
  List<double> _bottomBusyUntil = const [];

  Timer? _wakeTimer;
  Timer? _seekDebounceTimer;
  Timer? _viewportResizeTimer;
  bool _isViewportResizing = false;
  int _lastSeekTimeMs = 0;
  int _cursor = 0;
  double _clockMs = 0.0;
  Duration _lastElapsed = Duration.zero;

  double _viewWidth = 0.0;
  double _viewHeight = 0.0;
  double _deviceShortestSide = 0.0;
  double _dpr = 1.0;
  double _lineHeight = 24.0;
  double _nextExpiryMs = double.infinity;
  int _scrollingCount = 0;

  DanmakuController get _controller => widget.controller;
  bool get _hasViewport => _viewWidth > 0 && _viewHeight > 0;

  bool get _isDesktop {
    if (kIsWeb) {
      return defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux;
    }
    return Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  }

  bool get _isTablet => !_isDesktop && _deviceShortestSide >= 600.0;

  /// 自适应同屏并发弹幕密度硬预算 (借鉴 animaku 工业级密度模型)
  /// 防止弹幕高潮/名场面下所有轨道超载堆叠导致叠字糊屏与掉帧
  int get _maxRunning {
    final areaRatio = _controller.settings.area.clamp(0.2, 1.0);
    final lanes = _scrollTracks.length;
    if (lanes <= 0) return 32;
    if (_isDesktop) {
      return math.min(96, math.max(32, (72 * areaRatio).round()));
    } else if (_isTablet) {
      return math.min(64, math.max(24, (48 * areaRatio).round()));
    } else {
      return math.min(48, math.max(16, (36 * areaRatio).round()));
    }
  }

  /// 特殊处理说明：
  /// 视口形态敏感的滚动弹幕基准穿越耗时 (毫秒)
  /// 严格依照当前播放器渲染视口物理宽度自适应，杜绝按操作系统 Platform.isWindows 一刀切判断：
  /// - 宽屏 / 桌面全屏 (viewWidth >= 840): 12.5s (12500ms)，严格对齐桌面大屏适读舒适区，防眩晕；
  /// - 中等平板视口 (600 <= viewWidth < 840): 约 9s (9000ms)；
  /// - 移动端窄屏视口 (viewWidth < 600): 7.5s (7500ms)，保持小屏适读与紧凑轻快的平衡。
  double get _scrollBaseDurationMs {
    if (_viewWidth >= 840.0) return 12500.0;
    if (_viewWidth >= 600.0) return 9000.0;
    return _kScrollBaseDurationMs;
  }

  void _updateDeviceInfo(double shortestSide) {
    if ((_deviceShortestSide - shortestSide).abs() > 0.5) {
      _deviceShortestSide = shortestSide;
      if (_hasViewport) {
        _rebuildTracks();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _perfStats.start();
    _ticker = createTicker(_onTick);
    _controller.attach(this);
    if (_controller.playing) {
      _scheduleWork();
    }
  }

  @override
  void didUpdateWidget(covariant DanmakuView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.detach(this);
      _clearActive();
      widget.controller.attach(this);
      _cursor = _lowerBound(_controller.items, _clockMs);
      _scheduleWork();
    }
  }

  @override
  void dispose() {
    _controller.detach(this);
    _stopWork();
    _seekDebounceTimer?.cancel();
    _viewportResizeTimer?.cancel();
    _clearActive();
    _layoutPool.clear();
    _ticker.dispose();
    _repaintNotifier.dispose();
    _perfStats.stop();
    super.dispose();
  }

  // ==========================
  // 时钟驱动与低功耗状态机
  // ==========================

  void _onTick(Duration elapsed) {
    final delta = elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    if (delta <= Duration.zero) return;

    // 1. 微秒级连续平滑时间插值推进 (单调递增，无任何速度扰动)
    final dtMs = delta.inMicroseconds / 1000.0;
    _clockMs += dtMs * _controller.playbackRate;

    // 视口尺寸连续变动防抖期间：暂停发射新弹幕和绘制
    if (_isViewportResizing) {
      return;
    }

    // 2. 发射到期弹幕（带动态合流与入场调度）
    _emitDue();

    // 3. 淘汰出界弹幕
    _expire();

    _perfStats.updateActiveCount(_activeEntries.length);

    // 4. 重绘通知
    if (_scrollingCount > 0) {
      _repaintNotifier.value++;
    } else {
      // 5. 无滚动弹幕时立刻挂起 Ticker，进入休眠省电状态
      _scheduleWork();
    }
  }

  void _scheduleWork({bool forceWake = false}) {
    if (!_controller.playing || !_hasViewport || !mounted || !_controller.settings.enabled) {
      _stopWork();
      return;
    }

    // 若屏幕上有正在移动的滚动弹幕，必须保持 Ticker 60/120fps 运转
    if (_scrollingCount > 0) {
      _wakeTimer?.cancel();
      _wakeTimer = null;
      if (!_ticker.isActive) {
        _lastElapsed = Duration.zero;
        _ticker.start();
      }
      return;
    }

    // 无活动滚动弹幕：停止 Ticker
    _ticker.stop();

    // 计算下一个需要唤醒的时刻（下一条待发射的时刻，或当前固定弹幕的最早消失时刻）
    final items = _controller.items;
    final nextItemMs = _cursor < items.length
        ? items[_cursor].timeMs.toDouble()
        : double.infinity;
    final nextWakeMs = math.min(nextItemMs, _nextExpiryMs);

    if (!nextWakeMs.isFinite) {
      _wakeTimer?.cancel();
      _wakeTimer = null;
      return;
    }

    final rate = _controller.playbackRate;
    final delayMs = math.max(0.0, (nextWakeMs - _clockMs) / rate);

    _wakeTimer?.cancel();
    _wakeTimer = Timer(
      Duration(milliseconds: math.max(1, delayMs.ceil())),
      () {
        _wakeTimer = null;
        if (!_controller.playing || !mounted) return;
        _clockMs = math.max(_clockMs, nextWakeMs);
        _emitDue();
        _expire();
        _scheduleWork();
      },
    );
  }

  void _stopWork() {
    _wakeTimer?.cancel();
    _wakeTimer = null;
    if (_ticker.isActive) {
      _ticker.stop();
    }
  }

  // ==========================
  // 弹幕发射与动态合流逻辑
  // ==========================

  void _emitDue() {
    if (!_hasViewport || !_controller.settings.enabled) return;
    developer.Timeline.startSync('Danmaku._emitDue');
    try {
      final items = _controller.items;
      final initialCount = _activeEntries.length;

      while (_cursor < items.length && items[_cursor].timeMs <= _clockMs) {
        _tryEmit(items[_cursor]);
        _cursor++;
      }

      if (_activeEntries.length != initialCount) {
        _repaintNotifier.value++;
      }
    } finally {
      developer.Timeline.finishSync();
    }
  }

  void _tryEmit(DanmakuItem item, {bool checkFilter = true}) {
    if (!_hasViewport) return;
    final settings = _controller.settings;

    if (checkFilter) {
      if (!settings.enabled) return;
      if (_controller.isBlocked(item.text)) return;
      if (item.mode == DanmakuMode.scroll && settings.hideScroll) return;
      if (item.mode == DanmakuMode.top && settings.hideTop) return;
      if (item.mode == DanmakuMode.bottom && settings.hideBottom) return;
    }

    // === 核心算法：In-Flight 飞行中动态合流 (animaku 经典算法) ===
    if (tryMergeInFlight(item, _clockMs, _viewWidth)) {
      // 成功被屏幕上飞行的同类弹幕吸收，不再分配新轨道
      return;
    }

    // 无法合流，进入轨道分配流程
    switch (item.mode) {
      case DanmakuMode.scroll:
        _emitScroll(item);
      case DanmakuMode.top:
        _emitFixed(item, isTop: true);
      case DanmakuMode.bottom:
        _emitFixed(item, isTop: false);
    }
  }

  /// 飞行中动态合流判定
  bool tryMergeInFlight(DanmakuItem incoming, double nowMs, double viewWidth) {
    final normKey = DanmakuTextNormalizer.normalize(incoming.text);
    if (normKey.isEmpty) return false;

    for (var i = 0; i < _activeEntries.length; i++) {
      final active = _activeEntries[i];
      if (active.mode != incoming.mode) continue;
      // 优化：直接比对预缓存特征 Key，彻底避免在屏循环中高频重复正则与临时字符串分配
      if (active.normalizedKey != normKey) continue;

      final ageMs = nowMs - active.startMs;
      if (ageMs < 0 || ageMs >= active.durationMs) continue;

      // 滚动弹幕：必须确保其尾部还没有越过屏幕左侧边缘
      if (active.mode == DanmakuMode.scroll) {
        final currentX = viewWidth - (ageMs / active.durationMs) * (viewWidth + active.layout.size.width);
        if (currentX + active.layout.size.width < 20.0) continue;
      }

      // === 原地吸收 ===
      _perfStats.recordMerge();
      active.count++;
      final oldWidth = active.layout.size.width;
      active.layout.dispose();
      final fontPx = _calculateCalculatedFontSize();
      active.layout = _layoutPool.acquire(
        text: '${active.baseText} ×${active.count}',
        color: _controller.settings.hideColor ? Colors.white : incoming.color,
        fontSize: fontPx,
        strokeWidth: _controller.settings.strokeWidth,
        opacity: _controller.settings.opacity,
        fontFamily: widget.fontFamily,
        onCacheMiss: _perfStats.recordLayoutCreated,
      );
      final newWidth = active.layout.size.width;

      // === 头部 X 坐标 0 像素跳动补偿 ===
      if (active.mode == DanmakuMode.scroll) {
        final pathOld = viewWidth + oldWidth;
        final pathNew = viewWidth + newWidth;
        if (pathOld > 0 && pathNew > 0) {
          final adjustedAge = ageMs * (pathOld / pathNew);
          active.startMs = nowMs - adjustedAge;
          active.speed = pathNew / active.durationMs;
        }
      }
      return true;
    }
    return false;
  }

  void _emitScroll(DanmakuItem item) {
    if (_scrollTracks.isEmpty) return;
    final settings = _controller.settings;
    final durationMs = math.max(1000.0, _scrollBaseDurationMs / settings.speed);
    final fontPx = _calculateCalculatedFontSize();

    final layout = _layoutPool.acquire(
      text: item.text,
      color: settings.hideColor ? Colors.white : item.color,
      fontSize: fontPx,
      strokeWidth: settings.strokeWidth,
      opacity: settings.opacity,
      fontFamily: widget.fontFamily,
      onCacheMiss: _perfStats.recordLayoutCreated,
    );

    final speed = (_viewWidth + layout.size.width) / durationMs;

    // 寻找最佳空闲轨道（优先满足安全间距，加权避开顶部固定弹幕）
    int bestTrack = -1;
    double bestScore = -double.infinity;

    for (var i = 0; i < _scrollTracks.length; i++) {
      final track = _scrollTracks[i];
      final hasTopDanmaku = i < _topBusyUntil.length && _clockMs < _topBusyUntil[i];

      if (track.canAccept(_clockMs, speed, _viewWidth)) {
        // 空闲时长评分：越久没发弹幕的轨道越优先填充
        final idleMs = _clockMs - track.tailFreeMs;
        final score = idleMs - (hasTopDanmaku ? 10000.0 : 0.0);
        if (score > bestScore) {
          bestScore = score;
          bestTrack = i;
        }
      }
    }

    // 若所有轨道都在使用中：
    // 若当前在场弹幕数已经达到同屏密度硬预算，执行过载丢弃 (Congestion Shedding)，优先保障画面适读与高刷流畅
    if (bestTrack < 0) {
      if (_activeEntries.length >= _maxRunning) {
        _perfStats.recordDropped();
        layout.dispose();
        return;
      }
      double minBusyTime = double.infinity;
      for (var i = 0; i < _scrollTracks.length; i++) {
        final track = _scrollTracks[i];
        final busyUntil = track.tailFreeMs;
        if (busyUntil < minBusyTime) {
          minBusyTime = busyUntil;
          bestTrack = i;
        }
      }
    }

    if (bestTrack < 0) bestTrack = 0;

    final entry = DanmakuEntry(
      item: item,
      track: bestTrack,
      startMs: _clockMs,
      durationMs: durationMs,
      speed: speed,
      x: _viewWidth,
      y: bestTrack * _lineHeight * _kTrackSpacing,
      baseText: item.text,
      layout: layout,
    );

    _activeEntries.add(entry);
    _scrollingCount++;
    _nextExpiryMs = math.min(_nextExpiryMs, entry.endMs);
    _scrollTracks[bestTrack].register(
      startMs: entry.startMs,
      width: layout.size.width,
      speed: speed,
      viewWidth: _viewWidth,
    );
  }

  void _emitFixed(DanmakuItem item, {required bool isTop}) {
    final busyList = isTop ? _topBusyUntil : _bottomBusyUntil;
    if (busyList.isEmpty) return;

    var targetTrack = -1;
    for (var i = 0; i < busyList.length; i++) {
      if (_clockMs >= busyList[i]) {
        targetTrack = i;
        break;
      }
    }
    if (targetTrack < 0) {
      _perfStats.recordDropped();
      return; // 对应固定轨道已满
    }

    final settings = _controller.settings;
    final durationMs = isTop ? _kTopDurationMs : _kBottomDurationMs;
    final fontPx = _calculateCalculatedFontSize();

    final layout = _layoutPool.acquire(
      text: item.text,
      color: settings.hideColor ? Colors.white : item.color,
      fontSize: fontPx,
      strokeWidth: settings.strokeWidth,
      opacity: settings.opacity,
      fontFamily: widget.fontFamily,
      onCacheMiss: _perfStats.recordLayoutCreated,
    );

    busyList[targetTrack] = _clockMs + durationMs;

    final entry = DanmakuEntry(
      item: item,
      track: targetTrack,
      startMs: _clockMs,
      durationMs: durationMs,
      speed: 0.0,
      x: math.max(0.0, (_viewWidth - layout.size.width) / 2.0),
      y: isTop
          ? targetTrack * _lineHeight * _kTrackSpacing
          : _viewHeight - (targetTrack + 1) * _lineHeight * _kTrackSpacing,
      baseText: item.text,
      layout: layout,
    );

    _activeEntries.add(entry);
    _nextExpiryMs = math.min(_nextExpiryMs, entry.endMs);
  }

  void _expire() {
    if (_clockMs < _nextExpiryMs) return;
    var next = double.infinity;
    _activeEntries.removeWhere((entry) {
      if (_clockMs < entry.endMs) {
        next = math.min(next, entry.endMs);
        return false;
      }
      if (entry.mode == DanmakuMode.scroll) {
        _scrollingCount--;
      }
      entry.dispose();
      return true;
    });
    _nextExpiryMs = next;
    _repaintNotifier.value++;
  }

  // ==========================
  // 视口响应与字号计算
  // ==========================

  void _updateViewport(BoxConstraints constraints) {
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    if (w == _viewWidth && h == _viewHeight) return;

    final hadViewport = _hasViewport;
    _viewWidth = w;
    _viewHeight = h;
    if (!_hasViewport) return;

    if (!hadViewport) {
      // 首次布局完成（视口已知）且控制器已有位置时，用该位置初始化 _clockMs 并重建屏幕，避免从 0 开始
      final estimated = _controller.estimatedCurrentPosition;
      if (estimated != null) {
        _clockMs = estimated.inMicroseconds / 1000.0;
      }
      _rebuildTracks();
      _rebuildScreenAt(_clockMs);
      return;
    }

    // 特殊处理说明：
    // 视口尺寸连续变动防抖 (180ms)：
    // 在全屏/窗口切换或窗口拉伸过程中，防抖期间暂停绘制与发射，稳定后再重建屏幕与排轨，杜绝每帧重建
    _isViewportResizing = true;
    _viewportResizeTimer?.cancel();
    _viewportResizeTimer = Timer(const Duration(milliseconds: 180), () {
      _viewportResizeTimer = null;
      if (!mounted || !_hasViewport) return;
      _isViewportResizing = false;
      _rebuildTracks();
      _rebuildScreenAt(_clockMs);
    });
  }

  /// 特殊处理说明：
  /// 统一的“重建当前时刻屏幕”核心方法：
  /// 在当前时钟 targetClockMs 处，清空后按时间顺序补发 [targetClockMs - 窗口, targetClockMs] 内未过期的弹幕：
  /// 1. 按弹幕类型使用各自存活时长过滤过期弹幕（滚动弹幕用当前穿越时长，顶部/底部固定弹幕用 5000ms）；
  /// 2. 候选数量超过同屏上限时，保留时间上最新的那部分（数量 = 上限），再按时间顺序补发；
  /// 3. 被丢弃的弹幕不调用排版，零无用开销；
  /// 4. 补发时临时将 _clockMs 设为弹幕 timeMs，复用现有的 _tryEmit（合流、轨道分配、同屏上限），补完恢复 _clockMs 与游标。
  void _rebuildScreenAt(double targetClockMs) {
    if (!_hasViewport || !_controller.settings.enabled) return;

    final items = _controller.items;
    if (items.isEmpty) {
      _clearActive();
      _clockMs = targetClockMs;
      _cursor = 0;
      _repaintNotifier.value++;
      return;
    }

    final settings = _controller.settings;
    final scrollDurationMs = math.max(1000.0, _scrollBaseDurationMs / settings.speed);
    final maxWindowMs = math.max(scrollDurationMs, _kTopDurationMs);

    final windowStartMs = math.max(0.0, targetClockMs - maxWindowMs);
    final startIndex = _lowerBound(items, windowStartMs);
    final endIndex = _lowerBound(items, targetClockMs + 0.0001);

    // 1. 筛选未过期且未被屏蔽/隐藏的候选弹幕
    final validCandidates = <DanmakuItem>[];
    for (var i = startIndex; i < endIndex; i++) {
      final item = items[i];
      if (item.timeMs > targetClockMs) break;

      if (_controller.isBlocked(item.text)) continue;
      if (item.mode == DanmakuMode.scroll && settings.hideScroll) continue;
      if (item.mode == DanmakuMode.top && settings.hideTop) continue;
      if (item.mode == DanmakuMode.bottom && settings.hideBottom) continue;

      // 按弹幕类型分别计算存活时长，剔除当前时刻已经越界的旧弹幕
      final lifeDurationMs = item.mode == DanmakuMode.scroll
          ? scrollDurationMs
          : _kTopDurationMs;
      if (item.timeMs + lifeDurationMs <= targetClockMs) {
        continue;
      }

      validCandidates.add(item);
    }

    // 2. 候选数量超过同屏上限时，保留时间上最新的那部分（数量 = 上限）
    final budget = _maxRunning;
    final candidatesToEmit = validCandidates.length > budget
        ? validCandidates.sublist(validCandidates.length - budget)
        : validCandidates;

    // 清空现有在屏弹幕与轨道状态
    _clearActive();

    // 3. 按时间顺序补发，临时将 _clockMs 设为该弹幕的 timeMs 走现有调度
    for (final item in candidatesToEmit) {
      _clockMs = item.timeMs.toDouble();
      _tryEmit(item, checkFilter: false);
    }

    // 4. 补完恢复 _clockMs 为 targetClockMs，_cursor 指向 targetClockMs 之后的第一条
    _clockMs = targetClockMs;
    _cursor = _lowerBound(items, targetClockMs + 0.0001);

    var nextExp = double.infinity;
    for (final entry in _activeEntries) {
      nextExp = math.min(nextExp, entry.endMs);
    }
    _nextExpiryMs = nextExp;

    _perfStats.updateActiveCount(_activeEntries.length);
    _repaintNotifier.value++;
    _scheduleWork(forceWake: true);
  }

  /// 特殊处理说明：
  /// 多端型态自适应弹幕字号计算：
  /// 1. Windows / Desktop 桌面端：显示器物理面积大且视距远（50~70cm），解开原 18.9px 锁死限制，
  ///    对齐 B 站桌面网页 25px 与 animaku 桌面标定，在 [19.0, 24.5] 之间随视口平滑缩放；
  /// 2. Tablet 平板端（shortestSide >= 600）：屏幕大（10~13英寸），字号平滑标定在 [19.0, 22.0] 之间；
  /// 3. Mobile Phone 手机端：
  ///    - 横屏全屏（viewHeight < 600）基于短边高度限高在 [11.0, 14.0] 之间（animaku 黄金法则），防止糊屏；
  ///    - 竖屏模式基于 18px 基准缩放（[0.70, 1.05] 约 13~19px）。
  double _calculateCalculatedFontSize() {
    final settings = _controller.settings;
    final baseScale = settings.fontSizeScale;

    // 1. 桌面端 (Windows / macOS / Linux 且处于常规大窗形态)
    if (_isDesktop && _viewWidth >= 600.0 && _viewHeight > 260.0) {
      // 视口宽度 720 时约 21.2px，1080p 全屏 (1400~1920) 时平滑上升至 24.5px
      final targetBase = (19.0 + (_viewWidth / 960.0) * 3.0).clamp(19.0, 24.5);
      return targetBase * baseScale;
    }

    // 2. 平板端 (shortestSide >= 600)
    if (_isTablet && _viewWidth >= 600.0) {
      // 平板端适度收敛至 14.0~16.0px，大屏清爽细腻
      final targetBase = (14.0 + (_viewWidth / 1000.0) * 1.8).clamp(14.0, 16.0);
      return targetBase * baseScale;
    }

    // 3. 手机端或小窗形态 (Phone: shortestSide < 600 或桌面端缩窄小窗)
    // 动态基于视口高度与目标 10 轨道数推导，字号自然适中不糊屏
    final isWindowed = _viewHeight <= 260.0 || _viewWidth < 550.0;
    // 竖屏小窗目标锁定 10 轨；横屏全屏按高度自适应 14~18 轨
    final targetLanes = isWindowed
        ? 10.0
        : math.max(10.0, (_viewHeight / 24.0));
    final area = _controller.settings.area;
    final availableH = math.max(1.0, _viewHeight * area);
    final targetPitch = availableH / targetLanes;
    final rawFontPx = targetPitch / 1.35;
    final targetBase = isWindowed
        ? rawFontPx.clamp(9.5, 11.5)
        : rawFontPx.clamp(10.5, 12.0);
    return targetBase * baseScale;
  }

  void _rebuildTracks() {
    _layoutPool.clear();
    final fontPx = _calculateCalculatedFontSize();
    _lineHeight = fontPx * 1.25;
    final availableH = math.max(0.0, _viewHeight * _controller.settings.area);
    final trackPitch = _lineHeight * _kTrackSpacing;
    final rowCount = trackPitch > 0
        ? (availableH / trackPitch).floor()
        : 0;

    _scrollTracks = List.generate(rowCount, (_) => DanmakuScrollTrack());
    final fixedCount = math.max(1, rowCount ~/ 2);
    _topBusyUntil = List.filled(fixedCount, -double.infinity);
    _bottomBusyUntil = List.filled(fixedCount, -double.infinity);
  }

  void _clearActive() {
    for (final track in _scrollTracks) {
      track.reset();
    }
    _topBusyUntil.fillRange(0, _topBusyUntil.length, -double.infinity);
    _bottomBusyUntil.fillRange(0, _bottomBusyUntil.length, -double.infinity);

    for (final entry in _activeEntries) {
      entry.dispose();
    }
    _activeEntries.clear();
    _scrollingCount = 0;
    _nextExpiryMs = double.infinity;
  }

  // ==========================
  // DanmakuListener 实现
  // ==========================

  @override
  void onDanmakuTimeSync(Duration position) {
    final positionMs = position.inMilliseconds.toDouble();
    final drift = positionMs - _clockMs;

    // 1. 用户 Seek 大寻道 (|drift| > 600ms)：
    // 前沿立即执行 + 尾沿防抖 (Leading-edge Throttle + Trailing-edge Debounce)：
    // - 单次跳转（点击进度条 / 键盘按键快进）：0ms 立即原子重建，杜绝清屏空屏与闪烁！
    // - 连续快速拖拽：密集拖动期间清屏防错位，稳定 180ms 后完成最终重建。
    if (drift.abs() > _kSeekThresholdMs) {
      _clockMs = positionMs;
      _seekDebounceTimer?.cancel();

      final now = DateTime.now().millisecondsSinceEpoch;
      final elapsedSinceLastSeek = now - _lastSeekTimeMs;

      if (elapsedSinceLastSeek > 300) {
        // 单次跳转：前沿立即执行，零延迟原子重建，彻底消除 200ms 的空白与闪烁
        _lastSeekTimeMs = now;
        _rebuildScreenAt(_clockMs);
      } else {
        // 连续高频拖拽中：清屏防拉扯，防抖 180ms 稳定后更新最终位置
        _clearActive();
        _repaintNotifier.value++;
        _seekDebounceTimer = Timer(const Duration(milliseconds: 180), () {
          _seekDebounceTimer = null;
          if (!mounted || !_hasViewport) return;
          _lastSeekTimeMs = DateTime.now().millisecondsSinceEpoch;
          _rebuildScreenAt(_clockMs);
        });
      }
      return;
    }

    // 2. 正负对称死区 (|drift| <= 40ms)：
    // 吸收 24/30fps 解码步进与硬件采样抖动，不干预，保持绝对匀速
    if (drift.abs() <= _kSyncDeadbandMs) return;

    // 3. 一阶低通纠偏 (40ms < |drift| <= 600ms)：
    // 正负双向温和吸收漂移量 (alpha = 0.15)，杜绝向后微调时时钟死锁
    _clockMs += drift * _kSyncEmaAlpha;
  }

  @override
  void onDanmakuPlaybackRateChanged(double rate) {
    _scheduleWork(forceWake: true);
  }

  @override
  void onDanmakuItemsChanged() {
    _rebuildScreenAt(_clockMs);
  }

  @override
  void onDanmakuInject(DanmakuItem item) {
    if (!_hasViewport) return;
    _tryEmit(item, checkFilter: false);
    _scheduleWork();
  }

  @override
  void onDanmakuSettingsChanged(DanmakuSettings next, DanmakuSettings previous) {
    if (!next.enabled) {
      _clearActive();
      _stopWork();
    } else if (!previous.enabled) {
      _cursor = _lowerBound(_controller.items, _clockMs);
    }
    if (_hasViewport) {
      _rebuildTracks();
    }
    if (next.opacity != previous.opacity) {
      _layoutPool.clear();
    }
    _repaintNotifier.value++;
    if (next.enabled) {
      _scheduleWork(forceWake: true);
    }
  }

  @override
  void onDanmakuPause() {
    _stopWork();
  }

  @override
  void onDanmakuResume() {
    _scheduleWork();
  }

  @override
  void onDanmakuReset() {
    _stopWork();
    _clearActive();
    _cursor = 0;
    _clockMs = 0.0;
    _repaintNotifier.value++;
  }

  int _lowerBound(List<DanmakuItem> list, double targetMs) {
    var min = 0;
    var max = list.length;
    while (min < max) {
      final mid = min + ((max - min) >> 1);
      if (list[mid].timeMs < targetMs) {
        min = mid + 1;
      } else {
        max = mid;
      }
    }
    return min;
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.maybeOf(context);
    final shortestSide = mediaQuery?.size.shortestSide ?? 0.0;
    _updateDeviceInfo(shortestSide);
    final dpr = mediaQuery?.devicePixelRatio ?? 1.0;
    _dpr = dpr > 0.0 ? dpr : 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        _updateViewport(constraints);
        return IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              isComplex: true,
              willChange: true,
              painter: _DanmakuPainter(
                repaint: _repaintNotifier,
                state: this,
              ),
              child: const SizedBox.expand(),
            ),
          ),
        );
      },
    );
  }
}

/// 弹幕画布最终绘制器
class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter({
    required Listenable repaint,
    required this.state,
  }) : super(repaint: repaint);

  final _DanmakuViewState state;

  @override
  void paint(Canvas canvas, Size size) {
    if (!state._controller.settings.enabled || state._isViewportResizing) return;

    developer.Timeline.startSync('Danmaku.paint');
    try {
      final entries = state._activeEntries;
      final count = entries.length;
      if (count == 0) return;

      final now = state._clockMs;
      final width = size.width;
      final height = size.height;
      final dpr = state._dpr;

      // 特殊处理说明：
      // 彻底移除全屏 saveLayer！直接在文字 Paint 颜色与描边层混合透明度，
      // 杜绝 4K 120Hz 下每秒 4GB 的 GPU 离屏显存带宽雪崩，实现 100% 直通帧缓冲绘制。
      // Bilibili / animaku 三层 Z-Index 分层绘制管线 (直接内联循环，零闭包分配)：
      // Pass 1: 滚动弹幕（底层，绝不遮挡重要字幕，x 坐标物理像素对齐）
      for (var i = 0; i < count; i++) {
        final entry = entries[i];
        if (entry.mode != DanmakuMode.scroll) continue;
        final rawX = width - (now - entry.startMs) * entry.speed;
        final x = (rawX * dpr).roundToDouble() / dpr;
        final textSize = entry.layout.size;
        if (x >= width || x + textSize.width <= 0) continue;
        if (entry.y >= height || entry.y + textSize.height <= 0) continue;
        entry.layout.paintAt(canvas, x, entry.y);
      }

      // Pass 2: 底部固定弹幕（中层字幕与歌词译文）
      for (var i = 0; i < count; i++) {
        final entry = entries[i];
        if (entry.mode != DanmakuMode.bottom) continue;
        final x = entry.x;
        final textSize = entry.layout.size;
        if (x >= width || x + textSize.width <= 0) continue;
        if (entry.y >= height || entry.y + textSize.height <= 0) continue;
        entry.layout.paintAt(canvas, x, entry.y);
      }

      // Pass 3: 顶部固定弹幕（顶层高能预警与剧情注解）
      for (var i = 0; i < count; i++) {
        final entry = entries[i];
        if (entry.mode != DanmakuMode.top) continue;
        final x = entry.x;
        final textSize = entry.layout.size;
        if (x >= width || x + textSize.width <= 0) continue;
        if (entry.y >= height || entry.y + textSize.height <= 0) continue;
        entry.layout.paintAt(canvas, x, entry.y);
      }
    } finally {
      developer.Timeline.finishSync();
    }
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter oldDelegate) => true;
}
