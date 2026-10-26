import 'dart:async';
import 'package:flutter/foundation.dart';
import 'models/source_models.dart';
import 'source_aggregator.dart';

enum AutoPickAction {
  none,
  immediate,
  waitGrace,
}

class AutoSourcePickDecision {
  final AutoPickAction action;
  final AggregatedSourceState? candidate;
  final List<String> higherPriorityInFlight;

  const AutoSourcePickDecision({
    required this.action,
    this.candidate,
    this.higherPriorityInFlight = const [],
  });
}

/// 自适应宽限自动选源仲裁器 (1:1 严格对齐 animaku use-auto-source-pick.ts)
///
/// 核心裁决策略：
/// 1. 默认源搜索失败时启动自动保底探测；
/// 2. 0ms 秒提 (Immediate): 当就绪源是当前优先级最高的源（即队列中无更高优先级源在探测），直接起播；
/// 3. 自适应宽限 (Wait Grace): 当较低优先级的源先探测完成，而更高优先级的源仍在探测/排队中，
///    启动 1200ms 宽限窗口。若高优先级源在 1200ms 内就绪，优先采用高优先级源；若超时或失败，则降级采用已就绪源；
/// 4. 用户操作互斥锁 (User Locked): 用户一旦在 UI 上点击了任何源卡片或自定义了关键词，立即永久作废自动选源，由用户完全主导；
/// 5. 保底全灭感知: 若探测配额内的保底源全军覆没，自动触发回调通知 UI 展开面板。
class AutoSourcePickCoordinator {
  AutoSourcePickCoordinator({
    required this.onSwitchSource,
    this.onAllFallbacksFailed,
    this.gracePeriodMs = 1200,
    this.waitHigherPriority = false,
  });

  final void Function(SourceMeta meta, SourceSearchResult hit) onSwitchSource;
  final VoidCallback? onAllFallbacksFailed;
  final int gracePeriodMs;
  final bool waitHigherPriority;

  int _currentBangumiId = 0;
  bool _userLocked = false;
  bool _autoPicked = false;
  bool _allFallbacksTriggered = false;
  Timer? _graceTimer;
  String? _pendingCandidateId;

  String? get pendingCandidateId => _pendingCandidateId;
  bool get isUserLocked => _userLocked;

  /// 计算指定源在优先级列表中的权重位序
  static int getPluginRank(String sourceId, List<String> sourceOrder) {
    final idx = sourceOrder.indexWhere((n) => n.toLowerCase() == sourceId.toLowerCase());
    return idx >= 0 ? idx : sourceOrder.length + 999;
  }

  /// 纯函数裁决逻辑 (支持方案 A 极速起播与可选自适应宽限)
  static AutoSourcePickDecision resolveDecision({
    required Map<String, AggregatedSourceState> sources,
    required List<String> inFlightSources,
    required List<String> sourceOrder,
    bool waitHigherPriority = false,
  }) {
    final readyCandidates = sources.values
        .where((s) => s.status == SourceProbeStatus.ready && s.matchedHit != null)
        .toList();

    if (readyCandidates.isEmpty) {
      return const AutoSourcePickDecision(action: AutoPickAction.none);
    }

    // 按用户配置优先级从高到低排序，位列第 1 的为当前就绪最优源
    readyCandidates.sort((a, b) {
      final rankA = getPluginRank(a.meta.id, sourceOrder);
      final rankB = getPluginRank(b.meta.id, sourceOrder);
      if (rankA != rankB) return rankA.compareTo(rankB);
      return a.meta.name.compareTo(b.meta.name);
    });

    final bestCandidate = readyCandidates.first;

    // 方案 A: 极速起播策略（默认），一旦有任何候选源就绪立即采纳，不等待更高顺位慢源
    if (!waitHigherPriority) {
      return AutoSourcePickDecision(
        action: AutoPickAction.immediate,
        candidate: bestCandidate,
      );
    }

    // 宽限模式：检查在正在探测/排队的源中是否有优先级高于 bestCandidate 的源
    final bestRank = getPluginRank(bestCandidate.meta.id, sourceOrder);
    final higherPriorityInFlight = inFlightSources.where((name) {
      if (name.toLowerCase() == bestCandidate.meta.id.toLowerCase()) return false;
      return getPluginRank(name, sourceOrder) < bestRank;
    }).toList();

    if (higherPriorityInFlight.isEmpty) {
      return AutoSourcePickDecision(
        action: AutoPickAction.immediate,
        candidate: bestCandidate,
      );
    }

    return AutoSourcePickDecision(
      action: AutoPickAction.waitGrace,
      candidate: bestCandidate,
      higherPriorityInFlight: higherPriorityInFlight,
    );
  }

  /// 切换番剧时重置内部状态机
  void resetSubject(int bangumiId) {
    _currentBangumiId = bangumiId;
    _userLocked = false;
    _autoPicked = false;
    _allFallbacksTriggered = false;
    _clearGraceTimer();
    _pendingCandidateId = null;
  }

  /// 用户操作互斥锁：用户点击任意源、点击选集、换词时立即调用
  void onUserAction() {
    _userLocked = true;
    _clearGraceTimer();
    _pendingCandidateId = null;
  }

  /// 驱动自动选源决议
  void update({
    required int bangumiId,
    required bool enabled,
    required Map<String, AggregatedSourceState> sources,
    required List<String> inFlightSources,
    required List<String> sourceOrder,
    required bool allFallbacksExhausted,
  }) {
    if (_currentBangumiId != bangumiId) {
      resetSubject(bangumiId);
    }

    // 未开启或已被用户加锁或已经自动选过源，直接退出
    if (!enabled || _userLocked || _autoPicked) {
      _clearGraceTimer();
      _pendingCandidateId = null;
      return;
    }

    final decision = resolveDecision(
      sources: sources,
      inFlightSources: inFlightSources,
      sourceOrder: sourceOrder,
      waitHigherPriority: waitHigherPriority,
    );

    if (decision.action == AutoPickAction.none) {
      _clearGraceTimer();
      _pendingCandidateId = null;
      // 所有保底源均已探测完毕（全灭），单次触发失败回调
      if (allFallbacksExhausted &&
          !_autoPicked &&
          !_userLocked &&
          !_allFallbacksTriggered) {
        _allFallbacksTriggered = true;
        onAllFallbacksFailed?.call();
      }
      return;
    }

    final candidate = decision.candidate!;

    // Case 1: 0ms 秒提 (无更高优先级源在排队)
    if (decision.action == AutoPickAction.immediate) {
      _clearGraceTimer();
      _pendingCandidateId = null;
      _autoPicked = true;
      onSwitchSource(candidate.meta, candidate.matchedHit!);
      return;
    }

    // Case 2: 存在更高优先级源在探测，进入 1200ms 自适应宽限
    _pendingCandidateId = candidate.meta.id;

    _graceTimer ??= Timer(Duration(milliseconds: gracePeriodMs), () {
      if (_userLocked || _autoPicked) return;
      _autoPicked = true;
      _clearGraceTimer();
      _pendingCandidateId = null;
      onSwitchSource(candidate.meta, candidate.matchedHit!);
    });
  }

  void _clearGraceTimer() {
    _graceTimer?.cancel();
    _graceTimer = null;
  }

  void dispose() {
    _clearGraceTimer();
  }
}
