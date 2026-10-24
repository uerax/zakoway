/// 播放状态机确定性纯转移函数
///
/// 严格遵循 docs/player-rewrite/03-state-machine.md (v3.1) 第四节全矩阵定义
/// 零副作用、零异步、零 Timer，纯输入输出同步决策函数。
library;

import 'dart:math' as math;
import '../models/backend_error.dart';
import '../models/playback_constants.dart';
import '../models/playback_failure.dart';
import '../models/playback_state.dart';
import 'playback_event.dart';
import 'playback_fsm_context.dart';
import 'playback_side_effect.dart';

/// 状态转移处置判定
enum TransitionDisposition {
  /// 执行转移（可能发生状态迁移或派发副作用动作）
  exec,

  /// 排队意图（记录至上下文，待后续阶段消费）
  queue,

  /// 静默忽略（状态与上下文保持不变，无副作用）
  ignore,
}

/// 纯转移决策结果
class TransitionResult {
  const TransitionResult({
    required this.targetState,
    required this.disposition,
    required this.nextContext,
    this.sideEffects = const [],
  });

  /// 转移后的目标状态
  final PlaybackState targetState;

  /// 本次决策处置结果 (exec / queue / ignore)
  final TransitionDisposition disposition;

  /// 更新后的状态机上下文
  final PlaybackFsmContext nextContext;

  /// 需要执行的副作用描述列表
  final List<PlaybackSideEffect> sideEffects;

  /// 快速构造忽略结果
  factory TransitionResult.ignore(
    PlaybackState state,
    PlaybackFsmContext context,
  ) {
    return TransitionResult(
      targetState: state,
      disposition: TransitionDisposition.ignore,
      nextContext: context,
    );
  }

  /// 快速构造排队结果
  factory TransitionResult.queue(
    PlaybackState state,
    PlaybackFsmContext nextContext,
  ) {
    return TransitionResult(
      targetState: state,
      disposition: TransitionDisposition.queue,
      nextContext: nextContext,
    );
  }
}

/// 纯转移函数入口
TransitionResult evaluateTransition({
  required PlaybackState currentState,
  required PlaybackFsmContext context,
  required PlaybackEvent event,
}) {
  // DISPOSE 请求在任意状态均直接迁移至 disposed 终态
  if (event is DisposeRequestEvent) {
    if (currentState == PlaybackState.disposed) {
      return TransitionResult.ignore(currentState, context);
    }
    // 特殊处理说明：
    // 依赖倒置与所有权解耦 (Dependency Inversion & Resource Ownership)：
    // [PlaybackFsm] 仅管理单次播放会话的状态流转，[backend] 作为外部注入的底层引擎，
    // 其物理生命周期属于外层管理者（如 PlaybackEnginePool 或 Controller）。
    // 会话终结时 FSM 仅执行静音暂停与定时器撤销，严禁越权物理销毁外部注入的底层引擎，
    // 确保 GPU 硬件加速纹理与 mpv 实例能够被跨会话安全保活与池化复用。
    return TransitionResult(
      targetState: PlaybackState.disposed,
      disposition: TransitionDisposition.exec,
      nextContext: context,
      sideEffects: const [
        CancelTimersEffect(),
        CallBackendPauseEffect(),
      ],
    );
  }

  // disposed 终态拒绝响应除 DisposeRequestEvent 之外的任何事件
  if (currentState == PlaybackState.disposed) {
    return TransitionResult.ignore(currentState, context);
  }

  return switch (currentState) {
    PlaybackState.idle => _onIdle(context, event),
    PlaybackState.resolving => _onResolving(context, event),
    PlaybackState.preparing => _onPreparing(context, event),
    PlaybackState.prebuffering => _onPrebuffering(context, event),
    PlaybackState.playing => _onPlaying(context, event),
    PlaybackState.paused => _onPaused(context, event),
    PlaybackState.seeking => _onSeeking(context, event),
    PlaybackState.rebuffering => _onRebuffering(context, event),
    PlaybackState.recovering => _onRecovering(context, event),
    PlaybackState.completed => _onCompleted(context, event),
    PlaybackState.error => _onError(context, event),
    PlaybackState.disposed => TransitionResult.ignore(currentState, context),
  };
}

// =============================================================================
// 各状态迁移私有实现（严格匹配 03 设计矩阵，无任何 default fallback）
// =============================================================================

/// 统一加载与切集请求处理逻辑
///
/// 特殊处理说明：
/// 若 [event.isPreResolved] 为 true（外部业务层已提前通过源运行时解析出真实媒体直链），
/// 状态机直接跳过 [PlaybackState.resolving] 阶段与冗余的网络空转，直接转入 [PlaybackState.preparing]
/// 并派发 [CallBackendOpenEffect]；
/// 若为 false，则维持原有标准流程，先执行 [ResolveMediaEffect] 获取媒体直链。
TransitionResult _handleLoadRequest(
  PlaybackFsmContext context,
  LoadRequestEvent event,
) {
  final nextContext = context.copyWith(
    attemptId: context.attemptId + 1,
    currentUri: event.uri,
    initialResumePosition: event.startPosition,
    autoplay: event.autoplay,
    headers: event.headers,
    resolvedUrl: event.isPreResolved ? event.uri : null,
    currentPosition: event.startPosition ?? Duration.zero,
    targetPhaseAfterFirstFrame: null,
    clearTargetPhaseAfterFirstFrame: true,
    pendingSeekPosition: null,
    clearPendingSeekPosition: true,
    recoveryAttempts: 0,
    eofRecoveryCount: 0,
    firstFrameRendered: false,
    hasValidDimensions: false,
    hasPositionAdvanced: false,
  );

  if (event.isPreResolved) {
    return TransitionResult(
      targetState: PlaybackState.preparing,
      disposition: TransitionDisposition.exec,
      nextContext: nextContext,
      sideEffects: [
        const CancelTimersEffect(),
        CallBackendOpenEffect(
          url: event.uri,
          start: event.startPosition,
          autoplay: event.autoplay,
          headers: event.headers,
        ),
      ],
    );
  }

  return TransitionResult(
    targetState: PlaybackState.resolving,
    disposition: TransitionDisposition.exec,
    nextContext: nextContext,
    sideEffects: const [
      CancelTimersEffect(),
      ResolveMediaEffect(bypassCache: false),
    ],
  );
}

TransitionResult _onIdle(PlaybackFsmContext context, PlaybackEvent event) {
  return switch (event) {
    LoadRequestEvent() => _handleLoadRequest(context, event),
    PauseRequestEvent() ||
    PlayRequestEvent() ||
    SeekRequestEvent() ||
    FatalErrorReceivedEvent() ||
    BufferingStartedEvent() ||
    BufferingEndedEvent() ||
    FirstFrameRenderedEvent() ||
    CompletedReceivedEvent() ||
    DisposeRequestEvent() ||
    ResolveSuccessEvent() ||
    ResolveFailureEvent() ||
    BackendDispatchedEvent() ||
    FirstFrameTimeoutEvent() ||
    OpenDemuxWatchdogTimeoutEvent() ||
    BufferingTimeoutEvent() ||
    RecoveryTimerExpiredEvent() ||
    SeekAcknowledgedEvent() ||
    RetryRequestEvent() =>
      TransitionResult.ignore(PlaybackState.idle, context),
  };
}

TransitionResult _onResolving(
    PlaybackFsmContext context, PlaybackEvent event) {
  return switch (event) {
    LoadRequestEvent() => _handleLoadRequest(context, event),
    PauseRequestEvent() => TransitionResult.queue(
        PlaybackState.resolving,
        context.copyWith(targetPhaseAfterFirstFrame: PlaybackState.paused),
      ),
    PlayRequestEvent() =>
      TransitionResult.ignore(PlaybackState.resolving, context),
    SeekRequestEvent(:final position) => TransitionResult.queue(
        PlaybackState.resolving,
        context.copyWith(pendingSeekPosition: position),
      ),
    ResolveSuccessEvent(:final url, :final headers) => TransitionResult(
        targetState: PlaybackState.preparing,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(
          resolvedUrl: url,
          headers: headers,
        ),
        sideEffects: [
          CallBackendOpenEffect(
            url: url,
            start: context.initialResumePosition,
            autoplay: context.autoplay,
            headers: headers,
          ),
        ],
      ),
    ResolveFailureEvent(:final error) => TransitionResult(
        targetState: PlaybackState.error,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(
          lastFailure: PlaybackFailure(
            kind: BackendErrorKind.unknown,
            action: RecoveryAction.fatalError,
            message: '视频直链解析失败: $error',
            availableActions: const [
              PlaybackUserAction.retry,
              PlaybackUserAction.switchLine,
              PlaybackUserAction.switchSource,
            ],
          ),
        ),
        sideEffects: [
          EmitFailureEffect(
            PlaybackFailure(
              kind: BackendErrorKind.unknown,
              action: RecoveryAction.fatalError,
              message: '视频直链解析失败: $error',
              availableActions: const [
                PlaybackUserAction.retry,
                PlaybackUserAction.switchLine,
                PlaybackUserAction.switchSource,
              ],
            ),
          ),
        ],
      ),
    FatalErrorReceivedEvent(:final error) => _handleFatalError(
        PlaybackState.resolving,
        context,
        error,
      ),
    BufferingStartedEvent() ||
    BufferingEndedEvent() ||
    FirstFrameRenderedEvent() ||
    CompletedReceivedEvent() ||
    DisposeRequestEvent() ||
    BackendDispatchedEvent() ||
    FirstFrameTimeoutEvent() ||
    OpenDemuxWatchdogTimeoutEvent() ||
    BufferingTimeoutEvent() ||
    RecoveryTimerExpiredEvent() ||
    SeekAcknowledgedEvent() ||
    RetryRequestEvent() =>
      TransitionResult.ignore(PlaybackState.resolving, context),
  };
}

TransitionResult _onPreparing(
    PlaybackFsmContext context, PlaybackEvent event) {
  return switch (event) {
    LoadRequestEvent() => _handleLoadRequest(context, event),
    PauseRequestEvent() => TransitionResult.queue(
        PlaybackState.preparing,
        context.copyWith(targetPhaseAfterFirstFrame: PlaybackState.paused),
      ),
    PlayRequestEvent() =>
      TransitionResult.ignore(PlaybackState.preparing, context),
    SeekRequestEvent(:final position) => TransitionResult.queue(
        PlaybackState.preparing,
        context.copyWith(pendingSeekPosition: position),
      ),
    BackendDispatchedEvent(:final generationId) => TransitionResult(
        targetState: PlaybackState.prebuffering,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(
          generationId: generationId,
          hasValidDimensions: false,
          hasPositionAdvanced: false,
        ),
      ),
    FatalErrorReceivedEvent(:final error) => _handleFatalError(
        PlaybackState.preparing,
        context,
        error,
      ),
    BufferingStartedEvent() ||
    BufferingEndedEvent() ||
    FirstFrameRenderedEvent() ||
    CompletedReceivedEvent() ||
    DisposeRequestEvent() ||
    ResolveSuccessEvent() ||
    ResolveFailureEvent() ||
    FirstFrameTimeoutEvent() ||
    OpenDemuxWatchdogTimeoutEvent() ||
    BufferingTimeoutEvent() ||
    RecoveryTimerExpiredEvent() ||
    SeekAcknowledgedEvent() ||
    RetryRequestEvent() =>
      TransitionResult.ignore(PlaybackState.preparing, context),
  };
}

TransitionResult _onPrebuffering(
    PlaybackFsmContext context, PlaybackEvent event) {
  return switch (event) {
    LoadRequestEvent() => _handleLoadRequest(context, event),
    PauseRequestEvent() => TransitionResult.queue(
        PlaybackState.prebuffering,
        context.copyWith(targetPhaseAfterFirstFrame: PlaybackState.paused),
      ),
    PlayRequestEvent() =>
      TransitionResult.ignore(PlaybackState.prebuffering, context),
    SeekRequestEvent(:final position) => TransitionResult.queue(
        PlaybackState.prebuffering,
        context.copyWith(pendingSeekPosition: position),
      ),
    FirstFrameRenderedEvent() => _evaluateFirstFrameRendered(context),
    FirstFrameTimeoutEvent(:final hasLivenessProof) => hasLivenessProof
        ? _onFirstFrameSuccess(context)
        : _onWatchdogOrStallTriggered(
            context,
            message: '首帧出画超时且无存活证据',
          ),
    OpenDemuxWatchdogTimeoutEvent() => _onWatchdogOrStallTriggered(
        context,
        message: '解复用解析超时 (12s)',
      ),
    FatalErrorReceivedEvent(:final error) => _handleFatalError(
        PlaybackState.prebuffering,
        context,
        error,
      ),
    BufferingStartedEvent() ||
    BufferingEndedEvent() ||
    CompletedReceivedEvent() ||
    DisposeRequestEvent() ||
    ResolveSuccessEvent() ||
    ResolveFailureEvent() ||
    BackendDispatchedEvent() ||
    BufferingTimeoutEvent() ||
    RecoveryTimerExpiredEvent() ||
    SeekAcknowledgedEvent() ||
    RetryRequestEvent() =>
      TransitionResult.ignore(PlaybackState.prebuffering, context),
  };
}

TransitionResult _onPlaying(
    PlaybackFsmContext context, PlaybackEvent event) {
  return switch (event) {
    LoadRequestEvent() => _handleLoadRequest(context, event),
    PauseRequestEvent() => TransitionResult(
        targetState: PlaybackState.paused,
        disposition: TransitionDisposition.exec,
        nextContext: context,
        sideEffects: const [CallBackendPauseEffect()],
      ),
    PlayRequestEvent() =>
      TransitionResult.ignore(PlaybackState.playing, context),
    SeekRequestEvent(:final position) => TransitionResult(
        targetState: PlaybackState.seeking,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(
          phaseBeforeSeeking: PlaybackState.playing,
          currentPosition: position,
        ),
        sideEffects: [CallBackendSeekEffect(position)],
      ),
    BufferingStartedEvent() => TransitionResult(
        targetState: PlaybackState.rebuffering,
        disposition: TransitionDisposition.exec,
        nextContext: context,
      ),
    CompletedReceivedEvent(:final currentPosition, :final duration) =>
      _onCompletedReceived(
        context,
        currentPos: currentPosition,
        totalDur: duration,
      ),
    FatalErrorReceivedEvent(:final error) => _handleFatalError(
        PlaybackState.playing,
        context,
        error,
      ),
    BufferingEndedEvent() ||
    FirstFrameRenderedEvent() ||
    DisposeRequestEvent() ||
    ResolveSuccessEvent() ||
    ResolveFailureEvent() ||
    BackendDispatchedEvent() ||
    FirstFrameTimeoutEvent() ||
    OpenDemuxWatchdogTimeoutEvent() ||
    BufferingTimeoutEvent() ||
    RecoveryTimerExpiredEvent() ||
    SeekAcknowledgedEvent() ||
    RetryRequestEvent() =>
      TransitionResult.ignore(PlaybackState.playing, context),
  };
}

TransitionResult _onPaused(PlaybackFsmContext context, PlaybackEvent event) {
  return switch (event) {
    LoadRequestEvent() => _handleLoadRequest(context, event),
    PauseRequestEvent() =>
      TransitionResult.ignore(PlaybackState.paused, context),
    PlayRequestEvent() => TransitionResult(
        targetState: PlaybackState.playing,
        disposition: TransitionDisposition.exec,
        nextContext: context,
        sideEffects: const [CallBackendPlayEffect()],
      ),
    SeekRequestEvent(:final position) => TransitionResult(
        targetState: PlaybackState.seeking,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(
          phaseBeforeSeeking: PlaybackState.paused,
          currentPosition: position,
        ),
        sideEffects: [CallBackendSeekEffect(position)],
      ),
    FatalErrorReceivedEvent(:final error) => _handleFatalError(
        PlaybackState.paused,
        context,
        error,
      ),
    BufferingStartedEvent() ||
    BufferingEndedEvent() ||
    FirstFrameRenderedEvent() ||
    CompletedReceivedEvent() ||
    DisposeRequestEvent() ||
    ResolveSuccessEvent() ||
    ResolveFailureEvent() ||
    BackendDispatchedEvent() ||
    FirstFrameTimeoutEvent() ||
    OpenDemuxWatchdogTimeoutEvent() ||
    BufferingTimeoutEvent() ||
    RecoveryTimerExpiredEvent() ||
    SeekAcknowledgedEvent() ||
    RetryRequestEvent() =>
      TransitionResult.ignore(PlaybackState.paused, context),
  };
}

TransitionResult _onSeeking(PlaybackFsmContext context, PlaybackEvent event) {
  return switch (event) {
    LoadRequestEvent() => _handleLoadRequest(context, event),
    PauseRequestEvent() => TransitionResult.queue(
        PlaybackState.seeking,
        context.copyWith(phaseBeforeSeeking: PlaybackState.paused),
      ),
    PlayRequestEvent() => TransitionResult.queue(
        PlaybackState.seeking,
        context.copyWith(phaseBeforeSeeking: PlaybackState.playing),
      ),
    SeekRequestEvent(:final position) => TransitionResult(
        targetState: PlaybackState.seeking,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(currentPosition: position),
        sideEffects: [CallBackendSeekEffect(position)],
      ),
    SeekAcknowledgedEvent(:final newPosition) => TransitionResult(
        targetState: context.phaseBeforeSeeking,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(currentPosition: newPosition),
        sideEffects: context.phaseBeforeSeeking == PlaybackState.playing
            ? const [CallBackendPlayEffect()]
            : const [],
      ),
    CompletedReceivedEvent(:final currentPosition, :final duration) =>
      _onCompletedReceived(
        context,
        currentPos: currentPosition,
        totalDur: duration,
      ),
    FatalErrorReceivedEvent(:final error) => _handleFatalError(
        PlaybackState.seeking,
        context,
        error,
      ),
    BufferingStartedEvent() ||
    BufferingEndedEvent() ||
    FirstFrameRenderedEvent() ||
    DisposeRequestEvent() ||
    ResolveSuccessEvent() ||
    ResolveFailureEvent() ||
    BackendDispatchedEvent() ||
    FirstFrameTimeoutEvent() ||
    OpenDemuxWatchdogTimeoutEvent() ||
    BufferingTimeoutEvent() ||
    RecoveryTimerExpiredEvent() ||
    RetryRequestEvent() =>
      TransitionResult.ignore(PlaybackState.seeking, context),
  };
}

TransitionResult _onRebuffering(
    PlaybackFsmContext context, PlaybackEvent event) {
  return switch (event) {
    LoadRequestEvent() => _handleLoadRequest(context, event),
    PauseRequestEvent() => TransitionResult(
        targetState: PlaybackState.paused,
        disposition: TransitionDisposition.exec,
        nextContext: context,
        sideEffects: const [CallBackendPauseEffect()],
      ),
    PlayRequestEvent() =>
      TransitionResult.ignore(PlaybackState.rebuffering, context),
    SeekRequestEvent(:final position) => TransitionResult(
        targetState: PlaybackState.seeking,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(
          phaseBeforeSeeking: PlaybackState.playing,
          currentPosition: position,
        ),
        sideEffects: [CallBackendSeekEffect(position)],
      ),
    BufferingEndedEvent() => TransitionResult(
        targetState: PlaybackState.playing,
        disposition: TransitionDisposition.exec,
        nextContext: context,
      ),
    BufferingTimeoutEvent() => TransitionResult(
        targetState: PlaybackState.recovering,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(
          recoveryAttempts: context.recoveryAttempts + 1,
        ),
        sideEffects: const [
          ResolveMediaEffect(bypassCache: true),
        ],
      ),
    CompletedReceivedEvent(:final currentPosition, :final duration) =>
      _onCompletedReceived(
        context,
        currentPos: currentPosition,
        totalDur: duration,
      ),
    FatalErrorReceivedEvent(:final error) => _handleFatalError(
        PlaybackState.rebuffering,
        context,
        error,
      ),
    BufferingStartedEvent() ||
    FirstFrameRenderedEvent() ||
    DisposeRequestEvent() ||
    ResolveSuccessEvent() ||
    ResolveFailureEvent() ||
    BackendDispatchedEvent() ||
    FirstFrameTimeoutEvent() ||
    OpenDemuxWatchdogTimeoutEvent() ||
    RecoveryTimerExpiredEvent() ||
    SeekAcknowledgedEvent() ||
    RetryRequestEvent() =>
      TransitionResult.ignore(PlaybackState.rebuffering, context),
  };
}

TransitionResult _onRecovering(
    PlaybackFsmContext context, PlaybackEvent event) {
  return switch (event) {
    LoadRequestEvent() => _handleLoadRequest(context, event),
    PauseRequestEvent() => TransitionResult.queue(
        PlaybackState.recovering,
        context.copyWith(targetPhaseAfterFirstFrame: PlaybackState.paused),
      ),
    PlayRequestEvent() => TransitionResult.queue(
        PlaybackState.recovering,
        context.copyWith(targetPhaseAfterFirstFrame: PlaybackState.playing),
      ),
    SeekRequestEvent(:final position) => TransitionResult.queue(
        PlaybackState.recovering,
        context.copyWith(pendingSeekPosition: position),
      ),
    RecoveryTimerExpiredEvent() => TransitionResult(
        targetState: PlaybackState.resolving,
        disposition: TransitionDisposition.exec,
        nextContext: context,
        sideEffects: const [ResolveMediaEffect(bypassCache: true)],
      ),
    RetryRequestEvent() => TransitionResult(
        targetState: PlaybackState.resolving,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(recoveryAttempts: 0),
        sideEffects: const [ResolveMediaEffect(bypassCache: true)],
      ),
    FatalErrorReceivedEvent(:final error) => TransitionResult(
        targetState: PlaybackState.error,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(
          lastFailure: PlaybackFailure(
            kind: error.kind,
            action: error.action == RecoveryAction.switchLine
                ? RecoveryAction.switchLine
                : RecoveryAction.fatalError,
            message: error.rawMessage,
            host: error.host,
            port: error.port,
            availableActions: const [
              PlaybackUserAction.retry,
              PlaybackUserAction.switchLine,
              PlaybackUserAction.switchSource,
            ],
          ),
        ),
        sideEffects: [
          const CancelTimersEffect(),
          EmitFailureEffect(
            PlaybackFailure(
              kind: error.kind,
              action: error.action == RecoveryAction.switchLine
                  ? RecoveryAction.switchLine
                  : RecoveryAction.fatalError,
              message: error.rawMessage,
              host: error.host,
              port: error.port,
              availableActions: const [
                PlaybackUserAction.retry,
                PlaybackUserAction.switchLine,
                PlaybackUserAction.switchSource,
              ],
            ),
          ),
        ],
      ),
    BackendDispatchedEvent(:final generationId) => TransitionResult(
        targetState: PlaybackState.prebuffering,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(
          generationId: generationId,
          hasValidDimensions: false,
          hasPositionAdvanced: false,
        ),
      ),
    BufferingStartedEvent() ||
    BufferingEndedEvent() ||
    FirstFrameRenderedEvent() ||
    CompletedReceivedEvent() ||
    DisposeRequestEvent() ||
    ResolveSuccessEvent() ||
    ResolveFailureEvent() ||
    FirstFrameTimeoutEvent() ||
    OpenDemuxWatchdogTimeoutEvent() ||
    BufferingTimeoutEvent() ||
    SeekAcknowledgedEvent() =>
      TransitionResult.ignore(PlaybackState.recovering, context),
  };
}

TransitionResult _onCompleted(
    PlaybackFsmContext context, PlaybackEvent event) {
  return switch (event) {
    LoadRequestEvent() => _handleLoadRequest(context, event),
    PlayRequestEvent() => TransitionResult(
        targetState: PlaybackState.seeking,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(
          phaseBeforeSeeking: PlaybackState.playing,
          currentPosition: Duration.zero,
        ),
        sideEffects: const [
          CallBackendSeekEffect(Duration.zero),
          CallBackendPlayEffect(),
        ],
      ),
    SeekRequestEvent(:final position) => TransitionResult(
        targetState: PlaybackState.seeking,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(
          phaseBeforeSeeking: PlaybackState.playing,
          currentPosition: position,
        ),
        sideEffects: [CallBackendSeekEffect(position)],
      ),
    PauseRequestEvent() ||
    FatalErrorReceivedEvent() ||
    BufferingStartedEvent() ||
    BufferingEndedEvent() ||
    FirstFrameRenderedEvent() ||
    CompletedReceivedEvent() ||
    DisposeRequestEvent() ||
    ResolveSuccessEvent() ||
    ResolveFailureEvent() ||
    BackendDispatchedEvent() ||
    FirstFrameTimeoutEvent() ||
    OpenDemuxWatchdogTimeoutEvent() ||
    BufferingTimeoutEvent() ||
    RecoveryTimerExpiredEvent() ||
    SeekAcknowledgedEvent() ||
    RetryRequestEvent() =>
      TransitionResult.ignore(PlaybackState.completed, context),
  };
}

TransitionResult _onError(PlaybackFsmContext context, PlaybackEvent event) {
  return switch (event) {
    LoadRequestEvent() => _handleLoadRequest(context, event),
    RetryRequestEvent() => TransitionResult(
        targetState: PlaybackState.resolving,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(
          recoveryAttempts: 0,
        ),
        sideEffects: const [
          CancelTimersEffect(),
          ResolveMediaEffect(bypassCache: true),
        ],
      ),
    // 特殊处理说明：
    // 首帧事实出画自愈保护：
    // 当底层解码成功输出真实物理画面（有效尺寸且位置产生前进位移）时，
    // 事实出画具有最高权威，即使曾进入 error 态也直接自愈转入 playing，彻底消除残留的超时报错。
    FirstFrameRenderedEvent() => _evaluateFirstFrameRendered(
        context,
        currentState: PlaybackState.error,
      ),
    PauseRequestEvent() ||
    PlayRequestEvent() ||
    SeekRequestEvent() ||
    FatalErrorReceivedEvent() ||
    BufferingStartedEvent() ||
    BufferingEndedEvent() ||
    CompletedReceivedEvent() ||
    DisposeRequestEvent() ||
    ResolveSuccessEvent() ||
    ResolveFailureEvent() ||
    BackendDispatchedEvent() ||
    FirstFrameTimeoutEvent() ||
    OpenDemuxWatchdogTimeoutEvent() ||
    BufferingTimeoutEvent() ||
    RecoveryTimerExpiredEvent() ||
    SeekAcknowledgedEvent() =>
      TransitionResult.ignore(PlaybackState.error, context),
  };
}

// =============================================================================
// 辅助决策逻辑
// =============================================================================

/// 首帧条件评估（对齐 03 第五节规范：F2 修复）
/// 1. 播放意图：尺寸有效 且 位置推进 (>0)；
/// 2. 暂停意图：解码出物理首帧后被底层暂停定格，时钟保持在 0ms，尺寸有效即可；
/// 3. 纯音频媒体：realVideoTrackCount == 0，无视频尺寸事件，位置推进即可。
TransitionResult _evaluateFirstFrameRendered(
  PlaybackFsmContext context, {
  PlaybackState currentState = PlaybackState.prebuffering,
}) {
  final isPausedIntent = !context.autoplay ||
      context.targetPhaseAfterFirstFrame == PlaybackState.paused;

  final bool canTrigger;
  if (context.realVideoTrackCount == 0) {
    // 纯音频媒体：仅要求位置推进
    canTrigger = context.hasPositionAdvanced;
  } else if (isPausedIntent) {
    // 暂停意图：解码出物理首帧后被挂起，时钟停在 0ms，仅需尺寸有效
    canTrigger = context.hasValidDimensions;
  } else {
    // 播放意图：必须同时满足尺寸有效且位置推进（产生物理出画位移）
    canTrigger = context.hasValidDimensions && context.hasPositionAdvanced;
  }

  if (canTrigger) {
    return _onFirstFrameSuccess(context);
  } else {
    return TransitionResult.ignore(currentState, context);
  }
}

/// 首帧物理渲染或有证据放行时的状态决断
TransitionResult _onFirstFrameSuccess(PlaybackFsmContext context) {
  final targetState =
      context.targetPhaseAfterFirstFrame ?? (context.autoplay ? PlaybackState.playing : PlaybackState.paused);

  final List<PlaybackSideEffect> effects = [];
  if (targetState == PlaybackState.paused) {
    effects.add(const CallBackendPauseEffect());
  }
  if (context.pendingSeekPosition != null) {
    effects.add(CallBackendSeekEffect(context.pendingSeekPosition!));
  }

  return TransitionResult(
    targetState: targetState,
    disposition: TransitionDisposition.exec,
    nextContext: context.copyWith(
      firstFrameRendered: true,
      clearLastFailure: true,
      pendingSeekPosition: null,
      clearPendingSeekPosition: true,
    ),
    sideEffects: effects,
  );
}

/// 打开阶段看门狗或首帧死锁触发时的决策
///
/// 依据预算规则修订（修订 1）：起播 0s 满 12s 看门狗超时时，总预算 13s 剩余不足 5s，
/// 必须直接转入 error 并暴露重试与换线操作项！
TransitionResult _onWatchdogOrStallTriggered(
  PlaybackFsmContext context, {
  required String message,
}) {
  final failure = PlaybackFailure(
    kind: BackendErrorKind.openDemuxWatchdog,
    action: RecoveryAction.switchLine,
    message: message,
    availableActions: const [
      PlaybackUserAction.retry,
      PlaybackUserAction.switchLine,
      PlaybackUserAction.switchSource,
    ],
  );

  return TransitionResult(
    targetState: PlaybackState.error,
    disposition: TransitionDisposition.exec,
    nextContext: context.copyWith(
      lastFailure: failure,
    ),
    sideEffects: [
      const CancelTimersEffect(),
      const CallBackendPauseEffect(),
      EmitFailureEffect(failure),
    ],
  );
}

/// 致命错误统一研判处置
TransitionResult _handleFatalError(
  PlaybackState currentState,
  PlaybackFsmContext context,
  BackendError error,
) {
  // 根据错误本身的恢复动作和重试次数判断
  // 握手关闭 (handshakeClosed) 或连接超时 (connectTimeout) 等需要切线
  if (error.action == RecoveryAction.switchLine ||
      error.action == RecoveryAction.fatalError) {
    final failure = PlaybackFailure(
      kind: error.kind,
      action: error.action,
      message: error.rawMessage,
      host: error.host,
      port: error.port,
      availableActions: const [
        PlaybackUserAction.retry,
        PlaybackUserAction.switchLine,
        PlaybackUserAction.switchSource,
      ],
    );

    return TransitionResult(
      targetState: PlaybackState.error,
      disposition: TransitionDisposition.exec,
      nextContext: context.copyWith(lastFailure: failure),
      sideEffects: [
        const CancelTimersEffect(),
        const CallBackendPauseEffect(),
        EmitFailureEffect(failure),
      ],
    );
  }

  // 针对 openFailedUnknown 等可 refreshAndRetry 的错误
  if (error.action == RecoveryAction.refreshAndRetry) {
    if (context.recoveryAttempts < 1) {
      return TransitionResult(
        targetState: PlaybackState.recovering,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(
          recoveryAttempts: context.recoveryAttempts + 1,
        ),
        sideEffects: const [
          ResolveMediaEffect(bypassCache: true),
        ],
      );
    } else {
      // 超过 1 次重试，直接转 error
      final failure = PlaybackFailure(
        kind: error.kind,
        action: RecoveryAction.switchLine,
        message: '媒体重试刷新失败: ${error.rawMessage}',
        host: error.host,
        port: error.port,
        availableActions: const [
          PlaybackUserAction.retry,
          PlaybackUserAction.switchLine,
          PlaybackUserAction.switchSource,
        ],
      );
      return TransitionResult(
        targetState: PlaybackState.error,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(lastFailure: failure),
        sideEffects: [
          const CancelTimersEffect(),
          const CallBackendPauseEffect(),
          EmitFailureEffect(failure),
        ],
      );
    }
  }

  // 原地重试 (retryInPlace)
  if (context.recoveryAttempts < 2) {
    return TransitionResult(
      targetState: PlaybackState.recovering,
      disposition: TransitionDisposition.exec,
      nextContext: context.copyWith(
        recoveryAttempts: context.recoveryAttempts + 1,
      ),
      sideEffects: [
        if (context.resolvedUrl != null)
          CallBackendOpenEffect(
            url: context.resolvedUrl!,
            start: context.currentPosition,
            autoplay: context.autoplay,
            headers: context.headers,
          ),
      ],
    );
  }

  // 预算耗尽，转入 error
  final failure = PlaybackFailure(
    kind: error.kind,
    action: RecoveryAction.fatalError,
    message: error.rawMessage,
    host: error.host,
    port: error.port,
    availableActions: const [
      PlaybackUserAction.retry,
      PlaybackUserAction.switchLine,
      PlaybackUserAction.switchSource,
    ],
  );

  return TransitionResult(
    targetState: PlaybackState.error,
    disposition: TransitionDisposition.exec,
    nextContext: context.copyWith(lastFailure: failure),
    sideEffects: [
      const CancelTimersEffect(),
      const CallBackendPauseEffect(),
      EmitFailureEffect(failure),
    ],
  );
}

/// 自然完播与异常 EOF 拦截处置（03 第 5.3 节）
TransitionResult _onCompletedReceived(
  PlaybackFsmContext context, {
  required Duration currentPos,
  required Duration totalDur,
}) {
  // 1. 正常完播：当前进度已接近视频总时长 (容差 2 秒)
  if (totalDur > Duration.zero && currentPos >= totalDur - kCompletedTolerance) {
    return TransitionResult(
      targetState: PlaybackState.completed,
      disposition: TransitionDisposition.exec,
      nextContext: context.copyWith(currentPosition: totalDur),
      sideEffects: const [CancelTimersEffect()],
    );
  }

  // 2. 异常断流检测
  final lastEof = context.lastEofPosition;
  final eofCount = context.eofRecoveryCount;
  final isLoop = lastEof != null && (currentPos - lastEof).abs() < kEofLoopProgressThreshold;
  final isExhausted = eofCount >= kMaxEofRecoveryAttempts;

  // 2.1 回环保护触发或恢复次数用尽 (1次)
  if (isLoop || isExhausted) {
    final remaining = totalDur > Duration.zero ? totalDur - currentPos : Duration.zero;
    // 完播判定阈值：不足 30 秒或不到总时长的 2%
    final naturalCompletionThreshold = Duration(
      milliseconds: math.max(
        30000,
        (totalDur.inMilliseconds * 0.02).round(),
      ),
    );

    if (remaining <= naturalCompletionThreshold) {
      // 剩余极短，作为片尾自然完播终结
      return TransitionResult(
        targetState: PlaybackState.completed,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(currentPosition: totalDur),
        sideEffects: const [CancelTimersEffect()],
      );
    } else {
      // 中途严重断流，转入 error，卡片提供断点重试与换线，严禁标记已看！
      final failure = PlaybackFailure(
        kind: BackendErrorKind.unknown,
        action: RecoveryAction.fatalError,
        message: '视频播放意外中断，源文件可能残缺',
        availableActions: const [
          PlaybackUserAction.retry,
          PlaybackUserAction.switchLine,
          PlaybackUserAction.switchSource,
        ],
      );
      return TransitionResult(
        targetState: PlaybackState.error,
        disposition: TransitionDisposition.exec,
        nextContext: context.copyWith(lastFailure: failure),
        sideEffects: [
          CancelTimersEffect(),
          EmitFailureEffect(failure),
        ],
      );
    }
  }

  // 2.2 首次遇到中途异常 EOF：触发断点续接恢复
  return TransitionResult(
    targetState: PlaybackState.recovering,
    disposition: TransitionDisposition.exec,
    nextContext: context.copyWith(
      lastEofPosition: currentPos,
      eofRecoveryCount: eofCount + 1,
      recoveryAttempts: context.recoveryAttempts + 1,
      currentPosition: currentPos,
    ),
    sideEffects: [
      if (context.resolvedUrl != null)
        CallBackendOpenEffect(
          url: context.resolvedUrl!,
          start: currentPos,
          autoplay: context.autoplay,
          headers: context.headers,
        ),
    ],
  );
}
