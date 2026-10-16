import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/bangumi/bangumi_calendar.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/models/home/recommend_item.dart';
import '../../../core/theme/m3_surface.dart';
import '../../common/widgets/anime_card.dart';
import '../../common/widgets/shimmer_loading.dart';
import 'home_banner_carousel.dart';

/// 桌面/宽屏端 Hero 分栏黄金排版（智能推荐 + 全周新番）：
/// 1. 左侧：智能个性化推荐轮播图（注入算法标签与推荐理由，大图呼吸动效）；
/// 2. 右侧：与左侧等高对齐的“全周新番” 2行 × 3列 6 宫格矩阵，头部整合周一至周日胶囊快速切换；
/// 3. 支持右上角“换一批 / 翻页”微交互与平滑动画；
/// 4. 彻底解决大屏下单列轮播两边留白过宽与纯横向滑动割裂的问题。
class HomeDesktopHero extends StatefulWidget {
  final List<BangumiItem>? bannerItems;
  final List<RecommendItem>? recommendations;
  final List<BangumiCalendarDay>? calendarDays;
  final List<BangumiItem>? todayItems;
  final String? weekdayName;

  const HomeDesktopHero({
    super.key,
    this.bannerItems,
    this.recommendations,
    this.calendarDays,
    this.todayItems,
    this.weekdayName,
  });

  @override
  State<HomeDesktopHero> createState() => _HomeDesktopHeroState();
}

class _HomeDesktopHeroState extends State<HomeDesktopHero> {
  late final PageController _gridPageController;
  int _gridPageIndex = 0;
  late int _selectedDayIndex;
  late final int _todayWeekdayIndex;

  static const double _heroHeight = 340.0;
  static const int _cardsPerPage = 6;
  static const _weekLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  static const _singleWeekLabels = ['一', '二', '三', '四', '五', '六', '日'];

  @override
  void initState() {
    super.initState();
    _gridPageController = PageController();
    final todayWeekday = DateTime.now().weekday; // 1=Mon .. 7=Sun
    _todayWeekdayIndex = (todayWeekday - 1).clamp(0, 6);
    _selectedDayIndex = _todayWeekdayIndex;
  }

  @override
  void dispose() {
    _gridPageController.dispose();
    super.dispose();
  }

  List<BangumiItem> get _currentDayItems {
    final days = widget.calendarDays;
    if (days != null && days.isNotEmpty) {
      final targetDayId = _selectedDayIndex + 1;
      final matchedDay = days.firstWhere(
        (d) => d.weekday.id == targetDayId,
        orElse: () => BangumiCalendarDay(
          weekday: BangumiWeekday(
            id: targetDayId,
            en: '',
            cn: _weekLabels[_selectedDayIndex],
            ja: '',
          ),
          items: const [],
        ),
      );
      return matchedDay.items;
    }
    return widget.todayItems ?? const [];
  }

  int get _totalPages => (_currentDayItems.length / _cardsPerPage).ceil().clamp(1, 99);

  void _onSelectDay(int index) {
    if (index == _selectedDayIndex) return;
    HapticFeedback.lightImpact();
    setState(() {
      _selectedDayIndex = index;
      _gridPageIndex = 0;
    });
    if (_gridPageController.hasClients) {
      _gridPageController.jumpToPage(0);
    }
  }

  void _nextPage() {
    HapticFeedback.lightImpact();
    if (_totalPages <= 1) return;
    final next = (_gridPageIndex + 1) % _totalPages;
    _gridPageController.animateToPage(
      next,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _prevPage() {
    HapticFeedback.lightImpact();
    if (_totalPages <= 1) return;
    final prev = (_gridPageIndex - 1 + _totalPages) % _totalPages;
    _gridPageController.animateToPage(
      prev,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: _heroHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 左侧：智能推荐轮播图（flex: 5，占比约 46%）
          Expanded(
            flex: 5,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(isDark ? 55 : 18),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: HomeBannerCarousel(
                  items: widget.bannerItems,
                  recommendations: widget.recommendations,
                  height: _heroHeight,
                  padding: EdgeInsets.zero,
                  borderRadius: 14,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // 2. 右侧：全周新番 6 宫格矩阵（flex: 6，占比约 54%）
          Expanded(
            flex: 6,
            child: Container(
              height: _heroHeight,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              decoration: BoxDecoration(
                color: M3Surface.container(context, level: M3ContainerLevel.low),
                borderRadius: BorderRadius.circular(16),
                border: M3Surface.cardBorder(context),
                boxShadow: M3Surface.cardShadow(context),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 头部：标题与“换一批/翻页”控件
                  _buildHeader(theme, isDark),
                  const SizedBox(height: 5),

                  // 胶囊星期切换条
                  if (widget.calendarDays != null && widget.calendarDays!.isNotEmpty) ...[
                    _buildWeekdayCapsules(theme, isDark),
                    const SizedBox(height: 5),
                  ],

                  // 2行 × 3列 6宫格翻页视图
                  Expanded(
                    child: _currentDayItems.isEmpty
                        ? Center(
                            child: Text(
                              '当天暂无新番播出',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : PageView.builder(
                            key: ValueKey('desktop_grid_$_selectedDayIndex'),
                            controller: _gridPageController,
                            itemCount: _totalPages,
                            onPageChanged: (index) {
                              setState(() {
                                _gridPageIndex = index;
                              });
                            },
                            itemBuilder: (context, pageIndex) {
                              return _buildSixGridPage(pageIndex);
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 标题栏：轻量矢量图标 + 新番每日放送 + 翻页与换一批操作
  Widget _buildHeader(ThemeData theme, bool isDark) {
    final currentDayItems = _currentDayItems;
    final isToday = _selectedDayIndex == _todayWeekdayIndex;

    return Row(
      children: [
        Icon(
          Icons.calendar_month_rounded,
          size: 18,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(width: 7),
        Text(
          '每日放送',
          style: TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: theme.textTheme.titleMedium?.color,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${_weekLabels[_selectedDayIndex]} · ${isToday ? '今日 ' : ''}${currentDayItems.length} 部更新',
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.normal,
          ),
        ),
        const Spacer(),

        // 翻页指示与控制按钮组
        if (_totalPages > 1) ...[
          Text(
            '${_gridPageIndex + 1} / $_totalPages',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          _buildActionIconButton(
            icon: Icons.chevron_left_rounded,
            tooltip: '上一页',
            onTap: _prevPage,
            isDark: isDark,
          ),
          _buildActionIconButton(
            icon: Icons.chevron_right_rounded,
            tooltip: '下一页',
            onTap: _nextPage,
            isDark: isDark,
          ),
          const SizedBox(width: 4),
          // 换一批快速翻页按钮
          Material(
            color: theme.colorScheme.primary.withAlpha(isDark ? 36 : 20),
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              onTap: _nextPage,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.refresh_rounded,
                      size: 13,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '换一批',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 桌面端周一至周日单字分段条（独立跑道居中排布）：
  /// 1. 采用精致紧凑的跑道凹槽背景（高 28dp、宽 294dp），均分 7 等分，节省垂直空间给下方番剧卡片；
  /// 2. 融入桌面专属体验：hover 背景反馈、click 鼠标手型、长按或悬停 Tooltip 完整星期提示。
  Widget _buildWeekdayCapsules(ThemeData theme, bool isDark) {
    return Center(
      child: Container(
        height: 29,
        constraints: const BoxConstraints(maxWidth: 294),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
          borderRadius: BorderRadius.circular(15),
        ),
        padding: const EdgeInsets.all(2.5),
        child: Row(
          children: List.generate(7, (index) {
            final isSelected = index == _selectedDayIndex;
            final isCurrentDay = index == _todayWeekdayIndex;

            return Expanded(
              child: Tooltip(
                message: '${_weekLabels[index]}${isCurrentDay ? " · 今日" : ""}',
                waitDuration: const Duration(milliseconds: 300),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _onSelectDay(index),
                      hoverColor: theme.colorScheme.primary.withAlpha(isDark ? 28 : 16),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _singleWeekLabels[index],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : (isCurrentDay ? FontWeight.w600 : FontWeight.w500),
                            color: isSelected
                                ? theme.colorScheme.onPrimary
                                : (isCurrentDay
                                    ? theme.colorScheme.primary
                                    : (isDark ? Colors.white70 : Colors.black87)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildActionIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          child: Padding(
            padding: const EdgeInsets.all(4.0),
            child: Icon(
              icon,
              size: 18,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  /// 单页 6 宫格矩阵（2 行 × 3 列），通过 Row + Column + Expanded 严格等比填充
  Widget _buildSixGridPage(int pageIndex) {
    final startIndex = pageIndex * _cardsPerPage;

    return Column(
      children: [
        // 第 1 排（3 部）
        Expanded(
          child: Row(
            children: [
              _buildGridCard(startIndex + 0),
              const SizedBox(width: 8),
              _buildGridCard(startIndex + 1),
              const SizedBox(width: 8),
              _buildGridCard(startIndex + 2),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // 第 2 排（3 部）
        Expanded(
          child: Row(
            children: [
              _buildGridCard(startIndex + 3),
              const SizedBox(width: 8),
              _buildGridCard(startIndex + 4),
              const SizedBox(width: 8),
              _buildGridCard(startIndex + 5),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGridCard(int index) {
    final items = _currentDayItems;
    if (index < items.length) {
      return Expanded(
        child: AnimeCard(
          item: items[index],
          compact: true,
        ),
      );
    }
    // 最后一页不足 6 部时用空白占位填充，确保规整对齐
    return const Expanded(
      child: SizedBox.shrink(),
    );
  }
}

/// 1:1 桌面端分栏 Hero 流光骨架屏
class ShimmerDesktopHero extends StatelessWidget {
  const ShimmerDesktopHero({super.key});

  static const double _heroHeight = 340.0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: _heroHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 左侧轮播骨架
          Expanded(
            flex: 5,
            child: ShimmerLoading(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E22) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),

          // 右侧 6 宫格骨架
          Expanded(
            flex: 6,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E22).withAlpha(235)
                    : Colors.white.withAlpha(240),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withAlpha(28)
                      : Colors.black.withAlpha(18),
                  width: 1.0,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      ShimmerLoading(
                        child: Container(
                          height: 18,
                          width: 140,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: Row(
                            children: const [
                              Expanded(child: ShimmerAnimeCard()),
                              SizedBox(width: 8),
                              Expanded(child: ShimmerAnimeCard()),
                              SizedBox(width: 8),
                              Expanded(child: ShimmerAnimeCard()),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: Row(
                            children: const [
                              Expanded(child: ShimmerAnimeCard()),
                              SizedBox(width: 8),
                              Expanded(child: ShimmerAnimeCard()),
                              SizedBox(width: 8),
                              Expanded(child: ShimmerAnimeCard()),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
