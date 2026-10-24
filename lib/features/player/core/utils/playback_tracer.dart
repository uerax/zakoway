import 'package:flutter/foundation.dart';

/// 播放全链路耗时与性能可观测性追踪器
///
/// 记录从用户点击/切集开始，经由章节获取、直链解析、底层 IPC 派发到最终首帧物理出画的
/// 完整流水线耗时与阶段状态，方便线上排查瓶颈与性能优化。
class PlaybackTracer {
  PlaybackTracer._();

  static final PlaybackTracer instance = PlaybackTracer._();

  int _sessionIdCounter = 0;
  PlaybackTraceSession? _currentSession;

  /// 开启一个新的播放链路追踪会话
  PlaybackTraceSession startSession({
    required String title,
    required int episode,
    required String sourceId,
  }) {
    final session = PlaybackTraceSession(
      sessionId: ++_sessionIdCounter,
      title: title,
      episode: episode,
      sourceId: sourceId,
    );
    _currentSession = session;
    return session;
  }

  /// 获取当前活跃的追踪会话
  PlaybackTraceSession? get current => _currentSession;
}

/// 单次播放链路的耗时追踪上下文
class PlaybackTraceSession {
  PlaybackTraceSession({
    required this.sessionId,
    required this.title,
    required this.episode,
    required this.sourceId,
  }) : _startTime = DateTime.now();

  final int sessionId;
  final String title;
  final int episode;
  final String sourceId;

  final DateTime _startTime;
  DateTime? _chaptersTime;
  DateTime? _resolveStartTime;
  DateTime? _resolveSuccessTime;
  DateTime? _backendOpenTime;
  DateTime? _firstFrameTime;
  DateTime? _failureTime;

  bool _isPreResolved = false;

  /// 标记章节获取完成
  void markChaptersFetched({int roadCount = 0, int episodeCount = 0}) {
    if (_chaptersTime != null) return;
    _chaptersTime = DateTime.now();
    _logStage('章节就绪 ($roadCount条线路/$episodeCount集)', _chaptersTime!);
  }

  /// 标记开始解析直链
  void markResolveStarted() {
    _resolveStartTime ??= DateTime.now();
  }

  /// 标记直链解析完成
  void markResolveSuccess({bool preResolved = false}) {
    _isPreResolved = preResolved;
    _resolveSuccessTime ??= DateTime.now();
    _logStage(preResolved ? '直链已就绪(直通)' : '直链解析成功', _resolveSuccessTime!);
  }

  /// 标记已向底层播放器下发 open IPC 指令
  void markBackendOpenDispatched() {
    _backendOpenTime ??= DateTime.now();
    _logStage('底层Open指令派发', _backendOpenTime!);
  }

  /// 标记首帧物理出画成功
  void markFirstFrameRendered() {
    if (_firstFrameTime != null) return;
    _firstFrameTime = DateTime.now();

    final totalElapsedMs = _firstFrameTime!.difference(_startTime).inMilliseconds;
    final resolveMs = _resolveSuccessTime != null && _resolveStartTime != null
        ? _resolveSuccessTime!.difference(_resolveStartTime!).inMilliseconds
        : (_resolveSuccessTime != null ? _resolveSuccessTime!.difference(_startTime).inMilliseconds : 0);
    final openToFrameMs = _backendOpenTime != null
        ? _firstFrameTime!.difference(_backendOpenTime!).inMilliseconds
        : 0;

    if (kDebugMode) {
      debugPrint(
        '🏁 [PlaybackTracer #$sessionId] 《$title》EP$episode ($sourceId) 首帧物理出画就绪!\n'
        '   ├─ 预解析直通: $_isPreResolved\n'
        '   ├─ 直链耗时: ${resolveMs}ms\n'
        '   ├─ 底层解码出画: ${openToFrameMs}ms\n'
        '   └─ 起播总耗时: ${totalElapsedMs}ms',
      );
    }
  }

  /// 标记播放异常或失败
  void markFailure(String reason) {
    _failureTime ??= DateTime.now();
    final elapsedMs = _failureTime!.difference(_startTime).inMilliseconds;
    if (kDebugMode) {
      debugPrint('⚠️ [PlaybackTracer #$sessionId] 《$title》EP$episode 播放异常 (+${elapsedMs}ms): $reason');
    }
  }

  void _logStage(String stage, DateTime stageTime) {
    if (kDebugMode) {
      final elapsed = stageTime.difference(_startTime).inMilliseconds;
      debugPrint('⏱️ [PlaybackTracer #$sessionId] +${elapsed}ms -> $stage');
    }
  }
}
