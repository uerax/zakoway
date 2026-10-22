/// 播放器底层事件代际隔离与重置标记门禁 (Reset Marker Gate)
///
/// 遵循 docs/player-rewrite/03-state-machine.md (v3.1) 第六节规范
/// 纯 Dart 实现，无任何 UI/Flutter 框架依赖，负责在底层事件进入状态机 evaluateTransition 前完成物理代际过滤。
///
/// 核心职责：
/// 1. 有重置标记的流通道 (playing, position, duration, buffer, buffering, dimensions)：
///    收到该流自己的重置标记 (isResetMarker == true) 之前的旧流残余事件一律丢弃；
/// 2. stream.completed 无重置标记通道：
///    只在“本代际 duration > 0 且 position > 0”确立之后才放行，彻底杜绝切集起播初期的旧流假完播；
/// 3. stream.error 与 stream.log 诊断通道：
///    按 URL 或主机名精准归因，并核验“自 open 调用时刻以来”的时间窗口；
///    携带主机名且与当前目标主机不一致者坚决丢弃；不带主机名者仅作为诊断线索，不得触发状态迁移；
/// 4. stream.log 与 stream.error 重复发射去重：
///    media_kit 会将同一底层物理错误同时广播至两个流（时间戳容差 <= 10ms，文本相同），在此做去重。
library;

import '../backend/backend_event.dart';
import '../models/backend_error.dart';

/// 具有独立重置标记的底层流通道枚举
enum BackendStreamChannel {
  playing,
  buffering,
  position,
  duration,
  buffer,
  dimensions,
}

/// 经过门禁研判后的错误处置决策
enum GatedErrorDisposition {
  /// 致命错误通过门禁，具备当前目标主机归因，可触发状态机状态迁移 (FatalErrorReceivedEvent)
  passFatal,

  /// 不带主机名的底层孤立错误/日志，仅作诊断线索，不得直接触发状态机失败迁移
  diagnosticOnly,

  /// 主机名不匹配、旧代际残留或早于 open 时间窗口，坚决静默丢弃
  discard,
}

/// 经过门禁研判后的日志处置决策
enum GatedLogDisposition {
  /// 通过门禁的有效诊断日志
  passDiagnostic,

  /// 重复日志（stream.log 与 stream.error 在 10ms 容差内重复发射），已去重
  deduplicated,

  /// 主机不匹配、旧代际残留或早于 open 时间窗口，静默丢弃
  discard,
}

/// 最近接收到的日志记录项（用于 stream.log 与 stream.error 重复日志去重）
class _RecentLogEntry {
  const _RecentLogEntry({
    required this.text,
    required this.timestamp,
    this.source,
  });

  final String text;
  final DateTime timestamp;
  final String? source;
}

/// 纯 Dart 事件门禁实现
class BackendEventGate {
  BackendEventGate();

  int? _currentGenerationId;
  Uri? _targetUri;
  DateTime? _openTime;

  /// 本代际已识别并放行的重定向目标主机集合 (支持 302 重定向节点错误归因)
  final Set<String> _redirectHosts = {};

  /// 各流通道是否已收到本代际专属重置标记
  final Set<BackendStreamChannel> _receivedResetMarkers = {};

  /// 本代际当前确立的媒体总时长
  Duration _currentDuration = Duration.zero;

  /// 本代际当前确立的播放进度位置
  Duration _currentPosition = Duration.zero;

  /// 最近处理的日志记录滑窗（用于 10ms 容差去重）
  final List<_RecentLogEntry> _recentLogs = [];
  static const int _maxRecentLogs = 16;
  static const Duration _dedupTolerance = Duration(milliseconds: 10);

  // ===========================================================================
  // 只读属性查询
  // ===========================================================================

  /// 当前处于的底层 open 代际 ID
  int? get currentGenerationId => _currentGenerationId;

  /// 当前代际目标媒体 URI
  Uri? get targetUri => _targetUri;

  /// 当前代际 open 调用时刻
  DateTime? get openTime => _openTime;

  /// 当前代际记录的媒体总时长
  Duration get currentDuration => _currentDuration;

  /// 当前代际记录的播放进度位置
  Duration get currentPosition => _currentPosition;

  /// 检查指定流通道是否已收到本代际重置标记
  bool hasResetMarker(BackendStreamChannel channel) =>
      _receivedResetMarkers.contains(channel);

  // ===========================================================================
  // 生命周期与重置
  // ===========================================================================

  /// 当发起新的 open 调用时，开启全新代际隔离视窗
  void resetForNewOpen({
    required int generationId,
    required Uri targetUri,
    DateTime? openTime,
  }) {
    _currentGenerationId = generationId;
    _targetUri = targetUri;
    _openTime = openTime ?? DateTime.now();

    // 清空重置标记收集状态与媒体时长/进度基线
    _receivedResetMarkers.clear();
    _currentDuration = Duration.zero;
    _currentPosition = Duration.zero;
    _recentLogs.clear();
    _redirectHosts.clear();
  }

  /// 注册当前 open 会话中由 302 重定向触发的目标主机
  void registerRedirectHost(String host) {
    if (host.isNotEmpty) {
      _redirectHosts.add(host.toLowerCase());
    }
  }

  // ===========================================================================
  // 有重置标记通道门禁校验
  // ===========================================================================

  /// 通用重置标记流通道校验逻辑
  ///
  /// 规则：
  /// 1. 代际 ID 不匹配者一律丢弃；
  /// 2. 在本通道收到自己的 isResetMarker 之前，非重置事件一律丢弃；
  /// 3. 当本通道收到 isResetMarker == true 时，标记该通道重置就绪，并放行该重置标记；
  /// 4. 收到重置标记之后，同代际后续事件正常放行。
  bool _canPassChannel<T>(
    BackendStreamChannel channel,
    BackendEvent<T> event,
  ) {
    if (_currentGenerationId == null || event.generationId != _currentGenerationId) {
      return false;
    }

    if (!_receivedResetMarkers.contains(channel)) {
      if (event.isResetMarker) {
        _receivedResetMarkers.add(channel);
        return true;
      }
      // 重置标记到达前的旧流残留事件，一律丢弃
      return false;
    }

    return true;
  }

  /// 校验 playing 流事件
  bool canPassPlaying(BackendEvent<bool> event) {
    return _canPassChannel(BackendStreamChannel.playing, event);
  }

  /// 校验 buffering 流事件
  bool canPassBuffering(BackendEvent<bool> event) {
    return _canPassChannel(BackendStreamChannel.buffering, event);
  }

  /// 校验 position 流事件
  bool canPassPosition(BackendEvent<Duration> event) {
    final passed = _canPassChannel(BackendStreamChannel.position, event);
    if (passed) {
      _currentPosition = event.data;
    }
    return passed;
  }

  /// 校验 duration 流事件
  bool canPassDuration(BackendEvent<Duration> event) {
    final passed = _canPassChannel(BackendStreamChannel.duration, event);
    if (passed) {
      _currentDuration = event.data;
    }
    return passed;
  }

  /// 校验 buffer 缓冲区水位事件
  bool canPassBuffer(BackendEvent<Duration> event) {
    return _canPassChannel(BackendStreamChannel.buffer, event);
  }

  /// 校验 dimensions 视频尺寸变化事件
  bool canPassDimensions(BackendEvent<VideoDimensions> event) {
    return _canPassChannel(BackendStreamChannel.dimensions, event);
  }

  // ===========================================================================
  // 无重置标记流门禁：completed
  // ===========================================================================

  /// 校验 completed 完播/EOF 事件
  ///
  /// 遵循 03 第 6.2 节：
  /// completed 流在 open 时无重置标记，必须在收到本代际重置标记之后，
  /// 且“本代际 duration > 0 且 position > 0”确立之后才放行；
  /// 在 duration == 0 或 position == 0 时收到的任何 completed 事件视为旧流残留坚决丢弃。
  bool canPassCompleted(BackendEvent<bool> event) {
    if (_currentGenerationId == null || event.generationId != _currentGenerationId) {
      return false;
    }

    // 仅关注完播 true 信号
    if (!event.data) {
      return false;
    }

    // 必须确立时长与进度均大于 0
    if (_currentDuration <= Duration.zero || _currentPosition <= Duration.zero) {
      return false;
    }

    return true;
  }

  // ===========================================================================
  // 错误与诊断日志门禁：error & log
  // ===========================================================================

  /// 研判底层结构化错误 BackendError
  ///
  /// 核心门禁职责：
  /// 1. 时间窗口门禁：错误发生的相对耗时必须 >= Duration.zero；若提供 eventTime，必须晚于或等于 openTime；
  /// 2. 通用重定向放行：流媒体广泛采用 HTTP 301/302 重定向至 CDN 节点或网盘存储桶，
  ///    只要事件在当前代际 open 时间窗口内发生，底层致命错误一律放行进入状态机，绝不以初始 host/path 粗暴误杀。
  GatedErrorDisposition evaluateError(
    BackendError error, {
    DateTime? eventTime,
  }) {
    // 时间窗口门禁
    if (error.relativeTime < Duration.zero) {
      return GatedErrorDisposition.discard;
    }
    if (eventTime != null && _openTime != null && eventTime.isBefore(_openTime!)) {
      return GatedErrorDisposition.discard;
    }

    final host = error.host ?? _extractHostFromText(error.rawMessage);
    if (host == null || host.isEmpty) {
      // 不带主机名的底层日志，仅作诊断线索，不触发状态迁移 (TC-26)
      return GatedErrorDisposition.diagnosticOnly;
    }

    if (_targetUri == null) {
      return GatedErrorDisposition.discard;
    }

    final isTargetHost = host.toLowerCase() == _targetUri!.host.toLowerCase();
    final isRedirectHost = _redirectHosts.contains(host.toLowerCase());

    // 既不是目标主机，也不是当前代际已识别的重定向主机，坚决丢弃旧媒体残留 (TC-27, TC-29)
    if (!isTargetHost && !isRedirectHost) {
      return GatedErrorDisposition.discard;
    }

    // 端口比对（如果双方均有显式有效端口，且属于初始目标主机）
    if (isTargetHost && error.port != null && _targetUri!.hasPort) {
      if (error.port != _targetUri!.port) {
        return GatedErrorDisposition.discard;
      }
    }

    // 路径比对（若错误携带目标 cleanUrl，且属于初始目标主机，比对 URL 路径是否与当前代际一致）
    if (isTargetHost && error.cleanUrl != null && error.cleanUrl!.isNotEmpty) {
      final errorUri = Uri.tryParse(error.cleanUrl!);
      if (errorUri != null && errorUri.path.isNotEmpty && _targetUri!.path.isNotEmpty) {
        if (errorUri.path != _targetUri!.path) {
          return GatedErrorDisposition.discard;
        }
      }
    }

    return GatedErrorDisposition.passFatal;
  }

  /// 研判底层原生日志 PlayerLogMessage 并完成去重
  ///
  /// 遵循 04 第 4.1 节第 3 点规范：
  /// 1. 代际匹配与时间窗口校验；
  /// 2. stream.log 与 stream.error 10ms 容差内同文本去重；
  /// 3. 若日志中含有明确的主机名且与当前目标主机或已知重定向不一致，静默丢弃；
  /// 4. 其余正常通过，作为诊断线索。
  GatedLogDisposition evaluateLog(
    PlayerLogMessage log, {
    String? source,
  }) {
    // 代际校验
    if (_currentGenerationId != null && log.generationId != _currentGenerationId) {
      return GatedLogDisposition.discard;
    }

    // 时间窗口校验
    if (_openTime != null && log.timestamp.isBefore(_openTime!)) {
      return GatedLogDisposition.discard;
    }

    final trimmedText = log.text.trim();
    if (trimmedText.isEmpty) {
      return GatedLogDisposition.discard;
    }

    // 10ms 容差去重校验
    for (final entry in _recentLogs) {
      if (entry.text == trimmedText) {
        final diff = log.timestamp.difference(entry.timestamp).abs();
        if (diff <= _dedupTolerance) {
          // 命中去重规则，视为同一底层物理日志重复发射，丢弃
          return GatedLogDisposition.deduplicated;
        }
      }
    }

    // 记录入最近日志滑窗
    _recentLogs.add(_RecentLogEntry(
      text: trimmedText,
      timestamp: log.timestamp,
      source: source,
    ));
    if (_recentLogs.length > _maxRecentLogs) {
      _recentLogs.removeAt(0);
    }

    // 自动捕获当前会话抛出的 302 重定向失败或底层重定向目标主机
    if (trimmedText.startsWith('Failed to open')) {
      final failedHost = _extractHostFromText(trimmedText);
      if (failedHost != null && failedHost.isNotEmpty) {
        registerRedirectHost(failedHost);
      }
    }

    // 主机名归因校验
    final host = _extractHostFromText(trimmedText);
    if (host != null && host.isNotEmpty && _targetUri != null) {
      final isTargetHost = host.toLowerCase() == _targetUri!.host.toLowerCase();
      final isRedirectHost = _redirectHosts.contains(host.toLowerCase());
      if (!isTargetHost && !isRedirectHost) {
        // 主机名不匹配（如上个会话的后台 DNS 线程迟到日志），丢弃
        return GatedLogDisposition.discard;
      }
    }

    return GatedLogDisposition.passDiagnostic;
  }

  // ===========================================================================
  // 辅助正则提取工具
  // ===========================================================================

  static final RegExp _dnsHostRegex =
      RegExp(r'Failed to resolve hostname\s+([^\s:]+)', caseSensitive: false);
  static final RegExp _failedToOpenRegex =
      RegExp(r'Failed to open\s+(.+)$', caseSensitive: false);
  static final RegExp _urlRegex =
      RegExp(r'https?://([a-zA-Z0-9.-]+)(?::(\d+))?', caseSensitive: false);
  static final RegExp _hostPortRegex =
      RegExp(r'\b([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}):(\d+)\b');

  /// 从日志文本中智能提取可能携带的目标主机名
  static String? _extractHostFromText(String text) {
    // 1. Failed to resolve hostname <host>
    final dnsMatch = _dnsHostRegex.firstMatch(text);
    if (dnsMatch != null) {
      return dnsMatch.group(1);
    }

    // 2. Failed to open <url>
    final failedMatch = _failedToOpenRegex.firstMatch(text);
    if (failedMatch != null) {
      var raw = failedMatch.group(1)!.trim();
      while (raw.endsWith('.')) {
        raw = raw.substring(0, raw.length - 1);
      }
      final parsed = Uri.tryParse(raw);
      if (parsed != null && parsed.host.isNotEmpty) {
        return parsed.host;
      }
    }

    // 3. 通用 HTTP/HTTPS URL
    final urlMatch = _urlRegex.firstMatch(text);
    if (urlMatch != null) {
      return urlMatch.group(1);
    }

    // 4. host:port 格式
    final hostPortMatch = _hostPortRegex.firstMatch(text);
    if (hostPortMatch != null) {
      return hostPortMatch.group(1);
    }

    return null;
  }
}
