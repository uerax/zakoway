library;

import 'dart:async';

/// 底层 mpv 命令执行函数签名（与具体播放内核解耦，保持纯 Dart 可测试性）
typedef MpvCommandRunner = Future<void> Function(List<String> command);

/// Anime4K 着色器注入串行互斥队列与超时熔断管理器
///
/// 遵循 docs/player-rewrite/09-adapter-plan.md 第五节规范：
/// 1. 串行互斥：同一时刻仅允许一个着色器编译/注入任务在底层显卡线程运行；
/// 2. 合并最新：执行期间到达的连续请求自动合并暂存，完成后直接应用最新目标着色器链；
/// 3. 超时熔断：设置着色器链提供 4 秒硬超时，清空着色器提供 3 秒硬超时，杜绝 D3D/ANGLE 挂起死锁。
class ShaderQueueManager {
  ShaderQueueManager({
    this.setShaderTimeout = const Duration(seconds: 4),
    this.clearShaderTimeout = const Duration(seconds: 3),
  });

  /// 注入着色器链的硬超时阈值 (默认 4 秒)
  final Duration setShaderTimeout;

  /// 清空着色器链的硬超时阈值 (默认 3 秒)
  final Duration clearShaderTimeout;

  bool _isApplying = false;
  List<String>? _pendingShaderPaths;

  /// 当前是否正在执行底层着色器应用
  bool get isApplying => _isApplying;

  /// 排队等待应用的最新着色器路径列表
  List<String>? get pendingShaderPaths => _pendingShaderPaths;

  /// 应用着色器路径列表（为空列表表示清空滤镜）
  Future<void> apply(
    MpvCommandRunner commandRunner,
    List<String> shaderPaths,
  ) async {
    _pendingShaderPaths = List<String>.unmodifiable(shaderPaths);
    if (_isApplying) return;
    _isApplying = true;

    try {
      while (_pendingShaderPaths != null) {
        final current = _pendingShaderPaths!;
        _pendingShaderPaths = null;

        if (current.isEmpty) {
          // 清空着色器（3 秒熔断）
          await commandRunner(const [
            'change-list',
            'glsl-shaders',
            'clr',
            '',
          ]).timeout(clearShaderTimeout);
        } else {
          // 设置着色器链（4 秒熔断）
          final shaderString = current.join(';');
          await commandRunner([
            'change-list',
            'glsl-shaders',
            'set',
            shaderString,
          ]).timeout(setShaderTimeout);
        }
      }
    } catch (_) {
      // 捕获超时或编译异常，杜绝挂起，保证管线不崩溃
    } finally {
      _isApplying = false;
      if (_pendingShaderPaths != null) {
        unawaited(apply(commandRunner, _pendingShaderPaths!));
      }
    }
  }

  /// 释放与重置
  void reset() {
    _isApplying = false;
    _pendingShaderPaths = null;
  }
}
