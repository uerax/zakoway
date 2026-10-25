import 'dart:developer' as developer;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../core/models/bangumi/bangumi_calendar.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/models/home/recommend_item.dart';
import '../../../core/network/bangumi_client.dart';
import '../../../core/services/daily_recommend_service.dart';
import '../../../core/services/watch_history_service.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/font_manager.dart';
import '../../../core/utils/responsive.dart';
import '../../common/widgets/anime_card.dart';
import '../../common/widgets/shimmer_loading.dart';
import '../../player/core/proxy/media_preload_coordinator.dart';
import '../../history/pages/history_page.dart';
import '../widgets/continue_watching_shelf.dart';
import '../widgets/daily_spotlight_card.dart';
import '../widgets/home_desktop_hero.dart';
import '../widgets/rank_horizontal_section.dart';
import '../widgets/today_anime_shelf.dart';

class HomePage extends StatefulWidget {
  final BangumiClient client;
  final void Function(String category, {int? year, int? month})? onNavigateToCategory;

  const HomePage({
    super.key,
    required this.client,
    this.onNavigateToCategory,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with AutomaticKeepAliveClientMixin {
  // 业务配置：精选探索模块预留开关（后续完善后可直接切为 true 开启）
  static const bool _showExploreSection = false;

  // 模块解耦与渐进式加载（Incremental Loading）：
  // 1. 各货架与周历状态解耦，谁先返回谁先渲染，杜绝单接口卡死整页；
  // 2. 本地追番历史 0ms 呈现，即便弱网断网，用户也能即刻使用核心播放与历史功能；
  // 3. 图片在各个卡片内部独立异步下载与解码，未就绪时纯色占位，绝不阻塞应用交互。
  List<BangumiCalendarDay>? _calendarDays;
  List<BangumiItem>? _tv;
  List<BangumiItem>? _movies;
  List<BangumiItem>? _ova;
  List<RecommendItem>? _recommendations;
  bool _isLoading = false;
  Object? _error;

  // 保证页面切走后状态保活不被销毁，切回 0ms 瞬间呈现，不重复请求网络
  @override
  bool get wantKeepAlive => true;

  List<BangumiItem> get _todayItems {
    final days = _calendarDays;
    if (days == null || days.isEmpty) return const [];
    final todayWeekday = DateTime.now().weekday;
    return days.firstWhere(
      (d) => d.weekday.id == todayWeekday,
      orElse: () => days.first,
    ).items;
  }

  String get _weekdayName {
    final todayWeekday = DateTime.now().weekday;
    const weekLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return weekLabels[(todayWeekday - 1).clamp(0, 6)];
  }

  bool get _hasAnyData =>
      (_calendarDays != null && _calendarDays!.isNotEmpty) ||
      (_tv != null && _tv!.isNotEmpty) ||
      (_movies != null && _movies!.isNotEmpty) ||
      (_ova != null && _ova!.isNotEmpty) ||
      (_recommendations != null && _recommendations!.isNotEmpty);

  @override
  void initState() {
    super.initState();
    WatchHistoryService.instance.getHistory();
    _loadData();
  }

  Future<void> _loadData({bool forceRefresh = false}) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      if (!_hasAnyData) {
        _error = null;
      }
    });

    try {
      // 并发启动各子模块数据拉取，每个接口成功后立刻局部 setState 渐进上屏，弱网 0 阻塞
      final calendarTask = widget.client
          .getCalendar(forceRefresh: forceRefresh)
          .then((days) {
            if (mounted && days.isNotEmpty) {
              setState(() => _calendarDays = days);
            }
            return days;
          })
          .catchError((e) {
            developer.log('首页获取每日放送失败: $e');
            return <BangumiCalendarDay>[];
          });

      final tvTask = widget.client
          .getTrending(limit: 18, forceRefresh: forceRefresh)
          .then((items) {
            if (mounted && items.isNotEmpty) {
              setState(() => _tv = items);
            }
            return items;
          })
          .catchError((e) {
            developer.log('首页获取热门 TV 失败: $e');
            return <BangumiItem>[];
          });

      final moviesTask = widget.client
          .getHotMovies(limit: 18, forceRefresh: forceRefresh)
          .then((items) {
            if (mounted && items.isNotEmpty) {
              setState(() => _movies = items);
            }
            return items;
          })
          .catchError((e) {
            developer.log('首页获取热门剧场版失败: $e');
            return <BangumiItem>[];
          });

      final ovaTask = widget.client
          .getHotOva(limit: 18, forceRefresh: forceRefresh)
          .then((items) {
            if (mounted && items.isNotEmpty) {
              setState(() => _ova = items);
            }
            return items;
          })
          .catchError((e) {
            developer.log('首页获取热门 OVA 失败: $e');
            return <BangumiItem>[];
          });

      final recommendTask = () async {
        try {
          final watchedSubjectIds = WatchHistoryService.instance.items
              .map((e) => e.bangumiId)
              .where((id) => id > 0)
              .toSet();
          final userTagFreq = WatchHistoryService.instance.userGenreFrequencies;

          final recs = await DailyRecommendService.getDailyRecommendations(
            client: widget.client,
            rawUserTagFreq: userTagFreq,
            watchedSubjectIds: watchedSubjectIds,
            forceRefresh: forceRefresh,
          );
          if (mounted && recs.isNotEmpty) {
            setState(() => _recommendations = recs);
          }
          return recs;
        } catch (e) {
          developer.log('首页获取今日推荐失败: $e');
          return <RecommendItem>[];
        }
      }();

      await Future.wait([
        calendarTask,
        tvTask,
        moviesTask,
        ovaTask,
        recommendTask,
      ]);

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (!_hasAnyData) {
          _error = const BangumiApiException('无法连接到服务器，且本地无有效缓存');
        } else {
          _error = null;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        if (!_hasAnyData) {
          _error = e;
        }
      });

      if (_hasAnyData) {
        AppToast.error('刷新失败: 网络连接异常，已为您保留当前数据', context: context);
      }
    }
  }

  void _onShelfViewAllTap(String category, {int? year, int? month}) {
    // 点击“浏览全部”快捷入口：通知外层主壳切换到底栏“分类”标签页并定位分类
    if (widget.onNavigateToCategory != null) {
      widget.onNavigateToCategory!(category, year: year, month: month);
    }
  }

  /// 桌面端全局统一内容对齐容器：所有大屏模块（Hero、继续追番、热门货架）共用完全相同的居中约束与左右间距
  static const double _desktopContentMargin = 48.0;

  /// 货架与模块响应式对齐容器：
  Widget _buildResponsiveShelf(Widget shelf) {
    if (context.isDesktop) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxHeroWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: _desktopContentMargin),
            child: shelf,
          ),
        ),
      );
    }
    return shelf;
  }

  /// 继续追番模块构建辅助函数：
  /// 统一绑定本地播放历史单例（WatchHistoryService），无历史时返回 SizedBox.shrink() 0 像素占位。
  Widget _buildContinueWatchingShelf() {
    return _buildResponsiveShelf(
      ListenableBuilder(
        listenable: WatchHistoryService.instance,
        builder: (context, _) {
          final watchHistory = WatchHistoryService.instance.latestByAnime;
          if (watchHistory.isNotEmpty) {
            final top = watchHistory.first;
            if (top.pluginName.isNotEmpty && top.pageUrl.isNotEmpty) {
              // 特殊处理说明：首页继续追番首片预测性预拉取 (First-chunk Speculative Preload)
              // 在用户浏览首页的间隙，静默预载目标番剧首个切片到本地磁盘缓存，点击时直接命中 < 200ms 瞬开！
              MediaPreloadCoordinator.instance.preloadMediaFirstChunk(
                sourceId: top.pluginName,
                episodeUrl: top.pageUrl,
              ).ignore();
            }
          }
          return ContinueWatchingShelf(
            records: watchHistory,
            onResumeWatch: (record) {
              navigateToVideoPlayer(
                context,
                record.toBangumiItem(),
                initialPosition: Duration(seconds: record.position.toInt()),
                currentEpisode: record.episode,
                preferredSourceId: record.pluginName,
                initialPageUrl: record.pageUrl,
                initialRoad: record.road,
              );
            },
            onViewAllHistory: () {
              Navigator.of(context).push(
                CupertinoPageRoute(
                  builder: (context) => const HistoryPage(),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final safeTop = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 0. 极底：动态弥散环境光晕（Ambient Mesh Glow），赋予全屏通透景深与毛玻璃流光折射
          Positioned(
            top: -120,
            left: -80,
            right: -80,
            height: 420,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.2),
                    radius: 0.85,
                    colors: [
                      theme.colorScheme.primary.withAlpha(isDark ? 36 : 22),
                      theme.colorScheme.primary.withAlpha(isDark ? 10 : 6),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
          ),

          // 1. 底层：内容流区域
          Positioned.fill(
            child: _buildAnimeContent(context, theme, safeTop),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimeContent(BuildContext context, ThemeData theme, double safeTop) {
    // 渐进式渲染核心保护：
    // 只有在全量网络任务完成、所有网络数据彻底为空、存在异常且本地连播放历史都没有时，才展示居中错误重试视图
    if (!_isLoading &&
        !_hasAnyData &&
        _error != null &&
        WatchHistoryService.instance.latestByAnime.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                '加载失败',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFamily: FontManager.instance.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$_error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.redAccent,
                  fontFamily: FontManager.instance.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _loadData(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  '重试',
                  style: TextStyle(
                    fontFamily: FontManager.instance.activeFontFamily,
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final isDesktop = context.isDesktop;

    // 渐进式渲染：无论网络是否就绪，页面骨架瞬间进入，本地历史 0ms 呈现，网络货架谁先到谁先出
    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      child: isDesktop
          ? _buildDesktopLayout(
              context: context,
              theme: theme,
              safeTop: safeTop,
            )
          : _buildMobileLayout(
              context: context,
              theme: theme,
              safeTop: safeTop,
            ),
    );
  }

  /// 移动端布局流：
  /// 特殊处理说明：
  /// 1. 继续追番优先置顶：绑定本地持久化存储，冷启动第 0 毫秒呈现，弱网/离线立即可看；
  /// 2. 纵向渐进流排布：周历/推荐未就绪时局部轻量占位，就绪后平滑替换；
  /// 3. 精确限制可视区外预加载距离（250px），未进入视口的卡片不发起网络下载。
  Widget _buildMobileLayout({
    required BuildContext context,
    required ThemeData theme,
    required double safeTop,
  }) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      scrollCacheExtent: const ScrollCacheExtent.pixels(250),
      slivers: [
        // 顶部预留状态栏安全高度与自然留白
        SliverToBoxAdapter(
          child: SizedBox(height: safeTop + 10),
        ),

        // 移动端：继续追番置顶（本地 0ms 数据，弱网/断网立即可用）
        SliverToBoxAdapter(
          child: _buildContinueWatchingShelf(),
        ),

        // 每日放送周历横滑条 + 今日算法推荐卡片（局部解耦占位）
        SliverToBoxAdapter(
          child: Column(
            children: [
              if (_calendarDays == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 10),
                  child: Shimmer(child: ShimmerTodayShelf()),
                )
              else if (_calendarDays!.isNotEmpty || _todayItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                TodayAnimeShelf(
                  calendarDays: _calendarDays,
                  items: _todayItems,
                  weekdayName: _weekdayName,
                ),
                const SizedBox(height: 10),
              ],
              if (_recommendations != null && _recommendations!.isNotEmpty) ...[
                DailySpotlightCard(
                  recommendations: _recommendations!,
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),

        // 货架列表与探索板块
        ..._buildShelfSlivers(
          theme: theme,
        ),

        // 底部留出 96px 安全高度，保证页面滑动至最底端时不会被悬浮毛玻璃胶囊遮挡
        const SliverToBoxAdapter(
          child: SizedBox(height: 96),
        ),
      ],
    );
  }

  /// 桌面/宽屏端大屏布局：
  /// 特殊处理说明：
  /// 1. HomeDesktopHero 居首：数据未就绪时呈现骨架屏，数据到达后平滑替换；
  /// 2. 继续追番承接在 Hero 下方：绑定本地播放历史，始终即时可用；
  /// 3. 货架与模块全部限制在 maxContentWidth(1200dp) 居中垂直对齐。
  Widget _buildDesktopLayout({
    required BuildContext context,
    required ThemeData theme,
    required double safeTop,
  }) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      scrollCacheExtent: const ScrollCacheExtent.pixels(250),
      slivers: [
        // 顶部预留安全高度与自然留白
        SliverToBoxAdapter(
          child: SizedBox(height: safeTop + 16),
        ),

        // 桌面端：Hero 大屏门面（智能推荐轮播 + 全周新番 6 宫格矩阵）
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 12),
            child: _buildResponsiveShelf(
              (_tv == null && _calendarDays == null)
                  ? const Shimmer(child: ShimmerDesktopHero())
                  : HomeDesktopHero(
                      bannerItems: _tv,
                      recommendations: _recommendations,
                      calendarDays: _calendarDays,
                      todayItems: _todayItems,
                      weekdayName: _weekdayName,
                    ),
            ),
          ),
        ),

        // 桌面端：继续追番承接在 Hero 下方（本地数据，瞬时可用）
        SliverToBoxAdapter(
          child: _buildContinueWatchingShelf(),
        ),

        // 货架列表与探索板块
        ..._buildShelfSlivers(
          theme: theme,
        ),

        // 底部留出 96px 安全高度
        const SliverToBoxAdapter(
          child: SizedBox(height: 96),
        ),
      ],
    );
  }

  /// 单个货架独立流光骨架占位行
  Widget _buildShelfSkeletonRow(String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: ShimmerLoading(
            child: Container(
              height: 18,
              width: 140,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 250,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: 4,
            itemBuilder: (context, index) => const ShimmerRankCard(),
          ),
        ),
      ],
    );
  }

  /// 公共分类货架与探索板块 Slivers（模块级自决渲染，未就绪时局部骨架占位，就绪后平滑上屏）
  List<Widget> _buildShelfSlivers({
    required ThemeData theme,
  }) {
    final uniqueExploreItems = _showExploreSection
        ? () {
            final exploreItems = <BangumiItem>[
              ..._todayItems,
              ...(_tv ?? const []),
              ...(_movies ?? const []),
              ...(_ova ?? const []),
            ];
            final seenIds = <int>{};
            return exploreItems.where((item) => seenIds.add(item.id)).toList();
          }()
        : const <BangumiItem>[];

    return [
      // 货架 1：热门 TV 番剧独立货架
      SliverToBoxAdapter(
        child: _buildResponsiveShelf(
          _tv == null
              ? Shimmer(child: _buildShelfSkeletonRow('TV 番剧'))
              : AnimeHorizontalShelf(
                  icon: Icons.tv_rounded,
                  title: '热门 TV 番剧',
                  items: _tv!,
                  defaultStatType: 'heat',
                  viewAllSubtitle: '浏览全部 TV',
                  onViewAllTap: () => _onShelfViewAllTap('TV'),
                ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),

      // 货架 2：热门剧场版独立货架
      SliverToBoxAdapter(
        child: _buildResponsiveShelf(
          _movies == null
              ? Shimmer(child: _buildShelfSkeletonRow('剧场版'))
              : AnimeHorizontalShelf(
                  icon: Icons.movie_filter_rounded,
                  title: '热门剧场版',
                  items: _movies!,
                  defaultStatType: 'collect',
                  viewAllSubtitle: '浏览全部剧场版',
                  onViewAllTap: () => _onShelfViewAllTap('剧场版'),
                ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),

      // 货架 3：热门 OVA / 特别篇独立货架
      SliverToBoxAdapter(
        child: _buildResponsiveShelf(
          _ova == null
              ? Shimmer(child: _buildShelfSkeletonRow('OVA 特别篇'))
              : AnimeHorizontalShelf(
                  icon: Icons.album_rounded,
                  title: '热门 OVA / 特别篇',
                  items: _ova!,
                  defaultStatType: 'collect',
                  viewAllSubtitle: '浏览全部 OVA',
                  onViewAllTap: () => _onShelfViewAllTap('OVA'),
                ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),

      if (_showExploreSection) ...[
        const SliverToBoxAdapter(
          child: SizedBox(height: 12),
        ),

        // 纵向双列探索板块大标题
        if (uniqueExploreItems.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.explore_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '精选探索',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      fontFamily: FontManager.instance.activeFontFamily,
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                      color: theme.textTheme.titleLarge?.color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${uniqueExploreItems.length} 部精选',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: FontManager.instance.activeFontFamily,
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 纵向双列精选瀑布流网格
        if (uniqueExploreItems.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 14,
                crossAxisSpacing: 12,
                childAspectRatio: 0.65,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return AnimeCard(item: uniqueExploreItems[index]);
                },
                childCount: uniqueExploreItems.length,
              ),
            ),
          ),
      ],
    ];
  }
}
