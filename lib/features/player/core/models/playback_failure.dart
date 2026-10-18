/// 播放层向选源层 / UI 层抛出的结构化失败事实与可用操作模型
///
/// 遵循 docs/player-rewrite/04-error-policy.md (v3.1) 与 docs/player-rewrite/05-interfaces-and-contracts.md (v3)
library;

import 'package:flutter/foundation.dart';
import 'backend_error.dart';

/// 用户与选源层可执行的恢复操作意图
enum PlaybackUserAction {
  /// 手动重试（允许穿透建议性负缓存）
  retry,

  /// 切换同源备用线路
  switchLine,

  /// 切换其他视频源
  switchSource,
}

/// 播放失败领域实体
@immutable
class PlaybackFailure {
  const PlaybackFailure({
    required this.kind,
    required this.action,
    required this.message,
    this.host,
    this.port,
    this.availableActions = const [
      PlaybackUserAction.retry,
      PlaybackUserAction.switchLine,
    ],
  });

  /// 归一化错误分类
  final BackendErrorKind kind;

  /// 底层建议的恢复动作
  final RecoveryAction action;

  /// 用户可读的清洗后错误文案
  final String message;

  /// 涉及的目标主机
  final String? host;

  /// 涉及的目标端口
  final int? port;

  /// 当前错误状态下允许用户或选源层执行的操作列表
  final List<PlaybackUserAction> availableActions;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PlaybackFailure &&
        other.kind == kind &&
        other.action == action &&
        other.message == message &&
        other.host == host &&
        other.port == port &&
        listEquals(other.availableActions, availableActions);
  }

  @override
  int get hashCode => Object.hash(
        kind,
        action,
        message,
        host,
        port,
        Object.hashAll(availableActions),
      );

  @override
  String toString() =>
      'PlaybackFailure(kind: $kind, action: $action, message: $message, host: $host:$port, actions: $availableActions)';
}
