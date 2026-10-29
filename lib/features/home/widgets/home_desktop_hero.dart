import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/bangumi/bangumi_calendar.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/models/home/recommend_item.dart';
import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/anime_card.dart';
import '../../common/widgets/directional_horizontal_scroll.dart';
import '../../common/widgets/shimmer_loading.dart';
import 'home_banner_carousel.dart';

/// 桌面/宽屏端 Hero 分栏黄金排版（智能推荐 + 今日放送）：
/// 1. 左侧：智能个性化推荐轮播图（注入算法标签与推荐理由，大图呼吸动效）；
/// 2. 右侧：与左侧等高平行的“今日放送” 2行 × 3列 6 宫格矩阵；
/// 3. 顶部独立边框控制条：显示“今日放送 周X · N 部更新”，支持上一页/下一页及“时间表 ›”直达全周日历；
/// 4. 6 个番剧卡片无外边框包裹，直铺展示，卡片上下边界与左侧轮播图完美平行对齐。
class HomeDesktopHero extends StatefulWidget {
  final List<BangumiItem>? bannerItems;
  final List<RecommendItem>? recommendations;
  final List<BangumiCalendarDay>? calendarDays;
  final List<BangumiItem>? todayItems;
  final String? weekdayName;
  final VoidCallback? onOpenTimeline;

  const HomeDesktopHero({
    super.key,
    this.bannerItems,
    this.recommendations,
    this.calendarDays,
    this.todayItems,
    this.weekdayName,
    this.onOpenTimeline,
  });

  @override
  State<HomeDesktopHero> createState() => _HomeDesktopHeroState();
}

class _HomeDesktopHeroState extends State<HomeDesktopHero> {
  late final PageController _gridPageController;
  int _gridPageIndex = 0;

  static const double _heroHeight = 340.0;
  static const int _cardsPerPage = 6;
  static const _weekLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  void initState() {
    super.initState();
    _gridPageController = PageController();
  }

  @override
  void dispose() {
    _gridPageController.dispose();
    super.dispose();
  }

  List<BangumiItem> get _currentItems {
    if (widget.todayItems != null && widget.todayItems!.isNotEmpty) {
      return widget.todayItems!;
    }
    final days = widget.calendarDays;
    if (days != null && days.isNotEmpty) {
      final todayWeekday = DateTime.now().weekday; // 1=Mon .. 7=Sun
      final matchedDay = days.firstWhere(
        (d) => d.weekday.id == todayWeekday,
        orElse: () => days.first,
      );
      return matchedDay.items;
    }
    return const [];
  }

  String get _currentWeekdayLabel {
    if (widget.weekdayName != null && widget.weekdayName!.isNotEmpty) {
      return widget.weekdayName!;
    }
    final todayWeekday = DateTime.now().weekday;
    return _weekLabels[(todayWeekday - 1).clamp(0, 6)];
  }

  int get _totalPages => (_currentItems.length / _cardsPerPage).ceil().clamp(1, 99);

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

          // 2. 右侧：今日放送 6 宫格矩阵（flex: 6，占比约 54%）
          // 去除外层大框，让 6 张卡片与左侧轮播图完美平行对齐
          Expanded(
            flex: 6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 顶部独立控制条（带框胶囊条）
                _buildControlBar(theme, isDark),
                const SizedBox(height: 8),

                // 2行 × 3列 6宫格翻页视图（无外框）
                Expanded(
                  child: _currentItems.isEmpty
                      ? Center(
                          child: Text(
                            '当天暂无新番播出',
                            style: appTextStyle(
                              fontSize: 12.5,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : DirectionalHorizontalScroll(
                          child: PageView.builder(
                            key: const ValueKey('desktop_grid_today_hero'),
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 顶部独立边框控制条：显示“今日放送 周X · N 部更新”，翻页控件与“时间表 ›”入口
  Widget _buildControlBar(ThemeData theme, bool isDark) {
    final currentItems = _currentItems;

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: M3Surface.container(context, level: M3ContainerLevel.low),
        borderRadius: BorderRadius.circular(10),
        border: M3Surface.cardBorder(context),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 15,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            '今日放送',
            style: appTextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: theme.textTheme.titleMedium?.color,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$_currentWeekdayLabel · ${currentItems.length} 部更新',
            style: appTextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const Spacer(),

          // 翻页指示与控制按钮组
          if (_totalPages > 1) ...[
            Text(
              '${_gridPageIndex + 1} / $_totalPages',
              style: appTextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
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
            const SizedBox(width: 6),
          ],

          // 时间表入口直达
          if (widget.onOpenTimeline != null) ...[
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onOpenTimeline,
                  borderRadius: BorderRadius.circular(6),
                  hoverColor: theme.colorScheme.primary.withAlpha(isDark ? 28 : 16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '时间表',
                          style: appTextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
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
            padding: const EdgeInsets.all(3.0),
            child: Icon(
              icon,
              size: 17,
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
        const SizedBox(height: 8),

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
    final items = _currentItems;
    if (index < items.length) {
      return Expanded(
        child: AnimeCard(
          item: items[index],
          compact: true,
          glassOverlay: true,
        ),
      );
    }
    // 最后一页不足 6 部时用空白占位填充，确保规整对齐
    return const Expanded(
      child: SizedBox.shrink(),
    );
  }
}

/// 1:1 桌面端分栏 Hero 流光骨架屏（无外边框，完美对齐实际呈现）
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

          // 右侧 6 宫格骨架（无外框）
          Expanded(
            flex: 6,
            child: Column(
              children: [
                // 顶部控制条骨架
                ShimmerLoading(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF1E1E22)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withAlpha(22)
                            : Colors.black.withAlpha(15),
                        width: 1.0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
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
                      const SizedBox(height: 8),
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
        ],
      ),
    );
  }
}
