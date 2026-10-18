/// 纯 Dart 播放器底层结构化错误与恢复动作领域模型
///
/// 遵循设计文档 docs/player-rewrite/04-error-policy.md (v3.1)
/// 严格保持纯 Dart 语义，严禁 import flutter 或 media_kit
library;

/// 恢复处理动作枚举
enum RecoveryAction {
  /// 静默忽略 (仅限首帧之后的良性底层日志)
  ignore,

  /// 原地退避重试 (用于偶发网络抖动)
  retryInPlace,

  /// 刷新直链后重试 (用于鉴权过期或未知打开失败)
  refreshAndRetry,

  /// 切换同源备用线路 (用于确定性节点不可达、握手关闭或建联超时)
  switchLine,

  /// 彻底放弃并进入致命错误态，呈现错误卡片等待用户干预
  fatalError,
}

/// 归一化错误核心分类
///
/// 特殊设计约束：
/// 1. 不包含 [decodeCorrupted]：因尚无真实物理夹具，在 v3.1 设计文档中标记为待验证；
/// 2. 不包含 benign 类别：良性重连日志依赖播放阶段由状态机消费，分类器不产生；
/// 3. [openDemuxWatchdog] 为仅预留项：由上层状态机根据建联状态计时触发，分类器不产生。
enum BackendErrorKind {
  /// 握手阶段对端主动关闭连接 (tcp 0xdfb9b0bb + tls -0x4e)
  handshakeClosed,

  /// 未知原因打开失败 (Failed to open，但前置无明确网络证据)
  openFailedUnknown,

  /// DNS 解析域名失败 (getaddrinfo / NXDOMAIN)
  dnsResolutionFailed,

  /// 连接超时 (不可路由 IP 或建联握手死锁)
  connectTimeout,

  /// 打开阶段解复用看门狗超时 (仅预留，分类器不产生，由状态机计时产生)
  openDemuxWatchdog,

  /// 兜底未分类异常
  unknown;

  /// 各错误分类的默认恢复动作映射
  RecoveryAction get defaultAction => switch (this) {
        BackendErrorKind.handshakeClosed ||
        BackendErrorKind.dnsResolutionFailed ||
        BackendErrorKind.connectTimeout =>
          RecoveryAction.switchLine,
        BackendErrorKind.openFailedUnknown => RecoveryAction.refreshAndRetry,
        BackendErrorKind.openDemuxWatchdog => RecoveryAction.switchLine,
        BackendErrorKind.unknown => RecoveryAction.fatalError,
      };
}

/// 播放器适配层与分类器产生的结构化错误
class BackendError {
  BackendError({
    required this.kind,
    RecoveryAction? action,
    required this.rawMessage,
    this.cleanUrl,
    this.host,
    this.port,
    this.nativeErrorCode,
    required this.relativeTime,
  }) : action = action ?? kind.defaultAction;

  /// 归一化错误分类
  final BackendErrorKind kind;

  /// 恢复动作
  final RecoveryAction action;

  /// 底层原始错误文本
  final String rawMessage;

  /// 清洗后的目标 URL（剥离查询参数 sign、t 等）
  final String? cleanUrl;

  /// 目标主机名
  final String? host;

  /// 目标端口
  final int? port;

  /// 原生底层物理错误码 (如 mbedtls_ssl_handshake 返回的 -0x4e)
  final int? nativeErrorCode;

  /// 错误发生时距离本次 open 的相对耗时
  final Duration relativeTime;

  /// 是否为可在后台由状态机尝试自愈的可恢复错误
  bool get isRecoverable => action != RecoveryAction.fatalError;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BackendError &&
        other.kind == kind &&
        other.action == action &&
        other.rawMessage == rawMessage &&
        other.cleanUrl == cleanUrl &&
        other.host == host &&
        other.port == port &&
        other.nativeErrorCode == nativeErrorCode &&
        other.relativeTime == relativeTime;
  }

  @override
  int get hashCode => Object.hash(
        kind,
        action,
        rawMessage,
        cleanUrl,
        host,
        port,
        nativeErrorCode,
        relativeTime,
      );

  @override
  String toString() =>
      'BackendError(kind: $kind, action: $action, host: $host:$port, nativeErrorCode: $nativeErrorCode, relativeTime: ${relativeTime.inMilliseconds}ms)';
}
