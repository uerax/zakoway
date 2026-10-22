import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zakoway/core/services/network_connectivity_service.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/controller/playback_state.dart';
import 'package:zakoway/features/player/core/backend/media_kit_player_backend.dart';
import 'package:zakoway/features/player/core/backend/player_backend.dart';
import 'package:zakoway/features/player/core/fsm/playback_fsm.dart';
import 'package:zakoway/features/player/core/models/backend_error.dart';
import 'package:zakoway/features/player/core/models/playback_failure.dart';
import 'package:zakoway/features/player/core/models/playback_state.dart' as core_state;
import 'package:zakoway/features/player/core/models/resolved_media.dart';
import 'package:zakoway/features/player/services/player_preferences_service.dart';
import 'package:zakoway/features/player/services/shader_asset_service.dart';

/// 按照 04 设计规范清洗结构化错误文案，严禁在 UI 暴露原始 URL 或敏感 Token
String sanitizePlaybackError(BackendError? error, {String prefix = '播放失败'}) {
  if (error == null) return '$prefix: 发生未知网络异常，建议切换线路重试';
  switch (error.kind) {
    case BackendErrorKind.handshakeClosed:
      return '$prefix: 服务器在建立连接时关闭了连接，建议切换线路';
    case BackendErrorKind.openFailedUnknown:
      return '$prefix: 视频源加载异常，建议重试或切换线路';
    case BackendErrorKind.dnsResolutionFailed:
      return '$prefix: 域名解析失败，请检查网络设置或切换线路';
    case BackendErrorKind.connectTimeout:
      return '$prefix: 连接视频服务器超时，建议切换线路';
    case BackendErrorKind.openDemuxWatchdog:
      return '$prefix: 媒体解析响应超时，建议切换线路';
    case BackendErrorKind.unknown:
      return '$prefix: 发生未知网络异常，建议切换线路重试';
  }
}

/// 重写后的播放器控制门面 (RewrittenPlaybackController)
///
/// 遵循 docs/player-rewrite/11-facade-plan.md
/// 组合 PlaybackFsm + MediaKitPlayerBackend，对外 100% 遵守 PlaybackController 接口，
/// 同时实现 ZakowayPlaybackController 接口以无缝兼容现有所有 Widget 与测试代码。
class RewrittenPlaybackController implements PlaybackController, ZakowayPlaybackController {
  RewrittenPlaybackController({
    PlayerBackend? backend,
    Future<ResolvedMedia> Function({required bool bypassCache})? onResolve,
  })  : _injectedBackend = backend,
        _injectedOnResolve = onResolve;

  final PlayerBackend? _injectedBackend;
  final Future<ResolvedMedia> Function({required bool bypassCache})? _injectedOnResolve;

  // ===== UI 通知器 =====
  @override
  final ValueNotifier<PlaybackCoreState> core =
      ValueNotifier<PlaybackCoreState>(const PlaybackCoreState());

  @override
  final ValueNotifier<PlaybackTimelineState> timeline =
      ValueNotifier<PlaybackTimelineState>(const PlaybackTimelineState());

  @override
  final ValueNotifier<VideoController?> videoControllerNotifier =
      ValueNotifier<VideoController?>(null);

  final ValueNotifier<PlaybackFailure?> _failureNotifier =
      ValueNotifier<PlaybackFailure?>(null);
  final ValueNotifier<bool> _showLineSwitchPromptNotifier =
      ValueNotifier<bool>(false);

  ValueListenable<PlaybackFailure?> get failureNotifier => _failureNotifier;
  ValueListenable<bool> get showLineSwitchPromptNotifier =>
      _showLineSwitchPromptNotifier;

  // ===== 页面委托回调 =====
  VoidCallback? onRetryRequested;
  VoidCallback? onSwitchLineRequested;

  // ===== 核心组件引用 =====
  PlayerBackend? _backend;
  PlaybackFsm? _fsm;
  VideoController? _videoController;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _timelineThrottleTimer;
  Duration _lastPosition = Duration.zero;
  final Stopwatch _positionClock = Stopwatch()..start();
  Duration _lastPositionAt = Duration.zero;
  Duration _lastDuration = Duration.zero;
  Duration _lastBuffer = Duration.zero;

  bool _disposed = false;
  String? _currentUri;
  double _preMuteVolume = 1.0;
  bool _isInitialized = false;

  @override
  bool get isDisposed => _disposed;

  @override
  Player? get rawPlayer => _backend is MediaKitPlayerBackend
      ? (_backend as MediaKitPlayerBackend).rawPlayer
      : null;

  @override
  String? get currentUri => _currentUri;

  /// 暴露状态机引用供底层调试或深度测试使用
  PlaybackFsm? get fsm => _fsm;

  /// 暴露后端引用
  PlayerBackend? get backend => _backend;

  // ===========================================================================
  // 初始化与起播
  // ===========================================================================

  @override
  Future<void> initialize() async {
    if (_isInitialized || _disposed) return;
    _isInitialized = true;

    final isMetered = NetworkConnectivityService.instance.isMetered;
    core.value = core.value.copyWith(isMeteredNetwork: isMetered);

    // 1. 初始化或复用 Backend
    _backend = _injectedBackend ?? MediaKitPlayerBackend();
    await _backend!.initialize(isMeteredNetwork: isMetered);

    // 2. 若为原生媒体后端，装配 VideoController
    if (_backend is MediaKitPlayerBackend) {
      final nativeBackend = _backend as MediaKitPlayerBackend;
      _videoController = VideoController(
        nativeBackend.rawPlayer,
        configuration: const VideoControllerConfiguration(
          enableHardwareAcceleration: true,
        ),
      );
      videoControllerNotifier.value = _videoController;
    }

    // 3. 恢复用户偏好（倍速、音量、超分辨率）
    await PlayerPreferencesService.instance.initialize();
    final savedRate = PlayerPreferencesService.instance.playbackRate;
    final savedVolume = PlayerPreferencesService.instance.volume;
    final savedSuperRes = PlayerPreferencesService.instance.superResolutionMode;

    core.value = core.value.copyWith(
      playbackRate: savedRate,
      volume: savedVolume,
      muted: savedVolume <= 0.001,
      superResolution: savedSuperRes,
    );

    if (rawPlayer != null) {
      if (savedRate != 1.0) {
        await rawPlayer!.setRate(savedRate);
      }
      await rawPlayer!.setVolume(savedVolume * 100.0);
    }

    // 4. 构建并装载 PlaybackFsm
    _fsm = PlaybackFsm(
      backend: _backend!,
      onResolve: _injectedOnResolve ??
          ({required bool bypassCache}) async {
            return ResolvedMedia(url: _currentUri ?? '');
          },
    );

    // 5. 绑定 FSM 与 Backend 状态通知器
    _bindFsmSubscriptions();
  }

  void _bindFsmSubscriptions() {
    if (_fsm == null) return;

    // 监听 FSM coreState 并投影映射至现有 PlaybackCoreState
    _fsm!.coreNotifier.addListener(_onFsmCoreStateChanged);

    // 监听 FSM failure 并派发
    _fsm!.failureNotifier.addListener(() {
      _failureNotifier.value = _fsm!.failure;
    });

    // 监听换线提示条
    _fsm!.showLineSwitchPromptNotifier.addListener(() {
      _showLineSwitchPromptNotifier.value = _fsm!.showLineSwitchPrompt;
    });

    // 绑定高频时间线事件（250ms 节流）
    _subscriptions.add(
      _backend!.onPositionChanged.listen((e) {
        if (_disposed) return;
        _lastPosition = e.data;
        _lastPositionAt = _positionClock.elapsed;
        _scheduleTimelineEmit();
      }),
    );

    _subscriptions.add(
      _backend!.onDurationChanged.listen((e) {
        if (_disposed) return;
        _lastDuration = e.data;
        _scheduleTimelineEmit();
      }),
    );

    _subscriptions.add(
      _backend!.onBufferChanged.listen((e) {
        if (_disposed) return;
        _lastBuffer = e.data;
        _scheduleTimelineEmit();
      }),
    );

    // 动态网络环境监听
    _subscriptions.add(
      NetworkConnectivityService.instance.onMeteredChanged.listen((metered) {
        if (_disposed) return;
        core.value = core.value.copyWith(isMeteredNetwork: metered);
        if (_backend is MediaKitPlayerBackend) {
          (_backend as MediaKitPlayerBackend)
              .updateDemuxerCacheWatermark(isMeteredNetwork: metered)
              .ignore();
        }
      }),
    );
  }

  void _onFsmCoreStateChanged() {
    if (_disposed || _fsm == null) return;
    final fsmState = _fsm!.state;
    final fsmCore = _fsm!.coreState;
    final failure = _fsm!.failure;

    final isPlaying = fsmState == core_state.PlaybackState.playing;
    final isLoading = fsmState == core_state.PlaybackState.resolving ||
        fsmState == core_state.PlaybackState.preparing ||
        fsmState == core_state.PlaybackState.recovering ||
        !fsmCore.firstFrameRendered;
    final isBuffering = fsmState == core_state.PlaybackState.prebuffering ||
        fsmState == core_state.PlaybackState.rebuffering ||
        fsmState == core_state.PlaybackState.seeking;
    final isCompleted = fsmState == core_state.PlaybackState.completed;
    final hasFirstFrame = fsmCore.firstFrameRendered;

    final errorMsg = fsmState == core_state.PlaybackState.error
        ? (failure != null
            ? sanitizePlaybackError(BackendError(
                kind: failure.kind,
                action: failure.action,
                rawMessage: failure.message,
                host: failure.host,
                port: failure.port,
                relativeTime: Duration.zero,
              ))
            : fsmCore.errorMessage ?? '视频播放失败')
        : null;

    core.value = core.value.copyWith(
      playing: isPlaying,
      loading: isLoading,
      buffering: isBuffering,
      completed: isCompleted,
      firstFrameRendered: hasFirstFrame,
      errorMessage: errorMsg,
      clearError: fsmState != core_state.PlaybackState.error,
    );

    // 首帧物理出画后才注入 Anime4K 着色器
    if (hasFirstFrame && core.value.superResolution != SuperResolutionMode.off) {
      _applySuperResolutionToBackend(core.value.superResolution).ignore();
    }
  }

  Future<void> _applySuperResolutionToBackend(SuperResolutionMode mode) async {
    if (_backend is! MediaKitPlayerBackend) return;
    final nativeBackend = _backend as MediaKitPlayerBackend;
    if (mode == SuperResolutionMode.off) {
      await nativeBackend.applyShaders(const []);
    } else {
      final isQuality = mode == SuperResolutionMode.quality;
      final shaderPath = await ShaderAssetService.instance.getShadersPathForMode(isQuality: isQuality);
      if (shaderPath != null && shaderPath.isNotEmpty) {
        final separator = Platform.isWindows ? ';' : ':';
        final paths = shaderPath.split(separator).where((s) => s.isNotEmpty).toList();
        await nativeBackend.applyShaders(paths);
      }
    }
  }

  @override
  Future<void> open(
    String uri, {
    Map<String, String>? httpHeaders,
    Duration? start,
    bool autoplay = true,
  }) async {
    _currentUri = uri;

    // 起播/切集立即进入 loading 状态并撤销首帧遮罩标记，防止残影
    core.value = core.value.copyWith(
      loading: true,
      firstFrameRendered: false,
      clearError: true,
      completed: false,
    );

    timeline.value = const PlaybackTimelineState(
      position: Duration.zero,
      duration: Duration.zero,
      buffer: Duration.zero,
    );

    if (!_isInitialized) {
      await initialize();
    }

    if (_fsm != null) {
      await _fsm!.load(
        uri,
        startPosition: start,
        autoplay: autoplay,
        headers: httpHeaders,
      );
    }
  }

  // ===========================================================================
  // 基础播放控制
  // ===========================================================================

  @override
  Future<void> togglePlay() async {
    if (_disposed) return;
    if (_fsm == null) {
      core.value = core.value.copyWith(playing: !core.value.playing);
      return;
    }
    if (core.value.playing) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> play() async {
    if (_disposed) return;
    if (_fsm == null) {
      core.value = core.value.copyWith(playing: true);
      return;
    }
    await _fsm!.play();
  }

  @override
  Future<void> pause() async {
    if (_disposed) return;
    if (_fsm == null) {
      core.value = core.value.copyWith(playing: false);
      return;
    }
    await _fsm!.pause();
  }

  @override
  Future<void> seek(Duration target) async {
    if (_disposed) return;
    final dur = timeline.value.duration;
    var targetPosition = target < Duration.zero ? Duration.zero : target;

    // 特殊处理说明：Seek 终点 500ms 截断保护 (TC-07 与 11 号文档规范)
    if (dur > const Duration(seconds: 1) && targetPosition >= dur) {
      targetPosition = dur - const Duration(milliseconds: 500);
      if (targetPosition < Duration.zero) {
        targetPosition = Duration.zero;
      }
    }

    _lastPosition = targetPosition;
    _lastPositionAt = _positionClock.elapsed;

    timeline.value = timeline.value.copyWith(
      position: targetPosition,
      clearPreview: true,
    );

    // Seek 主动清除偶发错误与 completed 状态
    if (core.value.hasError || core.value.completed) {
      core.value = core.value.copyWith(
        clearError: true,
        completed: false,
      );
    }

    if (_fsm != null) {
      await _fsm!.seek(targetPosition);
    }
  }

  @override
  void updateSeekPreview(Duration previewTarget) {
    timeline.value = timeline.value.copyWith(previewPosition: previewTarget);
  }

  @override
  Future<void> endSeekPreview() async {
    final preview = timeline.value.previewPosition;
    if (preview != null) {
      await seek(preview);
    }
  }

  @override
  Future<void> seekBy(Duration offset) async {
    final current = timeline.value.position;
    final target = current + offset;
    await seek(target);
  }

  // ===========================================================================
  // 倍速、音量与超分辨率偏好控制
  // ===========================================================================

  @override
  Future<void> setPlaybackRate(double rate) async {
    if (_disposed) return;
    final clampedRate = math.max(0.25, math.min(3.0, rate));
    core.value = core.value.copyWith(playbackRate: clampedRate);
    if (rawPlayer != null) {
      await rawPlayer!.setRate(clampedRate);
    }
    PlayerPreferencesService.instance.savePlaybackRate(clampedRate).ignore();
  }

  @override
  Future<void> setVolume(double vol) async {
    final clamped = math.max(0.0, math.min(1.0, vol));
    core.value = core.value.copyWith(
      volume: clamped,
      muted: clamped <= 0.001,
    );
    if (rawPlayer != null) {
      await rawPlayer!.setVolume(clamped * 100.0);
    }
    PlayerPreferencesService.instance.saveVolume(clamped).ignore();
  }

  @override
  Future<void> muteForExit() async {
    if (_backend is MediaKitPlayerBackend) {
      await (_backend as MediaKitPlayerBackend).muteForExit();
    } else if (rawPlayer != null) {
      try {
        await rawPlayer!.setVolume(0.0);
      } catch (_) {}
    }
  }

  @override
  Future<void> toggleMute() async {
    if (core.value.muted) {
      await setVolume(_preMuteVolume > 0.05 ? _preMuteVolume : 0.7);
    } else {
      _preMuteVolume = core.value.volume;
      await setVolume(0.0);
    }
  }

  @override
  void setVideoFit(BoxFit fit) {
    core.value = core.value.copyWith(videoFit: fit);
  }

  @override
  Future<void> setSuperResolution(
    SuperResolutionMode mode, {
    bool persist = true,
  }) async {
    core.value = core.value.copyWith(superResolution: mode);
    if (persist) {
      await PlayerPreferencesService.instance.saveSuperResolutionMode(mode);
    }
    if (core.value.firstFrameRendered) {
      await _applySuperResolutionToBackend(mode);
    }
  }

  @override
  Future<Uint8List?> screenshot({String format = 'image/png'}) async {
    final player = rawPlayer;
    if (player == null) return null;
    try {
      return await player.screenshot(format: format);
    } catch (_) {
      return null;
    }
  }

  // ===========================================================================
  // 弹幕时钟位置外推算法 (与旧控制器完全对齐)
  // ===========================================================================

  @override
  Duration get extrapolatedPosition {
    if (_disposed) return Duration.zero;
    final state = core.value;
    if (!state.playing || state.buffering) return timeline.value.position;
    final ageUs = (_positionClock.elapsed - _lastPositionAt).inMicroseconds;
    if (ageUs <= 0) return _lastPosition;
    final cappedUs = math.min(ageUs, 250000);
    return _lastPosition +
        Duration(microseconds: (cappedUs * state.playbackRate).round());
  }

  /// 250ms 节流触发时间线更新，杜绝高频重绘
  void _scheduleTimelineEmit() {
    if (_timelineThrottleTimer != null && _timelineThrottleTimer!.isActive) {
      return;
    }

    _timelineThrottleTimer = Timer(const Duration(milliseconds: 250), () {
      if (_disposed) return;
      timeline.value = timeline.value.copyWith(
        position: _lastPosition,
        duration: _lastDuration,
        buffer: _lastBuffer,
      );
    });
  }

  /// 供错误卡片点击重试时调用
  Future<void> retry() async {
    if (_disposed) return;
    onRetryRequested?.call();
    if (_fsm != null) {
      await _fsm!.retry();
    }
  }

  /// 供换线提示或错误卡片点击换线时调用
  void switchLine() {
    onSwitchLineRequested?.call();
  }

  // ===========================================================================
  // 资源销毁
  // ===========================================================================

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _timelineThrottleTimer?.cancel();
    _timelineThrottleTimer = null;

    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();

    if (_fsm != null) {
      _fsm!.coreNotifier.removeListener(_onFsmCoreStateChanged);
      await _fsm!.dispose();
      _fsm = null;
    }

    videoControllerNotifier.value = null;

    if (_backend != null) {
      // 遵循 TC-14 与 11 号文档：非阻塞脱钩释放底层 C 实例
      final b = _backend;
      _backend = null;
      unawaited(b!.dispose());
    }

    core.dispose();
    timeline.dispose();
    videoControllerNotifier.dispose();
    _failureNotifier.dispose();
    _showLineSwitchPromptNotifier.dispose();
  }
}
