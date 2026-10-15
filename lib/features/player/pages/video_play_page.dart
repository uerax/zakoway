import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../core/models/bangumi/bangumi_episode.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/models/history/watch_history_item.dart';
import '../../../core/network/bangumi_client.dart';
import '../../../core/services/bangumi_oped_service.dart';
import '../../../core/services/watch_history_service.dart';
import '../../../core/services/watched_episodes_service.dart';
import '../../../core/utils/adaptive_page_route.dart';
import '../../../core/utils/anime_tag_filter.dart';
import '../../../core/utils/font_manager.dart';
import '../../../core/utils/responsive.dart';
import '../controller/playback_controller.dart';
import '../danmaku/danmaku.dart';
import '../services/player_preferences_service.dart';
import '../source/auto_source_pick_coordinator.dart';
import '../source/models/source_models.dart';
import '../source/services/source_binding_service.dart';
import '../source/source_aggregator.dart';
import '../source/source_bundle_manager.dart';
import '../source/source_keyword_matcher.dart';
import '../source/utils/playable_slot_engine.dart';
import '../widgets/episode_picker_section.dart';
import '../widgets/player_side_panel.dart';
import '../widgets/video_player_layouts.dart';
import '../widgets/video_player_placeholder.dart';
import '../widgets/video_player_surface_with_controls.dart';
import '../widgets/video_play_tabs.dart';
import '../widgets/video_source_view.dart';
import '../widgets/watch_comments_section.dart';
import '../widgets/watch_meta_view.dart';
import '../widgets/watch_recommend_section.dart';

/// zakoway 统一多端视频播放页面 (1:1 严格对齐 animaku 完整视频源生命周期与架构规范)
///
/// 核心流程与规范：
/// 1. 初始 0ms 直开: 检查 SourceBindingService，若命中该番剧在该源的历史绑定，直接取 sourceUrl 提取分集，跳过搜索；
/// 2. 关键词智能装配: 依据各源语言偏好 (TitlePreference) 解析最优单关键词，规避无效多轮串行网络阻塞；
/// 3. 单源自动选定 (Season Guard): 打分 >= 0.55 且无季数冲突才自动采用，低于门槛则停留在 needsPick 供用户确认；
/// 4. 默认源未收录时并发保底探测: 自动在后台启动 SourceAggregator 探测前 6 个保底源 (3 并发 + 5s 超时熔断)；
/// 5. 自适应宽限选源仲裁器 (AutoSourcePickCoordinator): 1200ms 宽限窗口判定高优先级源；用户手动点击即时互斥锁死；
/// 6. PlayableSlot 双层集数对齐: 自动过滤 PV/SP/特典，1:1 对齐 Bangumi 官方正片，根治剧名带数字被正则误杀问题；
/// 7. 视频源卡片抽屉 (Drawer): 搜出多条时供手动点选条目、候选关键词胶囊快捷换词、自定义输入框强制 bypassCache 重测。
class VideoPlayPage extends StatefulWidget {
  const VideoPlayPage({
    super.key,
    required this.title,
    this.bangumiItem,
    this.coverUrl,
    this.videoUrl,
    this.httpHeaders,
    this.initialPosition,
    this.danmakuItems,
    this.episodeCount = 12,
    this.currentEpisode,
    this.onEpisodeSelected,
  });

  /// 视频/番剧标题
  final String title;
  /// Bangumi 详情数据模型 (Seed)
  final BangumiItem? bangumiItem;
  /// 番剧海报封面地址 (Seed)
  final String? coverUrl;
  /// 预置静态视频流地址 (若不为空则直接起播)
  final String? videoUrl;
  /// 防盗链请求头 (如 Referer)
  final Map<String, String>? httpHeaders;
  /// 断点续播初始时间戳
  final Duration? initialPosition;
  /// 预加载弹幕数据
  final List<DanmakuItem>? danmakuItems;
  /// 总集数占位参数
  final int episodeCount;
  /// 当前播放集数 (从 1 开始，若为 null 则表示未起播占位态)
  final int? currentEpisode;
  /// 切集回调
  final ValueChanged<int>? onEpisodeSelected;

  @override
  State<VideoPlayPage> createState() => _VideoPlayPageState();
}

class _VideoPlayPageState extends State<VideoPlayPage>
    with TickerProviderStateMixin {
  late final ZakowayPlaybackController _playbackController;
  late final DanmakuController _danmakuController;
  late final DanmakuPlaybackBridge _danmakuBridge;
  late final DanmakuSessionCoordinator _danmakuCoordinator;
  late final TabController _tabController;
  late final TabController _desktopRightTabController;
  late final SourceAggregator _aggregator;
  late final AutoSourcePickCoordinator _autoPicker;

  /// 跨布局保活 Key：确保在全屏/桌面/移动端布局切换时复用同一 Element 节点，防止播放器和弹幕被卸载重建
  final GlobalKey _playerSubtreeKey = GlobalKey();

  bool _isAppFullscreen = false;
  bool _isTrueFullscreen = false;
  bool get _isFullscreen => _isAppFullscreen || _isTrueFullscreen;
  bool _isSidePanelOpen = false;
  PlayerSidePanelTab _sidePanelInitialTab = PlayerSidePanelTab.episodes;
  int? _activeEpisode;
  bool _hasStartedPlayback = false;
  int? _playingRoadIndex;
  String? _playingSourceId;
  bool _isLoadingAuthorityDetails = true;

  // 视频源与选集状态
  String _selectedSourceId = 'xifan-next';
  late final List<VideoSourceItem> _sources = getDefaultSourceItems();

  bool _isLoadingChapters = false;
  String? _resolveError;
  String? _sourceNotice;
  String? _hudToast;
  Timer? _hudToastTimer;
  bool _defaultSearchEmpty = false;

  List<SourceChapterRoad> _chapterRoads = [];
  int _selectedRoadIndex = 0;
  String? _currentPlayingPageUrl;

  // 观看统计、15秒有效播放门槛与完播仲裁状态 (对齐 animaku usePlaybackStats 核心规范)
  double _playSecAccumulated = 0.0;
  bool _isValidPlayReported = false;
  double _lastPlayTick = 0.0;
  int _lastSaveTimeMs = 0;

  int get _currentCanonicalEp => _activeEpisode ?? 1;

  // Bangumi 官方数据补全
  BangumiItem? _fullBangumiItem;
  List<BangumiEpisode>? _officialEpisodes;
  Map<int, EpisodeOpedSegment> _opedData = {};

  BangumiItem? get _effectiveBangumiItem => _fullBangumiItem ?? widget.bangumiItem;
  int get _effectiveBangumiId => _effectiveBangumiItem?.id ?? widget.bangumiItem?.id ?? 0;
  EpisodeOpedSegment? get _currentOpedSegment => _opedData[_activeEpisode ?? 1];

  BangumiEpisode? get _currentOfficialEpisode {
    final eps = _officialEpisodes;
    if (eps == null || eps.isEmpty) return null;
    final epNum = _currentCanonicalEp;
    return eps.where((e) => e.type == 0 && ((e.ep ?? e.sort).round() == epNum || e.sort.round() == epNum)).firstOrNull ??
        eps.where((e) => (e.ep ?? e.sort).round() == epNum).firstOrNull;
  }

  int get _currentOfficialDurationSeconds =>
      _currentOfficialEpisode?.durationSeconds ?? 0;

  List<SourceEpisode> get _currentEpisodes {
    if (_chapterRoads.isEmpty) return [];
    final idx = _selectedRoadIndex.clamp(0, _chapterRoads.length - 1);
    return _chapterRoads[idx].episodes;
  }

  int get _displayEpisodeCount =>
      _currentSlots.isNotEmpty ? _currentSlots.length : (_currentEpisodes.isNotEmpty ? _currentEpisodes.length : widget.episodeCount);

  /// 使用 PlayableSlotEngine 构建双层对齐的标准槽位列表
  List<PlayableSlot> get _currentSlots {
    return PlayableSlotEngine.buildPlayableSlots(
      episodes: _currentEpisodes,
      officialEpisodes: _officialEpisodes,
    );
  }

  List<String> get _mappedEpisodeTitles {
    final slots = _currentSlots;
    if (slots.isEmpty) return [];
    return slots.map((s) => s.displayTitle).toList();
  }

  List<String> get _roadNames {
    if (_chapterRoads.isEmpty) return const ['默认线路'];
    return _chapterRoads.map((r) => r.name).toList();
  }

  String get _selectedSourceName {
    final item = _sources.firstWhere(
      (s) => s.id == _selectedSourceId,
      orElse: () => _sources.first,
    );
    return item.name;
  }

  /// 多层级备选候选词列表 (供卡片抽屉推荐胶囊使用)
  List<String> get _keywordOptions {
    return SourceKeywordMatcher.buildCandidates(
      defaultTitle: widget.title,
      item: _effectiveBangumiItem,
      sourceId: _selectedSourceId,
    );
  }

  List<String> get _titleRefs {
    return [
      if (_effectiveBangumiItem?.nameCn.isNotEmpty ?? false) _effectiveBangumiItem!.nameCn,
      if (_effectiveBangumiItem?.name.isNotEmpty ?? false) _effectiveBangumiItem!.name,
      widget.title,
      ...(_effectiveBangumiItem?.alias ?? const <String>[]),
    ].map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  late final ValueNotifier<bool> _autoPlayNextNotifier;
  bool _lastPlaybackCompleted = false;

  @override
  void initState() {
    super.initState();
    _autoPlayNextNotifier =
        ValueNotifier<bool>(PlayerPreferencesService.instance.autoPlayNext);
    _activeEpisode = widget.currentEpisode;
    _danmakuController = DanmakuController();
    _danmakuCoordinator = DanmakuSessionCoordinator(
      danmakuController: _danmakuController,
    );
    _playbackController = ZakowayPlaybackController();
    _danmakuBridge = DanmakuPlaybackBridge(
      playbackController: _playbackController,
      danmakuController: _danmakuController,
    );
    _playbackController.core.addListener(_onPlaybackCoreStateChanged);
    _playbackController.timeline.addListener(_onPlaybackTimelineChanged);

    // 预热并同步用户上次持久化的弹幕外观设置与连播偏好
    PlayerPreferencesService.instance.initialize().then((_) {
      if (mounted) {
        _danmakuController.updateSettings(PlayerPreferencesService.instance.danmakuSettings);
        _autoPlayNextNotifier.value = PlayerPreferencesService.instance.autoPlayNext;
      }
    });

    // 初始化并发源探测器
    _aggregator = SourceAggregator();
    _aggregator.addListener(_onAggregatorUpdated);

    // 初始化自适应宽限自动选源仲裁器 (对齐 animaku useAutoSourcePick)
    _autoPicker = AutoSourcePickCoordinator(
      onSwitchSource: (meta, hit) {
        if (!mounted) return;
        _showHudToast('默认源未收录，已为你切换至 ${meta.name}');
        _handleSourceSelected(
          _sources.firstWhere((s) => s.id == meta.id, orElse: () => VideoSourceItem(id: meta.id, name: meta.name, description: '')),
          hit,
        );
      },
      onAllFallbacksFailed: () {
        if (!mounted) return;
        _showHudToast('所有备用源自动检索完毕，请在面板中换词重搜');
        if (_tabController.index != 0) {
          _tabController.animateTo(0);
        }
        if (_desktopRightTabController.index != 0) {
          _desktopRightTabController.animateTo(0);
        }
      },
    );

    // 全新双主 Tab 架构：[ 简介 ] (index: 0) 与 [ 评论 ] (index: 1)，默认聚焦「简介」
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: 0,
    );
    // 桌面端右侧栏双 Tab：[ 选集 ] (index: 0) 与 [ 视频源 ] (index: 1)，默认聚焦「选集」
    _desktopRightTabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: 0,
    );
    _tabController.addListener(() {
      if (_tabController.index == 0) {
        // 用户切换回「简介」Tab，自动同步嗅探状态
        _aggregator.syncAndProbe(
          bangumiId: _effectiveBangumiId,
          defaultTitle: widget.title,
          item: _effectiveBangumiItem,
          activeSourceId: _selectedSourceId,
          isOpen: true,
          autoProbeOnFallback: _defaultSearchEmpty,
          sourceOrder: _sources.map((s) => s.id).toList(),
        );
      }
    });
    _desktopRightTabController.addListener(() {
      if (_desktopRightTabController.index == 1) {
        // 用户切换至「视频源」Tab，激活后台嗅探探测器
        _aggregator.syncAndProbe(
          bangumiId: _effectiveBangumiId,
          defaultTitle: widget.title,
          item: _effectiveBangumiItem,
          activeSourceId: _selectedSourceId,
          isOpen: true,
          autoProbeOnFallback: _defaultSearchEmpty,
          sourceOrder: _sources.map((s) => s.id).toList(),
        );
      }
    });

    if (widget.danmakuItems != null && widget.danmakuItems!.isNotEmpty) {
      _danmakuController.loadItems(widget.danmakuItems!);
    }

    // 异步拉取 Bangumi 权威详情与分集
    _fetchBangumiAuthorityData();

    // 待首帧构建完成后安全启动起播或检索
    // 工业级标准优化：等待路由平滑推入动画（约 350ms）定格完成后，再启动重度视频源网络检索与起播，
    // 保证从点击番剧卡片到播放页滑入屏幕的全程享有 100% 独立主线程算力，彻底消除页面跳转时的第一下掉帧卡顿
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      void startPlaybackFlow() {
        if (!mounted) return;
        // 预先后台初始化持久化绑定服务
        SourceBindingService.instance.initialize().ignore();

        // 若有显式传入的固定 URL 则直接起播
        if (_activeEpisode != null &&
            widget.videoUrl != null &&
            widget.videoUrl!.isNotEmpty) {
          _hasStartedPlayback = true;
          _initPlayback();
        } else {
          // 启动主流程：先查绑定，再查默认源，未命中则后台探测保底源
          _startDefaultSourceSearch(autoPlayFirst: _activeEpisode != null);
        }
      }

      final route = ModalRoute.of(context);
      if (route != null && route.animation != null && !route.animation!.isCompleted) {
        void onAnimationFinished(AnimationStatus status) {
          if (status == AnimationStatus.completed) {
            route.animation?.removeStatusListener(onAnimationFinished);
            startPlaybackFlow();
          }
        }

        route.animation!.addStatusListener(onAnimationFinished);
      } else {
        startPlaybackFlow();
      }
    });
  }

  void _onAggregatorUpdated() {
    if (!mounted) return;
    setState(() {});

    // 驱动自动选源仲裁器判断是否执行 0ms 秒提或 1200ms 宽限切换
    _autoPicker.update(
      bangumiId: _effectiveBangumiId,
      enabled: _defaultSearchEmpty && _chapterRoads.isEmpty,
      sources: _aggregator.states,
      inFlightSources: _aggregator.inFlightSources,
      sourceOrder: _sources.map((s) => s.id).toList(),
      allFallbacksExhausted: _aggregator.allFallbacksExhausted,
    );
  }

  void _showHudToast(String message, {Duration duration = const Duration(milliseconds: 2200)}) {
    _hudToastTimer?.cancel();
    setState(() => _hudToast = message);
    _hudToastTimer = Timer(duration, () {
      if (mounted) {
        setState(() => _hudToast = null);
      }
    });
  }

  void _seekToPercent(double percent) {
    final total = _playbackController.timeline.value.duration;
    if (total <= Duration.zero) return;
    final targetMs = (total.inMilliseconds * percent).round();
    _playbackController.seek(Duration(milliseconds: targetMs));
    _showHudToast('跳转至 ${(percent * 100).toInt()}%');
  }

  void _resetPlaybackStats() {
    _playSecAccumulated = 0.0;
    _isValidPlayReported = false;
    _lastPlayTick = 0.0;
    _lastSaveTimeMs = 0;
  }

  /// 计算初始断点续播时间点并加入片尾与极短播放防卡死保护
  /// 特殊处理说明：
  /// 对齐 animaku usePlaybackResume 规范，若目标续播进度已处于视频终点附近（>= 95% 或 距离末尾不足 15s），
  /// 判定为该集已完整看毕，强制重置为 0 从头开播，彻底杜绝“重新点开已看剧集立刻触发片尾/被连播切走”的死循环陷阱；
  /// 若记录进度不足 15s 同样从 0 开播，避免 1~2 秒偶发抖动。
  Duration? _resolveInitialResumePosition(int canonicalEp) {
    Duration? target;
    if (widget.initialPosition != null && canonicalEp == widget.currentEpisode) {
      target = widget.initialPosition;
    } else if (_effectiveBangumiId > 0) {
      final historyId = WatchHistoryItem.buildId(_effectiveBangumiId, canonicalEp);
      final match = WatchHistoryService.instance.items.where((e) => e.id == historyId).firstOrNull;
      if (match != null && match.position > 0) {
        final d = match.duration;
        final p = match.position;
        if ((d > 30 && (p >= d - 15 || p / d >= 0.95)) || p < 15) {
          return null;
        }
        target = Duration(milliseconds: (p * 1000).round());
      }
    }

    if (target != null && target.inSeconds < 15) {
      return null;
    }
    return target;
  }

  /// 将当前播放进度正式落盘并广播至首页追番货架与历史记录页
  void _saveCurrentProgress(double position, double duration) {
    if (_effectiveBangumiId <= 0 || position <= 0 || !position.isFinite) return;

    final ep = _currentCanonicalEp;
    final effectiveTitle = (_effectiveBangumiItem?.nameCn.isNotEmpty ?? false)
        ? _effectiveBangumiItem!.nameCn
        : (_effectiveBangumiItem?.name ?? widget.title);

    // 提取并清洗有效题材标签，供推荐系统生成偏好词频画像
    final rawTags = (_fullBangumiItem?.tags.isNotEmpty ?? false)
        ? _fullBangumiItem!.tags
        : (widget.bangumiItem?.tags ?? const <BangumiTag>[]);
    final extractedGenres = rawTags
        .map((t) => t.name.trim())
        .where((t) => AnimeTagFilter.isAllowedGenre(t))
        .toSet()
        .toList();

    // 容灾处理：若当前拉取的条目尚未填充标签，优先复用同番剧已有历史中记录的有效标签
    final existingGenres = WatchHistoryService.instance.items
        .where((e) => e.bangumiId == _effectiveBangumiId && e.genres.isNotEmpty)
        .firstOrNull
        ?.genres;
    final finalGenres = extractedGenres.isNotEmpty
        ? extractedGenres
        : (existingGenres ?? const <String>[]);

    final item = WatchHistoryItem(
      id: WatchHistoryItem.buildId(_effectiveBangumiId, ep),
      bangumiId: _effectiveBangumiId,
      title: effectiveTitle,
      cover: _resolvedCoverUrl,
      episode: ep,
      road: _selectedRoadIndex,
      pluginName: _selectedSourceId,
      pageUrl: _currentPlayingPageUrl ?? '',
      position: position,
      duration: duration > 0 ? duration : 1440.0,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      genres: finalGenres,
    );

    WatchHistoryService.instance.recordProgress(item).ignore();
  }

  /// 页面销毁或返回退出时的安全落盘保护
  /// 特殊处理说明：
  /// 严禁任何起播秒退都无脑写入历史记录！
  /// 仅当达到 15 秒有效播放门槛或进度已达到 85% 完播兜底门槛时才执行保存，
  /// 杜绝用户仅进入页面挑源 1~2 秒就退出时在历史列表中产生大量 0 秒垃圾记录。
  void _saveProgressOnExit() {
    if (_effectiveBangumiId <= 0) return;
    final t = _playbackController.timeline.value.position.inMilliseconds / 1000.0;
    final d = _playbackController.timeline.value.duration.inMilliseconds / 1000.0;
    if (t > 0 && (_isValidPlayReported || (d > 30 && t / d >= 0.85))) {
      _saveCurrentProgress(t, d);
    }
  }

  /// 高频播放时间线监听（media_kit 250ms 节流触发）：
  /// 1. 15 秒自然有效播放累加（Anti-Bounce 门槛）；
  /// 2. 85% 实时完播兜底标记已看；
  /// 3. 达到 15 秒后每 10 秒周期性节流同步最新进度至 WatchHistoryService。
  void _onPlaybackTimelineChanged() {
    final t = _playbackController.timeline.value.position.inMilliseconds / 1000.0;
    final d = _playbackController.timeline.value.duration.inMilliseconds / 1000.0;
    final core = _playbackController.core.value;
    final isPlaying = core.playing && !core.buffering && !core.loading && core.firstFrameRendered;

    if (t < 0 || !t.isFinite) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. 累加实际自然有效播放时长并在满 15s 时标记已看并首次正式写入观看历史
    if (!_isValidPlayReported && _effectiveBangumiId > 0 && isPlaying) {
      final lastTick = _lastPlayTick > 0 ? _lastPlayTick : t;
      final tickDelta = t - lastTick;
      // 严禁在拖拽或非正常时间跳变时累加；仅自然递增 0 < tickDelta <= 2.5s 时累加
      if (tickDelta > 0 && tickDelta <= 2.5) {
        _playSecAccumulated += tickDelta;
        if (_playSecAccumulated >= 15.0) {
          _isValidPlayReported = true;
          final canonicalEp = _currentCanonicalEp;
          WatchedEpisodesService.instance.markWatched(_effectiveBangumiId, canonicalEp);
          _lastSaveTimeMs = now;
          _saveCurrentProgress(t, d);
        }
      }
    }
    _lastPlayTick = t;

    // 2. 完播兜底：单集播放接近末尾（d > 30 且 t / d >= 0.85）自动记录已看（纯客户端标记）
    if (_effectiveBangumiId > 0 && d > 30 && t / d >= 0.85) {
      final canonicalEp = _currentCanonicalEp;
      WatchedEpisodesService.instance.markWatched(_effectiveBangumiId, canonicalEp);
    }

    // 3. 周期保存历史进度：仅在达到有效播放门槛（满 15s）后，每 10s 同步一次最新进度
    if (_isValidPlayReported && now - _lastSaveTimeMs >= 10000) {
      _lastSaveTimeMs = now;
      _saveCurrentProgress(t, d);
    }
  }

  Future<void> _initPlayback() async {
    if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) {
      _resetPlaybackStats();
      _loadDanmakuForCurrentEpisode();
      final start = _resolveInitialResumePosition(_currentCanonicalEp);
      await _playbackController.open(
        widget.videoUrl!,
        httpHeaders: widget.httpHeaders,
        start: start,
      );
    }
  }

  void _loadDanmakuForCurrentEpisode() {
    final ep = _activeEpisode ?? 1;
    final effectiveTitle = (_effectiveBangumiItem?.nameCn.isNotEmpty ?? false)
        ? _effectiveBangumiItem!.nameCn
        : (_effectiveBangumiItem?.name ?? widget.title);

    _danmakuCoordinator.autoMatchAndLoad(
      bangumiId: _effectiveBangumiId,
      episode: ep,
      title: effectiveTitle,
      pluginName: _selectedSourceId,
      titleAliases: _titleRefs,
    ).ignore();
  }

  /// 异步补全 Bangumi 官方数据 (用于弹幕检索与选集映射)
  Future<void> _fetchBangumiAuthorityData() async {
    final bId = widget.bangumiItem?.id;
    if (bId == null || bId <= 0) {
      if (mounted) setState(() => _isLoadingAuthorityDetails = false);
      return;
    }

    try {
      final client = BangumiClient();
      // 1. 优先并发拉取 subject，获取到简介与标签后即时挂载，毫秒级响应
      final subjectFuture = client.getSubject(bId);
      final epsFuture = client.getEpisodes(bId);
      final opedFuture = BangumiOpedService.instance.getOpedData(bId);

      subjectFuture.then((subject) {
        if (mounted) {
          setState(() {
            _fullBangumiItem = subject;
            _isLoadingAuthorityDetails = false;
          });
        }
      }).catchError((_) {
        if (mounted) {
          setState(() => _isLoadingAuthorityDetails = false);
        }
      });

      // 2. 官方分集与 OP/ED 数据后台并行填充
      final results = await Future.wait([
        epsFuture.catchError((_) => <BangumiEpisode>[]),
        opedFuture.catchError((_) => <int, EpisodeOpedSegment>{}),
      ]);

      if (mounted) {
        setState(() {
          _officialEpisodes = results[0] as List<BangumiEpisode>;
          _opedData = results[1] as Map<int, EpisodeOpedSegment>;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingAuthorityDetails = false);
      }
    }
  }

  /// 启动主检索流程：
  /// Step 1: 检查持久化绑定 (SourceBindingService) -> 若存在直接 0ms 秒开；
  /// Step 2: 绑定不存在时向默认源发起精准检索 -> 若命中 (score >= 0.55) 则建立绑定并起播；
  /// Step 3: 若默认源未收录 -> 标记 defaultSearchEmpty，后台静默并发探测保底源，由 AutoSourcePickCoordinator 仲裁。
  Future<void> _startDefaultSourceSearch({bool autoPlayFirst = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingChapters = true;
      _resolveError = null;
      _sourceNotice = null;
    });

    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        setState(() {
          _chapterRoads = [
            SourceChapterRoad(
              name: '默认线路',
              episodes: List.generate(
                widget.episodeCount,
                (i) => SourceEpisode(name: '第 ${i + 1} 话', url: 'https://test/ep${i + 1}'),
              ),
            )
          ];
          _isLoadingChapters = false;
        });
        return;
      }

      await SourceBundleManager.instance.initialize();
      final runtime = SourceBundleManager.instance.runtime;
      final bangumiId = _effectiveBangumiId;

      // ==========================================
      // Step 1: 优先检查历史持久化绑定 (0ms 直开)
      // ==========================================
      final binding = SourceBindingService.instance.getBinding(bangumiId, _selectedSourceId);
      if (binding != null && binding.sourceUrl.isNotEmpty) {
        try {
          final roads = await runtime.chapters(_selectedSourceId, binding.sourceUrl);
          if (roads.isNotEmpty && roads.any((r) => r.episodes.isNotEmpty)) {
            if (!mounted) return;
            setState(() {
              _chapterRoads = roads;
              _selectedRoadIndex = 0;
              _isLoadingChapters = false;
              _defaultSearchEmpty = false;
            });

            if (autoPlayFirst && _currentEpisodes.isNotEmpty) {
              _selectEpisode(_activeEpisode ?? 1);
            } else if (_currentEpisodes.isNotEmpty) {
              runtime.resolve(_selectedSourceId, _currentEpisodes.first.url).ignore();
            }
            return;
          }
        } catch (_) {
          // 绑定失效 (如源站下架/URL变更)，自动移除失效绑定并平滑降级至 Step 2
          await SourceBindingService.instance.removeBinding(bangumiId, _selectedSourceId);
        }
      }

      // ==========================================
      // Step 2: 默认源单关键词精准检索
      // ==========================================
      final primaryKw = SourceKeywordMatcher.resolveDefaultKeyword(
        defaultTitle: widget.title,
        item: _effectiveBangumiItem,
        sourceId: _selectedSourceId,
      );

      SourceSearchResult? bestHit;
      if (primaryKw.isNotEmpty) {
        final rawHits = await runtime.search(_selectedSourceId, primaryKw);
        final ranked = SourceKeywordMatcher.rankSearchHits(rawHits, _titleRefs);
        if (ranked.isNotEmpty) {
          final score = SourceKeywordMatcher.bestSimilarity(ranked.first.name, _titleRefs);
          if (score >= SourceAggregator.autoPickMinSimilarity) {
            bestHit = ranked.first;
          }
        }
      }

      // 回退尝试中文备用名检索
      if (bestHit == null) {
        final fallbackKw = (_effectiveBangumiItem?.nameCn.isNotEmpty ?? false)
            ? _effectiveBangumiItem!.nameCn
            : widget.title;
        if (fallbackKw.isNotEmpty && fallbackKw != primaryKw) {
          final rawHits = await runtime.search(_selectedSourceId, fallbackKw);
          final ranked = SourceKeywordMatcher.rankSearchHits(rawHits, _titleRefs);
          if (ranked.isNotEmpty) {
            final score = SourceKeywordMatcher.bestSimilarity(ranked.first.name, _titleRefs);
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
          if (!mounted) return;
          setState(() {
            _chapterRoads = roads;
            _selectedRoadIndex = 0;
            _isLoadingChapters = false;
            _defaultSearchEmpty = false;
          });

          // 记录持久化绑定，供下次瞬间 0ms 起播
          await SourceBindingService.instance.setBinding(
            bangumiId: bangumiId,
            sourceId: _selectedSourceId,
            sourceUrl: bestHit.url,
            title: bestHit.name,
            referenceTitles: _titleRefs,
          );

          if (autoPlayFirst && _currentEpisodes.isNotEmpty) {
            _selectEpisode(_activeEpisode ?? 1);
          } else if (_currentEpisodes.isNotEmpty) {
            runtime.resolve(_selectedSourceId, _currentEpisodes.first.url).ignore();
          }
          return;
        }
      }

      // ==========================================
      // Step 3: 默认源未收录 -> 启动后台并发保底探测
      // ==========================================
      if (!mounted) return;
      setState(() {
        _isLoadingChapters = false;
        _chapterRoads = [];
        _defaultSearchEmpty = true;
        _sourceNotice = '默认源未收录《${widget.title}》，已为你并发检索备用播放源';
      });

      // 启动后台探测器 (严格限制前 6 个源，3 并发，5s 超时)
      _aggregator.syncAndProbe(
        bangumiId: bangumiId,
        defaultTitle: widget.title,
        item: _effectiveBangumiItem,
        activeSourceId: _selectedSourceId,
        isOpen: true,
        autoProbeOnFallback: true,
        sourceOrder: _sources.map((s) => s.id).toList(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingChapters = false;
        _resolveError = cleanErrorMessage(e, prefix: '检索异常');
      });
    }
  }

  /// 用户或仲裁器选择某视频源及条目 (切源并提取真实分集)
  Future<void> _handleSourceSelected(
    VideoSourceItem src, [
    SourceSearchResult? directHit,
    List<SourceChapterRoad>? cachedRoads,
  ]) async {
    _autoPicker.onUserAction();

    // 0ms 秒级直开：若探测器中已预先验活并缓存了分集线路，直接采纳，彻底杜绝“切过去又开始检索然后报错”
    if (cachedRoads != null &&
        cachedRoads.isNotEmpty &&
        cachedRoads.any((r) => r.episodes.isNotEmpty)) {
      setState(() {
        _selectedSourceId = src.id;
        _chapterRoads = cachedRoads;
        _selectedRoadIndex = 0;
        _isLoadingChapters = false;
        _resolveError = null;
        _sourceNotice = null;
        _defaultSearchEmpty = false;
      });

      if (_tabController.index != 0) {
        _tabController.animateTo(0);
      }
      if (_desktopRightTabController.index != 0) {
        _desktopRightTabController.animateTo(0);
      }

      if (directHit != null && _effectiveBangumiId > 0) {
        SourceBindingService.instance.setBinding(
          bangumiId: _effectiveBangumiId,
          sourceId: src.id,
          sourceUrl: directHit.url,
          title: directHit.name,
          referenceTitles: _titleRefs,
        ).ignore();
      }

      if (_hasStartedPlayback && _currentSlots.isNotEmpty) {
        _selectEpisode(_activeEpisode ?? 1);
      }
      return;
    }

    setState(() {
      _selectedSourceId = src.id;
      _chapterRoads = [];
      _selectedRoadIndex = 0;
      _isLoadingChapters = true;
      _resolveError = null;
      _sourceNotice = null;
      _playbackController.pause();
    });

    // 确保聚焦在「简介」Tab (选集舱所在页面) 与桌面端「选集」Tab
    if (_tabController.index != 0) {
      _tabController.animateTo(0);
    }
    if (_desktopRightTabController.index != 0) {
      _desktopRightTabController.animateTo(0);
    }

    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        setState(() {
          _chapterRoads = [
            SourceChapterRoad(
              name: '默认线路',
              episodes: List.generate(
                widget.episodeCount,
                (i) => SourceEpisode(name: '第 ${i + 1} 话', url: 'https://test/ep${i + 1}'),
              ),
            )
          ];
          _isLoadingChapters = false;
        });
        return;
      }

      final runtime = SourceBundleManager.instance.runtime;
      final bangumiId = _effectiveBangumiId;

      String? targetUrl = directHit?.url;
      String? targetTitle = directHit?.name;

      // 检查探测器是否已有就绪条目
      if (targetUrl == null) {
        final probeState = _aggregator.states[src.id];
        if (probeState?.matchedHit != null) {
          targetUrl = probeState!.matchedHit!.url;
          targetTitle = probeState.matchedHit!.name;
        }
      }

      // 检查持久化绑定
      if (targetUrl == null) {
        final binding = SourceBindingService.instance.getBinding(bangumiId, src.id);
        if (binding != null && binding.sourceUrl.isNotEmpty) {
          targetUrl = binding.sourceUrl;
          targetTitle = binding.title;
        }
      }

      // 若均无现成链接，发起单源搜索
      if (targetUrl == null) {
        final primaryKw = SourceKeywordMatcher.resolveDefaultKeyword(
          defaultTitle: widget.title,
          item: _effectiveBangumiItem,
          sourceId: src.id,
        );

        if (primaryKw.isNotEmpty) {
          final hits = await runtime.search(src.id, primaryKw);
          final ranked = SourceKeywordMatcher.rankSearchHits(hits, _titleRefs);
          if (ranked.isNotEmpty) {
            targetUrl = ranked.first.url;
            targetTitle = ranked.first.name;
          }
        }

        if (targetUrl == null) {
          final fallbackKw = (_effectiveBangumiItem?.nameCn.isNotEmpty ?? false)
              ? _effectiveBangumiItem!.nameCn
              : widget.title;
          if (fallbackKw.isNotEmpty && fallbackKw != primaryKw) {
            final hits = await runtime.search(src.id, fallbackKw);
            final ranked = SourceKeywordMatcher.rankSearchHits(hits, _titleRefs);
            if (ranked.isNotEmpty) {
              targetUrl = ranked.first.url;
              targetTitle = ranked.first.name;
            }
          }
        }
      }

      if (targetUrl == null) {
        throw Exception('在「${src.name}」未检索到《${widget.title}》，请在面板中展开换词');
      }

      final roads = await runtime.chapters(src.id, targetUrl);
      if (roads.isEmpty || roads.every((r) => r.episodes.isEmpty)) {
        throw Exception('未能从「${src.name}」解析到有效分集');
      }

      if (!mounted) return;
      setState(() {
        _chapterRoads = roads;
        _selectedRoadIndex = 0;
        _isLoadingChapters = false;
        _defaultSearchEmpty = false;
      });

      // 写入持久化绑定
      if (targetTitle != null && targetUrl.isNotEmpty) {
        await SourceBindingService.instance.setBinding(
          bangumiId: bangumiId,
          sourceId: src.id,
          sourceUrl: targetUrl,
          title: targetTitle,
          referenceTitles: _titleRefs,
        );
      }

      // 若之前处于在播态，换源后自动无缝续播当前集数
      if (_hasStartedPlayback && _currentEpisodes.isNotEmpty) {
        _selectEpisode(_activeEpisode ?? 1);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingChapters = false;
        _resolveError = cleanErrorMessage(e, prefix: '分集同步失败');
      });
    }
  }

  /// 通过 PlayableSlot 起播 (严格按照 Bangumi 映射对应真实媒体地址，彻底杜绝 PV/花絮错位)
  Future<void> _selectSlot(PlayableSlot slot) async {
    _autoPicker.onUserAction();

    setState(() {
      _activeEpisode = slot.canonicalEp;
      _currentPlayingPageUrl = slot.pageUrl;
      _hasStartedPlayback = true;
      _playingRoadIndex = _selectedRoadIndex;
      _playingSourceId = _selectedSourceId;
      _resolveError = null;
    });

    _resetPlaybackStats();
    widget.onEpisodeSelected?.call(slot.canonicalEp);
    _loadDanmakuForCurrentEpisode();

    final startPos = _resolveInitialResumePosition(slot.canonicalEp);

    // 1. 若有预置直接流地址 (或单测环境测试流)
    if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) {
      await _playbackController.open(
        widget.videoUrl!,
        httpHeaders: widget.httpHeaders,
        start: startPos,
      );
      return;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      await _playbackController.open(slot.pageUrl, start: startPos);
      return;
    }

    // 2. 否则通过当前视频源解析真实直链
    try {
      final runtime = SourceBundleManager.instance.runtime;
      final result = await runtime.resolve(_selectedSourceId, slot.pageUrl);

      if (result.url.isEmpty) {
        throw Exception('视频源未能生成有效媒体地址');
      }

      await _playbackController.open(
        result.url,
        httpHeaders: result.headers,
        start: startPos,
      );

      // 后台静默预热下一集
      final slots = _currentSlots;
      final currentIdx = slots.indexOf(slot);
      if (currentIdx != -1 && currentIdx + 1 < slots.length) {
        runtime.resolve(_selectedSourceId, slots[currentIdx + 1].pageUrl).ignore();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolveError = cleanErrorMessage(e, prefix: '播放解析失败');
      });
    }
  }

  /// 用户点击选集起播 (严格对应视频源真实分集，mapping 通过 index 互相链接)
  Future<void> _selectEpisode(int ep) async {
    final slots = _currentSlots;
    if (slots.isNotEmpty) {
      final targetSlot = slots.firstWhere(
        (s) => s.canonicalEp == ep,
        orElse: () => (ep - 1 >= 0 && ep - 1 < slots.length) ? slots[ep - 1] : slots.first,
      );
      await _selectSlot(targetSlot);
      return;
    }

    _autoPicker.onUserAction();

    final episodes = _currentEpisodes;
    if (episodes.isEmpty || ep < 1 || ep > episodes.length) {
      return;
    }

    final epIndex = ep - 1;
    final targetEp = episodes[epIndex];

    // mapping 是通过 index 互相链接的 (官方集数用于弹幕和历史进度)
    final int mappedOfficialEp = (_officialEpisodes != null &&
            epIndex < _officialEpisodes!.length &&
            _officialEpisodes![epIndex].sort > 0)
        ? _officialEpisodes![epIndex].sort.toInt()
        : ep;

    setState(() {
      _activeEpisode = ep;
      _currentPlayingPageUrl = targetEp.url;
      _hasStartedPlayback = true;
      _playingRoadIndex = _selectedRoadIndex;
      _playingSourceId = _selectedSourceId;
      _resolveError = null;
    });

    _resetPlaybackStats();
    widget.onEpisodeSelected?.call(mappedOfficialEp);
    final startPos = _resolveInitialResumePosition(mappedOfficialEp);

    // 1. 若有预置直接流地址 (或单测环境测试流)
    if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) {
      await _playbackController.open(
        widget.videoUrl!,
        httpHeaders: widget.httpHeaders,
        start: startPos,
      );
      return;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      await _playbackController.open(targetEp.url, start: startPos);
      return;
    }

    // 2. 否则通过当前视频源解析真实直链
    try {
      final runtime = SourceBundleManager.instance.runtime;
      final result = await runtime.resolve(_selectedSourceId, targetEp.url);

      if (result.url.isEmpty) {
        throw Exception('视频源未能生成有效媒体地址');
      }

      await _playbackController.open(
        result.url,
        httpHeaders: result.headers,
        start: startPos,
      );

      // 后台静默预热下一集播放直链
      if (epIndex + 1 < episodes.length) {
        runtime.resolve(_selectedSourceId, episodes[epIndex + 1].url).ignore();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _resolveError = cleanErrorMessage(e, prefix: '播放解析失败');
      });
    }
  }

  void _onPlaybackCoreStateChanged() {
    final core = _playbackController.core.value;
    final isCompleted = core.completed;

    // 暂停时保存：仅在已满 15 秒且视频时长有效时保存
    if (!core.playing && _isValidPlayReported) {
      final t = _playbackController.timeline.value.position.inMilliseconds / 1000.0;
      final d = _playbackController.timeline.value.duration.inMilliseconds / 1000.0;
      if (d > 0 && t > 0) {
        _saveCurrentProgress(t, d);
      }
    }

    if (isCompleted != _lastPlaybackCompleted) {
      _lastPlaybackCompleted = isCompleted;
      if (isCompleted) {
        // 完播（ended）时无条件标记已看
        if (_effectiveBangumiId > 0) {
          WatchedEpisodesService.instance.markWatched(_effectiveBangumiId, _currentCanonicalEp);
        }
        final d = _playbackController.timeline.value.duration.inMilliseconds / 1000.0;
        if (d > 0) {
          _saveCurrentProgress(d, d);
        }

        if (_autoPlayNextNotifier.value) {
          final slots = _currentSlots;
          final maxCount = slots.isNotEmpty ? slots.length : _currentEpisodes.length;
          if (_activeEpisode != null && _activeEpisode! < maxCount) {
            final nextEp = _activeEpisode! + 1;
            _showHudToast('本集播放完毕，即将自动播放第 $nextEp 话');
            _selectEpisode(nextEp);
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _hudToastTimer?.cancel();
    _danmakuBridge.dispose();
    _saveProgressOnExit();
    if (_isTrueFullscreen) {
      _exitTrueFullscreen();
    } else if (_isAppFullscreen) {
      _exitAppFullscreen();
    }
    _tabController.dispose();
    _desktopRightTabController.dispose();
    _playbackController.timeline.removeListener(_onPlaybackTimelineChanged);
    _playbackController.core.removeListener(_onPlaybackCoreStateChanged);
    _playbackController.dispose();
    _autoPlayNextNotifier.dispose();
    _danmakuCoordinator.dispose();
    _danmakuController.dispose();
    _aggregator.removeListener(_onAggregatorUpdated);
    _aggregator.dispose();
    _autoPicker.dispose();
    super.dispose();
  }

  Future<void> _enterAppFullscreen() async {
    if (_isTrueFullscreen) {
      if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        try {
          await defaultExitNativeFullscreen();
        } catch (_) {}
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }
    }
    setState(() {
      _isAppFullscreen = true;
      _isTrueFullscreen = false;
    });
  }

  Future<void> _exitAppFullscreen() async {
    if (_isTrueFullscreen) {
      await _exitTrueFullscreen();
      return;
    }
    setState(() {
      _isAppFullscreen = false;
      _isSidePanelOpen = false;
    });
  }

  void _toggleAppFullscreen() {
    if (_isTrueFullscreen) {
      // 若处于真全屏，点击应用全屏按钮表示降级切换至应用窗口全屏
      _enterAppFullscreen();
    } else if (_isAppFullscreen) {
      _exitAppFullscreen();
    } else {
      _enterAppFullscreen();
    }
  }

  Future<void> _enterTrueFullscreen() async {
    setState(() {
      _isTrueFullscreen = true;
      _isAppFullscreen = false;
    });
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        await defaultEnterNativeFullscreen();
      } catch (_) {}
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  Future<void> _exitTrueFullscreen() async {
    setState(() {
      _isTrueFullscreen = false;
      _isAppFullscreen = false;
      _isSidePanelOpen = false;
    });
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        await defaultExitNativeFullscreen();
      } catch (_) {}
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }

  void _toggleTrueFullscreen() {
    if (_isTrueFullscreen) {
      _exitTrueFullscreen();
    } else {
      _enterTrueFullscreen();
    }
  }

  void _exitFullscreen() {
    if (_isTrueFullscreen) {
      _exitTrueFullscreen();
    } else if (_isAppFullscreen) {
      _exitAppFullscreen();
    }
  }

  void _toggleFullscreen() =>
      _isFullscreen ? _exitFullscreen() : _enterTrueFullscreen();

  void _handleBackPressed() {
    if (_isSidePanelOpen) {
      setState(() => _isSidePanelOpen = false);
      return;
    }
    if (_isTrueFullscreen) {
      _exitTrueFullscreen();
      return;
    }
    if (_isAppFullscreen) {
      _exitAppFullscreen();
      return;
    }
    // 进度统一由 dispose 落盘（系统返回键 / 手势返回也走这条路径），这里不再重复写入：
    // 否则点击返回的瞬间会多触发一次历史落盘 + 全局 notifyListeners，让首页在退场动画期间重建。
    _playbackController.pause();
    // 仅静音底层播放器，避免退场动画期间还有声音。
    // 不能用 setVolume(0.0)：它会把 0 写进用户音量偏好，导致下次起播被静音。
    _playbackController.muteForExit();
    Navigator.of(context).maybePop();
  }

  String get _resolvedCoverUrl => (widget.coverUrl?.isNotEmpty ?? false)
      ? widget.coverUrl!
      : (_effectiveBangumiItem?.coverUrl ?? '');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !_isFullscreen && !_isSidePanelOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          if (_isSidePanelOpen) {
            setState(() => _isSidePanelOpen = false);
          } else if (_isFullscreen) {
            _exitFullscreen();
          }
        }
      },
      child: Focus(
        autofocus: true,
        canRequestFocus: true,
        onKeyEvent: (node, event) {
          // 特殊处理说明：桌面端页面级播放快捷键全局兜底守护
          // 原因：Flutter 的 KeyEvent 是从当前拥有焦点的节点沿父节点链单向向上冒泡，绝不向下分发。
          // 当用户点击右侧选集网格、线路 Tab 或页面空白处时，主焦点会离开播放器内部组件。
          // 若此处不兜底，所有媒体快捷键将彻底失灵。
          // 规则：只要当前用户未聚焦在输入框（EditableText 打字态），所有核心媒体快捷键一律安全路由至控制器。
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }

          final primaryWidget =
              FocusManager.instance.primaryFocus?.context?.widget;
          if (primaryWidget is EditableText) {
            return KeyEventResult.ignored;
          }

          final key = event.logicalKey;

          // 1. Esc 优先分级退出（全屏退出全屏，常规窗口返回上一页）
          if (key == LogicalKeyboardKey.escape) {
            _handleBackPressed();
            return KeyEventResult.handled;
          }

          // 未起播占位态下，不劫持播放控制键
          if (!_hasStartedPlayback) {
            return KeyEventResult.ignored;
          }

          // 2. 播放 / 暂停 (Space / K)
          if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
            _playbackController.togglePlay();
            return KeyEventResult.handled;
          }

          // 3. 快退 / 快进 (左右方向键 5秒，J / L 10秒)
          if (key == LogicalKeyboardKey.arrowLeft) {
            _playbackController.seekBy(const Duration(seconds: -5));
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowRight) {
            _playbackController.seekBy(const Duration(seconds: 5));
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.keyJ) {
            _playbackController.seekBy(const Duration(seconds: -10));
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.keyL) {
            _playbackController.seekBy(const Duration(seconds: 10));
            return KeyEventResult.handled;
          }

          // 4. 音量调节 (上下方向键)
          if (key == LogicalKeyboardKey.arrowUp) {
            final curVol = _playbackController.core.value.volume;
            final nextVol = (curVol + 0.05).clamp(0.0, 1.0);
            _playbackController.setVolume(nextVol);
            _showHudToast('音量：${(nextVol * 100).round()}%');
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.arrowDown) {
            final curVol = _playbackController.core.value.volume;
            final nextVol = (curVol - 0.05).clamp(0.0, 1.0);
            _playbackController.setVolume(nextVol);
            _showHudToast('音量：${(nextVol * 100).round()}%');
            return KeyEventResult.handled;
          }

          // 5. 静音切换 (M)
          if (key == LogicalKeyboardKey.keyM) {
            _playbackController.toggleMute();
            final isMuted = _playbackController.core.value.muted;
            _showHudToast(isMuted ? '已静音' : '取消静音');
            return KeyEventResult.handled;
          }

          // 6. 全屏切换 (F / Enter)
          if (key == LogicalKeyboardKey.keyF || key == LogicalKeyboardKey.enter) {
            _toggleFullscreen();
            return KeyEventResult.handled;
          }

          // 7. 切集 ([ / ])
          if (key == LogicalKeyboardKey.bracketLeft) {
            if (_activeEpisode != null && _activeEpisode! > 1) {
              _selectEpisode(_activeEpisode! - 1);
              _showHudToast('正在切换至上一集');
            }
            return KeyEventResult.handled;
          }
          if (key == LogicalKeyboardKey.bracketRight) {
            final maxCount = _currentSlots.isNotEmpty
                ? _currentSlots.length
                : _currentEpisodes.length;
            if (_activeEpisode != null && _activeEpisode! < maxCount) {
              _selectEpisode(_activeEpisode! + 1);
              _showHudToast('正在切换至下一集');
            }
            return KeyEventResult.handled;
          }

          // 8. 弹幕状态切换 (D)
          if (key == LogicalKeyboardKey.keyD) {
            final cfg = _danmakuController.settings;
            if (!cfg.enabled) {
              _danmakuController.updateSettings(
                  cfg.copyWith(enabled: true, simplify: false));
              _showHudToast('弹幕：全量开启');
            } else if (!cfg.simplify) {
              _danmakuController.updateSettings(
                  cfg.copyWith(enabled: true, simplify: true));
              _showHudToast('弹幕：智能精简');
            } else {
              _danmakuController.updateSettings(cfg.copyWith(enabled: false));
              _showHudToast('弹幕：已关闭');
            }
            return KeyEventResult.handled;
          }

          // 9. 百分比跳转 (0 ~ 9)
          if (key == LogicalKeyboardKey.digit0) {
            _seekToPercent(0.0);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.digit1) {
            _seekToPercent(0.1);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.digit2) {
            _seekToPercent(0.2);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.digit3) {
            _seekToPercent(0.3);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.digit4) {
            _seekToPercent(0.4);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.digit5) {
            _seekToPercent(0.5);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.digit6) {
            _seekToPercent(0.6);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.digit7) {
            _seekToPercent(0.7);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.digit8) {
            _seekToPercent(0.8);
            return KeyEventResult.handled;
          } else if (key == LogicalKeyboardKey.digit9) {
            _seekToPercent(0.9);
            return KeyEventResult.handled;
          }

          return KeyEventResult.ignored;
        },
        child: Scaffold(
          backgroundColor: _isFullscreen
              ? Colors.black
              : (isDark ? Colors.black : Theme.of(context).scaffoldBackgroundColor),
          body: LayoutBuilder(
            builder: (context, constraints) {
              // 判定双栏并排桌面布局：结合内置平台函数 AppPlatform.isDesktop 与响应式断点
              final isDesktopPlatform = AppPlatform.isDesktop;
              final isWideLayout = (isDesktopPlatform && constraints.maxWidth >= 680) ||
                  (!isDesktopPlatform && constraints.maxWidth >= AppBreakpoints.medium);
              final shouldUseDesktopLayout = isWideLayout && !_isFullscreen;

              if (_isFullscreen) {
                return _buildFullscreenLayout();
              } else if (shouldUseDesktopLayout) {
                return _buildDesktopLayout();
              } else {
                return _buildMobileLayout();
              }
            },
          ),
        ),
      ),
    );
  }

  /// 顶部播放器或未起播海报占位组件
  Widget _buildPlayerOrPlaceholder({required bool isFullscreen, bool? isDesktop}) {
    final effectiveIsDesktop = isDesktop ?? AppPlatform.isDesktop;

    if (!_hasStartedPlayback) {
      return VideoPlayerInitialPlaceholder(
        coverUrl: _resolvedCoverUrl,
        title: widget.title,
        isLoadingChapters: _isLoadingChapters,
        selectedSourceName: _selectedSourceName,
        hasEpisodes: _currentEpisodes.isNotEmpty,
        onBackPressed: _handleBackPressed,
        showBackAndTitle: !effectiveIsDesktop || isFullscreen,
        onPlayPressed: () {
          if (_currentEpisodes.isNotEmpty) {
            _selectEpisode(_activeEpisode ?? 1);
          } else if (!_isLoadingChapters) {
            _startDefaultSourceSearch(autoPlayFirst: true);
          }
        },
      );
    }

    final epTitle = _activeEpisode != null ? ' - 第 $_activeEpisode 话' : '';
    final primaryColor = Theme.of(context).colorScheme.primary;

    return VideoPlayerSurfaceWithControls(
      controller: _playbackController,
      title: '${widget.title}$epTitle',
      danmakuController: _danmakuController,
      danmakuCoordinator: _danmakuCoordinator,
      isFullscreen: isFullscreen,
      isAppFullscreen: _isAppFullscreen,
      isTrueFullscreen: _isTrueFullscreen,
      isDesktop: effectiveIsDesktop,
      onToggleFullscreen: _toggleFullscreen,
      onToggleAppFullscreen: (effectiveIsDesktop || isFullscreen) ? _toggleAppFullscreen : null,
      onToggleTrueFullscreen: (effectiveIsDesktop || isFullscreen) ? _toggleTrueFullscreen : null,
      onBackPressed: _handleBackPressed,
      onOpenEpisodePicker: isFullscreen
          ? () => setState(() {
                _sidePanelInitialTab = PlayerSidePanelTab.episodes;
                _isSidePanelOpen = !_isSidePanelOpen;
              })
          : null,
      onOpenSidePanel: isFullscreen
          ? (tab) => setState(() {
                _sidePanelInitialTab = tab;
                _isSidePanelOpen = true;
              })
          : null,
      onNextEpisode: (_activeEpisode != null &&
              _activeEpisode! < _currentEpisodes.length)
          ? () => _selectEpisode(_activeEpisode! + 1)
          : null,
      onPrevEpisode: (_activeEpisode != null && _activeEpisode! > 1)
          ? () => _selectEpisode(_activeEpisode! - 1)
          : null,
      opedSegment: _currentOpedSegment,
      autoPlayNextNotifier: _autoPlayNextNotifier,
      bangumiId: _effectiveBangumiId,
      canonicalEpisode: _currentCanonicalEp,
      officialDurationSeconds: _currentOfficialDurationSeconds,
      hudToast: _hudToast,
      resolveError: _resolveError,
      primaryColor: primaryColor,
      onRetryResolve: () {
        if (_activeEpisode != null) {
          _selectEpisode(_activeEpisode!);
        } else {
          _startDefaultSourceSearch(autoPlayFirst: true);
        }
      },
      onSwitchSource: () {
        _autoPicker.onUserAction();
        _showFullSourceSheet();
      },
    );
  }

  /// 呼出全功能选集与多视频源看板抽屉
  /// 呼出全功能选集与多视频源看板抽屉
  void _showFullSourceSheet() {
    _autoPicker.onUserAction();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.65 : 0.45),
      builder: (bottomSheetContext) {
        final screenHeight = MediaQuery.of(bottomSheetContext).size.height;
        return GestureDetector(
          // 点击半透明空白背景立即秒关
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(bottomSheetContext).pop(),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              // 阻断内容区点击冒泡
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: SizedBox(
                height: screenHeight * 0.82,
                child: DefaultTabController(
                  length: 2,
                  initialIndex: 1, // 直接定位至视频源看板
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF16161A) : Colors.white,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                          blurRadius: 20,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const SizedBox(height: 10),
                        Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white24 : Colors.black12,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Container(
                                  height: 36,
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: TabBar(
                                    splashFactory: NoSplash.splashFactory,
                                    overlayColor: WidgetStateProperty.all(Colors.transparent),
                                    dividerColor: Colors.transparent,
                                    indicatorSize: TabBarIndicatorSize.tab,
                                    indicator: BoxDecoration(
                                      color: isDark ? Colors.white.withValues(alpha: 0.16) : Colors.white,
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    labelColor: isDark ? Colors.white : Theme.of(context).colorScheme.primary,
                                    unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
                                    labelStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'MiSans',
                                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                                    ),
                                    unselectedLabelStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'MiSans',
                                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                                    ),
                                    tabs: const [
                                      Tab(text: '选集网格'),
                                      Tab(text: '切换视频源'),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () => Navigator.of(bottomSheetContext).pop(),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 12, thickness: 0.5),
                        Expanded(
                          child: TabBarView(
                            children: [
                              EpisodePickerSection(
                                episodeCount: _displayEpisodeCount,
                                currentEpisode: _activeEpisode,
                                slots: _currentSlots,
                                roads: _roadNames,
                                activeRoadIndex: _selectedRoadIndex,
                                playingRoadIndex: _hasStartedPlayback && _selectedSourceId == _playingSourceId ? _playingRoadIndex : null,
                                episodeTitles: _mappedEpisodeTitles,
                                onRoadSelected: (idx) {
                                  if (_selectedRoadIndex == idx) return;
                                  setState(() => _selectedRoadIndex = idx);
                                },
                                onSelectEpisode: (ep) {
                                  _selectEpisode(ep);
                                  Navigator.of(bottomSheetContext).pop();
                                },
                                onSelectSlot: (slot) {
                                  _selectSlot(slot);
                                  Navigator.of(bottomSheetContext).pop();
                                },
                                onRefresh: () => _startDefaultSourceSearch(autoPlayFirst: false),
                              ),
                              VideoSourceView(
                                sources: _sources,
                                selectedSourceId: _selectedSourceId,
                                aggregator: _aggregator,
                                keywordOptions: _keywordOptions,
                                onSourceSelected: (src) {
                                  _handleSourceSelected(src);
                                  Navigator.of(bottomSheetContext).pop();
                                },
                                onSelectHit: (src, hit, [roads]) {
                                  _handleSourceSelected(src, hit, roads);
                                  Navigator.of(bottomSheetContext).pop();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 详情 / 视频源 / 选集 组合分段面板
  Widget _buildTabSection() {
    return Column(
      children: [
        VideoPlaySegmentedTabBar(tabController: _tabController),
        Expanded(
          child: VideoPlayTabContentView(
            tabController: _tabController,
            title: widget.title,
            bangumiItem: _effectiveBangumiItem,
            isLoadingAuthorityDetails: _isLoadingAuthorityDetails,
            coverUrl: _resolvedCoverUrl,
            episodeCount: _displayEpisodeCount,
            sources: _sources,
            selectedSourceId: _selectedSourceId,
            selectedSourceName: _selectedSourceName,
            onSourceSelected: _handleSourceSelected,
            aggregator: _aggregator,
            sourceNotice: _sourceNotice,
            keywordOptions: _keywordOptions,
            onUserAction: _autoPicker.onUserAction,
            currentEpisode: _activeEpisode,
            playingRoadIndex: _hasStartedPlayback && _selectedSourceId == _playingSourceId ? _playingRoadIndex : null,
            isLoadingChapters: _isLoadingChapters,
            resolveError: _resolveError,
            hasEpisodes: _currentEpisodes.isNotEmpty,
            currentSlots: _currentSlots,
            roadNames: _roadNames,
            selectedRoadIndex: _selectedRoadIndex,
            mappedEpisodeTitles: _mappedEpisodeTitles,
            // 切换线路仅更新查看视图与集数列表，绝不自动切换起播，保持当前正在播放的线路和集数不被打断
            onRoadSelected: (idx) {
              if (_selectedRoadIndex == idx) return;
              setState(() => _selectedRoadIndex = idx);
            },
            onRefreshEpisodes: () =>
                _startDefaultSourceSearch(autoPlayFirst: false),
            onSelectEpisode: _selectEpisode,
            onSelectSlot: _selectSlot,
            onTapRecommendItem: (recItem) {
              Navigator.of(context).push(
                AdaptivePageRoute.build<void>(
                  context,
                  builder: (context) => VideoPlayPage(
                    title: recItem.displayName,
                    coverUrl: recItem.cover,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 1. 全屏横屏布局 (带 iOS/Kazumi 风格磨砂悬浮抽屉 PlayerSidePanel)
  Widget _buildFullscreenLayout() {
    return VideoPlayerFullscreenLayout(
      playerWidget: KeyedSubtree(
        key: _playerSubtreeKey,
        child: _buildPlayerOrPlaceholder(isFullscreen: true),
      ),
      sidePanelWidget: PlayerSidePanel(
        isOpen: _isSidePanelOpen,
        initialTab: _sidePanelInitialTab,
        onClose: () => setState(() => _isSidePanelOpen = false),
        bangumiId: _effectiveBangumiId,
        episodeCount: _displayEpisodeCount,
        currentEpisode: _activeEpisode,
        roads: _roadNames,
        activeRoadIndex: _selectedRoadIndex,
        playingRoadIndex: _hasStartedPlayback && _selectedSourceId == _playingSourceId ? _playingRoadIndex : null,
        episodeTitles: _mappedEpisodeTitles,
        slots: _currentSlots,
        isLoadingEpisodes: _isLoadingChapters,
        resolveError: _resolveError,
        onSelectEpisode: (ep) => _selectEpisode(ep),
        onSelectSlot: (slot) => _selectSlot(slot),
        // 切换线路仅更新查看视图与集数列表，绝不自动切换起播
        onRoadSelected: (idx) {
          if (_selectedRoadIndex == idx) return;
          setState(() => _selectedRoadIndex = idx);
        },
        onRefreshEpisodes: () =>
            _startDefaultSourceSearch(autoPlayFirst: false),
        sources: _sources,
        selectedSourceId: _selectedSourceId,
        aggregator: _aggregator,
        onSourceSelected: (src) => _handleSourceSelected(src),
        onSelectHit: (src, hit, [roads]) => _handleSourceSelected(src, hit, roads),
        danmakuController: _danmakuController,
        controller: _playbackController,
      ),
    );
  }

  /// 2. 桌面/宽屏并排布局 (全新分块架构：左栏播放器+简介+评论，右栏视频源展开框+选集+推荐)
  Widget _buildDesktopLayout() {
    return VideoPlayerDesktopLayout(
      title: widget.title,
      currentEpisode: _activeEpisode,
      onBackPressed: _handleBackPressed,
      playerWidget: KeyedSubtree(
        key: _playerSubtreeKey,
        child: _buildPlayerOrPlaceholder(isFullscreen: false, isDesktop: true),
      ),
      introSection: WatchMetaView(
        title: widget.title,
        bangumiItem: _effectiveBangumiItem,
        isLoadingDetails: _isLoadingAuthorityDetails,
        coverUrl: _resolvedCoverUrl,
        episodeCount: _displayEpisodeCount,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
      ),
      commentsSection: WatchCommentsSection(
        bangumiId: _effectiveBangumiId,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
      ),
      rightTabController: _desktopRightTabController,
      episodePickerSection: ListenableBuilder(
        listenable: WatchedEpisodesService.instance,
        builder: (context, _) {
          final watched =
              WatchedEpisodesService.instance.getWatchedEpisodes(_effectiveBangumiId);
          return EpisodePickerSection(
            episodeCount: _displayEpisodeCount,
            currentEpisode: _activeEpisode,
            roads: _roadNames,
            activeRoadIndex: _selectedRoadIndex,
            playingRoadIndex:
                _hasStartedPlayback && _selectedSourceId == _playingSourceId
                    ? _playingRoadIndex
                    : null,
            episodeTitles: _mappedEpisodeTitles,
            slots: _currentSlots,
            watchedEpisodes: watched,
            isLoading: _isLoadingChapters,
            loadingMessage: '正在从「$_selectedSourceName」解析分集...',
            onRoadSelected: (idx) {
              if (_selectedRoadIndex == idx) return;
              setState(() => _selectedRoadIndex = idx);
            },
            onRefresh: () => _startDefaultSourceSearch(autoPlayFirst: false),
            onSelectEpisode: _selectEpisode,
            onSelectSlot: _selectSlot,
            shrinkWrap: true,
          );
        },
      ),
      sourceViewSection: VideoSourceView(
        sources: _sources,
        selectedSourceId: _selectedSourceId,
        onSourceSelected: (src) => _handleSourceSelected(src),
        onSelectHit: (src, hit, [roads]) => _handleSourceSelected(src, hit, roads),
        aggregator: _aggregator,
        hintMessage: _sourceNotice,
        keywordOptions: _keywordOptions,
        onUserAction: _autoPicker.onUserAction,
        currentEpisodeNumber: _activeEpisode,
      ),
      recommendSection: WatchRecommendSection(
        bangumiId: _effectiveBangumiId,
        bangumiItem: _effectiveBangumiItem,
        onTapItem: (recItem) {
          Navigator.of(context).push(
            AdaptivePageRoute.build<void>(
              context,
              builder: (context) => VideoPlayPage(
                title: recItem.displayName,
                coverUrl: recItem.cover,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 3. 移动端竖屏布局 (上方 16:9 + 下方 iOS 风格 3 Tab)
  Widget _buildMobileLayout() {
    return VideoPlayerMobileLayout(
      playerWidget: KeyedSubtree(
        key: _playerSubtreeKey,
        child: _buildPlayerOrPlaceholder(
          isFullscreen: false,
          isDesktop: false, // 手机/窄屏单栏模式下统一进入移动端控制层，方便本地 100% 调测触屏手势、锁屏与 BottomSheet
        ),
      ),
      tabSection: _buildTabSection(),
    );
  }
}
