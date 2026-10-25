import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../core/models/bangumi/bangumi_episode.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/services/app_preferences.dart';
import '../../../core/services/bangumi_oped_service.dart';
import '../core/utils/playback_tracer.dart';
import '../danmaku/danmaku.dart';
import '../source/auto_source_pick_coordinator.dart';
import '../source/models/source_models.dart';
import '../source/services/source_binding_service.dart';
import '../source/source_aggregator.dart';
import '../source/source_bundle_manager.dart';
import '../source/source_keyword_matcher.dart';
import '../source/utils/playable_slot_engine.dart';
import '../widgets/video_source_view.dart';
import 'playback_controller.dart';
import 'watch_progress_tracker.dart';

/// 错误信息友好化清洗提炼
String cleanErrorMessage(dynamic error, {String prefix = '检索异常'}) {
  final raw = error.toString().trim();
  final stripped = raw
      .replaceAll('Exception: ', '')
      .replaceAll('DioException [bad response]: ', '')
      .replaceAll('DioException [connection error]: ', '')
      .replaceAll('DioException [connection timeout]: ', '');
  if (stripped.length > 80) {
    return '$prefix: ${stripped.substring(0, 80)}...';
  }
  return '$prefix: $stripped';
}

/// 视频播放页面全功能会话与源调度协调器 (纯业务状态与调度引擎)
///
/// 架构设计与职责分离：
/// 1. 多源并发检索与保底探测：负责持久化绑定直开、默认源单词命中与后台并发保底源探测；
/// 2. 自适应宽限选源仲裁：通过 AutoSourcePickCoordinator 管理宽限期切换与用户点击互斥；
/// 3. 单集直链解析与起播管道：负责 Tracer 埋点、防串号代际校验、预载下一集切片与分集原子切换；
/// 4. 槽位对齐与多线路管理：维护 PlayableSlot 双层对齐与多线路切换；
/// 5. 继承 ChangeNotifier：纯状态与业务驱动，彻底解耦 BuildContext 与 Widget 树。
class VideoPlaySessionCoordinator extends ChangeNotifier {
  VideoPlaySessionCoordinator({
    required this.title,
    required this.episodeCount,
    this.bangumiItem,
    this.coverUrl,
    this.videoUrl,
    this.httpHeaders,
    this.initialPosition,
    this.currentEpisode,
    this.preferredSourceId,
    this.initialPageUrl,
    this.initialRoad,
    this.onEpisodeSelected,
    required this.playbackController,
    required this.danmakuCoordinator,
    required this.progressTracker,
    required this.showHudToast,
    required this.onFocusEpisodesTab,
    required this.waitForRouteAnimation,
  }) {
    if (preferredSourceId != null && preferredSourceId!.isNotEmpty) {
      _selectedSourceId = preferredSourceId!;
    }
    if (initialRoad != null && initialRoad! >= 0) {
      _selectedRoadIndex = initialRoad!;
    }
    if (initialPageUrl != null && initialPageUrl!.isNotEmpty) {
      _currentPlayingPageUrl = initialPageUrl;
    }
    _activeEpisode = currentEpisode;

    _aggregator = SourceAggregator();
    _aggregator.addListener(_onAggregatorUpdated);

    _autoPicker = AutoSourcePickCoordinator(
      onSwitchSource: (meta, hit) {
        if (_disposed) return;
        showHudToast('默认源未收录，已为你切换至 ${meta.name}');
        handleSourceSelected(
          _sources.firstWhere(
            (s) => s.id == meta.id,
            orElse: () => VideoSourceItem(id: meta.id, name: meta.name, description: ''),
          ),
          hit,
        );
      },
      onAllFallbacksFailed: () {
        if (_disposed) return;
        showHudToast('所有备用源自动检索完毕，请在面板中换词重搜');
        onFocusEpisodesTab();
      },
    );
  }

  final String title;
  final int episodeCount;
  final BangumiItem? bangumiItem;
  final String? coverUrl;
  final String? videoUrl;
  final Map<String, String>? httpHeaders;
  final Duration? initialPosition;
  final int? currentEpisode;
  final String? preferredSourceId;
  final String? initialPageUrl;
  final int? initialRoad;
  final ValueChanged<int>? onEpisodeSelected;
  final ZakowayPlaybackController playbackController;
  final DanmakuSessionCoordinator danmakuCoordinator;
  final WatchProgressTracker progressTracker;
  final ValueChanged<String> showHudToast;
  final VoidCallback onFocusEpisodesTab;
  final Future<void> Function() waitForRouteAnimation;

  late final SourceAggregator _aggregator;
  late final AutoSourcePickCoordinator _autoPicker;

  bool _disposed = false;
  bool get isDisposed => _disposed;

  String _selectedSourceId = 'xifan-next';
  String get selectedSourceId => _selectedSourceId;

  List<VideoSourceItem> get _sources => getDefaultSourceItems();
  List<VideoSourceItem> get sources => _sources;

  bool _isLoadingChapters = false;
  bool get isLoadingChapters => _isLoadingChapters;

  String? _chaptersError;
  String? get chaptersError => _chaptersError;

  String? _playbackError;
  String? get playbackError => _playbackError;

  String? _sourceNotice;
  String? get sourceNotice => _sourceNotice;

  bool _defaultSearchEmpty = false;
  bool get defaultSearchEmpty => _defaultSearchEmpty;

  List<SourceChapterRoad> _chapterRoads = [];
  List<SourceChapterRoad> get chapterRoads => _chapterRoads;

  int _selectedRoadIndex = 0;
  int get selectedRoadIndex => _selectedRoadIndex;

  int _episodeResolveToken = 0;

  String? _currentPlayingPageUrl;
  String? get currentPlayingPageUrl => _currentPlayingPageUrl;

  int? _activeEpisode;
  int? get activeEpisode => _activeEpisode;

  bool _hasStartedPlayback = false;
  bool get hasStartedPlayback => _hasStartedPlayback;

  int? _playingRoadIndex;
  int? get playingRoadIndex => _playingRoadIndex;

  String? _playingSourceId;
  String? get playingSourceId => _playingSourceId;

  SourceAggregator get aggregator => _aggregator;
  AutoSourcePickCoordinator get autoPicker => _autoPicker;

  // 外部注入的权威数据 (Bangumi)
  BangumiItem? fullBangumiItem;
  List<BangumiEpisode>? officialEpisodes;
  Map<int, EpisodeOpedSegment> opedData = {};

  BangumiItem? get effectiveBangumiItem => fullBangumiItem ?? bangumiItem;
  int get effectiveBangumiId => effectiveBangumiItem?.id ?? bangumiItem?.id ?? 0;
  EpisodeOpedSegment? get currentOpedSegment => opedData[_activeEpisode ?? 1];

  int get currentCanonicalEp => _activeEpisode ?? 1;

  List<SourceEpisode> get currentEpisodes {
    if (_chapterRoads.isEmpty) return [];
    final idx = _selectedRoadIndex.clamp(0, _chapterRoads.length - 1);
    return _chapterRoads[idx].episodes;
  }

  List<PlayableSlot> get currentSlots {
    return PlayableSlotEngine.buildPlayableSlots(
      episodes: currentEpisodes,
      officialEpisodes: officialEpisodes,
    );
  }

  List<String> get mappedEpisodeTitles {
    final slots = currentSlots;
    if (slots.isEmpty) return [];
    return slots.map((s) => s.displayTitle).toList();
  }

  List<String> get roadNames {
    if (_chapterRoads.isEmpty) return const ['默认线路'];
    return _chapterRoads.map((r) => r.name).toList();
  }

  int get displayEpisodeCount =>
      currentSlots.isNotEmpty ? currentSlots.length : currentEpisodes.length;

  String get selectedSourceName {
    final match = _sources.where((s) => s.id == _selectedSourceId).firstOrNull;
    return match?.name ?? _selectedSourceId;
  }

  List<String> get keywordOptions {
    final Set<String> candidates = {};
    if (title.trim().isNotEmpty) candidates.add(title.trim());
    final effective = effectiveBangumiItem;
    if (effective != null) {
      if (effective.nameCn.trim().isNotEmpty) candidates.add(effective.nameCn.trim());
      if (effective.name.trim().isNotEmpty) candidates.add(effective.name.trim());
      for (final alias in effective.alias) {
        if (alias.trim().isNotEmpty) candidates.add(alias.trim());
      }
    }
    return candidates.toList();
  }

  List<String> get titleRefs {
    final refs = <String>[];
    if (effectiveBangumiItem?.nameCn.isNotEmpty ?? false) {
      refs.add(effectiveBangumiItem!.nameCn);
    }
    if (effectiveBangumiItem?.name.isNotEmpty ?? false) {
      refs.add(effectiveBangumiItem!.name);
    }
    if (title.isNotEmpty && !refs.contains(title)) {
      refs.add(title);
    }
    return refs;
  }

  void _onAggregatorUpdated() {
    if (_disposed) return;
    notifyListeners();

    _autoPicker.update(
      bangumiId: effectiveBangumiId,
      enabled: _defaultSearchEmpty && _chapterRoads.isEmpty,
      sources: _aggregator.states,
      inFlightSources: _aggregator.inFlightSources,
      sourceOrder: _sources.map((s) => s.id).toList(),
      allFallbacksExhausted: _aggregator.allFallbacksExhausted,
    );
  }

  void selectRoad(int idx) {
    if (_selectedRoadIndex == idx) return;
    _selectedRoadIndex = idx;
    notifyListeners();
  }

  /// 响应服务端模式关闭事件：清空扩展源分集列表并提示
  void notifyServerModeDisabled() {
    _chapterRoads = [];
    _chaptersError = '当前视频源需开启「Animaku 服务端模式」\n该源为服务端专属扩展源，本地直连模式下无法解析分集。';
    notifyListeners();
  }

  /// 若有显式传入的固定 URL 则直接起播
  Future<void> initPresetPlayback() async {
    if (videoUrl != null && videoUrl!.isNotEmpty) {
      _hasStartedPlayback = true;
      progressTracker.reset();
      loadDanmakuForCurrentEpisode();
      final start = progressTracker.resolveInitialResumePosition(
        bangumiId: effectiveBangumiId,
        canonicalEp: currentCanonicalEp,
        initialPosition: initialPosition,
        currentEpisodeParam: currentEpisode,
      );
      await safeOpenPlayback(
        videoUrl!,
        httpHeaders: httpHeaders,
        start: start,
      );
      notifyListeners();
    }
  }

  /// 统一安全起播辅助方法：确保硬件解码纹理挂载与路由动画安全解耦
  Future<void> safeOpenPlayback(
    String url, {
    Map<String, String>? httpHeaders,
    Duration? start,
    bool isPreResolved = true,
  }) async {
    await waitForRouteAnimation();
    if (_disposed) return;
    await playbackController.open(
      url,
      httpHeaders: httpHeaders,
      start: start,
      isPreResolved: isPreResolved,
    );
  }

  /// 加载弹幕
  void loadDanmakuForCurrentEpisode() {
    final ep = _activeEpisode ?? 1;
    final effectiveTitle = (effectiveBangumiItem?.nameCn.isNotEmpty ?? false)
        ? effectiveBangumiItem!.nameCn
        : (effectiveBangumiItem?.name ?? title);

    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (_disposed) return;
      danmakuCoordinator.autoMatchAndLoad(
        bangumiId: effectiveBangumiId,
        episode: ep,
        title: effectiveTitle,
        pluginName: _selectedSourceId,
        titleAliases: titleRefs,
      ).ignore();
    });
  }

  /// 启动主检索流程
  Future<void> startDefaultSourceSearch({bool autoPlayFirst = false}) async {
    if (_disposed) return;
    _isLoadingChapters = true;
    _chaptersError = null;
    _sourceNotice = null;
    notifyListeners();

    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        _chapterRoads = [
          SourceChapterRoad(
            name: '默认线路',
            episodes: List.generate(
              episodeCount,
              (i) => SourceEpisode(name: '第 ${i + 1} 话', url: 'https://test/ep${i + 1}'),
            ),
          )
        ];
        _isLoadingChapters = false;
        notifyListeners();
        return;
      }

      await SourceBundleManager.instance.initialize();
      final runtime = SourceBundleManager.instance.runtime;
      final bangumiId = effectiveBangumiId;

      // Step 1: 优先检查历史持久化绑定 (0ms 直开)
      final binding = SourceBindingService.instance.getBinding(bangumiId, _selectedSourceId);
      if (binding != null && binding.sourceUrl.isNotEmpty) {
        try {
          final roads = await runtime.chapters(_selectedSourceId, binding.sourceUrl);
          if (roads.isNotEmpty && roads.any((r) => r.episodes.isNotEmpty)) {
            if (_disposed) return;
            PlaybackTracer.instance.current?.markChaptersFetched(
              roadCount: roads.length,
              episodeCount: roads.first.episodes.length,
            );
            _chapterRoads = roads;
            _selectedRoadIndex = (initialRoad != null &&
                    initialRoad! >= 0 &&
                    initialRoad! < roads.length)
                ? initialRoad!
                : 0;
            _isLoadingChapters = false;
            _defaultSearchEmpty = false;
            notifyListeners();

            if (autoPlayFirst && currentEpisodes.isNotEmpty) {
              selectEpisode(_activeEpisode ?? 1);
            } else if (currentEpisodes.isNotEmpty) {
              runtime.resolve(_selectedSourceId, currentEpisodes.first.url).ignore();
            }
            return;
          }
        } catch (_) {
          await SourceBindingService.instance.removeBinding(bangumiId, _selectedSourceId);
        }
      }

      // Step 2: 默认源单关键词精准检索
      final primaryKw = SourceKeywordMatcher.resolveDefaultKeyword(
        defaultTitle: title,
        item: effectiveBangumiItem,
        sourceId: _selectedSourceId,
      );

      SourceSearchResult? bestHit;
      if (primaryKw.isNotEmpty) {
        final rawHits = await runtime.search(_selectedSourceId, primaryKw);
        final ranked = SourceKeywordMatcher.rankSearchHits(rawHits, titleRefs);
        if (ranked.isNotEmpty) {
          final score = SourceKeywordMatcher.bestSimilarity(ranked.first.name, titleRefs);
          if (score >= SourceAggregator.autoPickMinSimilarity) {
            bestHit = ranked.first;
          }
        }
      }

      if (bestHit == null) {
        final fallbackKw = (effectiveBangumiItem?.nameCn.isNotEmpty ?? false)
            ? effectiveBangumiItem!.nameCn
            : title;
        if (fallbackKw.isNotEmpty && fallbackKw != primaryKw) {
          final rawHits = await runtime.search(_selectedSourceId, fallbackKw);
          final ranked = SourceKeywordMatcher.rankSearchHits(rawHits, titleRefs);
          if (ranked.isNotEmpty) {
            final score = SourceKeywordMatcher.bestSimilarity(ranked.first.name, titleRefs);
            if (score >= SourceAggregator.autoPickMinSimilarity) {
              bestHit = ranked.first;
            }
          }
        }
      }

      // 默认源成功命中！
      if (bestHit != null) {
        final roads = await runtime.chapters(_selectedSourceId, bestHit.url);
        if (roads.isNotEmpty && roads.any((r) => r.episodes.isNotEmpty)) {
          if (_disposed) return;
          PlaybackTracer.instance.current?.markChaptersFetched(
            roadCount: roads.length,
            episodeCount: roads.first.episodes.length,
          );
          _chapterRoads = roads;
          _selectedRoadIndex = (initialRoad != null &&
                  initialRoad! >= 0 &&
                  initialRoad! < roads.length)
              ? initialRoad!
              : 0;
          _isLoadingChapters = false;
          _defaultSearchEmpty = false;
          notifyListeners();

          await SourceBindingService.instance.setBinding(
            bangumiId: bangumiId,
            sourceId: _selectedSourceId,
            sourceUrl: bestHit.url,
            title: bestHit.name,
            referenceTitles: titleRefs,
          );

          if (autoPlayFirst && currentEpisodes.isNotEmpty) {
            selectEpisode(_activeEpisode ?? 1);
          } else if (currentEpisodes.isNotEmpty) {
            runtime.resolve(_selectedSourceId, currentEpisodes.first.url).ignore();
          }
          return;
        }
      }

      // Step 3: 默认源未收录 -> 启动后台并发保底探测
      if (_disposed) return;
      _isLoadingChapters = false;
      _chapterRoads = [];
      _defaultSearchEmpty = true;
      _sourceNotice = '默认源未收录《$title》，已为你并发检索备用播放源';
      notifyListeners();

      _aggregator.syncAndProbe(
        bangumiId: bangumiId,
        defaultTitle: title,
        item: effectiveBangumiItem,
        activeSourceId: _selectedSourceId,
        isOpen: true,
        autoProbeOnFallback: true,
        sourceOrder: _sources.map((s) => s.id).toList(),
      );
    } catch (e) {
      if (_disposed) return;
      _isLoadingChapters = false;
      _chaptersError = cleanErrorMessage(e, prefix: '检索异常');
      notifyListeners();
    }
  }

  /// 换源并提取分集
  Future<void> handleSourceSelected(
    VideoSourceItem src, [
    SourceSearchResult? directHit,
    List<SourceChapterRoad>? cachedRoads,
  ]) async {
    _autoPicker.onUserAction();

    // 0ms 秒级直开：若探测器中已预先验活并缓存了分集线路，直接采纳
    if (cachedRoads != null &&
        cachedRoads.isNotEmpty &&
        cachedRoads.any((r) => r.episodes.isNotEmpty)) {
      _selectedSourceId = src.id;
      _chapterRoads = cachedRoads;
      _selectedRoadIndex = 0;
      _isLoadingChapters = false;
      _chaptersError = null;
      _sourceNotice = null;
      _defaultSearchEmpty = false;
      notifyListeners();

      onFocusEpisodesTab();

      if (directHit != null && effectiveBangumiId > 0) {
        SourceBindingService.instance.setBinding(
          bangumiId: effectiveBangumiId,
          sourceId: src.id,
          sourceUrl: directHit.url,
          title: directHit.name,
          referenceTitles: titleRefs,
        ).ignore();
      }
      return;
    }

    _selectedSourceId = src.id;
    _chapterRoads = [];
    _selectedRoadIndex = 0;
    _isLoadingChapters = true;
    _chaptersError = null;
    _sourceNotice = null;
    notifyListeners();

    onFocusEpisodesTab();

    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        _chapterRoads = [
          SourceChapterRoad(
            name: '默认线路',
            episodes: List.generate(
              episodeCount,
              (i) => SourceEpisode(name: '第 ${i + 1} 话', url: 'https://test/ep${i + 1}'),
            ),
          )
        ];
        _isLoadingChapters = false;
        notifyListeners();
        return;
      }

      final runtime = SourceBundleManager.instance.runtime;
      final bangumiId = effectiveBangumiId;

      String? targetUrl = directHit?.url;
      String? targetTitle = directHit?.name;

      if (targetUrl == null) {
        final probeState = _aggregator.states[src.id];
        if (probeState?.matchedHit != null) {
          targetUrl = probeState!.matchedHit!.url;
          targetTitle = probeState.matchedHit!.name;
        }
      }

      if (targetUrl == null) {
        final binding = SourceBindingService.instance.getBinding(bangumiId, src.id);
        if (binding != null && binding.sourceUrl.isNotEmpty) {
          targetUrl = binding.sourceUrl;
          targetTitle = binding.title;
        }
      }

      if (targetUrl == null) {
        final primaryKw = SourceKeywordMatcher.resolveDefaultKeyword(
          defaultTitle: title,
          item: effectiveBangumiItem,
          sourceId: src.id,
        );

        if (primaryKw.isNotEmpty) {
          final hits = await runtime.search(src.id, primaryKw);
          final ranked = SourceKeywordMatcher.rankSearchHits(hits, titleRefs);
          if (ranked.isNotEmpty) {
            targetUrl = ranked.first.url;
            targetTitle = ranked.first.name;
          }
        }

        if (targetUrl == null) {
          final fallbackKw = (effectiveBangumiItem?.nameCn.isNotEmpty ?? false)
              ? effectiveBangumiItem!.nameCn
              : title;
          if (fallbackKw.isNotEmpty && fallbackKw != primaryKw) {
            final hits = await runtime.search(src.id, fallbackKw);
            final ranked = SourceKeywordMatcher.rankSearchHits(hits, titleRefs);
            if (ranked.isNotEmpty) {
              targetUrl = ranked.first.url;
              targetTitle = ranked.first.name;
            }
          }
        }
      }

      if (targetUrl == null) {
        throw Exception('在「${src.name}」未检索到《$title》，请在面板中展开换词');
      }

      final roads = await runtime.chapters(src.id, targetUrl);
      if (roads.isEmpty || roads.every((r) => r.episodes.isEmpty)) {
        throw Exception('未能从「${src.name}」解析到有效分集');
      }

      if (_disposed) return;
      _chapterRoads = roads;
      _selectedRoadIndex = 0;
      _isLoadingChapters = false;
      _defaultSearchEmpty = false;
      notifyListeners();

      if (targetTitle != null && targetUrl.isNotEmpty) {
        await SourceBindingService.instance.setBinding(
          bangumiId: bangumiId,
          sourceId: src.id,
          sourceUrl: targetUrl,
          title: targetTitle,
          referenceTitles: titleRefs,
        );
      }
    } catch (e) {
      if (_disposed) return;
      _isLoadingChapters = false;
      _chaptersError = cleanErrorMessage(e, prefix: '分集同步失败');
      notifyListeners();
    }
  }

  /// 统一单集直链解析与安全起播核心管道
  Future<void> resolveAndStartPlayback({
    required String pageUrl,
    required int canonicalEp,
    required int sessionToken,
  }) async {
    final tracer = PlaybackTracer.instance.startSession(
      title: title,
      episode: canonicalEp,
      sourceId: _selectedSourceId,
    );

    progressTracker.reset();
    onEpisodeSelected?.call(canonicalEp);
    loadDanmakuForCurrentEpisode();

    final startPos = progressTracker.resolveInitialResumePosition(
      bangumiId: effectiveBangumiId,
      canonicalEp: canonicalEp,
      initialPosition: initialPosition,
      currentEpisodeParam: currentEpisode,
    );

    if (videoUrl != null && videoUrl!.isNotEmpty) {
      tracer.markResolveSuccess(preResolved: true);
      await safeOpenPlayback(
        videoUrl!,
        httpHeaders: httpHeaders,
        start: startPos,
        isPreResolved: true,
      );
      return;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      tracer.markResolveSuccess(preResolved: true);
      await safeOpenPlayback(pageUrl, start: startPos, isPreResolved: true);
      return;
    }

    try {
      tracer.markResolveStarted();
      final runtime = SourceBundleManager.instance.runtime;
      final result = await runtime.resolve(_selectedSourceId, pageUrl);

      if (sessionToken != _episodeResolveToken || _disposed) return;

      if (result.url.isEmpty) {
        throw Exception('视频源未能生成有效媒体地址');
      }

      tracer.markResolveSuccess(preResolved: true);
      await safeOpenPlayback(
        result.url,
        httpHeaders: result.headers,
        start: startPos,
        isPreResolved: true,
      );

      final slots = currentSlots;
      final currentIdx = slots.indexWhere((s) => s.canonicalEp == canonicalEp);
      if (currentIdx != -1 && currentIdx + 1 < slots.length) {
        runtime.resolve(_selectedSourceId, slots[currentIdx + 1].pageUrl).ignore();
      }
    } catch (e) {
      if (sessionToken != _episodeResolveToken || _disposed) return;
      tracer.markFailure(e.toString());
      _playbackError = cleanErrorMessage(e, prefix: '播放解析失败');
      notifyListeners();
    }
  }

  /// 用户从槽位列表中点击选集
  Future<void> selectSlot(PlayableSlot slot) async {
    _autoPicker.onUserAction();

    playbackController.stop().ignore();
    danmakuCoordinator.clearEpisodeComments();

    final sessionToken = ++_episodeResolveToken;

    _activeEpisode = slot.canonicalEp;
    _currentPlayingPageUrl = slot.pageUrl;
    _hasStartedPlayback = true;
    _playingRoadIndex = _selectedRoadIndex;
    _playingSourceId = _selectedSourceId;
    _playbackError = null;
    _chaptersError = null;
    notifyListeners();

    await resolveAndStartPlayback(
      pageUrl: slot.pageUrl,
      canonicalEp: slot.canonicalEp,
      sessionToken: sessionToken,
    );
  }

  /// 用户点击选集起播
  Future<void> selectEpisode(int ep) async {
    final slots = currentSlots;
    if (slots.isNotEmpty) {
      final targetSlot = slots.firstWhere(
        (s) => s.canonicalEp == ep,
        orElse: () => (ep - 1 >= 0 && ep - 1 < slots.length) ? slots[ep - 1] : slots.first,
      );
      await selectSlot(targetSlot);
      return;
    }

    _autoPicker.onUserAction();

    final episodes = currentEpisodes;
    if (episodes.isEmpty || ep < 1 || ep > episodes.length) {
      final runtime = SourceBundleManager.instance.runtime;
      if (!AppPreferences.isServerModeEnabled() && !runtime.isLocalSource(_selectedSourceId)) {
        showHudToast('当前源依赖服务端模式，无法解析播放，请开启服务端模式或手动换源');
        return;
      }
      showHudToast('当前视频源暂无可播放分集，请切换线路或视频源');
      return;
    }

    playbackController.stop().ignore();
    danmakuCoordinator.clearEpisodeComments();
    final sessionToken = ++_episodeResolveToken;

    final epIndex = ep - 1;
    final targetEp = episodes[epIndex];

    final int mappedOfficialEp = (officialEpisodes != null &&
            epIndex < officialEpisodes!.length &&
            officialEpisodes![epIndex].sort > 0)
        ? officialEpisodes![epIndex].sort.toInt()
        : ep;

    _activeEpisode = ep;
    _currentPlayingPageUrl = targetEp.url;
    _hasStartedPlayback = true;
    _playingRoadIndex = _selectedRoadIndex;
    _playingSourceId = _selectedSourceId;
    _playbackError = null;
    _chaptersError = null;
    notifyListeners();

    await resolveAndStartPlayback(
      pageUrl: targetEp.url,
      canonicalEp: mappedOfficialEp,
      sessionToken: sessionToken,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _aggregator.removeListener(_onAggregatorUpdated);
    _aggregator.dispose();
    _autoPicker.dispose();
    super.dispose();
  }
}
