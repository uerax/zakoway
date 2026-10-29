import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:zakoway/core/models/bangumi/bangumi_item.dart';
import 'models/source_models.dart';
import 'services/plugin_circuit_breaker.dart';
import 'services/source_binding_service.dart';
import 'services/source_order_service.dart';
import 'source_bundle_manager.dart';
import 'source_keyword_matcher.dart';

/// 视频源探测状态 (1:1 严格对齐 animaku SourceProbeStatus)
enum SourceProbeStatus {
  /// 待探活 (灰色)
  idle,

  /// 探活中 (蓝色旋转)
  probing,

  /// 已就绪 (绿色，相似度 >= 0.55，存在高置信度命中项且分集验证有效)
  ready,

  /// 需点选 (黄色，搜到多条候选但最高相似度 < 0.55，避免错选)
  needsPick,

  /// 未收录 (灰色，搜索结果为空或无可用分集)
  empty,

  /// 异常/超时 (红色，源站响应异常或 5s 超时)
  error,
}

/// 聚合探测源状态模型 (1:1 严格对齐 animaku AggregatedSourceState)
class AggregatedSourceState {
  final SourceMeta meta;
  final SourceProbeStatus status;
  final SourceBindingEntry? binding;
  final List<SourceSearchResult> items;
  final SourceSearchResult? matchedHit;
  final List<SourceChapterRoad> roads;
  final String? errorMsg;
  final bool searched;
  final String? keyword;

  const AggregatedSourceState({
    required this.meta,
    this.status = SourceProbeStatus.idle,
    this.binding,
    this.items = const [],
    this.matchedHit,
    this.roads = const [],
    this.errorMsg,
    this.searched = false,
    this.keyword,
  });

  AggregatedSourceState copyWith({
    SourceProbeStatus? status,
    SourceBindingEntry? binding,
    List<SourceSearchResult>? items,
    SourceSearchResult? matchedHit,
    List<SourceChapterRoad>? roads,
    String? errorMsg,
    bool? searched,
    String? keyword,
  }) {
    return AggregatedSourceState(
      meta: meta,
      status: status ?? this.status,
      binding: binding ?? this.binding,
      items: items ?? this.items,
      matchedHit: matchedHit ?? this.matchedHit,
      roads: roads ?? this.roads,
      errorMsg: errorMsg ?? this.errorMsg,
      searched: searched ?? this.searched,
      keyword: keyword ?? this.keyword,
    );
  }
}

/// 高性能视频源并发探测中枢与调度引擎
///
/// 核心规范与调度策略：
/// 1. 并发上限控制: concurrencyLimit = 5 (严格限制后台与并发探测槽位)
/// 2. 单源探活超时: probeTimeoutMs = 5000 (CancelToken + Future.timeout 双重熔断)
/// 3. 极速响应流: 任何一个源探活状态变更立即触发 notifyListeners，按钮秒级响应变色
/// 4. 排序首位优先决议，失败秒级竞速接管: 排序第一的源优先采纳起播；若第一位失败，已就绪的次选竞速源 0ms 瞬间接管起播
/// 5. 抢占式调度与用户互斥: 用户手动点选或换词时锁定为用户意图，废弃自动胜出
/// 6. 单飞熔断联动: 异常/超时接入 PluginCircuitBreaker，防止坏源反复卡死界面
class SourceAggregator extends ChangeNotifier {
  static const int concurrencyLimit = 5;
  static const int probeTimeoutMs = 5000;
  static const double autoPickMinSimilarity = 0.55;

  final Map<String, AggregatedSourceState> _states = {};
  final List<String> _queue = [];
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, Timer> _timeoutTimers = {};
  final Map<String, int> _probeActionIds = {};
  final Set<String> _probeDone = {};
  final Set<String> _activeAutoJobs = {};
  final Set<String> _userActionSources = {};
  final Map<String, String> _customKeywords = {};
  int _activeJobs = 0;
  bool _disposed = false;

  int _currentBangumiId = 0;
  int _sessionToken = 0;
  bool _userLocked = false;
  String? _winnerSourceId;

  String _defaultTitle = '';
  BangumiItem? _bangumiItem;
  List<String> _titleRefs = const [];

  Map<String, AggregatedSourceState> get states => Map.unmodifiable(_states);
  List<AggregatedSourceState> get items => _states.values.toList();
  int get activeJobsCount => _activeJobs;
  bool get isUserLocked => _userLocked;
  String? get winnerSourceId => _winnerSourceId;

  /// 更新指定源的探测状态并通知外部视图更新
  void updateSourceState(String sourceId, AggregatedSourceState state) {
    _states[sourceId] = state;
    notifyListeners();
  }

  @visibleForTesting
  void setSourceStateForTest(String sourceId, AggregatedSourceState state) {
    updateSourceState(sourceId, state);
  }

  /// 获取当前所有正在探测中或排队中的源列表
  List<String> get inFlightSources {
    final set = <String>{};
    for (final e in _states.entries) {
      if (e.value.status == SourceProbeStatus.probing) {
        set.add(e.key);
      }
    }
    set.addAll(_queue);
    return set.toList();
  }

  /// 是否存在探测任务正在执行 (供选源面板顶部转圈与状态指示)
  bool get isAutoProbing =>
      _activeJobs > 0 ||
      _queue.isNotEmpty ||
      _states.values.any((s) => s.status == SourceProbeStatus.probing);

  /// 初始化/同步当前播放番剧上下文信息 (供用户探活与换词使用)
  void initContext({
    required int bangumiId,
    required String defaultTitle,
    BangumiItem? item,
    List<String> titleRefs = const [],
  }) {
    if (_currentBangumiId != bangumiId) {
      resetSubject(bangumiId);
    }
    _defaultTitle = defaultTitle;
    _bangumiItem = item;
    _titleRefs = titleRefs.isNotEmpty
        ? titleRefs
        : [
            if (item?.nameCn.isNotEmpty ?? false) item!.nameCn,
            if (item?.name.isNotEmpty ?? false) item!.name,
            defaultTitle,
            ...(item?.alias ?? const <String>[]),
          ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  /// 当番剧 ID 变更时彻底重置所有状态与进行中任务
  void resetSubject(int bangumiId) {
    _cancelAll();
    _currentBangumiId = bangumiId;
    _activeJobs = 0;
    _queue.clear();
    _cancelTokens.clear();
    _timeoutTimers.clear();
    _probeActionIds.clear();
    _probeDone.clear();
    _activeAutoJobs.clear();
    _customKeywords.clear();
    _states.clear();
    _userLocked = false;
    _winnerSourceId = null;

    // 初始化所有可用源为待探活状态
    final allSources = SourceBundleManager.instance.sources;
    for (final s in allSources) {
      _states[s.id] = AggregatedSourceState(
        meta: s,
        status: SourceProbeStatus.idle,
        searched: false,
      );
    }
    notifyListeners();
  }

  /// 用户操作互斥锁：用户手动点击任意源卡片、分集或换词时调用，
  /// 锁定当前意图，杜绝后续后台完成的源自动覆盖用户正在查看或播放的内容
  void lockByUserAction() {
    _userLocked = true;
  }

  /// 统一核心入口：启动 Top-N 并发探活流水线 (高内聚闭环)
  ///
  /// 核心机制：
  /// 1. 初始化并对齐番剧上下文，重置上一个会话的状态与定时器；
  /// 2. 优先检查首选源 (preferredSourceId) 是否有真实有效的历史持久化绑定，若有 0ms 秒开胜出；
  /// 3. 并发派发前 5 个优选源的探活请求 (严格 5s 超时熔断与单飞保护)；
  /// 4. 任意单源完成探活立即更新状态并派发 notifyListeners，UI 按钮秒级响应变色；
  /// 5. 首个 Ready 的源若未被用户锁定，立即通过 onWinnerReady 回调起播；
  /// 6. 前 5 个源全部探测完毕若无一可用，通过 onAllFailed 统一通知。
  Future<void> startSession({
    required int bangumiId,
    required String defaultTitle,
    BangumiItem? item,
    List<String> titleRefs = const [],
    String? preferredSourceId,
    int maxProbeCount = 5,
    void Function(SourceMeta winnerSource, List<SourceChapterRoad> winnerRoads, SourceSearchResult winnerHit)? onWinnerReady,
    VoidCallback? onAllFailed,
  }) async {
    final currentSession = ++_sessionToken;
    _userLocked = false;
    _winnerSourceId = null;

    initContext(
      bangumiId: bangumiId,
      defaultTitle: defaultTitle,
      item: item,
      titleRefs: titleRefs,
    );

    await SourceBundleManager.instance.initialize();
    await SourceOrderService.instance.initialize();
    if (_disposed || _sessionToken != currentSession) return;

    final allRawSources = SourceBundleManager.instance.sources;
    final targetSources = SourceOrderService.instance.getTopSources(
      allRawSources,
      maxCount: maxProbeCount,
      preferredSourceId: preferredSourceId,
    );

    if (targetSources.isEmpty) {
      onAllFailed?.call();
      return;
    }

    final runtime = SourceBundleManager.instance.runtime;

    // 1. 优先检查首选源历史持久化绑定 (0ms 秒开)
    final topPreferredId = preferredSourceId ?? targetSources.first.id;
    final binding = SourceBindingService.instance.getBinding(bangumiId, topPreferredId);
    if (binding != null && binding.sourceUrl.isNotEmpty) {
      try {
        final boundRoads = await runtime
            .chapters(topPreferredId, binding.sourceUrl)
            .timeout(const Duration(milliseconds: probeTimeoutMs));
        if (boundRoads.isNotEmpty && boundRoads.any((r) => r.episodes.isNotEmpty)) {
          if (_disposed || _sessionToken != currentSession) return;

          final hit = SourceSearchResult(name: binding.title, url: binding.sourceUrl);
          final meta = targetSources.where((s) => s.id == topPreferredId).firstOrNull ??
              runtime.getSource(topPreferredId)?.toMeta() ??
              SourceMeta(id: topPreferredId, name: topPreferredId, version: '1.0');

          _states[topPreferredId] = AggregatedSourceState(
            meta: meta,
            status: SourceProbeStatus.ready,
            binding: binding,
            items: [hit],
            matchedHit: hit,
            roads: boundRoads,
            searched: true,
            keyword: binding.title,
          );
          _winnerSourceId = topPreferredId;
          notifyListeners();

          onWinnerReady?.call(meta, boundRoads, hit);

          // 首选源秒开后，后台继续平滑将剩余源探测完（填充看板按钮状态）
          for (final target in targetSources) {
            if (target.id != topPreferredId) {
              _queue.add(target.id);
            }
          }
          _processQueue();
          return;
        }
      } catch (_) {
        await SourceBindingService.instance.removeBinding(bangumiId, topPreferredId);
      }
    }

    if (_disposed || _sessionToken != currentSession) return;

    // 2. 5 源并发竞速探测
    // 立即将目标源置为 probing，让 UI 按钮第一时间显示“探活中”旋转动效
    for (final target in targetSources) {
      _states[target.id] = AggregatedSourceState(
        meta: target,
        status: SourceProbeStatus.probing,
        searched: true,
        keyword: SourceKeywordMatcher.resolveDefaultKeyword(
          defaultTitle: defaultTitle,
          item: item,
          sourceId: target.id,
        ),
      );
    }
    notifyListeners();

    int completedCount = 0;
    final totalTargets = targetSources.length;
    final primaryTarget = targetSources.first;
    final primaryId = primaryTarget.id;
    bool primaryFailed = false;

    // 特殊处理说明：
    // 当排序第一的主选源 (Top 1) 尚未决议时，其余并发源若先跑完且 Ready，
    // 绝不能立即“抢跑篡位”胜出起播，而是暂存为 standbyWinner 备用。
    // 只有在主选源确认失败 (empty/error/needsPick 或超时) 时，才秒级激活备用源接管起播，
    // 从而严格保障“排序第一优先起播，失败才由竞速就绪源接管”的决议调度秩序。
    ({SourceMeta target, List<SourceChapterRoad> roads, SourceSearchResult hit})? standbyWinner;

    // 真正并发向 5 个源同时发起探测
    for (final target in targetSources) {
      _executeSingleProbeWithCallback(
        target: target,
        sessionToken: currentSession,
        bangumiId: bangumiId,
        onProbeFinished: (sourceState) {
          if (_disposed || _sessionToken != currentSession) return;

          // 核心实时通知：只要某个源完成，立刻通知 UI 变色！
          notifyListeners();

          final isPrimary = target.id == primaryId;
          final isReady = sourceState.status == SourceProbeStatus.ready &&
              sourceState.matchedHit != null &&
              sourceState.roads.isNotEmpty;

          // 胜出判定：首位优先决议，失败秒级接管
          if (!_userLocked && _winnerSourceId == null) {
            if (isPrimary) {
              if (isReady) {
                // 1. 排序第一的主选源就绪：拥有最高决议权，无论比其他源早或晚，直接宣布胜出起播
                _winnerSourceId = target.id;
                onWinnerReady?.call(target, sourceState.roads, sourceState.matchedHit!);
              } else {
                // 2. 排序第一的主选源失败（未收录、异常、需点选或超时）
                primaryFailed = true;
                // 若此时已有其余次选源先行就绪，0ms 立即激活备用源接管起播
                if (standbyWinner != null) {
                  _winnerSourceId = standbyWinner!.target.id;
                  onWinnerReady?.call(
                    standbyWinner!.target,
                    standbyWinner!.roads,
                    standbyWinner!.hit,
                  );
                }
              }
            } else {
              if (isReady) {
                if (primaryFailed) {
                  // 主选源此前已明确失败，首个就绪的次选源直接胜出接管
                  _winnerSourceId = target.id;
                  onWinnerReady?.call(target, sourceState.roads, sourceState.matchedHit!);
                } else {
                  // 主选源尚在请求中，次选源暂存备用，绝不擅自抢跑起播
                  standbyWinner ??= (
                    target: target,
                    roads: sourceState.roads,
                    hit: sourceState.matchedHit!,
                  );
                }
              }
            }
          }

          completedCount++;
          // 若全部 5 个源均探测完毕且仍无任何胜出源
          if (completedCount >= totalTargets && !_userLocked && _winnerSourceId == null) {
            onAllFailed?.call();
          }
        },
      );
    }
  }

  Future<void> _executeSingleProbeWithCallback({
    required SourceMeta target,
    required int sessionToken,
    required int bangumiId,
    required void Function(AggregatedSourceState state) onProbeFinished,
  }) async {
    final sourceId = target.id;
    final actionId = (_probeActionIds[sourceId] ?? 0) + 1;
    _probeActionIds[sourceId] = actionId;

    final cancelToken = CancelToken();
    _cancelTokens[sourceId] = cancelToken;

    final timeoutTimer = Timer(const Duration(milliseconds: probeTimeoutMs), () {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('probe_timeout_5s');
      }
    });
    _timeoutTimers[sourceId] = timeoutTimer;

    try {
      // 熔断器单飞检查
      final breakerCheck = PluginCircuitBreaker.instance.checkBeforeRequest(sourceId);
      if (!breakerCheck.allowed) {
        final errState = AggregatedSourceState(
          meta: target,
          status: SourceProbeStatus.error,
          errorMsg: breakerCheck.reason ?? '源站熔断冷却中',
          searched: true,
        );
        _states[sourceId] = errState;
        onProbeFinished(errState);
        return;
      }

      final kw = _customKeywords[sourceId] ??
          SourceKeywordMatcher.resolveDefaultKeyword(
            defaultTitle: _defaultTitle,
            item: _bangumiItem,
            sourceId: sourceId,
          );

      if (kw.isEmpty || RegExp(r'^番剧\s*\d+$').hasMatch(kw)) {
        final emptyState = AggregatedSourceState(
          meta: target,
          status: SourceProbeStatus.empty,
          searched: true,
          keyword: kw,
        );
        _states[sourceId] = emptyState;
        onProbeFinished(emptyState);
        return;
      }

      final isCustomKw = _customKeywords.containsKey(sourceId);
      final runtime = SourceBundleManager.instance.runtime;

      // 5s 严格 Future 超时包裹（包含搜索 + 深度 chapters 验活）
      final state = await _runProbePipeline(
        sourceId: sourceId,
        meta: target,
        kw: kw,
        isCustomKw: isCustomKw,
        runtime: runtime,
        bangumiId: bangumiId,
        actionId: actionId,
      ).timeout(const Duration(milliseconds: probeTimeoutMs));

      if (_disposed || _probeActionIds[sourceId] != actionId || _sessionToken != sessionToken) {
        return;
      }

      PluginCircuitBreaker.instance.recordSuccess(sourceId);
      _states[sourceId] = state;
      onProbeFinished(state);
    } catch (e) {
      if (_disposed || _probeActionIds[sourceId] != actionId || _sessionToken != sessionToken) {
        return;
      }

      PluginCircuitBreaker.instance.recordFailure(sourceId, e.toString());

      final isTimeout = e is TimeoutException ||
          cancelToken.isCancelled ||
          e.toString().contains('probe_timeout_5s') ||
          e.toString().toLowerCase().contains('timeout');

      final errState = AggregatedSourceState(
        meta: target,
        status: SourceProbeStatus.error,
        errorMsg: isTimeout ? '源站响应超时' : '源站响应异常',
        searched: true,
      );
      _states[sourceId] = errState;
      onProbeFinished(errState);
    } finally {
      _timeoutTimers.remove(sourceId)?.cancel();
      _cancelTokens.remove(sourceId);
    }
  }

  Future<AggregatedSourceState> _runProbePipeline({
    required String sourceId,
    required SourceMeta meta,
    required String kw,
    required bool isCustomKw,
    required dynamic runtime,
    required int bangumiId,
    required int actionId,
  }) async {
    final rawHits = await (runtime.search(sourceId, kw, bypassCache: isCustomKw)
        as Future<List<SourceSearchResult>>);
    if (_disposed || _probeActionIds[sourceId] != actionId) {
      throw Exception('Task invalidated');
    }

    final ranked = SourceKeywordMatcher.rankSearchHits(rawHits, [
      ..._titleRefs,
      kw,
    ]);

    if (ranked.isEmpty) {
      return AggregatedSourceState(
        meta: meta,
        status: SourceProbeStatus.empty,
        searched: true,
        keyword: kw,
      );
    }

    final top = ranked.first;
    final score = SourceKeywordMatcher.bestSimilarity(top.name, [
      ..._titleRefs,
      kw,
    ]);

    if (score < autoPickMinSimilarity) {
      return AggregatedSourceState(
        meta: meta,
        status: SourceProbeStatus.needsPick,
        items: ranked,
        searched: true,
        keyword: kw,
      );
    }

    // 深度验活 chapters，杜绝假绿灯
    List<SourceChapterRoad> validatedRoads = const [];
    try {
      validatedRoads = await (runtime.chapters(sourceId, top.url, bypassCache: isCustomKw)
          as Future<List<SourceChapterRoad>>);
    } catch (_) {}

    if (_disposed || _probeActionIds[sourceId] != actionId) {
      throw Exception('Task invalidated');
    }

    if (validatedRoads.isNotEmpty && validatedRoads.any((r) => r.episodes.isNotEmpty)) {
      // 成功命中并包含分集，异步写入绑定服务
      SourceBindingService.instance.setBinding(
        bangumiId: bangumiId,
        sourceId: sourceId,
        sourceUrl: top.url,
        title: top.name,
        referenceTitles: _titleRefs,
      ).ignore();

      return AggregatedSourceState(
        meta: meta,
        status: SourceProbeStatus.ready,
        items: ranked,
        matchedHit: top,
        roads: validatedRoads,
        searched: true,
        keyword: kw,
      );
    } else {
      return AggregatedSourceState(
        meta: meta,
        status: SourceProbeStatus.empty,
        items: ranked,
        errorMsg: '未收录有效播放分集',
        searched: true,
        keyword: kw,
      );
    }
  }

  /// 为指定源提取分集（若已缓存则 0ms 秒返，否则执行精准提取）
  Future<List<SourceChapterRoad>> loadChaptersForSource(
    String sourceId, {
    SourceSearchResult? hit,
    bool bypassCache = false,
  }) async {
    final curState = _states[sourceId];
    if (!bypassCache &&
        curState?.roads != null &&
        curState!.roads.isNotEmpty &&
        curState.roads.any((r) => r.episodes.isNotEmpty)) {
      return curState.roads;
    }

    final runtime = SourceBundleManager.instance.runtime;
    final meta = runtime.getSource(sourceId)?.toMeta() ??
        curState?.meta ??
        SourceMeta(id: sourceId, name: sourceId, version: '1.0');

    String? targetUrl = hit?.url ?? curState?.matchedHit?.url;
    String? targetTitle = hit?.name ?? curState?.matchedHit?.name;

    // 查绑定
    if (targetUrl == null && _currentBangumiId > 0) {
      final binding = SourceBindingService.instance.getBinding(_currentBangumiId, sourceId);
      if (binding != null && binding.sourceUrl.isNotEmpty) {
        targetUrl = binding.sourceUrl;
        targetTitle = binding.title;
      }
    }

    // 搜词
    if (targetUrl == null) {
      final kw = _customKeywords[sourceId] ??
          SourceKeywordMatcher.resolveDefaultKeyword(
            defaultTitle: _defaultTitle,
            item: _bangumiItem,
            sourceId: sourceId,
          );
      if (kw.isNotEmpty) {
        final hits = await runtime.search(sourceId, kw, bypassCache: bypassCache);
        final ranked = SourceKeywordMatcher.rankSearchHits(hits, _titleRefs);
        if (ranked.isNotEmpty) {
          targetUrl = ranked.first.url;
          targetTitle = ranked.first.name;
        }
      }
    }

    if (targetUrl == null || targetUrl.isEmpty) {
      throw Exception('在「${meta.name}」未检索到《$_defaultTitle》，请在面板中换词');
    }

    final roads = await runtime.chapters(sourceId, targetUrl, bypassCache: bypassCache);
    if (roads.isEmpty || roads.every((r) => r.episodes.isEmpty)) {
      throw Exception('未能从「${meta.name}」解析到有效分集');
    }

    final effectiveHit = hit ?? SourceSearchResult(name: targetTitle ?? _defaultTitle, url: targetUrl);
    _states[sourceId] = AggregatedSourceState(
      meta: meta,
      status: SourceProbeStatus.ready,
      matchedHit: effectiveHit,
      roads: roads,
      searched: true,
      keyword: targetTitle,
    );
    notifyListeners();

    if (_currentBangumiId > 0 && targetTitle != null) {
      SourceBindingService.instance.setBinding(
        bangumiId: _currentBangumiId,
        sourceId: sourceId,
        sourceUrl: targetUrl,
        title: targetTitle,
        referenceTitles: _titleRefs,
      ).ignore();
    }

    return roads;
  }

  /// 抢占式调度：用户手动点击某源卡片时，将该源插队至队首；
  /// 若并发已满，主动 cancel 掉 1 个后台探测任务为用户让位
  void prioritizeSource(String sourceId, {bool isUserAction = true}) {
    final sId = sourceId.trim();
    if (sId.isEmpty) return;

    if (isUserAction) {
      lockByUserAction();
      PluginCircuitBreaker.instance.reset(sId);
    }

    // 取消当前该源自身的旧请求 (若有)，必须先清除定时器并递增 actionId 使旧任务失效
    _probeActionIds[sId] = (_probeActionIds[sId] ?? 0) + 1;
    _timeoutTimers.remove(sId)?.cancel();
    final oldToken = _cancelTokens.remove(sId);
    if (oldToken != null && !oldToken.isCancelled) {
      oldToken.cancel('prioritizeSource');
    }
    _probeDone.remove(sId);

    // 核心抢占逻辑：若并发已满且用户发起了手动操作，抢占并废弃一个后台任务
    if (isUserAction && _activeJobs >= concurrencyLimit) {
      for (final autoJobId in _activeAutoJobs.toList()) {
        if (autoJobId != sId && _cancelTokens.containsKey(autoJobId)) {
          // 废弃旧任务代数，防止后续慢网络返回时脏写
          _probeActionIds[autoJobId] = (_probeActionIds[autoJobId] ?? 0) + 1;
          _timeoutTimers.remove(autoJobId)?.cancel();
          final autoToken = _cancelTokens.remove(autoJobId);
          if (autoToken != null && !autoToken.isCancelled) {
            autoToken.cancel('preempted_by_user');
          }
          _activeAutoJobs.remove(autoJobId);
          _probeDone.remove(autoJobId);
          // 立即扣减 activeJobs 释放并发槽位，让队首的用户任务能够立即启动消费
          _activeJobs--;
          if (!_queue.contains(autoJobId)) {
            _queue.add(autoJobId);
          }
          break;
        }
      }
    }

    // 插队至队首
    _queue.remove(sId);
    _queue.insert(0, sId);
    if (isUserAction) {
      _userActionSources.add(sId);
    }
    _processQueue();
  }

  /// 手动重新探测指定视频源 (支持传入自定义关键词或胶囊关键词，强制绕过缓存)
  void reProbeSource(String sourceId, [String? customKeyword]) {
    lockByUserAction();
    final kw = customKeyword?.trim();
    if (kw != null && kw.isNotEmpty) {
      _customKeywords[sourceId] = kw;
    }

    final meta = SourceBundleManager.instance.runtime.getSource(sourceId)?.toMeta() ??
        _states[sourceId]?.meta;
    if (meta == null) return;

    // 即时视觉反馈：秒级置为 probing
    _states[sourceId] = AggregatedSourceState(
      meta: meta,
      status: SourceProbeStatus.probing,
      keyword: kw ?? _states[sourceId]?.keyword ?? _defaultTitle,
      searched: true,
    );
    notifyListeners();

    _userActionSources.add(sourceId.trim());
    prioritizeSource(sourceId, isUserAction: true);
  }

  /// 内部队列消费者 (维持最大并发限制)
  Future<void> _processQueue() async {
    while (_activeJobs < concurrencyLimit && _queue.isNotEmpty) {
      final sourceId = _queue.removeAt(0);
      _userActionSources.remove(sourceId);
      if (_probeDone.contains(sourceId)) continue;

      final source = SourceBundleManager.instance.runtime.getSource(sourceId);
      if (source == null) continue;

      _activeJobs++;
      _probeDone.add(sourceId);

      final customKw = _customKeywords[sourceId];
      final isCustomKw = customKw != null && customKw.isNotEmpty;

      if (!isCustomKw) {
        _activeAutoJobs.add(sourceId);
      } else {
        _activeAutoJobs.remove(sourceId);
      }

      final kw = isCustomKw
          ? customKw
          : SourceKeywordMatcher.resolveDefaultKeyword(
              defaultTitle: _defaultTitle,
              item: _bangumiItem,
              sourceId: sourceId,
            );

      _states[sourceId] = AggregatedSourceState(
        meta: source.toMeta(),
        status: SourceProbeStatus.probing,
        searched: true,
        keyword: kw,
      );
      notifyListeners();

      _probeSingleSource(source, kw, isCustomKw);
    }
  }

  Future<void> _probeSingleSource(
    dynamic source,
    String kw,
    bool isCustomKw,
  ) async {
    final sourceId = source.id as String;
    final meta = source.toMeta() as SourceMeta;

    final actionId = (_probeActionIds[sourceId] ?? 0) + 1;
    _probeActionIds[sourceId] = actionId;

    final cancelToken = CancelToken();
    _cancelTokens[sourceId] = cancelToken;

    final timeoutTimer = Timer(const Duration(milliseconds: probeTimeoutMs), () {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('probe_timeout_5s');
      }
    });
    _timeoutTimers[sourceId] = timeoutTimer;

    try {
      final breakerCheck = PluginCircuitBreaker.instance.checkBeforeRequest(sourceId);
      if (!breakerCheck.allowed) {
        _states[sourceId] = AggregatedSourceState(
          meta: meta,
          status: SourceProbeStatus.error,
          errorMsg: breakerCheck.reason ?? '源站熔断冷却中',
          searched: true,
        );
        return;
      }

      if (kw.isEmpty || RegExp(r'^番剧\s*\d+$').hasMatch(kw)) {
        _timeoutTimers.remove(sourceId)?.cancel();
        _states[sourceId] = AggregatedSourceState(
          meta: meta,
          status: SourceProbeStatus.empty,
          searched: true,
          keyword: kw,
        );
        return;
      }

      final res = await _runProbePipeline(
        sourceId: sourceId,
        meta: meta,
        kw: kw,
        isCustomKw: isCustomKw,
        runtime: SourceBundleManager.instance.runtime,
        bangumiId: _currentBangumiId,
        actionId: actionId,
      ).timeout(const Duration(milliseconds: probeTimeoutMs));

      if (_disposed || _probeActionIds[sourceId] != actionId) return;

      PluginCircuitBreaker.instance.recordSuccess(sourceId);
      _states[sourceId] = res;
    } catch (e) {
      if (_disposed || _probeActionIds[sourceId] != actionId) return;

      PluginCircuitBreaker.instance.recordFailure(sourceId, e.toString());

      final isTimeout = e is TimeoutException ||
          cancelToken.isCancelled ||
          e.toString().contains('probe_timeout_5s') ||
          e.toString().toLowerCase().contains('timeout');

      _states[sourceId] = AggregatedSourceState(
        meta: meta,
        status: SourceProbeStatus.error,
        errorMsg: isTimeout ? '源站响应超时' : '源站响应异常',
        searched: true,
        keyword: kw,
      );
    } finally {
      _timeoutTimers.remove(sourceId)?.cancel();
      if (!_disposed && _probeActionIds[sourceId] == actionId) {
        _finishJob(sourceId);
      }
    }
  }

  void _finishJob(String sourceId) {
    _activeJobs--;
    _activeAutoJobs.remove(sourceId);
    _timeoutTimers.remove(sourceId)?.cancel();
    _cancelTokens.remove(sourceId);
    if (_disposed) return;
    notifyListeners();
    _processQueue();
  }

  void _cancelAll() {
    _probeActionIds.clear();
    for (final timer in _timeoutTimers.values) {
      timer.cancel();
    }
    _timeoutTimers.clear();

    for (final token in _cancelTokens.values) {
      try {
        if (!token.isCancelled) {
          token.cancel('reset');
        }
      } catch (_) {}
    }
    _cancelTokens.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelAll();
    super.dispose();
  }
}
