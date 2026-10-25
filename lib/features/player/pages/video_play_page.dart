import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/models/bangumi/bangumi_episode.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/network/bangumi_client.dart';
import '../../../core/services/app_preferences.dart';
import '../../../core/services/bangumi_oped_service.dart';
import '../../../core/services/watched_episodes_service.dart';
import '../../../core/utils/adaptive_page_route.dart';
import '../../../core/utils/appearance_manager.dart';
import '../../../core/utils/responsive.dart';
import '../controller/playback_controller.dart';
import '../controller/watch_progress_tracker.dart';
import '../core/models/resolved_media.dart';
import '../core/utils/playback_tracer.dart';
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
import '../widgets/desktop/desktop_player_shortcuts.dart';
import '../widgets/mobile/mobile_episode_source_sheet.dart';
import '../widgets/player_side_panel.dart';
import '../widgets/video_player_layouts.dart';
import '../widgets/video_player_placeholder.dart';
import '../widgets/video_player_surface_with_controls.dart';
import '../widgets/video_play_tabs.dart';
import '../widgets/video_source_view.dart';
import '../widgets/watch_comments_section.dart';
import '../widgets/watch_meta_view.dart';
import '../widgets/watch_recommend_section.dart';
import '../../common/widgets/app_desktop_title_bar.dart';

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
    this.preferredSourceId,
    this.initialPageUrl,
    this.initialRoad,
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
  /// 偏好或历史指定的视频源 ID (用于“继续追番”精准直开)
  final String? preferredSourceId;
  /// 历史指定的直链播放页地址
  final String? initialPageUrl;
  /// 历史指定的线路索引
  final int? initialRoad;

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
  late final AppLifecycleListener _lifecycleListener;
  bool _lastWakelockState = false;

  /// 跨布局保活 Key：确保在全屏/桌面/移动端布局切换时复用同一 Element 节点，防止播放器和弹幕被卸载重建
  final GlobalKey _playerSubtreeKey = GlobalKey();

  bool _isAppFullscreen = false;
  bool _isTrueFullscreen = false;
  bool get _isFullscreen => _isAppFullscreen || _isTrueFullscreen;
  bool _isTheaterMode = false;
  bool _isSidePanelOpen = false;
  PlayerSidePanelTab _sidePanelInitialTab = PlayerSidePanelTab.episodes;
  int? _activeEpisode;
  bool _hasStartedPlayback = false;
  int? _playingRoadIndex;
  String? _playingSourceId;
  bool _isLoadingAuthorityDetails = true;

  // 视频源与选集状态
  String _selectedSourceId = 'xifan-next';
  List<VideoSourceItem> get _sources => getDefaultSourceItems();

  bool _isLoadingChapters = false;
  String? _chaptersError;
  String? _playbackError;
  String? _sourceNotice;
  late final ValueNotifier<String?> _hudToastNotifier;
  Timer? _hudToastTimer;
  bool _defaultSearchEmpty = false;

  List<SourceChapterRoad> _chapterRoads = [];
  int _selectedRoadIndex = 0;
  int _episodeResolveToken = 0;
  String? _currentPlayingPageUrl;

  /// 观看历史与播放进度追踪器 (负责 15s 有效门槛、完播仲裁与自动落盘)
  final WatchProgressTracker _progressTracker = WatchProgressTracker();

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
      _currentSlots.isNotEmpty ? _currentSlots.length : _currentEpisodes.length;

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
    _hudToastNotifier = ValueNotifier<String?>(null);
    _autoPlayNextNotifier =
        ValueNotifier<bool>(PlayerPreferencesService.instance.autoPlayNext);
    _activeEpisode = widget.currentEpisode;

    // 特殊处理说明：
    // 切后台自动暂停生命周期监听 (选项 A 规范)：
    // 仅在移动操作系统 (Android / iOS) 触发后台暂停与常亮释放，
    // 桌面端 (Windows / macOS / Linux) 保持窗口最小化或后台出声的原生桌面体验。
    _lifecycleListener = AppLifecycleListener(
      onPause: () {
        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          if (_playbackController.core.value.playing) {
            _playbackController.pause();
            if (_lastWakelockState) {
              _lastWakelockState = false;
              WakelockPlus.disable().ignore();
            }
          }
        }
      },
    );

    // 若通过“继续追番”等入口显式指定了历史源与线路，优先对齐历史上下文
    if (widget.preferredSourceId != null && widget.preferredSourceId!.isNotEmpty) {
      _selectedSourceId = widget.preferredSourceId!;
    }
    if (widget.initialRoad != null && widget.initialRoad! >= 0) {
      _selectedRoadIndex = widget.initialRoad!;
    }
    if (widget.initialPageUrl != null && widget.initialPageUrl!.isNotEmpty) {
      _currentPlayingPageUrl = widget.initialPageUrl;
    }

    _danmakuController = DanmakuController();
    _danmakuCoordinator = DanmakuSessionCoordinator(
      danmakuController: _danmakuController,
    );
    _playbackController = createPlaybackController(
      onResolve: ({required bool bypassCache}) async {
        final curPageUrl = _currentPlayingPageUrl;
        if (curPageUrl != null && curPageUrl.isNotEmpty) {
          final runtime = SourceBundleManager.instance.runtime;
          final res = await runtime.resolve(
            _selectedSourceId,
            curPageUrl,
            bypassCache: bypassCache,
          );
          if (res.url.isNotEmpty) {
            return ResolvedMedia(url: res.url, headers: res.headers);
          }
        }
        return ResolvedMedia(url: _playbackController.currentUri ?? '');
      },
    );
    _danmakuBridge = DanmakuPlaybackBridge(
      playbackController: _playbackController,
      danmakuController: _danmakuController,
    );
    _playbackController.core.addListener(_onPlaybackCoreStateChanged);
    _playbackController.timeline.addListener(_onPlaybackTimelineChanged);
    SourceBundleManager.instance.addListener(_onSourceBundleChanged);
    AppPreferences.serverModeNotifier.addListener(_onServerModeChanged);

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
    // 特殊处理说明：
    // 网络检索、历史持久化绑定提取与分集请求属于纯后台异步 I/O，绝不占用 UI 渲染算力。
    // 在首帧后立即无延迟并发发起检索（抢跑网络 RTT，缩短首帧出画耗时约 350ms）；
    // 仅在拿到直链、准备向底层硬件解码器推送媒体流（_playbackController.open）时，
    // 若路由推入动画未定格才挂起等待，实现“网络并行 + 渲染防掉帧”的最优解。
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
        // 启动主流程：先查番剧级绑定，再查指定偏好/默认源，未命中则后台探测保底源
        _startDefaultSourceSearch(autoPlayFirst: _activeEpisode != null);
      }
    });
  }

  /// 特殊处理说明：
  /// 若转场路由推入动画仍在执行（如 iOS/Android 侧滑 250~350ms），在真正向底层 mpv 播放器
  /// 挂载硬件解码视频纹理（_playbackController.open）前挂起等待动画定格。
  /// 使得网络检索、绑定解析在动画期间 100% 异步并发，而将高开销的硬件纹理挂载平滑移至动画终点，
  /// 既不掉帧，又为首帧出画抢回 300ms+ 网络 RTT。
  Future<void> _waitForRouteAnimationIfNeeded() async {
    final route = ModalRoute.of(context);
    final anim = route?.animation;
    if (anim != null && !anim.isCompleted) {
      final completer = Completer<void>();
      void listener(AnimationStatus status) {
        if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
          anim.removeStatusListener(listener);
          if (!completer.isCompleted) completer.complete();
        }
      }
      anim.addStatusListener(listener);
      await completer.future.timeout(
        const Duration(milliseconds: 450),
        onTimeout: () {
          anim.removeStatusListener(listener);
        },
      );
    }
  }

  /// 统一安全起播辅助方法：确保硬件解码纹理挂载与路由动画安全解耦
  Future<void> _safeOpenPlayback(
    String url, {
    Map<String, String>? httpHeaders,
    Duration? start,
    bool isPreResolved = true,
  }) async {
    await _waitForRouteAnimationIfNeeded();
    if (!mounted) return;
    await _playbackController.open(
      url,
      httpHeaders: httpHeaders,
      start: start,
      isPreResolved: isPreResolved,
    );
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
    _hudToastNotifier.value = message;
    _hudToastTimer = Timer(duration, () {
      _hudToastNotifier.value = null;
    });
  }

  void _seekToPercent(double percent) {
    final total = _playbackController.timeline.value.duration;
    if (total <= Duration.zero) return;
    final targetMs = (total.inMilliseconds * percent).round();
    _playbackController.seek(Duration(milliseconds: targetMs));
    _showHudToast('跳转至 ${(percent * 100).toInt()}%');
  }

  void _resetPlaybackStats() => _progressTracker.reset();

  /// 计算初始断点续播时间点并加入片尾与极短播放防卡死保护
  Duration? _resolveInitialResumePosition(int canonicalEp) {
    return _progressTracker.resolveInitialResumePosition(
      bangumiId: _effectiveBangumiId,
      canonicalEp: canonicalEp,
      initialPosition: widget.initialPosition,
      currentEpisodeParam: widget.currentEpisode,
    );
  }

  /// 将当前播放进度正式落盘并广播至首页追番货架与历史记录页
  void _saveCurrentProgress(double position, double duration) {
    _progressTracker.saveCurrentProgress(
      bangumiId: _effectiveBangumiId,
      canonicalEp: _currentCanonicalEp,
      title: widget.title,
      coverUrl: _resolvedCoverUrl,
      roadIndex: _playingRoadIndex ?? _selectedRoadIndex,
      sourceId: _playingSourceId ?? _selectedSourceId,
      pageUrl: _currentPlayingPageUrl ?? '',
      position: position,
      duration: duration,
      bangumiItem: _effectiveBangumiItem,
      fullBangumiItem: _fullBangumiItem,
    );
  }

  /// 页面销毁或返回退出时的安全落盘保护
  void _saveProgressOnExit() {
    final t = _playbackController.timeline.value.position.inMilliseconds / 1000.0;
    final d = _playbackController.timeline.value.duration.inMilliseconds / 1000.0;
    _progressTracker.saveProgressOnExit(
      bangumiId: _effectiveBangumiId,
      canonicalEp: _currentCanonicalEp,
      title: widget.title,
      coverUrl: _resolvedCoverUrl,
      roadIndex: _playingRoadIndex ?? _selectedRoadIndex,
      sourceId: _playingSourceId ?? _selectedSourceId,
      pageUrl: _currentPlayingPageUrl ?? '',
      position: t,
      duration: d,
      bangumiItem: _effectiveBangumiItem,
      fullBangumiItem: _fullBangumiItem,
    );
  }

  /// 高频播放时间线监听（media_kit 250ms 节流触发）
  void _onPlaybackTimelineChanged() {
    final t = _playbackController.timeline.value.position.inMilliseconds / 1000.0;
    final d = _playbackController.timeline.value.duration.inMilliseconds / 1000.0;
    final core = _playbackController.core.value;
    final isPlaying = core.playing && !core.buffering && !core.loading && core.firstFrameRendered;

    _progressTracker.onTimelineTick(
      positionSeconds: t,
      durationSeconds: d,
      isPlaying: isPlaying,
      bangumiId: _effectiveBangumiId,
      canonicalEp: _currentCanonicalEp,
      title: widget.title,
      coverUrl: _resolvedCoverUrl,
      roadIndex: _playingRoadIndex ?? _selectedRoadIndex,
      sourceId: _playingSourceId ?? _selectedSourceId,
      pageUrl: _currentPlayingPageUrl ?? '',
      slots: _currentSlots,
      bangumiItem: _effectiveBangumiItem,
      fullBangumiItem: _fullBangumiItem,
    );
  }

  Future<void> _initPlayback() async {
    if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) {
      _resetPlaybackStats();
      _loadDanmakuForCurrentEpisode();
      final start = _resolveInitialResumePosition(_currentCanonicalEp);
      await _safeOpenPlayback(
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

    // 特殊处理说明：
    // 起播网络避震：
    // 弹幕匹配与拉取包含跨站 DandanPlay/Bilibili 搜索，
    // 微延迟 350ms 发起，避免与起播瞬间视频流建立 TCP 连接抢占出口带宽
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      _danmakuCoordinator.autoMatchAndLoad(
        bangumiId: _effectiveBangumiId,
        episode: ep,
        title: effectiveTitle,
        pluginName: _selectedSourceId,
        titleAliases: _titleRefs,
      ).ignore();
    });
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
      _chaptersError = null;
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
            PlaybackTracer.instance.current?.markChaptersFetched(
              roadCount: roads.length,
              episodeCount: roads.first.episodes.length,
            );
            setState(() {
              _chapterRoads = roads;
              _selectedRoadIndex = (widget.initialRoad != null &&
                      widget.initialRoad! >= 0 &&
                      widget.initialRoad! < roads.length)
                  ? widget.initialRoad!
                  : 0;
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
          PlaybackTracer.instance.current?.markChaptersFetched(
            roadCount: roads.length,
            episodeCount: roads.first.episodes.length,
          );
          setState(() {
            _chapterRoads = roads;
            _selectedRoadIndex = (widget.initialRoad != null &&
                    widget.initialRoad! >= 0 &&
                    widget.initialRoad! < roads.length)
                ? widget.initialRoad!
                : 0;
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
        _chaptersError = cleanErrorMessage(e, prefix: '检索异常');
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
        _chaptersError = null;
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

      // 特殊处理说明：
      // 依照交互规范（子选项 2），换源操作仅切换分集查看列表与线路视图，
      // 绝不自动打断当前正在播放的视频或自动起播新源；用户在分集列表中点击具体集数时，才真正起播该视频源。
      return;
    }

    setState(() {
      _selectedSourceId = src.id;
      _chapterRoads = [];
      _selectedRoadIndex = 0;
      _isLoadingChapters = true;
      _chaptersError = null;
      _sourceNotice = null;
      // 特殊处理说明：
      // 依照交互规范（子选项 2），切源检索期间保持当前视频无缝播放，不暂停打断当前体验。
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

      // 特殊处理说明：
      // 依照交互规范（子选项 2），换源操作仅切换分集查看列表与线路视图，
      // 绝不自动打断当前正在播放的源与视频；用户在列表中点击具体集数才真正起播该视频源。
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingChapters = false;
        _chaptersError = cleanErrorMessage(e, prefix: '分集同步失败');
      });
    }
  }

  /// 统一单集直链解析与安全起播核心管道 (双轨解耦与 Tracer 接入)
  Future<void> _resolveAndStartPlayback({
    required String pageUrl,
    required int canonicalEp,
    required int sessionToken,
  }) async {
    final tracer = PlaybackTracer.instance.startSession(
      title: widget.title,
      episode: canonicalEp,
      sourceId: _selectedSourceId,
    );

    _resetPlaybackStats();
    widget.onEpisodeSelected?.call(canonicalEp);
    _loadDanmakuForCurrentEpisode();

    final startPos = _resolveInitialResumePosition(canonicalEp);

    // 1. 若有预置直接流地址 (或单测环境测试流)
    if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) {
      tracer.markResolveSuccess(preResolved: true);
      await _safeOpenPlayback(
        widget.videoUrl!,
        httpHeaders: widget.httpHeaders,
        start: startPos,
        isPreResolved: true,
      );
      return;
    }

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      tracer.markResolveSuccess(preResolved: true);
      await _safeOpenPlayback(pageUrl, start: startPos, isPreResolved: true);
      return;
    }

    // 2. 否则通过当前视频源解析真实直链
    try {
      tracer.markResolveStarted();
      final runtime = SourceBundleManager.instance.runtime;
      final result = await runtime.resolve(_selectedSourceId, pageUrl);

      // 若解析期间用户已切换至其他集数或组件已销毁，放弃旧请求响应
      if (sessionToken != _episodeResolveToken || !mounted) return;

      if (result.url.isEmpty) {
        throw Exception('视频源未能生成有效媒体地址');
      }

      tracer.markResolveSuccess(preResolved: true);
      await _safeOpenPlayback(
        result.url,
        httpHeaders: result.headers,
        start: startPos,
        isPreResolved: true,
      );

      // 后台静默预热下一集
      final slots = _currentSlots;
      final currentIdx = slots.indexWhere((s) => s.canonicalEp == canonicalEp);
      if (currentIdx != -1 && currentIdx + 1 < slots.length) {
        runtime.resolve(_selectedSourceId, slots[currentIdx + 1].pageUrl).ignore();
      }
    } catch (e) {
      if (sessionToken != _episodeResolveToken || !mounted) return;
      tracer.markFailure(e.toString());
      setState(() {
        _playbackError = cleanErrorMessage(e, prefix: '播放解析失败');
      });
    }
  }

  /// 用户从槽位列表中点击选集
  Future<void> _selectSlot(PlayableSlot slot) async {
    _autoPicker.onUserAction();

    // 特殊处理说明：
    // 切集瞬时原子归零：
    // 立即停止当前播放并重置画面为加载态（瞬间覆盖清除上一集画面与声音），
    // 并彻底清空上一集弹幕池与控制器，避免第二集起播期间错播上一集弹幕。
    _playbackController.stop().ignore();
    _danmakuCoordinator.clearEpisodeComments();

    final sessionToken = ++_episodeResolveToken;

    setState(() {
      _activeEpisode = slot.canonicalEp;
      _currentPlayingPageUrl = slot.pageUrl;
      _hasStartedPlayback = true;
      _playingRoadIndex = _selectedRoadIndex;
      _playingSourceId = _selectedSourceId;
      _playbackError = null;
      _chaptersError = null;
    });

    await _resolveAndStartPlayback(
      pageUrl: slot.pageUrl,
      canonicalEp: slot.canonicalEp,
      sessionToken: sessionToken,
    );
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
      final runtime = SourceBundleManager.instance.runtime;
      if (!AppPreferences.isServerModeEnabled() && !runtime.isLocalSource(_selectedSourceId)) {
        _showHudToast('当前源依赖服务端模式，无法解析播放，请开启服务端模式或手动换源');
        return;
      }
      _showHudToast('当前视频源暂无可播放分集，请切换线路或视频源');
      return;
    }

    // 立即停止当前播放并重置画面为加载态（瞬间覆盖清除上一集画面与声音），并彻底归零清空上一集弹幕池与控制器
    _playbackController.stop().ignore();
    _danmakuCoordinator.clearEpisodeComments();
    final sessionToken = ++_episodeResolveToken;

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
      _playbackError = null;
      _chaptersError = null;
    });

    await _resolveAndStartPlayback(
      pageUrl: targetEp.url,
      canonicalEp: mappedOfficialEp,
      sessionToken: sessionToken,
    );
  }

  void _onPlaybackCoreStateChanged() {
    final core = _playbackController.core.value;
    final isCompleted = core.completed;

    // 联动屏幕常亮 (Wakelock)：仅在真实播放中开启常亮，暂停/完播/退场时释放
    final isPlaying = core.playing;
    if (isPlaying != _lastWakelockState) {
      _lastWakelockState = isPlaying;
      if (isPlaying) {
        WakelockPlus.enable().ignore();
      } else {
        WakelockPlus.disable().ignore();
      }
    }

    // 暂停时保存：仅在已满 15 秒且视频时长有效时保存
    if (!core.playing && _progressTracker.isValidPlayReported) {
      final t = _playbackController.timeline.value.position.inMilliseconds / 1000.0;
      final d = _playbackController.timeline.value.duration.inMilliseconds / 1000.0;
      if (d > 0 && t > 0) {
        _saveCurrentProgress(t, d);
      }
    }

    if (isCompleted != _lastPlaybackCompleted) {
      _lastPlaybackCompleted = isCompleted;
      if (isCompleted) {
        final d = _playbackController.timeline.value.duration.inMilliseconds / 1000.0;
        _progressTracker.onPlaybackEnded(
          bangumiId: _effectiveBangumiId,
          canonicalEp: _currentCanonicalEp,
          title: widget.title,
          coverUrl: _resolvedCoverUrl,
          roadIndex: _playingRoadIndex ?? _selectedRoadIndex,
          sourceId: _playingSourceId ?? _selectedSourceId,
          pageUrl: _currentPlayingPageUrl ?? '',
          durationSeconds: d,
          bangumiItem: _effectiveBangumiItem,
          fullBangumiItem: _fullBangumiItem,
        );

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

  void _onSourceBundleChanged() {
    if (mounted) setState(() {});
  }

  void _onServerModeChanged() {
    final isServerMode = AppPreferences.isServerModeEnabled();
    final runtime = SourceBundleManager.instance.runtime;
    final isLocal = runtime.isLocalSource(_selectedSourceId);

    if (!isServerMode) {
      if (!isLocal) {
        // 当前在播视频绝不强行打断（让其缓冲播完），但由于本地无爬虫，选集区展示不可用错误状态
        setState(() {
          _chapterRoads = [];
          _chaptersError = '当前视频源需开启「Animaku 服务端模式」\n该源为服务端专属扩展源，本地直连模式下无法解析分集。';
        });
        _showHudToast('当前源需开启服务端模式，无法解析新集数');
      }
    } else {
      if (!isLocal) {
        _startDefaultSourceSearch(autoPlayFirst: false);
      }
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hudToastTimer?.cancel();
    _danmakuBridge.dispose();
    _lifecycleListener.dispose();
    WakelockPlus.disable().ignore();
    _saveProgressOnExit();
    DesktopTitleBarManager.instance.setPlayerFullscreen(false);
    if (_isTrueFullscreen) {
      _exitTrueFullscreen();
    } else if (_isAppFullscreen) {
      _exitAppFullscreen();
    }
    _restorePreferredOrientations();
    _tabController.dispose();
    _desktopRightTabController.dispose();
    _playbackController.timeline.removeListener(_onPlaybackTimelineChanged);
    _playbackController.core.removeListener(_onPlaybackCoreStateChanged);
    SourceBundleManager.instance.removeListener(_onSourceBundleChanged);
    AppPreferences.serverModeNotifier.removeListener(_onServerModeChanged);
    _playbackController.dispose();
    _hudToastNotifier.dispose();
    _autoPlayNextNotifier.dispose();
    _danmakuCoordinator.dispose();
    _danmakuController.dispose();
    _aggregator.removeListener(_onAggregatorUpdated);
    _aggregator.dispose();
    _autoPicker.dispose();
    super.dispose();
  }

  void _restorePreferredOrientations() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // 特殊处理说明：
      // 退出全屏或页面销毁时按设备物理形态智能恢复屏幕方向：
      // 1. 紧凑型手机 (最短边 < 600dp)：恢复为标准竖屏 (portraitUp)，避免倾斜手机误触发非播放页横屏挤压；
      // 2. 平板与大折叠屏 (最短边 >= 600dp)：恢复自适应旋转，允许平板横握使用。
      try {
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        if (shortestSide < AppBreakpoints.compact) {
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
          ]);
        } else {
          SystemChrome.setPreferredOrientations([
            DeviceOrientation.portraitUp,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        }
      } catch (_) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]);
      }
    }
  }

  Future<void> _enterAppFullscreen() async {
    if (_isTrueFullscreen) {
      if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
        try {
          await defaultExitNativeFullscreen();
        } catch (_) {}
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        _restorePreferredOrientations();
      }
    }
    if (!mounted) return;
    setState(() {
      _isAppFullscreen = true;
      _isTrueFullscreen = false;
    });
    DesktopTitleBarManager.instance.setPlayerFullscreen(true);
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
    DesktopTitleBarManager.instance.setPlayerFullscreen(false);
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
    DesktopTitleBarManager.instance.setPlayerFullscreen(true);
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
    DesktopTitleBarManager.instance.setPlayerFullscreen(false);
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        await defaultExitNativeFullscreen();
      } catch (_) {}
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      _restorePreferredOrientations();
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

  void _toggleTheaterMode() {
    setState(() {
      _isTheaterMode = !_isTheaterMode;
    });
    _showHudToast(_isTheaterMode ? '已开启剧场模式' : '已退出剧场模式');
  }

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
    if (_isTheaterMode) {
      _toggleTheaterMode();
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

  /// 特殊处理说明：
  /// 点击推荐番剧时采用 pushReplacement 替代 push：
  /// 1. 触发当前番剧的完整 dispose 生命周期（自动保存观看历史、彻底注销底层的 libmpv 播放器与硬件解码纹理），
  ///    杜绝多部番剧在后台同时解码发声与并发占用系统音频/显存；
  /// 2. 避免用户连续点击多部推荐番剧（A-B-C...）造成原生播放器实例与 GPU 纹理无限堆叠引发 OOM 或系统解码器耗尽崩溃；
  /// 3. 跳转前显式调用 pause() 与 muteForExit()，彻底切断退场动画期间的残留音频。
  void _navigateToRecommendedAnime(BangumiRecommendationItem recItem) {
    _playbackController.pause();
    _playbackController.muteForExit();

    final parsedEps =
        int.tryParse(recItem.epsLabel.replaceAll(RegExp(r'\D'), '')) ?? 0;
    final seedItem = BangumiItem.fromJson({
      'id': recItem.id,
      'name': recItem.name,
      'name_cn': recItem.nameCn,
      'image': recItem.cover,
      'rating': {'score': recItem.score},
      'airDate': recItem.year,
      'eps': parsedEps,
    });

    Navigator.of(context).pushReplacement(
      AdaptivePageRoute.build<void>(
        context,
        builder: (context) => VideoPlayPage(
          title: recItem.displayName,
          coverUrl: recItem.cover,
          bangumiItem: seedItem,
          episodeCount: parsedEps > 0 ? parsedEps : 12,
        ),
      ),
    );
  }

  String get _resolvedCoverUrl => (widget.coverUrl?.isNotEmpty ?? false)
      ? widget.coverUrl!
      : (_effectiveBangumiItem?.coverUrl ?? '');

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final pageContent = PopScope(
      canPop: !_isFullscreen && !_isSidePanelOpen && !_isTheaterMode,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          // 特殊处理说明：
          // 当用户使用 Android 侧滑返回手势或物理返回键退出播放页时，
          // 在退场过渡动画（250~350ms）起始的第 0 毫秒立即静音底层播放器并暂停，
          // 杜绝退场动画期间杂音外放，并安全释放常亮锁。
          _playbackController.pause();
          _playbackController.muteForExit();
          WakelockPlus.disable().ignore();
          return;
        }
        if (_isSidePanelOpen) {
          setState(() => _isSidePanelOpen = false);
        } else if (_isFullscreen) {
          _exitFullscreen();
        } else if (_isTheaterMode) {
          _toggleTheaterMode();
        }
      },
      child: DesktopPlayerShortcuts(
        playbackController: _playbackController,
        danmakuController: _danmakuController,
        hasStartedPlayback: _hasStartedPlayback,
        isFullscreen: _isFullscreen,
        onBackPressed: _handleBackPressed,
        onToggleFullscreen: _toggleFullscreen,
        onToggleTheaterMode: _toggleTheaterMode,
        onSeekToPercent: _seekToPercent,
        onShowHudToast: _showHudToast,
        onPreviousEpisode: (_activeEpisode != null && _activeEpisode! > 1)
            ? () {
                _selectEpisode(_activeEpisode! - 1);
                _showHudToast('正在切换至上一集');
              }
            : null,
        onNextEpisode: () {
          final maxCount = _currentSlots.isNotEmpty
              ? _currentSlots.length
              : _currentEpisodes.length;
          if (_activeEpisode != null && _activeEpisode! < maxCount) {
            _selectEpisode(_activeEpisode! + 1);
            _showHudToast('正在切换至下一集');
          }
        },
        child: ListenableBuilder(
          listenable: AppearanceManager.instance,
          builder: (context, _) {
            final layoutContent = LayoutBuilder(
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
            );

            // 特殊处理说明：
            // 无论全屏还是普通窗口，外层始终保持严格一致的 Scaffold 与 Stack 节点树深度。
            // 避免在全屏/应用全屏切换时外层 Widget 层级发生结构性增减，
            // 确保内部 layoutContent 的挂载深度在整页生命周期中始终恒定不变。
            return Scaffold(
              backgroundColor: _isFullscreen ? Colors.black : Colors.transparent,
              body: Stack(
                fit: StackFit.expand,
                children: [
                  // 0. 基础底衬
                  if (!_isFullscreen)
                    Positioned.fill(
                      child: ColoredBox(
                        color: isDark ? const Color(0xFF141416) : Theme.of(context).scaffoldBackgroundColor,
                      ),
                    ),
                  // 1. 个人专属背景壁纸层
                  if (!_isFullscreen)
                    AppearanceManager.instance.buildWallpaperLayer(pageKey: 'profile'),
                  // 2. 播放页面主体流
                  Positioned.fill(
                    child: MediaQuery.removePadding(
                      context: context,
                      removeTop: _isFullscreen,
                      child: layoutContent,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    // 特殊处理说明：
    // 桌面端 (Windows/macOS/Linux) 将播放页面全局排除在系统无障碍树 (Semantics) 之外。
    // 原因：Flutter Desktop 在 Windows 平台使用 Chromium ui::AXTree，当后台存在输入法、翻译取词、
    // 录屏或游戏浮层时会被动激活无障碍更新。播放页面包含实时 GPU 视频纹理、高频进度/弹幕刷新以及
    // 右侧数十个分集卡片与换源 Tab，在起播、全屏及退出全屏切换时极易触发 AXTree 拓扑反序列化脱节，
    // 进而产生海量 "Failed to update ui::AXTree, error: ... will not be in the tree" 刷屏日志，
    // 并在特定系统事件下引发野指针崩溃。
    // 播放页快捷键由 Focus/KeyEvent 驱动，所有点击/拖拽由 PointerEvent 处理，无障碍隔离对交互零影响。
    if (AppPlatform.isDesktop) {
      return ExcludeSemantics(
        child: pageContent,
      );
    }

    return pageContent;
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
      isTheaterMode: _isTheaterMode,
      isDesktop: effectiveIsDesktop,
      onToggleFullscreen: _toggleFullscreen,
      onToggleAppFullscreen: (effectiveIsDesktop || isFullscreen) ? _toggleAppFullscreen : null,
      onToggleTrueFullscreen: (effectiveIsDesktop || isFullscreen) ? _toggleTrueFullscreen : null,
      onToggleTheaterMode: effectiveIsDesktop ? _toggleTheaterMode : null,
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
      hudToastListenable: _hudToastNotifier,
      resolveError: _playbackError,
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
  void _showFullSourceSheet() {
    _autoPicker.onUserAction();
    MobileEpisodeSourceSheet.show(
      context,
      bangumiId: _effectiveBangumiId,
      displayEpisodeCount: _displayEpisodeCount,
      currentEpisode: _activeEpisode,
      currentSlots: _currentSlots,
      roadNames: _roadNames,
      selectedRoadIndex: _selectedRoadIndex,
      playingRoadIndex:
          _hasStartedPlayback && _selectedSourceId == _playingSourceId
              ? _playingRoadIndex
              : null,
      mappedEpisodeTitles: _mappedEpisodeTitles,
      isLoadingChapters: _isLoadingChapters,
      selectedSourceName: _selectedSourceName,
      chaptersError: _chaptersError,
      selectedSourceId: _selectedSourceId,
      playingSourceId: _hasStartedPlayback ? _playingSourceId : null,
      hasStartedPlayback: _hasStartedPlayback,
      sources: _sources,
      aggregator: _aggregator,
      keywordOptions: _keywordOptions,
      onSelectEpisode: _selectEpisode,
      onSelectSlot: _selectSlot,
      onRoadSelected: (idx) {
        if (_selectedRoadIndex == idx) return;
        setState(() => _selectedRoadIndex = idx);
      },
      onRefresh: () => _startDefaultSourceSearch(autoPlayFirst: false),
      onSourceSelected: _handleSourceSelected,
      onSelectHit: _handleSourceSelected,
      initialTabIndex: 1,
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
            playingSourceId: _hasStartedPlayback ? _playingSourceId : null,
            onSourceSelected: _handleSourceSelected,
            aggregator: _aggregator,
            sourceNotice: _sourceNotice,
            keywordOptions: _keywordOptions,
            onUserAction: _autoPicker.onUserAction,
            currentEpisode: _activeEpisode,
            playingRoadIndex: _hasStartedPlayback && _selectedSourceId == _playingSourceId ? _playingRoadIndex : null,
            isLoadingChapters: _isLoadingChapters,
            resolveError: _chaptersError,
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
            onTapRecommendItem: _navigateToRecommendedAnime,
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
        resolveError: _chaptersError,
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
        playingSourceId: _hasStartedPlayback ? _playingSourceId : null,
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
      isTheaterMode: _isTheaterMode,
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
            sourceName: _selectedSourceName,
            errorMessage: _chaptersError,
            onEnableServerMode: (!AppPreferences.isServerModeEnabled() &&
                    !SourceBundleManager.instance.runtime.isLocalSource(_selectedSourceId))
                ? () => AppPreferences.setServerModeEnabled(true)
                : null,
            onSwitchSource: () {
              if (_desktopRightTabController.index != 1) {
                _desktopRightTabController.animateTo(1);
              }
            },
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
        playingSourceId: _hasStartedPlayback ? _playingSourceId : null,
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
        onTapItem: _navigateToRecommendedAnime,
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
