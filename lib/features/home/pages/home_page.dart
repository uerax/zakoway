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
import '../../../core/utils/responsive.dart';
import '../../common/widgets/anime_card.dart';
import '../../common/widgets/shimmer_loading.dart';
import '../../category/models/category_constants.dart';
import '../../history/pages/history_page.dart';
import '../widgets/continue_watching_shelf.dart';
import '../widgets/daily_spotlight_card.dart';
import '../widgets/home_desktop_hero.dart';
import '../widgets/rank_horizontal_section.dart';
import '../widgets/today_anime_shelf.dart';

typedef _HomeData = ({
  List<BangumiCalendarDay> calendarDays,
  List<BangumiItem> today,
  String weekdayName,
  List<RecommendItem> recommendations,
  List<BangumiItem> tv,
  List<BangumiItem> movies,
  List<BangumiItem> ova,
});

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

  // Stale-While-Revalidate 机制：保存当前已成功加载的首页数据，
  // 刷新中或网络失败时保留旧数据平滑呈现，杜绝骨架屏闪烁与清空白屏
  _HomeData? _homeData;
  bool _isLoading = false;
  Object? _error;

  // 保证页面切走后状态保活不被销毁，切回 0ms 瞬间呈现，不重复请求网络
  @override
  bool get wantKeepAlive => true;

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
      if (_homeData == null) {
        _error = null;
      }
    });

    try {
      final data = await _fetchHomeData(forceRefresh: forceRefresh);
      if (!mounted) return;
      setState(() {
        _homeData = data;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e;
      });

      // 特殊处理说明：当屏幕上已有旧数据时，刷新失败绝不清空列表，仅弹出轻量提醒告知用户
      if (_homeData != null) {
        ScaffoldMessenger.of(context).removeCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('刷新失败: 网络连接异常，已为您保留当前数据'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _onShelfViewAllTap(String category, {int? year, int? month}) {
    // 点击“浏览全部”快捷入口：通知外层主壳切换到底栏“分类”标签页并定位分类
    if (widget.onNavigateToCategory != null) {
      widget.onNavigateToCategory!(category, year: year, month: month);
    }
  }

  /// 货架响应式对齐容器：
  /// 特殊处理说明：
  /// 1. 桌面/宽屏端（>= 840dp）：通过 Center + ConstrainedBox(maxWidth: 1200) 与顶栏和 Hero 区域基线严格垂直对齐，两边优雅留白；
  /// 2. 手机与平板竖屏（< 840dp）：直接返回原货架组件，保持 100% 贴边无阻碍全宽滑动流与边缘露头（Peek）手势引导，零视觉副作用。
  Widget _buildResponsiveShelf(Widget shelf) {
    if (context.isDesktop) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
          return ContinueWatchingShelf(
            records: watchHistory,
            onResumeWatch: (record) {
              navigateToVideoPlayer(
                context,
                record.toBangumiItem(),
                initialPosition: Duration(seconds: record.position.toInt()),
                currentEpisode: record.episode,
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

  Future<_HomeData> _fetchHomeData({
    bool forceRefresh = false,
  }) async {
    // 容灾设计：并发子请求相互隔离降级，避免单个接口异常击垮整页
    final calendarFuture = widget.client
        .getCalendar(forceRefresh: forceRefresh)
        .catchError((e) {
          developer.log('首页获取每日放送失败: $e');
          return <BangumiCalendarDay>[];
        });
    final tvFuture = widget.client
        .getTrending(limit: 18, forceRefresh: forceRefresh)
        .catchError((e) {
          developer.log('首页获取热门 TV 失败: $e');
          return <BangumiItem>[];
        });
    final moviesFuture = widget.client
        .getHotMovies(limit: 18, forceRefresh: forceRefresh)
        .catchError((e) {
          developer.log('首页获取热门剧场版失败: $e');
          return <BangumiItem>[];
        });
    final ovaFuture = widget.client
        .getHotOva(limit: 18, forceRefresh: forceRefresh)
        .catchError((e) {
          developer.log('首页获取热门 OVA 失败: $e');
          return <BangumiItem>[];
        });

    final results = await Future.wait([
      calendarFuture,
      tvFuture,
      moviesFuture,
      ovaFuture,
    ]);

    final fetchedCalendar = results[0] as List<BangumiCalendarDay>;
    final fetchedTv = results[1] as List<BangumiItem>;
    final fetchedMovies = results[2] as List<BangumiItem>;
    final fetchedOva = results[3] as List<BangumiItem>;

    // 特殊处理说明：优先使用新拉取的数据；若新请求因网络异常返回空列表，
    // 优先回退复用当前内存中已有数据（Stale-While-Revalidate），绝不开天窗
    final calendarDays = fetchedCalendar.isNotEmpty
        ? fetchedCalendar
        : (_homeData?.calendarDays ?? const <BangumiCalendarDay>[]);
    final tv = fetchedTv.isNotEmpty
        ? fetchedTv
        : (_homeData?.tv ?? const <BangumiItem>[]);
    final movies = fetchedMovies.isNotEmpty
        ? fetchedMovies
        : (_homeData?.movies ?? const <BangumiItem>[]);
    final ova = fetchedOva.isNotEmpty
        ? fetchedOva
        : (_homeData?.ova ?? const <BangumiItem>[]);

    final now = DateTime.now();
    final todayWeekday = now.weekday; // 1=Mon .. 7=Sun
    const weekLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    final weekdayName = weekLabels[(todayWeekday - 1).clamp(0, 6)];

    final todayItems = calendarDays
        .firstWhere(
          (d) => d.weekday.id == todayWeekday,
          orElse: () => calendarDays.isNotEmpty
              ? calendarDays[0]
              : BangumiCalendarDay(
                  weekday: BangumiWeekday(
                    id: todayWeekday,
                    en: '',
                    cn: weekdayName,
                    ja: '',
                  ),
                  items: const [],
                ),
        )
        .items;

    // 今日推荐算法抓取与调度：带天内幂等、L2 磁盘缓存与三级降级保护
    List<RecommendItem> recommendations = const [];
    try {
      final watchedSubjectIds = WatchHistoryService.instance.items
          .map((e) => e.bangumiId)
          .where((id) => id > 0)
          .toSet();
      final userTagFreq = WatchHistoryService.instance.userGenreFrequencies;

      recommendations = await DailyRecommendService.getDailyRecommendations(
        client: widget.client,
        rawUserTagFreq: userTagFreq,
        watchedSubjectIds: watchedSubjectIds,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      developer.log('首页获取今日推荐失败: $e');
      recommendations = _homeData?.recommendations ?? const [];
    }

    // 若所有数据源均彻底为空（冷启动首开且网络完全断开），则抛出异常以便展示全屏错误重试视图
    if (calendarDays.isEmpty &&
        tv.isEmpty &&
        movies.isEmpty &&
        ova.isEmpty &&
        recommendations.isEmpty) {
      throw const BangumiApiException('无法连接到服务器，且本地无有效缓存');
    }

    return (
      calendarDays: calendarDays,
      today: todayItems,
      weekdayName: weekdayName,
      recommendations: recommendations,
      tv: tv,
      movies: movies,
      ova: ova,
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
    // 1. 首次冷启动且完全无任何数据：呈现 1:1 流光骨架屏
    // 特殊处理说明：当已有数据时（_homeData != null），重新加载或下拉刷新绝不退回骨架屏，平滑保留当前界面
    if (_isLoading && _homeData == null) {
      return _buildShimmerSkeleton(context, theme, safeTop);
    }

    // 2. 首次加载失败且完全无任何数据：呈现居中错误重试视图
    if (_homeData == null && _error != null) {
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
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '$_error',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.redAccent),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _loadData(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final data = _homeData;
    if (data == null) {
      return const SizedBox.shrink();
    }

    // 精选探索流预留数据（开关开启时使用）
    final exploreItems = <BangumiItem>[
      ...data.today,
      ...data.tv,
      ...data.movies,
      ...data.ova,
    ];
    final seenIds = <int>{};
    final uniqueExploreItems = exploreItems.where((item) => seenIds.add(item.id)).toList();

    final isDesktop = context.isDesktop;

    // 3. 正常呈现内容：下拉刷新直接触发 _loadData，即使网络失败也会保留 _homeData 绝不清空
    return RefreshIndicator(
      onRefresh: () => _loadData(forceRefresh: true),
      child: isDesktop
          ? _buildDesktopLayout(
              context: context,
              theme: theme,
              safeTop: safeTop,
              data: data,
              uniqueExploreItems: uniqueExploreItems,
            )
          : _buildMobileLayout(
              context: context,
              theme: theme,
              safeTop: safeTop,
              data: data,
              uniqueExploreItems: uniqueExploreItems,
            ),
    );
  }

  /// 移动端布局流：
  /// 特殊处理说明：
  /// 1. 继续追番优先置顶：满足手机端单手操作“即开即看”的高频直达体验；
  /// 2. 纵向流排布：周历每日放送横滑条 + 今日推荐算法大卡片 + 热门分类货架；
  /// 3. 精确限制可视区外预加载距离（250px），未进入视口的卡片不发起网络下载。
  Widget _buildMobileLayout({
    required BuildContext context,
    required ThemeData theme,
    required double safeTop,
    required _HomeData data,
    required List<BangumiItem> uniqueExploreItems,
  }) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      scrollCacheExtent: const ScrollCacheExtent.pixels(250),
      slivers: [
        // 顶部预留状态栏安全高度与自然留白
        SliverToBoxAdapter(
          child: SizedBox(height: safeTop + 10),
        ),

        // 移动端：继续追番置顶
        SliverToBoxAdapter(
          child: _buildContinueWatchingShelf(),
        ),

        // 每日放送周历横滑条 + 今日算法推荐卡片
        SliverToBoxAdapter(
          child: Column(
            children: [
              if (data.today.isNotEmpty || data.calendarDays.isNotEmpty) ...[
                const SizedBox(height: 8),
                TodayAnimeShelf(
                  calendarDays: data.calendarDays,
                  items: data.today,
                  weekdayName: data.weekdayName,
                ),
                const SizedBox(height: 10),
              ],
              if (data.recommendations.isNotEmpty) ...[
                DailySpotlightCard(
                  recommendations: data.recommendations,
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),

        // 货架列表与探索板块
        ..._buildShelfSlivers(
          data: data,
          theme: theme,
          uniqueExploreItems: uniqueExploreItems,
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
  /// 1. HomeDesktopHero 居首：以大图轮播+6宫格周历撑起大屏开阔门面与环境流光景深；
  /// 2. 继续追番下移至 Hero 之后：符合从“宏观焦点”到“个人记录”再到“深度探索”的认知流向，避免扁平小卡片在首屏破坏视觉质感；
  /// 3. 货架与模块全部限制在 maxContentWidth(1200dp) 居中垂直对齐。
  Widget _buildDesktopLayout({
    required BuildContext context,
    required ThemeData theme,
    required double safeTop,
    required _HomeData data,
    required List<BangumiItem> uniqueExploreItems,
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
        if (data.tv.isNotEmpty || data.today.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: HomeDesktopHero(
                      bannerItems: data.tv,
                      recommendations: data.recommendations,
                      calendarDays: data.calendarDays,
                      todayItems: data.today,
                      weekdayName: data.weekdayName,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // 桌面端：继续追番承接在 Hero 下方
        SliverToBoxAdapter(
          child: _buildContinueWatchingShelf(),
        ),

        // 货架列表与探索板块
        ..._buildShelfSlivers(
          data: data,
          theme: theme,
          uniqueExploreItems: uniqueExploreItems,
        ),

        // 底部留出 96px 安全高度
        const SliverToBoxAdapter(
          child: SizedBox(height: 96),
        ),
      ],
    );
  }

  /// 公共分类货架与探索板块 Slivers
  List<Widget> _buildShelfSlivers({
    required _HomeData data,
    required ThemeData theme,
    required List<BangumiItem> uniqueExploreItems,
  }) {
    return [
      // 货架 1：热门 TV 番剧独立货架
      SliverToBoxAdapter(
        child: _buildResponsiveShelf(
          AnimeHorizontalShelf(
            icon: Icons.tv_rounded,
            title: '热门 TV 番剧',
            items: data.tv,
            defaultStatType: 'heat',
            viewAllSubtitle: '浏览全部 TV',
            onViewAllTap: () => _onShelfViewAllTap(
              'TV',
              year: CategoryConstants.currentYear,
              month: CategoryConstants.currentSeasonMonth,
            ),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 12)),

      // 货架 2：热门剧场版独立货架
      SliverToBoxAdapter(
        child: _buildResponsiveShelf(
          AnimeHorizontalShelf(
            icon: Icons.movie_filter_rounded,
            title: '热门剧场版',
            items: data.movies,
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
          AnimeHorizontalShelf(
            icon: Icons.album_rounded,
            title: '热门 OVA / 特别篇',
            items: data.ova,
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
                      color: theme.textTheme.titleLarge?.color,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${uniqueExploreItems.length} 部精选',
                    style: TextStyle(
                      fontSize: 12,
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

  /// 1:1 动态流光骨架屏结构：对应轮播图、今日更新与 3 行独立货架的平滑加载占位
  Widget _buildShimmerSkeleton(BuildContext context, ThemeData theme, double safeTop) {
    Widget buildShelfSkeletonRow(String title) {
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

    return Shimmer(
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(height: safeTop + 10),
          ),
          SliverToBoxAdapter(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 840;

                if (isDesktop) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 12),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16),
                          child: ShimmerDesktopHero(),
                        ),
                      ),
                    ),
                  );
                }

                return const Column(
                  children: [
                    SizedBox(height: 8),
                    ShimmerTodayShelf(),
                    SizedBox(height: 12),
                  ],
                );
              },
            ),
          ),
          // 3 行独立货架骨架流光
          SliverToBoxAdapter(
            child: _buildResponsiveShelf(buildShelfSkeletonRow('TV 番剧')),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: _buildResponsiveShelf(buildShelfSkeletonRow('剧场版')),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: _buildResponsiveShelf(buildShelfSkeletonRow('OVA 特别篇')),
          ),

          if (_showExploreSection) ...[
            const SliverToBoxAdapter(
              child: SizedBox(height: 14),
            ),
            // 探索标题骨架
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: ShimmerLoading(
                  child: Container(
                    height: 18,
                    width: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
            // 双列网格骨架（6 张卡片占位）
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
                  (context, index) => const ShimmerAnimeCard(),
                  childCount: 6,
                ),
              ),
            ),
          ],
          const SliverToBoxAdapter(
            child: SizedBox(height: 96),
          ),
        ],
      ),
    );
  }
}
