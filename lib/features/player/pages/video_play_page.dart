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
import '../../../core/utils/adaptive_page_route.dart';
import '../../../core/utils/appearance_manager.dart';
import '../../../core/utils/responsive.dart';
import '../controller/playback_controller.dart';
import '../controller/video_play_session_coordinator.dart';
import '../controller/watch_progress_tracker.dart';
import '../core/models/resolved_media.dart';
import '../danmaku/danmaku.dart';
import '../services/player_preferences_service.dart';
import '../source/models/source_models.dart';
import '../source/services/source_binding_service.dart';
import '../source/source_aggregator.dart';
import '../source/source_bundle_manager.dart';
import '../source/utils/playable_slot_engine.dart';
import '../widgets/desktop/desktop_play_content.dart';
import '../widgets/desktop/desktop_player_shortcuts.dart';
import '../widgets/mobile/mobile_episode_source_sheet.dart';
import '../widgets/mobile/mobile_play_tab_section.dart';
import '../widgets/player_side_panel.dart';
import '../widgets/video_player_layouts.dart';
import '../widgets/video_player_placeholder.dart';
import '../widgets/video_player_surface_with_controls.dart';
import '../widgets/video_source_view.dart';
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
  late final AppLifecycleListener _lifecycleListener;
  bool _lastWakelockState = false;

  /// 视频播放会话与源调度协调器 (负责多源检索、自动选源、分集对齐与直链解析)
  late final VideoPlaySessionCoordinator _session;

  /// 跨布局保活 Key：确保在全屏/桌面/移动端布局切换时复用同一 Element 节点，防止播放器和弹幕被卸载重建
  final GlobalKey _playerSubtreeKey = GlobalKey();

  bool _isAppFullscreen = false;
  bool _isTrueFullscreen = false;
  bool get _isFullscreen => _isAppFullscreen || _isTrueFullscreen;
  bool _isTheaterMode = false;
  bool _isSidePanelOpen = false;
  PlayerSidePanelTab _sidePanelInitialTab = PlayerSidePanelTab.episodes;
  bool _isLoadingAuthorityDetails = true;

  late final ValueNotifier<String?> _hudToastNotifier;
  Timer? _hudToastTimer;

  // 协调器状态代理 Getter
  String get _selectedSourceId => _session.selectedSourceId;
  List<VideoSourceItem> get _sources => _session.sources;
  bool get _isLoadingChapters => _session.isLoadingChapters;
  String? get _chaptersError => _session.chaptersError;
  String? get _playbackError => _session.playbackError;
  String? get _sourceNotice => _session.sourceNotice;
  int get _selectedRoadIndex => _session.selectedRoadIndex;
  String? get _currentPlayingPageUrl => _session.currentPlayingPageUrl;
  int? get _activeEpisode => _session.activeEpisode;
  bool get _hasStartedPlayback => _session.hasStartedPlayback;
  int? get _playingRoadIndex => _session.playingRoadIndex;
  String? get _playingSourceId => _session.playingSourceId;
  SourceAggregator get _aggregator => _session.aggregator;
  List<SourceEpisode> get _currentEpisodes => _session.currentEpisodes;
  List<PlayableSlot> get _currentSlots => _session.currentSlots;
  List<String> get _mappedEpisodeTitles => _session.mappedEpisodeTitles;
  List<String> get _roadNames => _session.roadNames;
  int get _displayEpisodeCount => _session.displayEpisodeCount;
  String get _selectedSourceName => _session.selectedSourceName;
  List<String> get _keywordOptions => _session.keywordOptions;

  /// 观看历史与播放进度追踪器 (负责 15s 有有效门槛、完播仲裁与自动落盘)
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

  late final ValueNotifier<bool> _autoPlayNextNotifier;
  bool _lastPlaybackCompleted = false;

  @override
  void initState() {
    super.initState();
    _hudToastNotifier = ValueNotifier<String?>(null);
    _autoPlayNextNotifier =
        ValueNotifier<bool>(PlayerPreferencesService.instance.autoPlayNext);

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

    // 初始化核心播放会话与多源调度协调器
    _session = VideoPlaySessionCoordinator(
      title: widget.title,
      episodeCount: widget.episodeCount,
      bangumiItem: widget.bangumiItem,
      coverUrl: widget.coverUrl,
      videoUrl: widget.videoUrl,
      httpHeaders: widget.httpHeaders,
      initialPosition: widget.initialPosition,
      currentEpisode: widget.currentEpisode,
      preferredSourceId: widget.preferredSourceId,
      initialPageUrl: widget.initialPageUrl,
      initialRoad: widget.initialRoad,
      onEpisodeSelected: widget.onEpisodeSelected,
      playbackController: _playbackController,
      danmakuCoordinator: _danmakuCoordinator,
      progressTracker: _progressTracker,
      showHudToast: _showHudToast,
      onFocusEpisodesTab: () {
        if (!mounted) return;
        if (_tabController.index != 0) _tabController.animateTo(0);
        if (_desktopRightTabController.index != 0) {
          _desktopRightTabController.animateTo(0);
        }
      },
      waitForRouteAnimation: _waitForRouteAnimationIfNeeded,
    );
    _session.addListener(_onSessionUpdated);

    // 预热并同步用户上次持久化的弹幕外观设置与连播偏好
    PlayerPreferencesService.instance.initialize().then((_) {
      if (mounted) {
        _danmakuController.updateSettings(PlayerPreferencesService.instance.danmakuSettings);
        _autoPlayNextNotifier.value = PlayerPreferencesService.instance.autoPlayNext;
      }
    });

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
        _session.initPresetPlayback();
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

  void _onSessionUpdated() {
    if (mounted) setState(() {});
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
            _session.fullBangumiItem = subject;
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
          _session.officialEpisodes = _officialEpisodes;
          _session.opedData = _opedData;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingAuthorityDetails = false);
      }
    }
  }

  Future<void> _startDefaultSourceSearch({bool autoPlayFirst = false}) =>
      _session.startDefaultSourceSearch(autoPlayFirst: autoPlayFirst);

  /// 用户或仲裁器选择某视频源及条目 (切源并提取真实分集)
  Future<void> _handleSourceSelected(
    VideoSourceItem src, [
    SourceSearchResult? directHit,
    List<SourceChapterRoad>? cachedRoads,
  ]) =>
      _session.handleSourceSelected(src, directHit, cachedRoads);

  Future<void> _selectSlot(PlayableSlot slot) => _session.selectSlot(slot);

  Future<void> _selectEpisode(int ep) => _session.selectEpisode(ep);

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
        _session.notifyServerModeDisabled();
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
    _session.removeListener(_onSessionUpdated);
    _session.dispose();
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
        _onUserAction();
        _showFullSourceSheet();
      },
    );
  }

  void _onUserAction() {
    _aggregator.lockByUserAction();
  }

  /// 呼出全功能选集与多视频源看板抽屉
  void _showFullSourceSheet() {
    _onUserAction();
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
      onRoadSelected: _session.selectRoad,
      onRefresh: () => _startDefaultSourceSearch(autoPlayFirst: false),
      onSourceSelected: _handleSourceSelected,
      onSelectHit: _handleSourceSelected,
      initialTabIndex: 1,
    );
  }

  /// 详情 / 视频源 / 选集 移动端分段内容面板
  Widget _buildTabSection() {
    return MobilePlayTabSection(
      tabController: _tabController,
      title: widget.title,
      effectiveBangumiItem: _effectiveBangumiItem,
      isLoadingAuthorityDetails: _isLoadingAuthorityDetails,
      resolvedCoverUrl: _resolvedCoverUrl,
      displayEpisodeCount: _displayEpisodeCount,
      sources: _sources,
      selectedSourceId: _selectedSourceId,
      selectedSourceName: _selectedSourceName,
      playingSourceId: _hasStartedPlayback ? _playingSourceId : null,
      onSourceSelected: _handleSourceSelected,
      aggregator: _aggregator,
      sourceNotice: _sourceNotice,
      keywordOptions: _keywordOptions,
      onUserAction: _onUserAction,
      activeEpisode: _activeEpisode,
      playingRoadIndex: _hasStartedPlayback && _selectedSourceId == _playingSourceId
          ? _playingRoadIndex
          : null,
      isLoadingChapters: _isLoadingChapters,
      chaptersError: _chaptersError,
      hasEpisodes: _currentEpisodes.isNotEmpty,
      currentSlots: _currentSlots,
      roadNames: _roadNames,
      selectedRoadIndex: _selectedRoadIndex,
      mappedEpisodeTitles: _mappedEpisodeTitles,
      onRoadSelected: _session.selectRoad,
      onRefreshEpisodes: () => _startDefaultSourceSearch(autoPlayFirst: false),
      onSelectEpisode: _selectEpisode,
      onSelectSlot: _selectSlot,
      onTapRecommendItem: _navigateToRecommendedAnime,
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
        onRoadSelected: _session.selectRoad,
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

  /// 2. 桌面/宽屏并排布局 (分块架构：左栏播放器+简介+评论，右栏视频源展开框+选集+推荐)
  Widget _buildDesktopLayout() {
    return DesktopPlayContent(
      title: widget.title,
      currentEpisode: _activeEpisode,
      isTheaterMode: _isTheaterMode,
      onBackPressed: _handleBackPressed,
      playerWidget: KeyedSubtree(
        key: _playerSubtreeKey,
        child: _buildPlayerOrPlaceholder(isFullscreen: false, isDesktop: true),
      ),
      effectiveBangumiItem: _effectiveBangumiItem,
      effectiveBangumiId: _effectiveBangumiId,
      isLoadingAuthorityDetails: _isLoadingAuthorityDetails,
      resolvedCoverUrl: _resolvedCoverUrl,
      displayEpisodeCount: _displayEpisodeCount,
      rightTabController: _desktopRightTabController,
      roadNames: _roadNames,
      selectedRoadIndex: _selectedRoadIndex,
      playingRoadIndex: _hasStartedPlayback && _selectedSourceId == _playingSourceId
          ? _playingRoadIndex
          : null,
      mappedEpisodeTitles: _mappedEpisodeTitles,
      currentSlots: _currentSlots,
      isLoadingChapters: _isLoadingChapters,
      selectedSourceName: _selectedSourceName,
      selectedSourceId: _selectedSourceId,
      chaptersError: _chaptersError,
      onSwitchSourceTab: () {
        if (_desktopRightTabController.index != 1) {
          _desktopRightTabController.animateTo(1);
        }
      },
      onRoadSelected: _session.selectRoad,
      onRefreshEpisodes: () => _startDefaultSourceSearch(autoPlayFirst: false),
      onSelectEpisode: _selectEpisode,
      onSelectSlot: _selectSlot,
      sources: _sources,
      playingSourceId: _hasStartedPlayback ? _playingSourceId : null,
      hasStartedPlayback: _hasStartedPlayback,
      onSourceSelected: _handleSourceSelected,
      aggregator: _aggregator,
      sourceNotice: _sourceNotice,
      keywordOptions: _keywordOptions,
      onUserAction: _onUserAction,
      onTapRecommendItem: _navigateToRecommendedAnime,
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
