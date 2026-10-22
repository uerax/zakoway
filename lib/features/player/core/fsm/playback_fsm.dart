/// 播放状态机执行器 (PlaybackFsm)
///
/// 遵循 docs/player-rewrite/03-state-machine.md (v3.1) 与 docs/player-rewrite/04-error-policy.md (v3.1)
/// 负责将纯转移函数 evaluateTransition 计算产出的副作用（SideEffects）映射到具体的 Timer、时钟调度与 PlayerBackend 异步调用。
///
/// 核心契约保证：
/// 1. 严格遵守全链路预算：首帧超时 12s、换线提示 5s、总预算 13s、恢复退避 500ms、直链解析 2.5s；
/// 2. 状态迁移时依据 CancelTimersEffect 彻底取消无用定时器；dispose 时取消全部；
/// 3. 所有异步回调与定时器触发均严密校验 attemptId 与 generationId，杜绝旧集/旧会话竞态污染；
/// 4. 彻底消除未捕获的异步异常（TC-18、TC-19）；
/// 5. 换线失败只通过 PlaybackFailure 暴露可用操作供选源层/UI层调度。
library;

import 'dart:async';
import 'package:flutter/foundation.dart';

import '../backend/player_backend.dart';
import '../gate/backend_event_gate.dart';
import '../models/backend_error.dart';
import '../models/playback_constants.dart';
import '../models/playback_failure.dart';
import '../models/playback_state.dart';
import '../models/playback_timeline_state.dart';
import '../models/resolved_media.dart';
import 'playback_event.dart';
import 'playback_fsm_context.dart';
import 'playback_side_effect.dart';
import 'playback_transition.dart';

/// 定时器工厂方法签名（支持 fakeAsync 注入）
typedef TimerFactory = Timer Function(Duration duration, void Function() callback);

/// 时钟提取函数签名
typedef Clock = DateTime Function();

/// 播放状态机执行器
class PlaybackFsm {
  PlaybackFsm({
    required this.backend,
    required this.onResolve,
    BackendEventGate? gate,
    Clock? clock,
    TimerFactory? timerFactory,
    Duration? resolvingTimeout,
  })  : _gate = gate ?? BackendEventGate(),
        _clock = clock ?? DateTime.now,
        _timerFactory = timerFactory ?? Timer.new,
        _resolvingTimeout = resolvingTimeout ?? kResolvingTimeout {
    _initSubscriptions();
  }

  /// 底层音视频播放引擎后端
  final PlayerBackend backend;

  /// 直链解析回调函数
  final Future<ResolvedMedia> Function({required bool bypassCache}) onResolve;

  final BackendEventGate _gate;
  final Clock _clock;
  final TimerFactory _timerFactory;
  final Duration _resolvingTimeout;

  // ===== 状态机核心状态 =====
  PlaybackState _state = PlaybackState.idle;
  PlaybackFsmContext _context = PlaybackFsmContext.initial;
  PlaybackFailure? _lastFailure;
  bool _showLineSwitchPrompt = false;
  bool _isDisposed = false;
  DateTime? _requestStartTime;
  DateTime? _recoveryStartTime;

  // ===== 核心定时器 =====
  Timer? _resolvingTimeoutTimer;
  Timer? _coverPromptTimer;
  Timer? _firstFrameTimeoutTimer;
  Timer? _totalBudgetTimer;
  Timer? _midStreamBudgetTimer;
  Timer? _recoveryBackoffTimer;
  Timer? _rebufferingTimeoutTimer;

  // ===== 底层流订阅列表 =====
  final List<StreamSubscription> _subscriptions = [];

  // ===== UI 只读状态通知器 =====
  final ValueNotifier<PlaybackCoreState> _coreNotifier =
      ValueNotifier<PlaybackCoreState>(
    PlaybackCoreState.fromState(PlaybackState.idle),
  );
  final ValueNotifier<PlaybackTimelineState> _timelineNotifier =
      ValueNotifier<PlaybackTimelineState>(const PlaybackTimelineState());
  final ValueNotifier<bool> _showLineSwitchPromptNotifier =
      ValueNotifier<bool>(false);
  final ValueNotifier<PlaybackFailure?> _failureNotifier =
      ValueNotifier<PlaybackFailure?>(null);

  // ===========================================================================
  // 公开只读属性与通知器
  // ===========================================================================

  PlaybackState get state => _state;
  PlaybackFsmContext get context => _context;
  PlaybackCoreState get coreState => _coreNotifier.value;
  PlaybackTimelineState get timelineState => _timelineNotifier.value;
  PlaybackFailure? get failure => _lastFailure;
  bool get showLineSwitchPrompt => _showLineSwitchPrompt;
  bool get isDisposed => _isDisposed;
  BackendEventGate get gate => _gate;

  ValueListenable<PlaybackCoreState> get coreNotifier => _coreNotifier;
  ValueListenable<PlaybackTimelineState> get timelineNotifier =>
      _timelineNotifier;
  ValueListenable<bool> get showLineSwitchPromptNotifier =>
      _showLineSwitchPromptNotifier;
  ValueListenable<PlaybackFailure?> get failureNotifier => _failureNotifier;

  // ===========================================================================
  // 底层事件流监听与门禁分发
  // ===========================================================================

  void _initSubscriptions() {
    _subscriptions.add(
      backend.onPlayingChanged.listen((event) {
        if (_isDisposed) return;
        if (!_gate.canPassPlaying(event)) return;
      }),
    );

    _subscriptions.add(
      backend.onBufferingChanged.listen((event) {
        if (_isDisposed) return;
        if (!_gate.canPassBuffering(event)) return;

        if (event.data) {
          dispatch(const BufferingStartedEvent());
        } else {
          dispatch(const BufferingEndedEvent());
        }
      }),
    );

    _subscriptions.add(
      backend.onPositionChanged.listen((event) {
        if (_isDisposed) return;
        if (!_gate.canPassPosition(event)) return;

        final isAdvanced = event.data > Duration.zero;
        if (isAdvanced) {
          _context = _context.copyWith(
            currentPosition: event.data,
            hasPositionAdvanced: true,
          );
        } else {
          _context = _context.copyWith(currentPosition: event.data);
        }
        _timelineNotifier.value =
            _timelineNotifier.value.copyWith(position: event.data);

        // prebuffering 阶段若时钟推进，检查首帧条件（由转移函数研判）
        if (_state == PlaybackState.prebuffering && isAdvanced) {
          dispatch(const FirstFrameRenderedEvent());
        }
      }),
    );

    _subscriptions.add(
      backend.onDurationChanged.listen((event) {
        if (_isDisposed) return;
        if (!_gate.canPassDuration(event)) return;

        _context = _context.copyWith(totalDuration: event.data);
        _timelineNotifier.value =
            _timelineNotifier.value.copyWith(duration: event.data);
      }),
    );

    _subscriptions.add(
      backend.onBufferChanged.listen((event) {
        if (_isDisposed) return;
        if (!_gate.canPassBuffer(event)) return;

        _timelineNotifier.value =
            _timelineNotifier.value.copyWith(buffer: event.data);
      }),
    );

    _subscriptions.add(
      backend.onDimensionsChanged.listen((event) {
        if (_isDisposed) return;
        if (!_gate.canPassDimensions(event)) return;

        if (event.data.hasValidSize) {
          _context = _context.copyWith(hasValidDimensions: true);
          if (_state == PlaybackState.prebuffering) {
            dispatch(const FirstFrameRenderedEvent());
          }
        }
      }),
    );

    _subscriptions.add(
      backend.onCompletedChanged.listen((event) {
        if (_isDisposed) return;
        if (!_gate.canPassCompleted(event)) return;

        dispatch(CompletedReceivedEvent(
          currentPosition: _context.currentPosition,
          duration: _context.totalDuration,
        ));
      }),
    );

    _subscriptions.add(
      backend.onErrorOccurred.listen((error) {
        if (_isDisposed) return;

        final disposition = _gate.evaluateError(error, eventTime: _clock());
        if (disposition == GatedErrorDisposition.passFatal) {
          dispatch(FatalErrorReceivedEvent(error));
        }
      }),
    );

    _subscriptions.add(
      backend.onLog.listen((log) {
        if (_isDisposed) return;
        _gate.evaluateLog(log);
      }),
    );
  }

  // ===========================================================================
  // 核心调度入口 (dispatch)
  // ===========================================================================

  /// 向状态机派发事件并执行副作用
  void dispatch(PlaybackEvent event) {
    if (_isDisposed && event is! DisposeRequestEvent) {
      return;
    }

    final previousState = _state;
    final result = evaluateTransition(
      currentState: _state,
      context: _context,
      event: event,
    );

    _state = result.targetState;
    _context = result.nextContext;

    // 同步更新 UI 只读状态
    _syncCoreNotifier();

    // 状态迁移若进入 recovering，检查是否从中途状态触发
    final isEnteringRecoveringFromMidStream =
        _state == PlaybackState.recovering &&
            previousState != PlaybackState.recovering &&
            (previousState == PlaybackState.playing ||
                previousState == PlaybackState.rebuffering ||
                previousState == PlaybackState.seeking ||
                previousState == PlaybackState.paused);

    if (isEnteringRecoveringFromMidStream) {
      _recoveryStartTime = _clock();
      _startMidStreamBudgetTimer(_context.attemptId);
    }

    // 状态迁移若达到确定性终态，撤销起播总预算与中途自愈总预算看门狗
    if (_state == PlaybackState.playing ||
        _state == PlaybackState.paused ||
        _state == PlaybackState.error ||
        _state == PlaybackState.completed ||
        _state == PlaybackState.disposed) {
      _totalBudgetTimer?.cancel();
      _totalBudgetTimer = null;
      _requestStartTime = null;

      _midStreamBudgetTimer?.cancel();
      _midStreamBudgetTimer = null;
      _recoveryStartTime = null;
    }

    // 状态退出 recovering 时撤销退避定时器
    if (previousState == PlaybackState.recovering &&
        _state != PlaybackState.recovering) {
      _recoveryBackoffTimer?.cancel();
      _recoveryBackoffTimer = null;
    }

    // 状态退出 rebuffering 时撤销重缓冲定时器 (F3)
    if (previousState == PlaybackState.rebuffering &&
        _state != PlaybackState.rebuffering) {
      _rebufferingTimeoutTimer?.cancel();
      _rebufferingTimeoutTimer = null;
    }

    // 状态进入 rebuffering 时启动 30s 重缓冲超时定时器 (F3)
    if (_state == PlaybackState.rebuffering &&
        previousState != PlaybackState.rebuffering) {
      _startRebufferingTimeoutTimer();
    }

    // 执行纯转移函数产出的副作用意图列表
    _executeSideEffects(result.sideEffects, previousState: previousState);
  }

  void _startRebufferingTimeoutTimer() {
    _rebufferingTimeoutTimer?.cancel();
    _rebufferingTimeoutTimer = _timerFactory(kRebufferingTimeout, () {
      if (_isDisposed || _state != PlaybackState.rebuffering) {
        return;
      }
      dispatch(const BufferingTimeoutEvent());
    });
  }

  void _syncCoreNotifier() {
    _coreNotifier.value = PlaybackCoreState.fromState(
      _state,
      firstFrameRendered: _context.firstFrameRendered,
      errorMessage: _lastFailure?.message,
    );
  }

  // ===========================================================================
  // 副作用执行调度器 (SideEffect Executor)
  // ===========================================================================

  void _executeSideEffects(
    List<PlaybackSideEffect> effects, {
    required PlaybackState previousState,
  }) {
    CallBackendOpenEffect? pendingOpen;
    ResolveMediaEffect? pendingResolve;

    for (final effect in effects) {
      switch (effect) {
        case CancelTimersEffect():
          _cancelPrebufferingTimers();
          _resolvingTimeoutTimer?.cancel();
          _resolvingTimeoutTimer = null;
          _recoveryBackoffTimer?.cancel();
          _recoveryBackoffTimer = null;
          _rebufferingTimeoutTimer?.cancel();
          _rebufferingTimeoutTimer = null;

        case CallBackendOpenEffect(
            :final url,
            :final start,
            :final autoplay,
            :final headers
          ):
          if (_state == PlaybackState.recovering) {
            // 在 recovering 状态下遇到直接断点重开意图，暂存并待 500ms 退避到期后执行
            pendingOpen = effect;
          } else {
            _executeBackendOpen(
              url: url,
              start: start,
              autoplay: autoplay,
              headers: headers,
            );
          }

        case CallBackendPlayEffect():
          backend.play().ignore();

        case CallBackendPauseEffect():
          backend.pause().ignore();

        case CallBackendSeekEffect(:final position):
          backend.seek(position).ignore();

        case CallBackendDisposeEffect():
          backend.dispose().ignore();

        case ResolveMediaEffect():
          if (_state == PlaybackState.recovering) {
            // 在 recovering 状态下遇到重新解析意图，暂存并待 500ms 退避到期后执行
            pendingResolve = effect;
          } else {
            _executeResolveMedia(bypassCache: effect.bypassCache);
          }

        case EmitFailureEffect(:final failure):
          _lastFailure = failure;
          _failureNotifier.value = failure;
          _syncCoreNotifier();
      }
    }

    // 若转入 recovering 状态，启动 500ms 自愈退避定时器
    if (_state == PlaybackState.recovering &&
        previousState != PlaybackState.recovering) {
      _startRecoveryBackoff(
        pendingOpen: pendingOpen,
        pendingResolve: pendingResolve,
      );
    }
  }

  // ===========================================================================
  // 异步副作用与定时器实现
  // ===========================================================================

  /// 执行直链解析与 2.5s 超时守卫
  void _executeResolveMedia({required bool bypassCache}) async {
    final currentAttemptId = _context.attemptId;

    // 启动 2.5s 解析超时定时器
    _startResolvingTimeout(currentAttemptId);

    try {
      final media = await onResolve(bypassCache: bypassCache);

      if (_isDisposed || _context.attemptId != currentAttemptId) {
        return;
      }

      _resolvingTimeoutTimer?.cancel();
      _resolvingTimeoutTimer = null;

      dispatch(ResolveSuccessEvent(
        url: media.url,
        headers: media.headers,
      ));
    } catch (e) {
      if (_isDisposed || _context.attemptId != currentAttemptId) {
        return;
      }

      _resolvingTimeoutTimer?.cancel();
      _resolvingTimeoutTimer = null;

      dispatch(ResolveFailureEvent(e.toString()));
    }
  }

  /// 启动直链解析超时定时器 (默认 3.5s，支持构造注入)
  void _startResolvingTimeout(int scheduledAttemptId) {
    _resolvingTimeoutTimer?.cancel();
    _resolvingTimeoutTimer = _timerFactory(_resolvingTimeout, () {
      if (_isDisposed || _context.attemptId != scheduledAttemptId) {
        return;
      }
      dispatch(ResolveFailureEvent(
        '直链解析超时 (${_resolvingTimeout.inMilliseconds / 1000}s)',
      ));
    });
  }

  /// 执行底层 open IPC 派发
  void _executeBackendOpen({
    required String url,
    Duration? start,
    bool autoplay = true,
    Map<String, String>? headers,
  }) async {
    final currentAttemptId = _context.attemptId;

    try {
      // 1. 同步自增并分配新代际 ID (F1)
      final genId = backend.beginOpen();

      // 2. 立即以新代际初始化事件门禁，早于底层 open 派发以捕获 6~7ms 内的重置标记 (F1)
      _gate.resetForNewOpen(
        generationId: genId,
        targetUri: Uri.parse(url),
        openTime: _clock(),
      );

      // 3. 异步派发底层 open
      await backend.open(
        url,
        headers: headers,
        start: start,
        autoplay: autoplay,
        generationId: genId,
      );

      if (_isDisposed || _context.attemptId != currentAttemptId) {
        return;
      }

      // 4. 通知底层 open 派发成功，若处于 preparing 或 recovering 则由 evaluateTransition 转入 prebuffering (F4)
      dispatch(BackendDispatchedEvent(genId));

      // 5. 启动首帧出画 12s 看门狗与 5s 换线提示定时器
      if (_state == PlaybackState.prebuffering) {
        _startPrebufferingTimers(currentAttemptId, genId);
      }
    } catch (e) {
      if (_isDisposed || _context.attemptId != currentAttemptId) {
        return;
      }

      dispatch(FatalErrorReceivedEvent(BackendError(
        kind: BackendErrorKind.unknown,
        action: RecoveryAction.fatalError,
        rawMessage: e.toString(),
        relativeTime: Duration.zero,
      )));
    }
  }

  /// 启动 prebuffering 阶段守护定时器 (5s 换线提示 + 12s 看门狗)
  void _startPrebufferingTimers(int scheduledAttemptId, int scheduledGenId) {
    _cancelPrebufferingTimers();

    _showLineSwitchPrompt = false;
    _showLineSwitchPromptNotifier.value = false;

    // 1. 5.0 秒 UI 换线提示定时器
    _coverPromptTimer = _timerFactory(kFirstFrameCoverPromptWait, () {
      if (_isDisposed ||
          _context.attemptId != scheduledAttemptId ||
          _context.generationId != scheduledGenId) {
        return;
      }
      if (_state == PlaybackState.prebuffering) {
        _showLineSwitchPrompt = true;
        _showLineSwitchPromptNotifier.value = true;
      }
    });

    // 2. 12.0 秒首帧出画硬上限看门狗
    _firstFrameTimeoutTimer = _timerFactory(kFirstFrameTimeout, () {
      if (_isDisposed ||
          _context.attemptId != scheduledAttemptId ||
          _context.generationId != scheduledGenId) {
        return;
      }
      if (_state == PlaybackState.prebuffering) {
        final hasProof =
            _context.isAudioOnly || _context.currentPosition > Duration.zero;
        dispatch(FirstFrameTimeoutEvent(hasLivenessProof: hasProof));
      }
    });
  }

  /// 取消 prebuffering 阶段的临时定时器
  void _cancelPrebufferingTimers() {
    _coverPromptTimer?.cancel();
    _coverPromptTimer = null;

    _firstFrameTimeoutTimer?.cancel();
    _firstFrameTimeoutTimer = null;

    _showLineSwitchPrompt = false;
    _showLineSwitchPromptNotifier.value = false;
  }

  /// 启动自愈恢复 500ms 退避定时器（含 5s 剩余预算熔断检查）
  void _startRecoveryBackoff({
    CallBackendOpenEffect? pendingOpen,
    ResolveMediaEffect? pendingResolve,
  }) {
    _recoveryBackoffTimer?.cancel();

    // 依据 04 第五节动态剩余预算准则：
    // 若从中途状态触发自愈，以本次自愈开始时刻为起点计算剩余预算 (kMidStreamRecoveryBudget)；
    // 若在起播阶段触发自愈，以会话请求时刻为起点计算剩余预算 (kTotalBudget)。
    final Duration budget;
    final Duration elapsed;
    if (_recoveryStartTime != null) {
      budget = kMidStreamRecoveryBudget;
      elapsed = _clock().difference(_recoveryStartTime!);
    } else {
      budget = kTotalBudget;
      elapsed = _requestStartTime != null
          ? _clock().difference(_requestStartTime!)
          : Duration.zero;
    }

    final remaining = budget - elapsed;

    if (remaining < kMinRemainingBudgetForRecovery) {
      // 剩余自愈预算不足 5 秒，强行重试必定超期被暴力截断，立即转入 error
      dispatch(FatalErrorReceivedEvent(BackendError(
        kind: BackendErrorKind.unknown,
        action: RecoveryAction.fatalError,
        rawMessage: '剩余自愈预算不足 5 秒 (剩余 ${remaining.inMilliseconds}ms)，放弃自愈重试',
        relativeTime: elapsed,
      )));
      return;
    }

    final currentAttemptId = _context.attemptId;
    _recoveryBackoffTimer = _timerFactory(kRecoveryBackoffDelay, () {
      if (_isDisposed || _context.attemptId != currentAttemptId) {
        return;
      }
      if (_state != PlaybackState.recovering) {
        return;
      }

      if (pendingOpen != null) {
        _executeBackendOpen(
          url: pendingOpen.url,
          start: pendingOpen.start,
          autoplay: pendingOpen.autoplay,
          headers: pendingOpen.headers,
        );
      } else if (pendingResolve != null) {
        // 标记状态迁移至 resolving
        _state = PlaybackState.resolving;
        _syncCoreNotifier();
        _executeResolveMedia(bypassCache: pendingResolve.bypassCache);
      } else {
        dispatch(const RecoveryTimerExpiredEvent());
      }
    });
  }

  /// 启动中途自愈 13.0 秒硬上限总预算定时器
  void _startMidStreamBudgetTimer(int scheduledAttemptId) {
    _midStreamBudgetTimer?.cancel();

    _midStreamBudgetTimer = _timerFactory(kMidStreamRecoveryBudget, () {
      if (_isDisposed || _context.attemptId != scheduledAttemptId) {
        return;
      }
      if (_state == PlaybackState.playing ||
          _state == PlaybackState.paused ||
          _state == PlaybackState.completed ||
          _state == PlaybackState.error ||
          _state == PlaybackState.disposed) {
        return;
      }

      // 中途自愈 13 秒硬上限触发，强行进入 error 终态
      dispatch(FatalErrorReceivedEvent(BackendError(
        kind: BackendErrorKind.unknown,
        action: RecoveryAction.fatalError,
        rawMessage: '中途自愈恢复总预算超时 (${kMidStreamRecoveryBudget.inSeconds}s)',
        relativeTime: kMidStreamRecoveryBudget,
      )));
    });
  }

  /// 启动全局 13.0 秒端到端硬上限总预算定时器
  void _startTotalBudgetTimer(int scheduledAttemptId) {
    _totalBudgetTimer?.cancel();
    _requestStartTime = _clock();

    _totalBudgetTimer = _timerFactory(kTotalBudget, () {
      if (_isDisposed || _context.attemptId != scheduledAttemptId) {
        return;
      }
      if (_state == PlaybackState.playing ||
          _state == PlaybackState.paused ||
          _state == PlaybackState.completed ||
          _state == PlaybackState.error ||
          _state == PlaybackState.disposed) {
        return;
      }

      // 13 秒硬上限触发，强行进入 error 终态
      dispatch(FatalErrorReceivedEvent(BackendError(
        kind: BackendErrorKind.unknown,
        action: RecoveryAction.fatalError,
        rawMessage: '会话端到端总预算超时 (13.0s)',
        relativeTime: kTotalBudget,
      )));
    });
  }

  // ===========================================================================
  // 外部公共控制方法
  // ===========================================================================

  /// 加载并启动视频起播会话
  Future<void> load(
    String uri, {
    Duration? startPosition,
    bool autoplay = true,
    Map<String, String>? headers,
  }) async {
    if (_isDisposed) return;

    // 每次用户发起起播，启动 13s 总预算定时器
    final nextAttemptId = _context.attemptId + 1;
    _startTotalBudgetTimer(nextAttemptId);

    dispatch(LoadRequestEvent(
      uri: uri,
      startPosition: startPosition,
      autoplay: autoplay,
      headers: headers,
    ));
  }

  /// 幂等播放
  Future<void> play() async {
    if (_isDisposed) return;
    dispatch(const PlayRequestEvent());
  }

  /// 幂等暂停
  Future<void> pause() async {
    if (_isDisposed) return;
    dispatch(const PauseRequestEvent());
  }

  /// 精准寻道（内置末尾 500ms 截断保护）
  Future<void> seek(Duration position) async {
    if (_isDisposed) return;

    var target = position;
    final dur = _context.totalDuration;

    // 特殊处理说明：
    // 若寻道目标极其接近或达到总时长，底层会提前抛出 EOF 触发 completed。
    // 在总时长有效且大于 1 秒时，对寻道终点做 500ms 安全余量截断保护 (TC-07)。
    if (dur > const Duration(seconds: 1) && target >= dur) {
      target = dur - const Duration(milliseconds: 500);
      if (target < Duration.zero) {
        target = Duration.zero;
      }
    }

    _timelineNotifier.value = _timelineNotifier.value.copyWith(
      position: target,
      clearPreview: true,
    );

    dispatch(SeekRequestEvent(target));
  }

  /// 拖拽进度条时实时更新预览
  void updateSeekPreview(Duration position) {
    if (_isDisposed) return;
    _timelineNotifier.value =
        _timelineNotifier.value.copyWith(previewPosition: position);
  }

  /// 结束拖拽并真正 Seek
  Future<void> endSeekPreview() async {
    if (_isDisposed) return;
    final target = _timelineNotifier.value.previewPosition;
    if (target != null) {
      await seek(target);
    }
  }

  /// 发生可恢复错误或展示错误卡片时，用户手动点击重试
  Future<void> retry() async {
    if (_isDisposed) return;
    // 重试重新启动 13s 总预算
    final nextAttemptId = _context.attemptId + 1;
    _startTotalBudgetTimer(nextAttemptId);
    dispatch(const RetryRequestEvent());
  }

  /// 销毁并释放所有资源
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    // 立即同步派发销毁事件并将状态迁移至 disposed
    dispatch(const DisposeRequestEvent());

    // 撤销全部定时器
    _cancelPrebufferingTimers();
    _resolvingTimeoutTimer?.cancel();
    _resolvingTimeoutTimer = null;
    _recoveryBackoffTimer?.cancel();
    _recoveryBackoffTimer = null;
    _rebufferingTimeoutTimer?.cancel();
    _rebufferingTimeoutTimer = null;
    _totalBudgetTimer?.cancel();
    _totalBudgetTimer = null;
    _midStreamBudgetTimer?.cancel();
    _midStreamBudgetTimer = null;
    _recoveryStartTime = null;

    // 取消所有底层流订阅
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }
}
