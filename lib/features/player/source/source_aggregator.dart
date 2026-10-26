import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:zakoway/core/models/bangumi/bangumi_item.dart';
import 'models/source_models.dart';
import 'services/source_binding_service.dart';
import 'source_bundle_manager.dart';
import 'source_keyword_matcher.dart';

/// 视频源探测状态 (1:1 严格对齐 animaku SourceProbeStatus)
enum SourceProbeStatus {
  /// 待探活 (灰色)
  idle,

  /// 探活中 (蓝色旋转)
  probing,

  /// 已就绪 (绿色，相似度 >= 0.55，存在高置信度命中项)
  ready,

  /// 需点选 (黄色，搜到多条候选但最高相似度 < 0.55，避免错选)
  needsPick,

  /// 未收录 (灰色，搜索结果为空)
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

/// 高性能视频源并发探测器与调度中心 (1:1 严格对齐 animaku useSourceAggregator 核心机理)
///
/// 核心规范与调度策略：
/// 1. 并发上限控制: CONCURRENCY_LIMIT = 3 (杜绝瞬间网络风暴)
/// 2. 单源探活超时: PROBE_TIMEOUT_MS = 5000 (CancelToken 毫秒级熔断)
/// 3. 自动探测限额: AUTO_PROBE_LIMIT = 6 (面板展开时仅探测优先级前 6 个源，超额保持 idle)
/// 4. 抢占式调度: 用户手动点击任意源时插队至队首；若并发已满直接 abort 掉一个后台自动任务为用户让位
/// 5. 手动重测换词: 抽屉内支持快捷候选词胶囊和自定义关键词，强制 bypass 缓存插队重测
/// 6. 单飞熔断器联动: 软故障 2 次超时/硬故障网络中断自动冷却 90 秒
class SourceAggregator extends ChangeNotifier {
  static const int concurrencyLimit = 5;
  static const int probeTimeoutMs = 5000;
  static const int autoProbeLimit = 5;
  static const double autoPickMinSimilarity = 0.55;

  final Map<String, AggregatedSourceState> _states = {};
  final List<String> _queue = [];
  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, Timer> _timeoutTimers = {};
  final Map<String, int> _probeActionIds = {};
  final Set<String> _probeDone = {};
  final Set<String> _activeAutoJobs = {};
  final Set<String> _autoProbedSources = {};
  final Set<String> _userActionSources = {};
  final Map<String, String> _customKeywords = {};
  int _activeJobs = 0;
  bool _disposed = false;

  int _currentBangumiId = 0;
  String? _activeSourceId;
  bool _isOpen = false;
  bool _autoProbeOnFallback = false;

  String _defaultTitle = '';
  BangumiItem? _bangumiItem;
  List<String> _titleRefs = const [];

  Map<String, AggregatedSourceState> get states => Map.unmodifiable(_states);
  List<AggregatedSourceState> get items => _states.values.toList();
  int get activeJobsCount => _activeJobs;

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

  /// 是否存在后台自动探测任务正在执行
  bool get isAutoProbing =>
      _autoProbeOnFallback &&
      (inFlightSources.isNotEmpty || _autoProbedSources.isEmpty);

  /// 保底探测的源是否已全灭 (全部探测完毕且无一 ready)
  bool get allFallbacksExhausted =>
      _autoProbeOnFallback &&
      inFlightSources.isEmpty &&
      _autoProbedSources.isNotEmpty &&
      !_states.values.any((s) => s.status == SourceProbeStatus.ready);

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
    _autoProbedSources.clear();
    _customKeywords.clear();
    _states.clear();

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

  /// 同步上下文并启动自动探测 (面板展开或默认源失败时触发)
  void syncAndProbe({
    required int bangumiId,
    required String defaultTitle,
    BangumiItem? item,
    String? activeSourceId,
    bool isOpen = false,
    bool autoProbeOnFallback = false,
    List<String> sourceOrder = const [],
    SourceSearchResult? currentActiveHit,
  }) {
    if (bangumiId <= 0) return;
    if (_currentBangumiId != bangumiId) {
      resetSubject(bangumiId);
    }

    _defaultTitle = defaultTitle;
    _bangumiItem = item;
    _activeSourceId = activeSourceId;
    _isOpen = isOpen;
    _autoProbeOnFallback = autoProbeOnFallback;

    _titleRefs = [
      if (item?.nameCn.isNotEmpty ?? false) item!.nameCn,
      if (item?.name.isNotEmpty ?? false) item!.name,
      defaultTitle,
      ...(item?.alias ?? const <String>[]),
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    // 1. 同步当前生效源与持久化绑定
    final bindingService = SourceBindingService.instance;
    final allSources = SourceBundleManager.instance.sources;

    for (final s in allSources) {
      final isCurrentActive = _activeSourceId != null &&
          s.id.toLowerCase() == _activeSourceId!.toLowerCase();

      if (isCurrentActive && currentActiveHit != null) {
        _probeDone.add(s.id);
        _states[s.id] = AggregatedSourceState(
          meta: s,
          status: SourceProbeStatus.ready,
          items: [currentActiveHit],
          matchedHit: currentActiveHit,
          searched: true,
          keyword: _defaultTitle,
        );
      } else if (!_states.containsKey(s.id) || !_states[s.id]!.searched) {
        final binding = bindingService.getBinding(bangumiId, s.id);
        if (binding != null && binding.sourceUrl.isNotEmpty) {
          _probeDone.add(s.id);
          final boundHit = SourceSearchResult(name: binding.title, url: binding.sourceUrl);
          _states[s.id] = AggregatedSourceState(
            meta: s,
            status: SourceProbeStatus.ready,
            binding: binding,
            items: [boundHit],
            matchedHit: boundHit,
            searched: true,
            keyword: binding.title,
          );
        } else {
          _states[s.id] ??= AggregatedSourceState(
            meta: s,
            status: SourceProbeStatus.idle,
            searched: false,
          );
        }
      }
    }

    // 2. 检查是否满足自动探测触发条件
    final shouldProbe = _isOpen || _autoProbeOnFallback;
    if (!shouldProbe) return;

    // 自动探测配额已耗尽，绝不继续自动探测
    if (_autoProbedSources.length >= autoProbeLimit) return;

    // 3. 排序所有候选源：在播源优先 -> 用户自定义顺序 -> 内置权重
    final ordered = List<SourceMeta>.from(allSources);
    ordered.sort((a, b) {
      if (_activeSourceId != null) {
        if (a.id.toLowerCase() == _activeSourceId!.toLowerCase()) return -1;
        if (b.id.toLowerCase() == _activeSourceId!.toLowerCase()) return 1;
      }
      final ia = sourceOrder.indexOf(a.id);
      final ib = sourceOrder.indexOf(b.id);
      if (ia != -1 && ib != -1) return ia.compareTo(ib);
      if (ia != -1) return -1;
      if (ib != -1) return 1;
      return a.name.compareTo(b.name);
    });

    // 4. 严格限制仅取前 6 个源进入自动探测队列
    final topCandidates = ordered.take(autoProbeLimit).toList();
    final toProbe = <String>[];

    for (final s in topCandidates) {
      if (_probeDone.contains(s.id)) {
        _autoProbedSources.add(s.id);
        continue;
      }
      if (_autoProbedSources.contains(s.id) || _queue.contains(s.id)) {
        continue;
      }
      if (_autoProbedSources.length + toProbe.length < autoProbeLimit) {
        toProbe.add(s.id);
      }
    }

    if (toProbe.isNotEmpty) {
      _autoProbedSources.addAll(toProbe);
      for (final id in toProbe) {
        if (!_queue.contains(id)) {
          _queue.add(id);
        }
      }
      _processQueue();
    }
  }

  /// 批量启动指定前 N 个目标源并发探测
  void probeTargetSources({
    required int bangumiId,
    required String defaultTitle,
    BangumiItem? item,
    required List<String> targetSourceIds,
    String? activeSourceId,
  }) {
    if (bangumiId <= 0 || targetSourceIds.isEmpty) return;
    if (_currentBangumiId != bangumiId) {
      resetSubject(bangumiId);
    }

    _defaultTitle = defaultTitle;
    _bangumiItem = item;
    _activeSourceId = activeSourceId;
    _autoProbeOnFallback = true;

    _titleRefs = [
      if (item?.nameCn.isNotEmpty ?? false) item!.nameCn,
      if (item?.name.isNotEmpty ?? false) item!.name,
      defaultTitle,
      ...(item?.alias ?? const <String>[]),
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    // 检查持久化绑定
    final bindingService = SourceBindingService.instance;
    final allSources = SourceBundleManager.instance.sources;

    for (final s in allSources) {
      if (!_states.containsKey(s.id) || !_states[s.id]!.searched) {
        final binding = bindingService.getBinding(bangumiId, s.id);
        if (binding != null && binding.sourceUrl.isNotEmpty) {
          _probeDone.add(s.id);
          final boundHit = SourceSearchResult(name: binding.title, url: binding.sourceUrl);
          _states[s.id] = AggregatedSourceState(
            meta: s,
            status: SourceProbeStatus.ready,
            binding: binding,
            items: [boundHit],
            matchedHit: boundHit,
            searched: true,
            keyword: binding.title,
          );
        } else {
          _states[s.id] ??= AggregatedSourceState(
            meta: s,
            status: SourceProbeStatus.idle,
            searched: false,
          );
        }
      }
    }

    final toProbe = <String>[];
    for (final id in targetSourceIds) {
      if (_probeDone.contains(id)) {
        _autoProbedSources.add(id);
        continue;
      }
      if (!_autoProbedSources.contains(id) && !_queue.contains(id)) {
        toProbe.add(id);
      }
    }

    if (toProbe.isNotEmpty) {
      _autoProbedSources.addAll(toProbe);
      _queue.addAll(toProbe);
      _processQueue();
    }
  }

  /// 抢占式调度：用户手动点击某源卡片时，将该源插队至队首；
  /// 若 3 个并发已满，主动 cancel 掉 1 个后台自动探测任务为用户让位！
  void prioritizeSource(String sourceId, {bool isUserAction = true}) {
    final sId = sourceId.trim();
    if (sId.isEmpty) return;

    // 取消当前该源自身的旧请求 (若有)，必须先清除定时器并递增 actionId 使旧任务失效
    _probeActionIds[sId] = (_probeActionIds[sId] ?? 0) + 1;
    _timeoutTimers.remove(sId)?.cancel();
    final oldToken = _cancelTokens.remove(sId);
    if (oldToken != null && !oldToken.isCancelled) {
      oldToken.cancel('prioritizeSource');
    }
    _probeDone.remove(sId);

    // 核心抢占逻辑：若并发已满且用户发起了手动操作，抢占并废弃一个后台自动任务
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
          // 关键：立即扣减 activeJobs 释放并发槽位，让队首的用户任务能够立即启动消费
          _activeJobs--;
          // 将被挤掉的后台任务推回队尾，后续空闲时恢复
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

  /// 动态更新选源面板是否处于展开状态 (供移动端 BottomSheet 展开与收起时同步，已解除自动并发绑定)
  void setOpen(bool isOpen) {
    if (_isOpen == isOpen) return;
    _isOpen = isOpen;
  }

  /// 手动重新探测指定视频源 (支持传入自定义关键词或胶囊关键词，强制绕过缓存)
  void reProbeSource(String sourceId, [String? customKeyword]) {
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

  /// 内部队列消费者 (维持最大 3 并发)
  Future<void> _processQueue() async {
    while (_activeJobs < concurrencyLimit && _queue.isNotEmpty) {
      final nextSourceId = _queue.first;
      final isUserAction = _userActionSources.contains(nextSourceId);

      // 特殊处理说明：
      // 用户主动触发的探活或首屏保底探测任务具有最高执行权限，
      // 解除与面板是否展开(_isOpen)的强绑定，杜绝展开面板时的并发风暴。
      final shouldProbe = isUserAction || _autoProbeOnFallback;
      if (!shouldProbe) return;

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

      // 启动单源探测微任务 (带 5s 超时与 CancelToken)
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

    // 每次单源探测启动均生成唯一 actionId；若超时或被抢占，后续底层异步返回将因 actionId 失效而被安全丢弃
    final actionId = (_probeActionIds[sourceId] ?? 0) + 1;
    _probeActionIds[sourceId] = actionId;

    final cancelToken = CancelToken();
    _cancelTokens[sourceId] = cancelToken;

    // 集中管理超时定时器：由 _timeoutTimers 统一持有，页面退出或任务抢占时可立即取消，
    // 同时通过 !cancelToken.isCancelled 避免被 reset/抢占后重复取消触发 Dio 警告。
    final timeoutTimer = Timer(const Duration(milliseconds: probeTimeoutMs), () {
      if (!cancelToken.isCancelled) {
        cancelToken.cancel('probe_timeout_5s');
      }
    });
    _timeoutTimers[sourceId] = timeoutTimer;

    try {
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

      // 核心熔断设计：将搜索 + 相似度排序 + 分集深度验活 (chapters) 整体包裹于 5s 严格 Future 超时中，
      // 彻底解决 Dio CancelToken 难以深层传递导致的底层网络挂死，以及 chapters 阶段脱离超时保护的问题。
      await _executeProbeFlow(
        sourceId: sourceId,
        meta: meta,
        kw: kw,
        isCustomKw: isCustomKw,
        actionId: actionId,
      ).timeout(const Duration(milliseconds: probeTimeoutMs));
    } catch (e) {
      // 若该任务已被抢占或页面已销毁，直接返回，不写状态也不重复上报
      if (_disposed || _probeActionIds[sourceId] != actionId) return;

      _timeoutTimers.remove(sourceId)?.cancel();
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
      // 仅当当前 actionId 依然生效时才由本次流程负责释放并发槽位 (被抢占的任务在抢占时刻已立即扣减)
      if (!_disposed && _probeActionIds[sourceId] == actionId) {
        _finishJob(sourceId);
      }
    }
  }

  /// 封装单源完整探测与深度验活链路
  Future<void> _executeProbeFlow({
    required String sourceId,
    required SourceMeta meta,
    required String kw,
    required bool isCustomKw,
    required int actionId,
  }) async {
    final runtime = SourceBundleManager.instance.runtime;
    final rawHits = await runtime.search(sourceId, kw, bypassCache: isCustomKw);

    if (_disposed || _probeActionIds[sourceId] != actionId) return;

    // 请求成功，记录熔断器成功状态
    // 对搜索结果按标题相似度打分排序
    final ranked = SourceKeywordMatcher.rankSearchHits(rawHits, [
      ..._titleRefs,
      kw,
    ]);

    if (ranked.isEmpty) {
      _states[sourceId] = AggregatedSourceState(
        meta: meta,
        status: SourceProbeStatus.empty,
        searched: true,
        keyword: kw,
      );
      return;
    }

    final top = ranked.first;
    final score = SourceKeywordMatcher.bestSimilarity(top.name, [
      ..._titleRefs,
      kw,
    ]);

    if (score >= autoPickMinSimilarity) {
      // 深度验活：调用 chapters 验证分集是否真实可用，杜绝“假绿灯”
      List<SourceChapterRoad> validatedRoads = const [];
      try {
        validatedRoads = await runtime.chapters(sourceId, top.url, bypassCache: isCustomKw);
      } catch (_) {}

      if (_disposed || _probeActionIds[sourceId] != actionId) return;

      if (validatedRoads.isNotEmpty &&
          validatedRoads.any((r) => r.episodes.isNotEmpty)) {
        // 真实有效分集 -> 进入就绪态 (真正绿灯)，并直接缓存分集线路
        _states[sourceId] = AggregatedSourceState(
          meta: meta,
          status: SourceProbeStatus.ready,
          items: ranked,
          matchedHit: top,
          roads: validatedRoads,
          searched: true,
          keyword: kw,
        );
      } else {
        // 搜到了名称但分集为空或解析失败 -> 绝不标绿，标为未收录有效分集
        _states[sourceId] = AggregatedSourceState(
          meta: meta,
          status: SourceProbeStatus.empty,
          items: ranked,
          errorMsg: '未收录有效播放分集',
          searched: true,
          keyword: kw,
        );
      }
    } else {
      // 相似度低于 0.55，进入需人工点选态 (黄灯)，绝不盲目误起播
      _states[sourceId] = AggregatedSourceState(
        meta: meta,
        status: SourceProbeStatus.needsPick,
        items: ranked,
        searched: true,
        keyword: kw,
      );
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
