import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zakoway/core/services/network_connectivity_service.dart';
import 'package:zakoway/features/player/controller/playback_state.dart';
import 'package:zakoway/features/player/core/backend/media_kit_player_backend.dart';
import 'package:zakoway/features/player/core/backend/playback_engine_pool.dart';
import 'package:zakoway/features/player/core/backend/player_backend.dart';
import 'package:zakoway/features/player/core/fsm/playback_event.dart';
import 'package:zakoway/features/player/core/fsm/playback_fsm.dart';
import 'package:zakoway/features/player/core/models/backend_error.dart';
import 'package:zakoway/features/player/core/models/playback_failure.dart';
import 'package:zakoway/features/player/core/models/playback_state.dart' as core_state;
import 'package:zakoway/features/player/core/models/resolved_media.dart';
import 'package:zakoway/features/player/core/proxy/local_media_proxy_server.dart';
import 'package:zakoway/features/player/core/utils/playback_tracer.dart';
import 'package:zakoway/features/player/services/player_preferences_service.dart';
import 'package:zakoway/features/player/services/shader_asset_service.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'playback_controller_interface.dart';

export 'playback_controller_factory.dart';
export 'playback_controller_interface.dart';

// 移除无用常量与死代码

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

/// 播放器主控制器 (ZakowayPlaybackController)
///
/// 遵循 docs/player-rewrite/ 架构设计：
/// 组合 PlaybackFsm + MediaKitPlayerBackend，对外 100% 遵守 PlaybackController 接口契约，
/// 驱动 12 状态流转、单调时钟弹幕位置外推、250ms 节流、Anime4K 串行熔断与自适应分级网络缓存。
class ZakowayPlaybackController implements PlaybackController {
  ZakowayPlaybackController({
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

  final ValueNotifier<List<SourceSubtitleTrack>> _availableSubtitlesNotifier =
      ValueNotifier<List<SourceSubtitleTrack>>(const []);
  @override
  ValueNotifier<List<SourceSubtitleTrack>> get availableSubtitlesNotifier =>
      _availableSubtitlesNotifier;

  final ValueNotifier<SourceSubtitleTrack?> _currentSubtitleTrackNotifier =
      ValueNotifier<SourceSubtitleTrack?>(null);
  @override
  ValueNotifier<SourceSubtitleTrack?> get currentSubtitleTrackNotifier =>
      _currentSubtitleTrackNotifier;

  List<SourceSubtitleTrack> _currentExternalSubtitles = const [];

  final StreamController<Duration> _seekStreamController =
      StreamController<Duration>.broadcast();

  @override
  Stream<Duration> get onSeek => _seekStreamController.stream;

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
  PlayerBackend? get backend => _backend ?? _injectedBackend;

  // ===========================================================================
  // 初始化与起播
  // ===========================================================================

  @override
  Future<void> initialize() async {
    if (_isInitialized || _disposed) return;
    _isInitialized = true;

    final isMetered = NetworkConnectivityService.instance.isMetered;
    core.value = core.value.copyWith(isMeteredNetwork: isMetered);

    // 0. 预热本地流媒体代理服务 (Local Media Proxy)
    await LocalMediaProxyServer.instance.ensureStarted();

    // 1. 从播放器内核与 GPU 纹理池中获取预热就绪的实例，省去 200~400ms 驱动冷启动
    final pooled = _injectedBackend == null ? PlaybackEnginePool.instance.acquire() : null;
    if (pooled != null) {
      _backend = pooled.backend;
      _videoController = pooled.videoController;
      videoControllerNotifier.value = _videoController;
    } else {
      _backend = _injectedBackend ?? MediaKitPlayerBackend();
      await _backend!.initialize(isMeteredNetwork: isMetered);

      // 2. 若为原生媒体后端，装配 VideoController 并申请 GPU 硬件加速纹理
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

        // 当底层完成真实寻道并推进新位置时，若状态机仍在 seeking，派发 SeekAcknowledgedEvent
        if (_fsm != null && _fsm!.state == core_state.PlaybackState.seeking) {
          _fsm!.dispatch(SeekAcknowledgedEvent(e.data));
        }

        // 若时间轴产生有效物理前进但 UI 仍处于加载/首帧未就绪态，主动触发状态自愈刷新
        if (_lastPosition > Duration.zero && !core.value.firstFrameRendered) {
          _onFsmCoreStateChanged();
        }
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

    // 监听本地代理从 HLS Master 播放列表提取的内置字幕轨
    _subscriptions.add(
      LocalMediaProxyServer.instance.onEmbeddedSubtitlesExtracted.listen((event) {
        if (_disposed) return;
        _handleEmbeddedSubtitles(event.masterUrl, event.tracks);
      }),
    );
  }

  void _onFsmCoreStateChanged() {
    if (_disposed || _fsm == null) return;
    final fsmState = _fsm!.state;
    final fsmCore = _fsm!.coreState;
    final failure = _fsm!.failure;

    // 特殊处理说明：
    // 事实存活与状态自愈双重对齐 (Liveness Proof Overrides Stale FSM)：
    // 若底层播放时间轴已向前推进 (例如直链 MP4 瞬间解码开播)，事实播放拥有最高权威；
    // 强制将 hasFirstFrame 置为 true、isPlaying 置为 true、isLoading 置为 false，
    // 彻底杜绝底层已经在播但 UI 误显暂停图标或小菊花卡死的问题。
    final isFactuallyPlaying = fsmCore.playing || _lastPosition > Duration.zero;
    final hasFirstFrame = fsmCore.firstFrameRendered || isFactuallyPlaying;
    final isPlaying = isFactuallyPlaying;
    final isLoading = (fsmState == core_state.PlaybackState.resolving ||
            fsmState == core_state.PlaybackState.preparing ||
            fsmState == core_state.PlaybackState.recovering ||
            !hasFirstFrame) &&
        !isFactuallyPlaying &&
        fsmState != core_state.PlaybackState.error;
    final isBuffering = fsmCore.buffering;
    final isCompleted = fsmCore.completed;

    // 若真实物理出画已就绪，事实出画具有最高权威，绝不在 UI 呈现报错；
    // 仅在出画前发生无法自愈的致命错误时才在界面展示脱敏错误
    final errorMsg = (fsmState == core_state.PlaybackState.error && !hasFirstFrame)
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
      clearError: errorMsg == null,
    );

    if (hasFirstFrame) {
      PlaybackTracer.instance.current?.markFirstFrameRendered();
      // 特殊处理说明：
      // 动态分级缓冲水线调度：
      // 首帧物理出画前保持极低水线 (1s 数据快速出画)；出画后静默将解复用器水线拉升至巡航水位 (15s 蓄水池)，
      // 既保障起播瞬间出画毫无拖泥带水，又保障后续高码率视频播放流畅不卡顿。
      if (_backend is MediaKitPlayerBackend) {
        (_backend as MediaKitPlayerBackend).boostToSteadyWatermark().ignore();
      }
    }

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
    bool isPreResolved = true,
    List<SourceSubtitleTrack>? subtitles,
  }) async {
    _currentUri = uri;
    PlaybackTracer.instance.current?.markBackendOpenDispatched();

    final subs = subtitles ?? const [];
    _currentExternalSubtitles = subs;

    // 优先读取本地代理已从该 Master M3U8 提取的内置字幕轨（二次起播/切集秒取）
    final cachedEmbedded = LocalMediaProxyServer.instance.getEmbeddedSubtitles(uri);

    // 按照 简体 -> 繁体 -> 内置简体 -> 内置繁体 严格优先级自动决策
    final defaultTrack = selectBestSubtitle(
      externalSubtitles: subs,
      embeddedSubtitles: cachedEmbedded,
    );

    _availableSubtitlesNotifier.value = defaultTrack != null ? [defaultTrack] : const [];
    _currentSubtitleTrackNotifier.value = defaultTrack;

    // 起播/切集立即进入 loading 状态并撤销首帧遮罩标记，防止残影
    core.value = core.value.copyWith(
      playing: false,
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
    } else if (_backend != null) {
      try {
        await _backend!.pause();
      } catch (_) {}
    }

    // 预注入当前选定的默认外挂字幕轨
    _backend?.setSubtitleTrack(defaultTrack).ignore();

    // 特殊处理说明：
    // 本地流媒体反向代理无缝映射 (Local Media Proxy)：
    // 远程流无论是 MP4 还是 HLS M3U8，全部自动重定向至纯本地回环地址 (127.0.0.1:port)。
    // 1. 底层 FFmpeg/mbedtls 与本地回环建立连接，握手耗时 0ms，彻底杜绝 -0x4e connection reset 致命重连循环；
    // 2. 由代理层的 Dart 高性能 HttpClient 连接池负责对远程 CDN 进行持久化复用拉取，大幅加速首帧物理出画。
    final effectiveUri = LocalMediaProxyServer.instance.buildProxyUrl(
      uri,
      headers: httpHeaders,
    );

    if (_fsm != null) {
      await _fsm!.load(
        effectiveUri,
        startPosition: start,
        autoplay: autoplay,
        headers: httpHeaders,
        isPreResolved: isPreResolved,
      );
    }
  }

  @override
  Future<void> setSubtitleTrack(SourceSubtitleTrack? track) async {
    _currentSubtitleTrackNotifier.value = track;
    await _backend?.setSubtitleTrack(track);
  }

  /// 判定字幕标签是否表达“简体中文”
  static bool _isSimplified(String label) {
    final l = label.toLowerCase();
    if (l.contains('简') ||
        l.contains('chs') ||
        l.contains('zh-hans') ||
        l.contains('zh-cn') ||
        l.contains('gb')) {
      return true;
    }
    return RegExp(r'(^|[^a-z])(sc)($|[^a-z])', caseSensitive: false).hasMatch(l);
  }

  /// 判定字幕标签是否表达“繁体中文”
  static bool _isTraditional(String label) {
    final l = label.toLowerCase();
    if (l.contains('繁') ||
        l.contains('cht') ||
        l.contains('zh-hant') ||
        l.contains('zh-tw') ||
        l.contains('zh-hk') ||
        l.contains('big5')) {
      return true;
    }
    return RegExp(r'(^|[^a-z])(tc)($|[^a-z])', caseSensitive: false).hasMatch(l);
  }

  /// 字幕自动决选算法（严格遵循优先级：外挂简体 -> 外挂繁体 -> 内置简体 -> 内置繁体，其余全部抛弃）
  ///
  /// 特殊处理说明：
  /// 用户明确要求后台自动化决策，不再向用户呈现繁杂的选择面板：
  /// 1. 优先采用外挂简体字幕；
  /// 2. 次选外挂繁体字幕；
  /// 3. 若无合适外挂字幕，自动选用 HLS 清单解耦出的内置简体字幕；
  /// 4. 再次选内置繁体字幕；
  /// 5. 其他任何非中文字幕完全忽略抛弃，不挂载。
  static SourceSubtitleTrack? selectBestSubtitle({
    List<SourceSubtitleTrack>? externalSubtitles,
    List<SourceSubtitleTrack>? embeddedSubtitles,
  }) {
    final ext = externalSubtitles ?? const [];
    final emb = embeddedSubtitles ?? const [];

    // 1. 外挂简体
    for (final s in ext) {
      if (_isSimplified(s.label)) return s;
    }

    // 2. 外挂繁体
    for (final s in ext) {
      if (_isTraditional(s.label)) return s;
    }

    // 3. 内置简体
    for (final s in emb) {
      if (_isSimplified(s.label)) return s;
    }

    // 4. 内置繁体
    for (final s in emb) {
      if (_isTraditional(s.label)) return s;
    }

    return null;
  }

  void _handleEmbeddedSubtitles(String masterUrl, List<SourceSubtitleTrack> tracks) {
    if (_disposed || _currentUri == null) return;
    if (!masterUrl.contains(_currentUri!) && !_currentUri!.contains(masterUrl)) {
      return;
    }

    // 若当前已选中的是外挂字幕中的简体或繁体，则因外挂优先级天然高于内置字幕，保持不变
    final current = _currentSubtitleTrackNotifier.value;
    final hasExternalMatch = current != null &&
        _currentExternalSubtitles.contains(current) &&
        (_isSimplified(current.label) || _isTraditional(current.label));

    if (hasExternalMatch) {
      return;
    }

    final bestTrack = selectBestSubtitle(
      externalSubtitles: _currentExternalSubtitles,
      embeddedSubtitles: tracks,
    );

    if (bestTrack != null && bestTrack.id != current?.id) {
      _currentSubtitleTrackNotifier.value = bestTrack;
      _availableSubtitlesNotifier.value = [bestTrack];
      _backend?.setSubtitleTrack(bestTrack).ignore();
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
  Future<void> stop() async {
    if (_disposed) return;

    _timelineThrottleTimer?.cancel();
    _timelineThrottleTimer = null;

    _lastPosition = Duration.zero;
    _lastDuration = Duration.zero;
    _lastBuffer = Duration.zero;
    timeline.value = const PlaybackTimelineState();

    if (_fsm != null) {
      await _fsm!.stop();
    } else {
      try {
        await _backend?.pause();
      } catch (_) {}

      core.value = core.value.copyWith(
        playing: false,
        loading: true,
        buffering: false,
        completed: false,
        firstFrameRendered: false,
        clearError: true,
      );
    }
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

    // 重置 250ms 节流定时器，避免旧进度事件在毫秒内回弹覆盖最新 Seek 点
    _timelineThrottleTimer?.cancel();
    _timelineThrottleTimer = null;

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

    _seekStreamController.add(targetPosition);

    if (_fsm != null) {
      await _fsm!.seek(targetPosition);
      // 若处于暂停态（底层不会自然推进播放时钟），800ms 安全兜底确保退出 seeking
      if (!core.value.playing) {
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!_disposed && _fsm?.state == core_state.PlaybackState.seeking) {
            _fsm?.dispatch(SeekAcknowledgedEvent(targetPosition));
          }
        });
      }
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
  // 弹幕时钟位置外推算法
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
    unawaited(_seekStreamController.close());

    final b = _backend;
    final vc = _videoController;
    _backend = null;
    _videoController = null;

    if (b != null) {
      if (_injectedBackend == null && b is MediaKitPlayerBackend && vc != null) {
        // 特殊处理说明：GPU 硬件渲染纹理与播放内核对象池化保活
        // 退出页面时清洗旧状态并归还至池中，避免频繁向 Direct3D 11 申请与销毁纹理上下文。
        PlaybackEnginePool.instance.recycle(b, vc);
      } else {
        unawaited(b.dispose());
      }
    }

    core.dispose();
    timeline.dispose();
    videoControllerNotifier.dispose();
    _failureNotifier.dispose();
    _showLineSwitchPromptNotifier.dispose();
  }
}

/// 兼容别名：保留 RewrittenPlaybackController 符号以完全兼容现有测试与调用点
typedef RewrittenPlaybackController = ZakowayPlaybackController;
