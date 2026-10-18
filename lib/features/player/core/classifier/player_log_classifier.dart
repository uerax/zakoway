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

  /// 本次 open 匹配到的 Failed to open 目标 URI
  Uri? get failedToOpenUri => _failedToOpenUri;

  // ===== 去重状态 (针对 stream.log 与 stream.error 重复发射) =====
  String? _lastSource;
  String? _lastText;
  Duration? _lastRelativeTime;

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
    // 2.1 EOF 证据：tcp: ffurl_read returned 0xdfb9b0bb
    if (text.contains('0xdfb9b0bb') || text.contains('ffurl_read returned')) {
      // 特殊处理说明：底层 TCP 错误日志行未输出主机名，分类器无法做 URL 归因校验，保留进入缓冲。
      // 此为已知残余风险，依据设计文档 v3.1 第 4.1 节，由“同时具备 EOF 与握手两类证据”
      // 及“建议性负缓存允许手动穿透”双重兜底，并在上层依靠 open 代际标记彻底隔离。
      _hasEofEvidence = true;
    }

    // 2.2 握手证据：tls: mbedtls_ssl_handshake returned -0x4e
    if (text.contains('mbedtls_ssl_handshake returned -0x4e')) {
      // 特殊处理说明：仅作为底层错误码 -0x4e 记录，严禁称作 RST 或连接重置。
      // 该日志行同样不包含主机名，作为已知残余风险保留入库。
      _hasHandshakeEvidence = true;
      _handshakeNativeErrorCode = -0x4e;
    }

    // 2.3 DNS 证据：Failed to resolve hostname <host>
    final dnsMatch = RegExp(r'Failed to resolve hostname\s+([^\s:]+)')
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

    // 2.4 Failed to open <url> 致命行
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

    // 隔离规则：URL 中的 sign、t 等可能被替换为 "..."，只比对 host:port 与路径（若有），不比较完整字符串
    // 若 host:port 不一致，忽略该事件
    final expectedPort = expectedUrl.hasPort
        ? expectedUrl.port
        : (expectedUrl.scheme == 'https' ? 443 : 80);
    final parsedPort =
        parsed.hasPort ? parsed.port : (parsed.scheme == 'https' ? 443 : 80);

    if (parsed.host.toLowerCase() != expectedUrl.host.toLowerCase() ||
        parsedPort != expectedPort) {
      // 主机或端口不匹配，忽略该 Failed to open 事件
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
    // 若既没有收到匹配的 Failed to open，也没有匹配的 DNS 失败行，尚未达到判定时机
    if (!_failedToOpenReceived && !_hasDnsFailure) {
      return null;
    }

    final effectiveRelativeTime = _failedToOpenRelativeTime ?? _dnsRelativeTime ?? now;
    final cleanUrl = _cleanUrl(expectedUrl);
    final port = expectedUrl.hasPort
        ? expectedUrl.port
        : (expectedUrl.scheme == 'https' ? 443 : 80);

    // 规则 1：缓冲里同时有 EOF 证据和握手证据 -> handshakeClosed
    if (_hasEofEvidence && _hasHandshakeEvidence) {
      return BackendError(
        kind: BackendErrorKind.handshakeClosed,
        action: RecoveryAction.switchLine,
        rawMessage: _failedToOpenRawMessage ?? 'Handshake closed by peer',
        cleanUrl: cleanUrl,
        host: expectedUrl.host,
        port: port,
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
        host: _dnsHost ?? expectedUrl.host,
        port: port,
        nativeErrorCode: null,
        relativeTime: _dnsRelativeTime ?? effectiveRelativeTime,
      );
    }

    // 规则 3：耗时达到或超过连接超时阈值 -> connectTimeout
    // 特殊处理说明：对应设计文档 v3.1 第 5.3 节，此为分类器层面的事后定性；
    // 状态机层面的 12s 看门狗负责主动救场，而底层若在 16.5s 抛出打开失败，分类器精准定性为 connectTimeout
    if (effectiveRelativeTime >= connectTimeoutThreshold) {
      return BackendError(
        kind: BackendErrorKind.connectTimeout,
        action: RecoveryAction.switchLine,
        rawMessage: _failedToOpenRawMessage ?? 'Connect timeout',
        cleanUrl: cleanUrl,
        host: expectedUrl.host,
        port: port,
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
      host: expectedUrl.host,
      port: port,
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

    _lastSource = null;
    _lastText = null;
    _lastRelativeTime = null;
  }

  /// 剥离查询参数（如 sign、t 等），保留干净的协议、主机、端口和路径
  String _cleanUrl(Uri uri) {
    final cleanUri = uri.replace(queryParameters: {}, fragment: '');
    final str = cleanUri.toString();
    final qIndex = str.indexOf('?');
    return qIndex >= 0 ? str.substring(0, qIndex) : str;
  }
}
