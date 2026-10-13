import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/utils/font_manager.dart';
import '../../../core/utils/responsive.dart';
import '../../common/widgets/anime_card.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import '../../common/widgets/cached_anime_image.dart';
import '../../common/widgets/directional_horizontal_scroll.dart';

/// 现代流媒体原生多轨货架组件（Netflix / Apple TV / Animaku 经典设计）：
/// 1. 纯净大气的原生标题栏，无任何 Web 杂乱超链接；
/// 2. 达到列表末端时展示原生“浏览全部”专属探索卡片，顺应用户滑尽意犹未尽的自然动线；
/// 3. 严格控制预加载范围（scrollCacheExtent: 100px）与图片降采样（resizeWidth: 300），
///    即便多行同屏，也绝不引发图片并发风暴与掉帧；
/// 4. 桌面端鼠标滚轮上下滑动平滑转横向平滑滚动 + 卡片按压弹性手感。
class AnimeHorizontalShelf extends StatefulWidget {
  static const double cardWidth = 136;
  static const double cardAspectRatio = 2 / 3;
  static const double cardHeight = cardWidth / cardAspectRatio; // 204

  static const Color _goldColor = Color(0xFFFFD700);
  static const Color _silverColor = Color(0xFFC0C0C0);
  static const Color _bronzeColor = Color(0xFFCD7F32);

  // Animaku 原生规范统计标签语义色彩：
  // 热度: 玫瑰火红 (rose-400), 在看: 琥珀金黄 (amber-400), 已看: 翡翠翠绿 (emerald-400)
  static const Color heatColor = Color(0xFFFB7185);
  static const Color doingColor = Color(0xFFFBBF24);
  static const Color collectColor = Color(0xFF34D399);

  final IconData? icon;
  final String title;
  final List<BangumiItem> items;
  final VoidCallback? onViewAllTap;
  final String viewAllSubtitle;
  final bool showRankBadges;
  final String defaultStatType; // 'heat' | 'collect' | 'doing'

  const AnimeHorizontalShelf({
    super.key,
    this.icon,
    required this.title,
    required this.items,
    this.onViewAllTap,
    this.viewAllSubtitle = '浏览全部',
    this.showRankBadges = true,
    this.defaultStatType = 'heat',
  });

  @override
  State<AnimeHorizontalShelf> createState() => _AnimeHorizontalShelfState();
}

/// 向后兼容类型别名（兼容旧引用）
typedef RankHorizontalSection = AnimeHorizontalShelf;

class _AnimeHorizontalShelfState extends State<AnimeHorizontalShelf> {
  final ScrollController _scrollController = ScrollController();
  bool _isHovering = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
  }

  @override
  void didUpdateWidget(covariant AnimeHorizontalShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollButtons);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!mounted || !_scrollController.hasClients) return;
    final offset = _scrollController.offset;
    final max = _scrollController.position.maxScrollExtent;
    final canLeft = offset > 10;
    final canRight = offset < max - 10;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  void _scrollBy(double offsetDelta) {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + offsetDelta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  /// 依据 Animaku 规范解析卡片左下角统计指标与语义色彩
  ({String count, String label, Color color})? _resolveCardStat(BangumiItem item) {
    if (widget.defaultStatType == 'heat') {
      if (item.heat != null && item.heat! > 0) {
        return (count: formatCompactCount(item.heat), label: '热度', color: AnimeHorizontalShelf.heatColor);
      }
      if (item.doing != null && item.doing! > 0) {
        return (count: formatCompactCount(item.doing), label: '在看', color: AnimeHorizontalShelf.doingColor);
      }
      if (item.collect != null && item.collect! > 0) {
        return (count: formatCompactCount(item.collect), label: '已看', color: AnimeHorizontalShelf.collectColor);
      }
      return null;
    }

    if (item.collect != null && item.collect! > 0) {
      return (count: formatCompactCount(item.collect), label: '已看', color: AnimeHorizontalShelf.collectColor);
    }
    if (item.heat != null && item.heat! > 0) {
      return (count: formatCompactCount(item.heat), label: '热度', color: AnimeHorizontalShelf.heatColor);
    }
    if (item.doing != null && item.doing! > 0) {
      return (count: formatCompactCount(item.doing), label: '在看', color: AnimeHorizontalShelf.doingColor);
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    // 列表项总数：实际动漫数量 + 末端“浏览全部”专属探索卡片
    final hasViewAllCard = widget.onViewAllTap != null && widget.items.isNotEmpty;
    final totalItemCount = widget.items.length + (hasViewAllCard ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context),
        const SizedBox(height: 6),
        SizedBox(
          height: AnimeHorizontalShelf.cardHeight + 46,
          child: widget.items.isEmpty
              ? _buildEmptyPlaceholder(context)
              : DirectionalHorizontalScroll(
                  child: MouseRegion(
                    onEnter: (_) {
                      if (context.isDesktop) setState(() => _isHovering = true);
                    },
                    onExit: (_) {
                      if (context.isDesktop) setState(() => _isHovering = false);
                    },
                    child: Stack(
                      children: [
                        Listener(
                          // 特殊处理说明：
                          // 针对桌面端（Windows/macOS），仅响应真正的横向滚轮/触摸板横向滑动手势 (dx != 0)。
                          // 绝对不拦截普通垂直滚轮 (dy)，让垂直滚动事件自然冒泡传递给外层页面，
                          // 彻底解决鼠标光标停留在卡片上导致整页滚动卡死、货架左右乱窜的问题。
                          onPointerSignal: (pointerSignal) {
                            if (pointerSignal is PointerScrollEvent) {
                              final double delta = pointerSignal.scrollDelta.dx;
                              if (delta != 0 && _scrollController.hasClients) {
                                final double targetOffset = (_scrollController.offset + delta).clamp(
                                  0.0,
                                  _scrollController.position.maxScrollExtent,
                                );
                                _scrollController.jumpTo(targetOffset);
                              }
                            }
                          },
                          child: ListView.builder(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            // 核心性能防线：仅预加载可视区外 100px (约半张卡片)，未进入视口的卡片绝不发起网络下载与解码
                            scrollCacheExtent: const ScrollCacheExtent.pixels(100),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: totalItemCount,
                            itemBuilder: (context, index) {
                              if (index < widget.items.length) {
                                return _buildAnimeItemCard(context, widget.items[index], index);
                              } else {
                                // 列表末端专属的“浏览全部”卡片（Netflix / Apple TV 官方体验）
                                return _buildViewAllCard(context);
                              }
                            },
                          ),
                        ),

                        // 桌面端专属：悬浮翻页左右导航按钮（Netflix/B站网页端经典交互）
                        if (context.isDesktop && _canScrollLeft)
                          Positioned(
                            left: 6,
                            top: (AnimeHorizontalShelf.cardHeight - 38) / 2,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              opacity: _isHovering ? 1.0 : 0.0,
                              child: _buildScrollNavButton(
                                isRight: false,
                                onTap: () => _scrollBy(-420),
                              ),
                            ),
                          ),
                        if (context.isDesktop && _canScrollRight)
                          Positioned(
                            right: 6,
                            top: (AnimeHorizontalShelf.cardHeight - 38) / 2,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              opacity: _isHovering ? 1.0 : 0.0,
                              child: _buildScrollNavButton(
                                isRight: true,
                                onTap: () => _scrollBy(420),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// 桌面端悬浮翻页导航按钮
  Widget _buildScrollNavButton({
    required bool isRight,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: isDark
          ? theme.colorScheme.surfaceContainerHigh.withAlpha(230)
          : theme.colorScheme.surface.withAlpha(240),
      shape: const CircleBorder(),
      elevation: 4,
      shadowColor: Colors.black38,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(
            isRight ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
            size: 26,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  /// 规范排印的原生大标题 + 矢量图标与直达“全部”入口
  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Row(
        children: [
          if (widget.icon != null) ...[
            Icon(
              widget.icon,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: theme.textTheme.titleLarge?.color,
              ),
            ),
          ),
          if (widget.onViewAllTap != null)
            Material(
              color: theme.colorScheme.primary.withAlpha(isDark ? 36 : 20),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: widget.onViewAllTap,
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.grid_view_rounded,
                        size: 13,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        '全部',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: FontManager.instance.activeFontFamily,
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 常规动漫卡片（搭载金银铜勋章、语义色彩角标、按压弹性手感）
  Widget _buildAnimeItemCard(BuildContext context, BangumiItem item, int index) {
    final rank = index + 1;
    final rankColor = _getRankColor(rank);
    final stat = _resolveCardStat(item);

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: BouncingScaleCard(
        immediateTap: true,
        onTap: () => navigateToVideoPlayer(context, item),
        child: SizedBox(
          width: AnimeHorizontalShelf.cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 封面图片区
              SizedBox(
                height: AnimeHorizontalShelf.cardHeight,
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: AspectRatio(
                        aspectRatio: AnimeHorizontalShelf.cardAspectRatio,
                        child: CachedAnimeImage(
                          imageUrl: item.thumbnailUrl.isNotEmpty
                              ? item.thumbnailUrl
                              : item.coverUrl,
                          width: AnimeHorizontalShelf.cardWidth,
                          height: AnimeHorizontalShelf.cardHeight,
                        ),
                      ),
                    ),
                    // 左上角排名勋章
                    if (widget.showRankBadges)
                      _buildRankBadge(rank, rankColor),
                    // 右上角评分角标 (M3 胶囊药丸)
                    if (item.ratingScore > 0)
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
                              const SizedBox(width: 2),
                              Text(
                                '${item.ratingScore}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    // 封面底部暗色渐变遮罩
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 40,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withAlpha(200),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 左下角：按 Animaku 规范呈现高亮数字与柔和标签
                    if (stat != null)
                      Positioned(
                        left: 6,
                        bottom: 4,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              stat.count,
                              style: TextStyle(
                                color: stat.color,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 2.5),
                            Text(
                              stat.label,
                              style: TextStyle(
                                color: Colors.white.withAlpha(210),
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),

              // 标题固定 32px 高度（恒定容纳 2 行高度），杜绝不同条目标题行数差异造成的卡片垂直高度抖动
              SizedBox(
                height: 32,
                child: Text(
                  item.preferredName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 列表末端专属的“浏览全部”探索卡片（Netflix / Apple TV 官方规范）：
  /// 尺寸与普通卡片完全一致，用户滑到货架尽头时自然映入眼帘，点击带弹性反馈直接跳转
  Widget _buildViewAllCard(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: BouncingScaleCard(
        onTap: widget.onViewAllTap,
        child: SizedBox(
          width: AnimeHorizontalShelf.cardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: AnimeHorizontalShelf.cardHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: theme.colorScheme.surfaceContainerHigh,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.secondaryContainer,
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 22,
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.viewAllSubtitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.items.length}+ 部作品',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              // 与普通卡片的 32px 标题高度严格保持一致，确保整体水平基线规整
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRankBadge(int rank, Color rankColor) {
    return Positioned(
      top: 0,
      left: 0,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: rankColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            bottomRight: Radius.circular(12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 4,
              offset: const Offset(1, 1),
            ),
          ],
        ),
        child: Text(
          '#$rank',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            fontSize: 11.5,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  Color _getRankColor(int rank) {
    if (rank == 1) return AnimeHorizontalShelf._goldColor;
    if (rank == 2) return AnimeHorizontalShelf._silverColor;
    if (rank == 3) return AnimeHorizontalShelf._bronzeColor;
    return Colors.blueGrey.withAlpha(200);
  }

  Widget _buildEmptyPlaceholder(BuildContext context) {
    final theme = Theme.of(context);
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: SizedBox(
            width: AnimeHorizontalShelf.cardWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: AnimeHorizontalShelf.cardHeight,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 14,
                  width: 90,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
