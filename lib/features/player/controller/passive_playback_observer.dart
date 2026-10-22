import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/core/backend/backend_event.dart';
import 'package:zakoway/features/player/core/backend/player_backend.dart';
import 'package:zakoway/features/player/core/classifier/player_log_classifier.dart';
import 'package:zakoway/features/player/core/fsm/playback_fsm.dart';
import 'package:zakoway/features/player/core/gate/backend_event_gate.dart';
import 'package:zakoway/features/player/core/models/backend_error.dart';
import 'package:zakoway/features/player/core/models/playback_state.dart' as core_state;
import 'package:zakoway/features/player/core/models/resolved_media.dart';

/// 被动观察器（Passive Playback Observer）
///
/// 遵循 docs/player-rewrite/11-facade-plan.md（修订版）
/// 仅在调试模式 (kDebugMode) 下运行。
/// 核心契约：
/// 1. 纯只读被动观察：直接订阅旧控制器正在使用的同一个 media_kit Player 实例的流；
/// 2. 严禁发出任何控制指令：不调用 play / pause / seek / open；
/// 3. 绝不打开第二个播放器，不发起任何额外的网络请求；
/// 4. open 的时刻由旧控制器通知同步（beginOpen / 重置门禁）；
/// 5. 差异日志在调试模式输出，保留标准 JSON 格式。
///
/// 【被动观察无法覆盖的盲区声明】：
/// 因被动观察器不主动下发指令，因此无法检验新核心自愈动作的实际物理效果
/// （如断流后 reopen 是否顺利恢复传输、着色器编译超时 4s 熔断后的实际渲染表现等）。
/// 自愈恢复效果通过专用单测（TC-35、TC-36）与真实窗口探针（Win-F）予以闭环检验。
class PassivePlaybackObserver {
  PassivePlaybackObserver._(this.controller) {
    _init();
  }

  final ZakowayPlaybackController controller;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  _PassiveNoopBackend? _backend;
  PlaybackFsm? _fsm;
  Player? _attachedPlayer;
  Timer? _diffDebounceTimer;
  String? _lastDiffSignature;

  /// 在调试模式下为旧控制器挂载被动观察器
  static PassivePlaybackObserver? attach(ZakowayPlaybackController controller) {
    if (!kDebugMode) return null;
    return PassivePlaybackObserver._(controller);
  }

  void _init() {
    // 监听 VideoController/Player 实例装载时机
    controller.videoControllerNotifier.addListener(_onPlayerInstanceAvailable);
    if (controller.rawPlayer != null) {
      _attachToPlayer(controller.rawPlayer!);
    }

    // 监听旧控制器 core 状态变更
    controller.core.addListener(_scheduleDiffComparison);
  }

  void _onPlayerInstanceAvailable() {
    final player = controller.rawPlayer;
    if (player != null && player != _attachedPlayer) {
      _attachToPlayer(player);
    }
  }

  void _attachToPlayer(Player player) {
    _attachedPlayer = player;

    _backend = _PassiveNoopBackend(player);
    _fsm = PlaybackFsm(
      backend: _backend!,
      gate: _backend!.gate,
      onResolve: ({required bool bypassCache}) async {
        return ResolvedMedia(url: controller.currentUri ?? '');
      },
    );

    _fsm!.coreNotifier.addListener(_scheduleDiffComparison);

    // 观察旧控制器当前 URI 并初始化首个代际
    if (controller.currentUri != null) {
      onOpenInitiated(controller.currentUri!);
    }
  }

  /// 旧控制器发起 open 时由外部同步通知，更新门禁代际与时间基准
  void onOpenInitiated(String uri) {
    if (_backend == null || _fsm == null) return;
    final genId = _backend!.beginOpen();
    final parsedUri = Uri.tryParse(uri) ?? Uri.parse('http://localhost');
    _backend!.gate.resetForNewOpen(
      generationId: genId,
      targetUri: parsedUri,
      openTime: DateTime.now(),
    );
    _fsm!.load(uri).ignore();
  }

  void _scheduleDiffComparison() {
    _diffDebounceTimer?.cancel();
    _diffDebounceTimer = Timer(const Duration(milliseconds: 500), _compareStates);
  }

  void _compareStates() {
    if (_fsm == null || controller.isDisposed) return;

    final legacyCore = controller.core.value;
    final fsmState = _fsm!.state;
    final fsmCore = _fsm!.coreState;

    final legacyPlaying = legacyCore.playing;
    final legacyLoading = legacyCore.loading;
    final legacyBuffering = legacyCore.buffering;

    final fsmPlaying = fsmState == core_state.PlaybackState.playing;
    final fsmLoading = fsmState == core_state.PlaybackState.resolving ||
        fsmState == core_state.PlaybackState.preparing ||
        fsmState == core_state.PlaybackState.recovering ||
        !fsmCore.firstFrameRendered;
    final fsmBuffering = fsmState == core_state.PlaybackState.prebuffering ||
        fsmState == core_state.PlaybackState.rebuffering ||
        fsmState == core_state.PlaybackState.seeking;

    final diffs = <String>[];
    if (legacyPlaying != fsmPlaying) diffs.add('playing');
    if (legacyLoading != fsmLoading) diffs.add('loading');
    if (legacyBuffering != fsmBuffering) diffs.add('buffering');

    if (diffs.isEmpty) return;

    final signature = '$diffs:$fsmState';
    if (signature == _lastDiffSignature) return;
    _lastDiffSignature = signature;

    final jsonLog = jsonEncode({
      'event': 'PLAYER_PASSIVE_OBSERVER_DIFF',
      'timestamp': DateTime.now().toIso8601String(),
      'uri': controller.currentUri ?? '',
      'legacy': {
        'playing': legacyPlaying,
        'loading': legacyLoading,
        'buffering': legacyBuffering,
      },
      'observedFsm': {
        'state': fsmState.name,
        'playing': fsmPlaying,
        'loading': fsmLoading,
        'buffering': fsmBuffering,
        'firstFrameRendered': fsmCore.firstFrameRendered,
      },
      'difference': diffs,
      'details': '被动观察器检测到旧引擎与新状态机流转差异',
    });

    debugPrint('[PassiveObserver] $jsonLog');
  }

  void dispose() {
    _diffDebounceTimer?.cancel();
    controller.core.removeListener(_scheduleDiffComparison);
    controller.videoControllerNotifier.removeListener(_onPlayerInstanceAvailable);

    for (final s in _subscriptions) {
      s.cancel();
    }
    _subscriptions.clear();

    _fsm?.dispose().ignore();
    _fsm = null;
    _backend?.dispose().ignore();
    _backend = null;
  }
}

/// 纯只读被动后端：仅订阅底层 stream，绝不下发任何实际控制指令
class _PassiveNoopBackend implements PlayerBackend {
  _PassiveNoopBackend(this.player) {
    _initStreams();
  }

  final Player player;
  final BackendEventGate gate = BackendEventGate();

  int _generationId = 0;
  final List<StreamSubscription<dynamic>> _subs = [];

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

  PlayerLogClassifier? _classifier;

  void _initStreams() {
    _subs.add(player.stream.playing.listen((isPlaying) {
      _playingController.add(BackendEvent<bool>(
        isPlaying,
        generationId: _generationId,
      ));
    }));

    _subs.add(player.stream.buffering.listen((isBuffering) {
      _bufferingController.add(BackendEvent<bool>(
        isBuffering,
        generationId: _generationId,
      ));
    }));

    _subs.add(player.stream.position.listen((pos) {
      _positionController.add(BackendEvent<Duration>(
        pos,
        generationId: _generationId,
      ));
    }));

    _subs.add(player.stream.duration.listen((dur) {
      _durationController.add(BackendEvent<Duration>(
        dur,
        generationId: _generationId,
      ));
    }));

    _subs.add(player.stream.buffer.listen((buf) {
      _bufferController.add(BackendEvent<Duration>(
        buf,
        generationId: _generationId,
      ));
    }));

    _subs.add(player.stream.width.listen((w) {
      _updateDimensions();
    }));

    _subs.add(player.stream.height.listen((h) {
      _updateDimensions();
    }));

    _subs.add(player.stream.completed.listen((comp) {
      _completedController.add(BackendEvent<bool>(
        comp,
        generationId: _generationId,
      ));
    }));

    _subs.add(player.stream.error.listen((errText) {
      final now = DateTime.now();
      _logController.add(PlayerLogMessage(
        prefix: 'mpv',
        level: 'error',
        text: errText,
        timestamp: now,
        generationId: _generationId,
      ));
      if (_classifier != null) {
        _classifier!.onLogReceived(
          source: 'stream.error',
          level: 'error',
          prefix: 'mpv',
          text: errText,
          relativeTime: Duration.zero,
        );
        final err = _classifier!.evaluate(Duration.zero);
        if (err != null) {
          _errorController.add(err);
        }
      }
    }));
  }

  void _updateDimensions() {
    final w = player.state.width;
    final h = player.state.height;
    _dimensionsController.add(BackendEvent<VideoDimensions>(
      VideoDimensions(w, h),
      generationId: _generationId,
    ));
  }

  @override
  int beginOpen() {
    _generationId++;
    return _generationId;
  }

  // 纯被动拦截：绝不向底层下发指令，不打开第二个播放器，不产生网络请求
  @override
  Future<void> open(
    String uri, {
    Map<String, String>? headers,
    Duration? start,
    bool autoplay = true,
    required int generationId,
  }) async {
    _classifier = PlayerLogClassifier(expectedUrl: Uri.parse(uri));
  }

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> initialize({required bool isMeteredNetwork}) async {}

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  @override
  int get realVideoTrackCount => 1;

  @override
  Stream<BackendEvent<bool>> get onBufferingChanged => _bufferingController.stream;

  @override
  Stream<BackendEvent<bool>> get onCompletedChanged => _completedController.stream;

  @override
  Stream<BackendEvent<VideoDimensions>> get onDimensionsChanged => _dimensionsController.stream;

  @override
  Stream<BackendEvent<Duration>> get onDurationChanged => _durationController.stream;

  @override
  Stream<BackendError> get onErrorOccurred => _errorController.stream;

  @override
  Stream<PlayerLogMessage> get onLog => _logController.stream;

  @override
  Stream<BackendEvent<bool>> get onPlayingChanged => _playingController.stream;

  @override
  Stream<BackendEvent<Duration>> get onPositionChanged => _positionController.stream;

  @override
  Stream<BackendEvent<Duration>> get onBufferChanged => _bufferController.stream;
}
