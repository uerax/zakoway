/// 纯 Dart 原生日志有状态分类器
///
/// 遵循设计文档 docs/player-rewrite/04-error-policy.md (v3.1)
/// 严格保持纯 Dart 语义，严禁 import flutter 或 media_kit
library;

import '../models/backend_error.dart';

/// 识别首帧之后的良性底层重连关键字（纯函数，不区分大小写）
///
/// 仅供后续状态机在首帧渲染之后用于忽略底层重连日志，分类器本身不基于此产生 benign 错误
bool isBenignReconnectLine(String text) {
  final lower = text.toLowerCase();
  return lower.contains('0xdfb9b0bb') ||
      lower.contains('ffurl_read returned') ||
      lower.contains('end of file') ||
      lower.contains('connection reset by peer');
}

/// 针对单次 open 收集诊断证据的有状态日志分类器
class PlayerLogClassifier {
  PlayerLogClassifier({
    required this.expectedUrl,
    this.connectTimeoutThreshold = const Duration(seconds: 12),
  });

  /// 本次 open 正在拉取的目标媒体 URL
  final Uri expectedUrl;

  /// 连接超时判定阈值（默认 12 秒，与设计文档 v3.1 中的状态机看门狗超时时间对齐）
  final Duration connectTimeoutThreshold;

  // ===== 证据缓冲状态 (Evidence Buffer) =====
  bool _hasEofEvidence = false;
  bool _hasHandshakeEvidence = false;
  int? _handshakeNativeErrorCode;

  bool _hasDnsFailure = false;
  String? _dnsHost;
  String? _dnsRawMessage;
  Duration? _dnsRelativeTime;

  bool _failedToOpenReceived = false;
  String? _failedToOpenRawMessage;
  Uri? _failedToOpenUri;
  Duration? _failedToOpenRelativeTime;

  final Set<String> _redirectHosts = {};

  /// 本次 open 匹配到的 Failed to open 目标 URI
  Uri? get failedToOpenUri => _failedToOpenUri;

  // ===== 去重状态 (针对 stream.log 与 stream.error 重复发射) =====
  String? _lastSource;
  String? _lastText;
  Duration? _lastRelativeTime;
  bool _errorEmitted = false;

  /// 接收单条底层日志事件并提取证据
  void onLogReceived({
    required String source,
    required String level,
    required String prefix,
    required String text,
    required Duration relativeTime,
  }) {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) return;

    // 1. 去重规则：
    // stream.log 与 stream.error 会向 Dart 广播同一底层物理错误（时间戳相同，文本相同）
    // 依据实测夹具 scenario_1_handshake_closed_al_prod.txt 第 30、31 行，相对时间存在 1ms 测量微差
    // 若不同 source、文本相同且时间差在 10ms 容差内，视为重复日志，只计 1 次证据
    if (_lastSource != null &&
        _lastSource != source &&
        _lastText == trimmedText &&
        _lastRelativeTime != null &&
        (relativeTime - _lastRelativeTime!).abs() <=
            const Duration(milliseconds: 10)) {
      return;
    }

    _lastSource = source;
    _lastText = trimmedText;
    _lastRelativeTime = relativeTime;

    // 2. 证据提取与隔离校验
    _extractEvidence(
      source: source,
      level: level,
      prefix: prefix,
      text: trimmedText,
      relativeTime: relativeTime,
    );
  }

  /// 提取底层关键错误证据
  void _extractEvidence({
    required String source,
    required String level,
    required String prefix,
    required String text,
    required Duration relativeTime,
  }) {
    final lower = text.toLowerCase();

    // 2.1 网络断开/EOF 证据
    if (lower.contains('0xdfb9b0bb') ||
        lower.contains('ffurl_read returned') ||
        lower.contains('connection reset') ||
        lower.contains('connection closed') ||
        lower.contains('end of file') ||
        lower.contains('broken pipe')) {
      _hasEofEvidence = true;
    }

    // 2.2 TLS / 握手异常证据
    if (lower.contains('handshake') ||
        lower.contains('ssl') ||
        lower.contains('tls') ||
        lower.contains('schannel') ||
        lower.contains('certificate') ||
        lower.contains('terminated during handshake')) {
      _hasHandshakeEvidence = true;
      if (text.contains('-0x4e')) {
        _handshakeNativeErrorCode = -0x4e;
      }
    }

    // 2.3 捕获底层 HTTP 302 重定向目标
    final redirectMatch = RegExp(
      r'(?:Redirecting to|Location:)\s+(https?://[^\s]+)',
      caseSensitive: false,
    ).firstMatch(text);
    if (redirectMatch != null) {
      final u = Uri.tryParse(redirectMatch.group(1)!);
      if (u != null && u.host.isNotEmpty) {
        _redirectHosts.add(u.host.toLowerCase());
      }
    }

    // 2.4 DNS 证据：Failed to resolve hostname <host>
    final dnsMatch = RegExp(r'Failed to resolve hostname\s+([^\s:]+)', caseSensitive: false)
        .firstMatch(text);
    if (dnsMatch != null) {
      final host = dnsMatch.group(1)!;
      // 隔离规则：若提取的主机名与 expectedUrl 主机名不一致，坚决丢弃，防止旧连接迟到日志污染
      if (host.toLowerCase() == expectedUrl.host.toLowerCase()) {
        _hasDnsFailure = true;
        _dnsHost = host;
        _dnsRawMessage = text;
        _dnsRelativeTime = relativeTime;
      }
      return;
    }

    // 2.5 Failed to open <url> 致命行
    if (text.startsWith('Failed to open')) {
      _handleFailedToOpen(text, relativeTime);
    }
  }

  /// 处理 `Failed to open <url>.` 行
  void _handleFailedToOpen(String text, Duration relativeTime) {
    // 提取 URL 字符串，剥离可能包裹的空白和末尾的英文句号 '.'
    final match = RegExp(r'Failed to open\s+(.+)$').firstMatch(text);
    if (match == null) return;

    var rawUrl = match.group(1)!.trim();
    while (rawUrl.endsWith('.')) {
      rawUrl = rawUrl.substring(0, rawUrl.length - 1);
    }

    final parsed = Uri.tryParse(rawUrl);
    if (parsed == null) return;

    final expectedPort = expectedUrl.hasPort
        ? expectedUrl.port
        : (expectedUrl.scheme == 'https' ? 443 : 80);
    final parsedPort =
        parsed.hasPort ? parsed.port : (parsed.scheme == 'https' ? 443 : 80);

    final isExpectedHost =
        parsed.host.toLowerCase() == expectedUrl.host.toLowerCase() &&
            parsedPort == expectedPort;
    final isRedirectHost = _redirectHosts.contains(parsed.host.toLowerCase());

    // 若既非预期目标主机/端口，亦非已确认的重定向目标主机，视为旧连接残留忽略
    if (!isExpectedHost && !isRedirectHost) {
      return;
    }

    _failedToOpenReceived = true;
    _failedToOpenRawMessage = text;
    _failedToOpenUri = parsed;
    _failedToOpenRelativeTime = relativeTime;
  }

  /// 执行错误分类判定
  ///
  /// 触发时机：
  /// 1. `Failed to open <url>` 致命行到达；
  /// 2. 匹配当前主机的 DNS 失败致命行到达；
  /// 3. 若均未到达（如慢起播正常出画、或单纯 demux seek 失败），返回 null。
  BackendError? evaluate(Duration now) {
    // 保证单次 open 只产出一个错误，杜绝 stream.log 与 stream.error 重复发射导致的多重错误产出
    if (_errorEmitted) {
      return null;
    }

    // 若既没有收到匹配的 Failed to open，也没有匹配的 DNS 失败行，尚未达到判定时机
    if (!_failedToOpenReceived && !_hasDnsFailure) {
      return null;
    }

    _errorEmitted = true;

    final effectiveRelativeTime = _failedToOpenRelativeTime ?? _dnsRelativeTime ?? now;
    final effectiveHost = _failedToOpenUri?.host.isNotEmpty == true
        ? _failedToOpenUri!.host
        : expectedUrl.host;
    final effectivePort = _failedToOpenUri?.hasPort == true
        ? _failedToOpenUri!.port
        : (expectedUrl.hasPort
            ? expectedUrl.port
            : (expectedUrl.scheme == 'https' ? 443 : 80));
    final cleanUrl = _cleanUrl(_failedToOpenUri ?? expectedUrl);

    // 规则 1：缓冲里有握手异常证据，或同时有 EOF 与握手证据 -> handshakeClosed
    if (_hasHandshakeEvidence || (_hasEofEvidence && _hasHandshakeEvidence)) {
      return BackendError(
        kind: BackendErrorKind.handshakeClosed,
        action: RecoveryAction.switchLine,
        rawMessage: _failedToOpenRawMessage ?? 'TLS handshake failed or closed by peer',
        cleanUrl: cleanUrl,
        host: effectiveHost,
        port: effectivePort,
        nativeErrorCode: _handshakeNativeErrorCode ?? -0x4e,
        relativeTime: effectiveRelativeTime,
      );
    }

    // 规则 2：有主机名匹配的 DNS 证据 -> dnsResolutionFailed
    if (_hasDnsFailure) {
      return BackendError(
        kind: BackendErrorKind.dnsResolutionFailed,
        action: RecoveryAction.switchLine,
        rawMessage: _dnsRawMessage ?? 'DNS resolution failed',
        cleanUrl: cleanUrl,
        host: _dnsHost ?? effectiveHost,
        port: effectivePort,
        nativeErrorCode: null,
        relativeTime: _dnsRelativeTime ?? effectiveRelativeTime,
      );
    }

    // 规则 3：耗时达到或超过连接超时阈值 -> connectTimeout
    if (effectiveRelativeTime >= connectTimeoutThreshold) {
      return BackendError(
        kind: BackendErrorKind.connectTimeout,
        action: RecoveryAction.switchLine,
        rawMessage: _failedToOpenRawMessage ?? 'Connect timeout',
        cleanUrl: cleanUrl,
        host: effectiveHost,
        port: effectivePort,
        nativeErrorCode: null,
        relativeTime: effectiveRelativeTime,
      );
    }

    // 规则 4：前置无明确网络证据的打开失败 -> openFailedUnknown
    return BackendError(
      kind: BackendErrorKind.openFailedUnknown,
      action: RecoveryAction.refreshAndRetry,
      rawMessage: _failedToOpenRawMessage ?? 'Failed to open media',
      cleanUrl: cleanUrl,
      host: effectiveHost,
      port: effectivePort,
      nativeErrorCode: null,
      relativeTime: effectiveRelativeTime,
    );
  }

  /// 清空证据库与触发标记
  void reset() {
    _hasEofEvidence = false;
    _hasHandshakeEvidence = false;
    _handshakeNativeErrorCode = null;

    _hasDnsFailure = false;
    _dnsHost = null;
    _dnsRawMessage = null;
    _dnsRelativeTime = null;

    _failedToOpenReceived = false;
    _failedToOpenRawMessage = null;
    _failedToOpenUri = null;
    _failedToOpenRelativeTime = null;
    _redirectHosts.clear();

    _lastSource = null;
    _lastText = null;
    _lastRelativeTime = null;
    _errorEmitted = false;
  }

  /// 剥离查询参数（如 sign、t 等），保留干净的协议、主机、端口和路径
  String _cleanUrl(Uri uri) {
    final cleanUri = uri.replace(queryParameters: {}, fragment: '');
    final str = cleanUri.toString();
    final qIndex = str.indexOf('?');
    return qIndex >= 0 ? str.substring(0, qIndex) : str;
  }
}
