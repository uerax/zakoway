import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:zakoway/features/player/danmaku/models/danmaku_item.dart';
import 'package:zakoway/features/player/danmaku/utils/danmaku_filter_engine.dart';
import 'package:zakoway/features/player/services/player_preferences_service.dart';

/// 弹幕事件监听接口，由视图层 DanmakuView 实现并绑定
abstract interface class DanmakuListener {
  /// 时间轴平滑同步（常规连续位置对齐，不触发清屏）
  void onDanmakuTimeSync(Duration position);

  /// 显式寻道跳转（用户拖动进度条、快进快退触发的大跨步跳转，执行清屏与重排）
  void onDanmakuSeek(Duration position);

  /// 弹幕播放倍速改变
  void onDanmakuPlaybackRateChanged(double rate);

  /// 弹幕数据源重新加载或全量变更
  void onDanmakuItemsChanged();

  /// 用户实时注入新弹幕（自己发的或外部推送）
  void onDanmakuInject(DanmakuItem item);

  /// 弹幕设置变更
  void onDanmakuSettingsChanged(DanmakuSettings next, DanmakuSettings previous);

  /// 暂停
  void onDanmakuPause();

  /// 恢复播放
  void onDanmakuResume();

  /// 重置清屏
  void onDanmakuReset();
}

/// 弹幕业务调度控制器
class DanmakuController extends ChangeNotifier with WidgetsBindingObserver {
  DanmakuController({
    DanmakuSettings? initialSettings,
  }) : _settings = initialSettings ??
            (PlayerPreferencesService.instance.isInitialized
                ? PlayerPreferencesService.instance.danmakuSettings
                : const DanmakuSettings()) {
    _recompileFilters();
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  final List<DanmakuItem> _items = <DanmakuItem>[];
  late UnmodifiableListView<DanmakuItem> _itemsView =
      UnmodifiableListView<DanmakuItem>(_items);
  DanmakuSettings _settings;
  DanmakuListener? _listener;

  Timer? _saveDebounceTimer;
  DanmakuSettings? _pendingSaveSettings;

  bool _playing = false;
  double _playbackRate = 1.0;
  List<DanmakuCompiledRule> _compiledFilters = const [];
  bool _disposed = false;

  Duration? _lastPosition;
  final Stopwatch _syncStopwatch = Stopwatch();

  /// @visibleForTesting
  bool get hasPendingSaveForTest => _pendingSaveSettings != null;

  /// 控制器是否已销毁
  bool get isDisposed => _disposed;

  /// 最近一次同步的视频时间轴位置
  Duration? get lastPosition => _lastPosition;

  /// 计算基于最近一次采样时刻估算的当前视频位置：
  /// - 若播放中：初始时钟 = lastPosition + 距采样已过时间 × 倍速；
  /// - 若暂停：直接使用 lastPosition。
  Duration? get estimatedCurrentPosition {
    if (_lastPosition == null) return null;
    if (!_playing || !_syncStopwatch.isRunning) {
      return _lastPosition;
    }
    final elapsedUs = _syncStopwatch.elapsedMicroseconds;
    final progressUs = (elapsedUs * _playbackRate).round();
    return _lastPosition! + Duration(microseconds: progressUs);
  }

  /// 当前所有已就绪并排序的弹幕列表（只读视图，不复制底层列表）
  UnmodifiableListView<DanmakuItem> get items => _itemsView;

  /// 当前弹幕配置
  DanmakuSettings get settings => _settings;

  /// 是否正在播放
  bool get playing => _playing;

  /// 播放倍速
  double get playbackRate => _playbackRate;

  /// 挂载视图监听器
  void attach(DanmakuListener listener) {
    if (_disposed) return;
    _listener = listener;
  }

  /// 解绑视图监听器
  void detach(DanmakuListener listener) {
    if (identical(_listener, listener)) {
      _listener = null;
    }
  }

  /// 批量载入全集弹幕数据（内部自动按时间轴毫秒排序）
  void loadItems(List<DanmakuItem> newItems) {
    if (_disposed) return;
    _items.clear();
    _items.addAll(newItems);
    _items.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    _itemsView = UnmodifiableListView<DanmakuItem>(_items);
    _listener?.onDanmakuItemsChanged();
    notifyListeners();
  }

  /// 动态发射/注入单条弹幕
  void inject(DanmakuItem item) {
    if (_disposed) return;
    _listener?.onDanmakuInject(item);
  }

  /// 特殊处理说明：
  /// 本地持久化落盘 400ms 防抖刷盘机制：
  /// 当滑块连续拖动时，推迟 JSON 序列化与 SharedPreferences 写入，
  /// 确保内存中的 _settings 与 PlayerPreferencesService 内存态立即生效，杜绝多余 I/O 挤占系统资源。
  void _flushSaveSettings() {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = null;
    final toSave = _pendingSaveSettings;
    if (toSave != null) {
      _pendingSaveSettings = null;
      PlayerPreferencesService.instance.writeDanmakuSettingsToDisk(toSave).ignore();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 特殊处理说明：
    // 当应用进入后台、窗口失焦或关闭时，若仍有未落盘的弹幕设置，必须立刻刷盘，避免配置丢失。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _flushSaveSettings();
    }
  }

  /// 更新弹幕配置项
  void updateSettings(DanmakuSettings newSettings) {
    if (_disposed) return;
    final previous = _settings;
    if (previous == newSettings) return;
    _settings = newSettings;
    _recompileFilters();
    _listener?.onDanmakuSettingsChanged(_settings, previous);
    notifyListeners();

    // 内存状态与通知保持立即生效
    PlayerPreferencesService.instance.updateDanmakuSettingsMemory(newSettings);

    // 磁盘持久化写入做 400ms 防抖
    _pendingSaveSettings = newSettings;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      _flushSaveSettings();
    });
  }

  /// 同步视频时间轴
  void syncTime(Duration position) {
    if (_disposed) return;
    _lastPosition = position;
    _syncStopwatch
      ..reset()
      ..start();
    _listener?.onDanmakuTimeSync(position);
  }

  /// 显式用户寻道跳转（触发清屏重定位）
  void seek(Duration position) {
    if (_disposed) return;
    _lastPosition = position;
    _syncStopwatch
      ..reset()
      ..start();
    _listener?.onDanmakuSeek(position);
  }

  /// 播放倍速联动
  void setPlaybackRate(double rate) {
    if (_disposed || _playbackRate == rate) return;
    if (_playing && _syncStopwatch.isRunning && _lastPosition != null) {
      final elapsedUs = _syncStopwatch.elapsedMicroseconds;
      final progressUs = (elapsedUs * _playbackRate).round();
      _lastPosition = _lastPosition! + Duration(microseconds: progressUs);
      _syncStopwatch.reset();
      _syncStopwatch.start();
    }
    _playbackRate = math.max(0.1, rate);
    _listener?.onDanmakuPlaybackRateChanged(_playbackRate);
    notifyListeners();
  }

  /// 播放状态控制：播放
  void resume() {
    if (_disposed) return;
    _playing = true;
    if (_lastPosition != null && !_syncStopwatch.isRunning) {
      _syncStopwatch.start();
    }
    _listener?.onDanmakuResume();
    notifyListeners();
  }

  /// 播放状态控制：暂停
  void pause() {
    if (_disposed) return;
    _playing = false;
    if (_syncStopwatch.isRunning) {
      final elapsedUs = _syncStopwatch.elapsedMicroseconds;
      final progressUs = (elapsedUs * _playbackRate).round();
      if (_lastPosition != null) {
        _lastPosition = _lastPosition! + Duration(microseconds: progressUs);
      }
      _syncStopwatch.reset();
    }
    _listener?.onDanmakuPause();
    notifyListeners();
  }

  /// 清空当前屏幕与状态
  void reset() {
    if (_disposed) return;
    _lastPosition = null;
    _syncStopwatch.reset();
    _listener?.onDanmakuReset();
  }

  /// 清空所有数据
  void clearAll() {
    if (_disposed) return;
    _items.clear();
    _itemsView = UnmodifiableListView<DanmakuItem>(_items);
    reset();
    notifyListeners();
  }

  /// 检查某条文本是否命中屏蔽过滤规则
  bool isBlocked(String text) {
    for (final filter in _compiledFilters) {
      if (filter.matches(text)) return true;
    }
    return false;
  }

  void _recompileFilters() {
    _compiledFilters = DanmakuFilterEngine.compileRules(_settings.filters);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _flushSaveSettings();
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _disposed = true;
    _syncStopwatch.stop();
    _listener = null;
    super.dispose();
  }
}
