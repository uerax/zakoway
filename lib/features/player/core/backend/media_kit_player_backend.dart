library;

import 'dart:async';
import 'package:media_kit/media_kit.dart';

import '../classifier/player_log_classifier.dart';
import '../models/backend_error.dart';
import 'backend_event.dart';
import 'native_mpv_policy.dart';
import 'player_backend.dart';
import 'shader_queue_manager.dart';

/// 逐流初始重置标记跟踪器
///
/// 遵循 docs/player-rewrite/09-adapter-plan.md 2.3 节规范
/// 单次 open 期间每个通道只允许捕获一次初始物理重置信号 (isResetMarker = true)
class StreamResetTracker {
  bool playingResetCaptured = false;
  bool bufferingResetCaptured = false;
  bool positionResetCaptured = false;
  bool durationResetCaptured = false;
  bool bufferResetCaptured = false;
  bool dimensionsResetCaptured = false;

  void reset() {
    playingResetCaptured = false;
    bufferingResetCaptured = false;
    positionResetCaptured = false;
    durationResetCaptured = false;
    bufferResetCaptured = false;
    dimensionsResetCaptured = false;
  }
}

/// 底层 原生属性写入接口（便于离线单元测试与依赖注入）
typedef NativePropertyWriter = Future<void> Function(String key, String value);

/// media_kit 与 libmpv 播放引擎适配器实现
///
/// 遵循 docs/player-rewrite/09-adapter-plan.md (v1.0)
/// 核心职责：
/// 1. 代际隔离打戳：beginOpen() 同步自增代际，各状态广播事件均携带 generationId；
/// 2. 逐流重置标记：StreamResetTracker 保证单次 open 各流重置标记只捕获一次；
/// 3. 日志与错误分类：订阅 stream.log 与 stream.error (MPVLogLevel.error 级别)，挂载单次 open 独立 PlayerLogClassifier；
/// 4. 真实视频轨过滤：realVideoTrackCount 过滤内置 auto/no 占位轨；
/// 5. 辅助特性保留：muteForExit 轻量静音、非阻塞 dispose、计量网络水线热更新、Anime4K 4秒熔断着色器队列。
class MediaKitPlayerBackend implements PlayerBackend {
  MediaKitPlayerBackend({
    Player? player,
    NativeMpvPolicy? policy,
    ShaderQueueManager? shaderQueueManager,
    this.propertyWriter,
  })  : _player = player ??
            Player(
              configuration: const PlayerConfiguration(
                title: 'zakoway Player',
                logLevel: MPVLogLevel.error,
                libass: true, // 开启原生 libass 特效字幕与字体排版渲染引擎
              ),
            ),
        policy = policy ?? const NativeMpvPolicy(),
        _shaderQueueManager = shaderQueueManager ?? ShaderQueueManager() {
    _initSubscriptions();
  }

  final Player _player;

  /// 底层 mpv 属性配置策略
  final NativeMpvPolicy policy;

  final ShaderQueueManager _shaderQueueManager;
  final StreamResetTracker _resetTracker = StreamResetTracker();
  final NativePropertyWriter? propertyWriter;

  bool _isInitialized = false;

  /// 底层 mpv 属性是否已完成初始化
  bool get isInitialized => _isInitialized;

  int _currentGenerationId = 0;
  DateTime? _openTime;
  PlayerLogClassifier? _classifier;
  bool _hasEmittedErrorForCurrentOpen = false;
  int _cachedRealVideoTrackCount = 1;
  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  int? _streamWidth;
  int? _streamHeight;
  int? _videoParamsDw;
  int? _videoParamsDh;
  int? _lastEmittedWidth = -1;
  int? _lastEmittedHeight = -1;

  final List<StreamSubscription<dynamic>> _subscriptions = [];

  // ===== 广播流控制器 =====
  final StreamController<BackendEvent<bool>> _playingController =
      StreamController.broadcast();
  final StreamController<BackendEvent<bool>> _bufferingController =
      StreamController.broadcast();
  final StreamController<BackendEvent<Duration>> _positionController =
      StreamController.broadcast();
  final StreamController<BackendEvent<Duration>> _durationController =
      StreamController.broadcast();
  final StreamController<BackendEvent<Duration>> _bufferController =
      StreamController.broadcast();
  final StreamController<BackendEvent<VideoDimensions>> _dimensionsController =
      StreamController.broadcast();
  final StreamController<BackendEvent<bool>> _completedController =
      StreamController.broadcast();
  final StreamController<BackendError> _errorController =
      StreamController.broadcast();
  final StreamController<PlayerLogMessage> _logController =
      StreamController.broadcast();

  // ===========================================================================
  // PlayerBackend 抽象契约实现
  // ===========================================================================

  Future<void> _setProperty(String key, String value) async {
    if (propertyWriter != null) {
      await propertyWriter!(key, value);
      return;
    }
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await platform.setProperty(key, value);
    }
  }

  /// 初始化播放器底层引擎并配置原生属性
  ///
  /// 调用时机：在创建 [PlayerBackend] 之后、第一次调用 [open] 之前显式调用。
  /// 若上层未显式调用，[open] 内部将在第一次打开媒体前自动以非计量网络（[isMeteredNetwork] = false）完成兜底初始化。
  @override
  Future<void> initialize({required bool isMeteredNetwork}) async {
    await _player.platform?.waitForPlayerInitialization;
    final props = policy.toMpvProperties(isMeteredNetwork: isMeteredNetwork);
    for (final entry in props.entries) {
      await _setProperty(entry.key, entry.value);
    }
    _isInitialized = true;
  }

  @override
  int beginOpen() {
    _currentGenerationId++;
    return _currentGenerationId;
  }

  @override
  Future<void> open(
    String uri, {
    Map<String, String>? headers,
    Duration? start,
    bool autoplay = true,
    required int generationId,
  }) async {
    // 若尚未显式初始化，兜底执行初始化（默认非计量网络）
    if (!_isInitialized) {
      await initialize(isMeteredNetwork: false);
    }

    _currentGenerationId = generationId;
    _hasEmittedErrorForCurrentOpen = false;
    _resetTracker.reset();
    _streamWidth = null;
    _streamHeight = null;
    _videoParamsDw = null;
    _videoParamsDh = null;
    _lastEmittedWidth = -1;
    _lastEmittedHeight = -1;

    final targetUri = Uri.tryParse(uri);
    _openTime = DateTime.now();
    _classifier = targetUri != null
        ? PlayerLogClassifier(expectedUrl: targetUri)
        : null;

    // 确保底层 mpv C 实例与日志订阅管道完全就绪
    await _player.platform?.waitForPlayerInitialization;

    // 起播阶段重置为极速起播水线 (预读 1s 即出画)
    await resetToStartupWatermark();

    final media = Media(
      uri,
      httpHeaders: headers,
      start: start,
    );

    await _player.open(media, play: autoplay);
  }

  @override
  Future<void> play() async {
    await _player.play();
  }

  @override
  Future<void> pause() async {
    await _player.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  @override
  int get realVideoTrackCount => _cachedRealVideoTrackCount;

  @override
  Stream<BackendEvent<bool>> get onPlayingChanged => _playingController.stream;

  @override
  Stream<BackendEvent<bool>> get onBufferingChanged =>
      _bufferingController.stream;

  @override
  Stream<BackendEvent<Duration>> get onPositionChanged =>
      _positionController.stream;

  @override
  Stream<BackendEvent<Duration>> get onDurationChanged =>
      _durationController.stream;

  @override
  Stream<BackendEvent<Duration>> get onBufferChanged => _bufferController.stream;

  @override
  Stream<BackendEvent<VideoDimensions>> get onDimensionsChanged =>
      _dimensionsController.stream;

  @override
  Stream<BackendEvent<bool>> get onCompletedChanged =>
      _completedController.stream;

  @override
  Stream<BackendError> get onErrorOccurred => _errorController.stream;

  @override
  Stream<PlayerLogMessage> get onLog => _logController.stream;

  // ===========================================================================
  // 底层流订阅与事件包装分发
  // ===========================================================================

  void _initSubscriptions() {
    _subscriptions.add(
      _player.stream.playing.listen((isPlaying) {
        if (_isDisposed) return;
        final isReset = !_resetTracker.playingResetCaptured;
        if (isReset) {
          _resetTracker.playingResetCaptured = true;
          _classifier?.reset();
        }
        _playingController.add(BackendEvent<bool>(
          isPlaying,
          generationId: _currentGenerationId,
          isResetMarker: isReset,
        ));
      }),
    );

    _subscriptions.add(
      _player.stream.buffering.listen((isBuffering) {
        if (_isDisposed) return;
        final isReset = !_resetTracker.bufferingResetCaptured;
        if (isReset) {
          _resetTracker.bufferingResetCaptured = true;
          _classifier?.reset();
        }
        _bufferingController.add(BackendEvent<bool>(
          isBuffering,
          generationId: _currentGenerationId,
          isResetMarker: isReset,
        ));
      }),
    );

    _subscriptions.add(
      _player.stream.position.listen((pos) {
        if (_isDisposed) return;
        final isReset = !_resetTracker.positionResetCaptured;
        if (isReset) {
          _resetTracker.positionResetCaptured = true;
          _classifier?.reset();
        }
        _positionController.add(BackendEvent<Duration>(
          pos,
          generationId: _currentGenerationId,
          isResetMarker: isReset,
        ));
      }),
    );

    _subscriptions.add(
      _player.stream.duration.listen((dur) {
        if (_isDisposed) return;
        final isReset = !_resetTracker.durationResetCaptured;
        if (isReset) {
          _resetTracker.durationResetCaptured = true;
          _classifier?.reset();
        }
        _durationController.add(BackendEvent<Duration>(
          dur,
          generationId: _currentGenerationId,
          isResetMarker: isReset,
        ));
      }),
    );

    _subscriptions.add(
      _player.stream.buffer.listen((buf) {
        if (_isDisposed) return;
        final isReset = !_resetTracker.bufferResetCaptured;
        if (isReset) {
          _resetTracker.bufferResetCaptured = true;
          _classifier?.reset();
        }
        _bufferController.add(BackendEvent<Duration>(
          buf,
          generationId: _currentGenerationId,
          isResetMarker: isReset,
        ));
      }),
    );

    _subscriptions.add(
      _player.stream.width.listen((w) {
        if (_isDisposed) return;
        _streamWidth = w;
        _updateDimensions();
      }),
    );

    _subscriptions.add(
      _player.stream.height.listen((h) {
        if (_isDisposed) return;
        _streamHeight = h;
        _updateDimensions();
      }),
    );

    _subscriptions.add(
      _player.stream.videoParams.listen((params) {
        if (_isDisposed) return;
        _videoParamsDw = params.dw;
        _videoParamsDh = params.dh;
        _updateDimensions();
      }),
    );

    _subscriptions.add(
      _player.stream.completed.listen((isCompleted) {
        if (_isDisposed) return;
        // completed 流切集时不发射重置标记，一律标为 false
        _completedController.add(BackendEvent<bool>(
          isCompleted,
          generationId: _currentGenerationId,
          isResetMarker: false,
        ));
      }),
    );

    _subscriptions.add(
      _player.stream.tracks.listen((tracks) {
        if (_isDisposed) return;
        _cachedRealVideoTrackCount =
            filterRealVideoTracks(tracks.video).length;
      }),
    );

    _subscriptions.add(
      _player.stream.log.listen((log) {
        if (_isDisposed) return;
        final now = DateTime.now();
        final relativeTime =
            _openTime != null ? now.difference(_openTime!) : Duration.zero;

        final logMsg = PlayerLogMessage(
          prefix: log.prefix,
          level: log.level,
          text: log.text,
          timestamp: now,
          generationId: _currentGenerationId,
        );
        _logController.add(logMsg);

        if (_classifier != null) {
          _classifier!.onLogReceived(
            source: 'stream.log',
            level: log.level,
            prefix: log.prefix,
            text: log.text,
            relativeTime: relativeTime,
          );
          final err = _classifier!.evaluate(relativeTime);
          if (err != null && !_hasEmittedErrorForCurrentOpen) {
            _hasEmittedErrorForCurrentOpen = true;
            _errorController.add(err);
          }
        }
      }),
    );

    _subscriptions.add(
      _player.stream.error.listen((errorText) {
        if (_isDisposed) return;
        final now = DateTime.now();
        final relativeTime =
            _openTime != null ? now.difference(_openTime!) : Duration.zero;

        final logMsg = PlayerLogMessage(
          prefix: 'mpv',
          level: 'error',
          text: errorText,
          timestamp: now,
          generationId: _currentGenerationId,
        );
        _logController.add(logMsg);

        if (_classifier != null) {
          _classifier!.onLogReceived(
            source: 'stream.error',
            level: 'error',
            prefix: 'mpv',
            text: errorText,
            relativeTime: relativeTime,
          );
          final err = _classifier!.evaluate(relativeTime);
          if (err != null && !_hasEmittedErrorForCurrentOpen) {
            _hasEmittedErrorForCurrentOpen = true;
            _errorController.add(err);
          }
        }
      }),
    );
  }

  void _updateDimensions() {
    if (_isDisposed) return;
    // 渲染尺寸优先：优先 stream.width / stream.height 非空，其次 videoParams 的 dw/dh 非空；不再使用容器尺寸 w/h
    final w = _streamWidth ?? _videoParamsDw;
    final h = _streamHeight ?? _videoParamsDh;
    final isReset = !_resetTracker.dimensionsResetCaptured;
    if (isReset) {
      _resetTracker.dimensionsResetCaptured = true;
      _classifier?.reset();
    } else if (w == _lastEmittedWidth && h == _lastEmittedHeight) {
      return;
    }
    _lastEmittedWidth = w;
    _lastEmittedHeight = h;
    _dimensionsController.add(BackendEvent<VideoDimensions>(
      VideoDimensions(w, h),
      generationId: _currentGenerationId,
      isResetMarker: isReset,
    ));
  }

  // ===========================================================================
  // 辅助特性与生命周期实现
  // ===========================================================================

  /// 底层原生 Player 实例句柄（供 UI Video 渲染组件挂载）
  Player get rawPlayer => _player;

  /// 重置标记跟踪器（供测试观察与断言）
  StreamResetTracker get resetTracker => _resetTracker;

  /// 当前代际号
  int get currentGenerationId => _currentGenerationId;

  /// 过滤排除底层内置 auto 与 no 等占位轨道的真实视频轨数量
  static List<VideoTrack> filterRealVideoTracks(Iterable<VideoTrack> tracks) {
    return tracks.where((t) => t.id != 'auto' && t.id != 'no').toList();
  }

  /// 退出页面前轻量静音（不触发音量偏好持久化）
  Future<void> muteForExit() async {
    try {
      await _player.setVolume(0.0);
    } catch (_) {}
  }

  /// 计量网络（移动蜂窝 vs Wi-Fi）缓冲水线在线热更新
  Future<void> updateDemuxerCacheWatermark({
    required bool isMeteredNetwork,
  }) async {
    try {
      final props = policy.getDemuxerWatermarkProperties(
        isMeteredNetwork: isMeteredNetwork,
      );
      for (final entry in props.entries) {
        await _setProperty(entry.key, entry.value);
      }
    } catch (_) {}
  }

  /// 将解复用器缓冲水线动态提升至巡航水位 (首帧物理出画后平滑提升蓄水量)
  Future<void> boostToSteadyWatermark() async {
    try {
      final props = policy.getSteadyBufferingProperties();
      for (final entry in props.entries) {
        await _setProperty(entry.key, entry.value);
      }
    } catch (_) {}
  }

  /// 重置为极速起播缓冲水线 (仅需 1s 数据即可完成解码出画)
  Future<void> resetToStartupWatermark() async {
    try {
      final props = policy.getStartupBufferingProperties();
      for (final entry in props.entries) {
        await _setProperty(entry.key, entry.value);
      }
    } catch (_) {}
  }

  /// 动态应用 Anime4K 超分着色器链（4 秒熔断保护）
  Future<void> applyShaders(List<String> shaderPaths) async {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      await _shaderQueueManager.apply(platform.command, shaderPaths);
    }
  }

  /// 释放播放器底层资源
  ///
  /// [synchronized] 为 true 时同步等待底层 mpv 实例完全退出（适用于测试环境隔离）；
  /// 默认 false 时在后台微任务中脱钩异步释放，不阻断页面退出动画（生产规范）。
  @override
  Future<void> dispose({bool synchronized = false}) async {
    if (_isDisposed) return;
    _isDisposed = true;

    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    await _playingController.close();
    await _bufferingController.close();
    await _positionController.close();
    await _durationController.close();
    await _bufferController.close();
    await _dimensionsController.close();
    await _completedController.close();
    await _errorController.close();
    await _logController.close();

    _shaderQueueManager.reset();

    final p = _player;
    if (synchronized) {
      try {
        await p.pause();
        await p.dispose();
      } catch (_) {}
    } else {
      unawaited(() async {
        try {
          await p.pause();
          await p.dispose();
        } catch (_) {}
      }());
    }
  }
}
