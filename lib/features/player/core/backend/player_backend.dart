/// 播放器底层引擎抽象契约
///
/// 遵循 docs/player-rewrite/05-interfaces-and-contracts.md (v3)
///
/// 核心契约与代际分界规则（03 第六节与 08 事实 8）：
/// 1. 只有 playing / position / duration / buffer / buffering / width / height / videoParams 在每次 open 后的 6~7ms 内有底层同步发射的重置标记值；
/// 2. completed、stream.error、stream.log 三条流没有重置标记，必须依靠状态机门禁进行代际隔离（completed 需 duration > 0，error/log 需时间窗口与主机名归因）；
/// 3. generationId 由适配层在收到底层事件时统一打上，随事件向上派发。
library;

import '../models/backend_error.dart';
import 'backend_event.dart';

/// 底层音视频播放引擎核心抽象契约（最小集）
abstract class PlayerBackend {
  /// 初始化播放器底层引擎并配置原生属性参数
  ///
  /// 调用时机：在创建播放器实例后、第一次调用 [open] 之前显式调用。
  /// 若未显式调用，具体实现可在 [open] 时执行兜底初始化。
  Future<void> initialize({required bool isMeteredNetwork});

  /// 同步自增并分配新底层 open 的全局单调自增物理代际 [generationId]
  int beginOpen();

  /// 打开媒体流并起播
  ///
  /// 传入由 [beginOpen] 分配的物理代际 [generationId]。
  /// 耗时仅约 11~36ms（仅代表向底层 IPC 派发，不代表已建联）。
  Future<void> open(
    String uri, {
    Map<String, String>? headers,
    Duration? start,
    bool autoplay = true,
    required int generationId,
  });

  /// 恢复播放（底层保证幂等）
  Future<void> play();

  /// 暂停播放（底层保证幂等）
  Future<void> pause();

  /// 精准寻道
  Future<void> seek(Duration position);

  /// 释放播放器底层资源
  Future<void> dispose();

  /// 当前媒体包含的真实视频轨数量（已由适配层过滤排除 auto 与 no 等内置占位伪轨道）
  ///
  /// 状态机依据 `realVideoTrackCount == 0` 判断当前是否为纯音频媒体。
  /// 特殊标注：待验证：加载真实文件后 stream.tracks 的计数与时钟行为。
  int get realVideoTrackCount;

  // ==========================================
  // 底层带 generationId 与 isResetMarker 的状态广播流
  // ==========================================

  /// 播放状态变化广播流 (有重置标记: false)
  Stream<BackendEvent<bool>> get onPlayingChanged;

  /// 缓冲状态变化广播流 (有重置标记: false)
  Stream<BackendEvent<bool>> get onBufferingChanged;

  /// 播放位置推进广播流 (有重置标记: 0ms)
  Stream<BackendEvent<Duration>> get onPositionChanged;

  /// 视频总时长变化广播流 (有重置标记: 0ms)
  Stream<BackendEvent<Duration>> get onDurationChanged;

  /// 缓冲区水位变化广播流 (有重置标记: 0ms)
  Stream<BackendEvent<Duration>> get onBufferChanged;

  /// 画面物理尺寸变化广播流 (有重置标记: null)
  Stream<BackendEvent<VideoDimensions>> get onDimensionsChanged;

  /// 自然播放完成信号广播流
  ///
  /// 注意：该流无重置标记，状态机需通过 `duration > 0` 与时间容差门禁隔离旧流残余。
  Stream<BackendEvent<bool>> get onCompletedChanged;

  /// 结构化底层错误流（由适配层结合诊断日志研判产出）
  ///
  /// 注意：该流无重置标记，需依赖发生时间窗口与 URL/主机名归因隔离。
  Stream<BackendError> get onErrorOccurred;

  /// 原生全量日志广播流（供诊断与错误分类收集证据）
  ///
  /// 注意：该流无重置标记，需依赖发生时间窗口与 URL/主机名归因隔离。
  Stream<PlayerLogMessage> get onLog;
}
