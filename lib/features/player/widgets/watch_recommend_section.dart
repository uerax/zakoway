import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/models/bangumi/bangumi_recommendation_item.dart';
import '../../../core/providers/bangumi_providers.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import '../../common/widgets/cached_anime_image.dart';

/// 播放页视频推荐区组件
///
/// 特性：
/// 1. 续作/前传 (Slot 0) 独立极速请求，提前返回并置顶展示，杜绝等待；
/// 2. 相似推荐仅保留日本番剧、评分 > 0 且评分人数 >= 50；
/// 3. 首屏默认快速加载前 5 部，避免长耗时旋转等待；
/// 4. 监听页面滚动，下滑触底时自动懒加载更多推荐。
class WatchRecommendSection extends ConsumerStatefulWidget {
  const WatchRecommendSection({
    super.key,
    this.bangumiId,
    this.bangumiItem,
    this.onTapItem,
  });

  final int? bangumiId;
  final BangumiItem? bangumiItem;
  final ValueChanged<BangumiRecommendationItem>? onTapItem;

  @override
  ConsumerState<WatchRecommendSection> createState() => _WatchRecommendSectionState();
}

class _WatchRecommendSectionState extends ConsumerState<WatchRecommendSection> {
  // 续作/前传（Slot 0 独立状态，毫秒级快速上屏）
  BangumiRecommendationItem? _relationItem;
  bool _isLoadingRelation = false;

  // 相似推荐列表（分批与懒加载）
  final List<BangumiRecommendationItem> _similarItems = [];
  bool _isLoadingSimilar = false;
  bool _isLoadingMore = false;
  bool _hasMoreSimilar = true;
  int _currentPage = 1;
  int _refreshCount = 0;
  String? _error;

  ScrollPosition? _scrollPosition;

  @override
  void initState() {
    super.initState();
    _fetchRecommendations();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 监听外部滚动容器的滚动位置，实现平滑触底懒加载
    final scrollable = Scrollable.maybeOf(context);
    final position = scrollable?.position;
    if (_scrollPosition != position) {
      _scrollPosition?.removeListener(_onScroll);
      _scrollPosition = position;
      _scrollPosition?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollPosition;
    if (pos == null || !pos.hasContentDimensions) return;
    // 距离底部不足 300px 时自动预加载下一页
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMoreSimilar();
    }
  }

  @override
  void didUpdateWidget(covariant WatchRecommendSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bangumiId != widget.bangumiId ||
        (oldWidget.bangumiItem == null && widget.bangumiItem != null) ||
        ((oldWidget.bangumiItem?.tags.isEmpty ?? true) &&
            (widget.bangumiItem?.tags.isNotEmpty ?? false))) {
      _refreshCount = 0;
      _fetchRecommendations();
    }
  }

  Future<void> _fetchRecommendations({bool forceRefresh = false}) async {
    final subjectId = widget.bangumiId ?? widget.bangumiItem?.id ?? 0;
    if (subjectId <= 0) return;

    if (forceRefresh) {
      _refreshCount++;
    }

    setState(() {
      _isLoadingRelation = true;
      _isLoadingSimilar = true;
      _error = null;
      _currentPage = 1;
      _hasMoreSimilar = true;
      if (forceRefresh) {
        _relationItem = null;
        _similarItems.clear();
      }
    });

    final client = ref.read(bangumiClientProvider);

    // 1. 续作/前传请求（单次轻量独立请求，提前返回展示，绝不阻塞）
    client.getRelationItem(subjectId, forceRefresh: forceRefresh).then((relItem) {
      if (!mounted) return;
      setState(() {
        _relationItem = relItem;
        _isLoadingRelation = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _isLoadingRelation = false;
      });
    });

    // 2. 相似推荐首屏请求（基于多维题材切面与质数散列深度大跨度散落，默认加载 5 部）
    final rawTags = widget.bangumiItem?.tags.map((t) => t.name).toList();
    final isMovie = widget.bangumiItem != null
        ? (widget.bangumiItem!.totalEpisodes == 1 && widget.bangumiItem!.eps == 1) ||
            widget.bangumiItem!.name.contains('剧场版') ||
            widget.bangumiItem!.nameCn.contains('剧场版') ||
            widget.bangumiItem!.tags.any((t) => t.name.contains('剧场版') || t.name.contains('动画电影'))
        : null;

    try {
      final res = await client.getSimilarRecommendations(
        subjectId,
        tags: rawTags,
        isMovie: isMovie,
        page: 1,
        pageSize: 5,
        refreshIndex: _refreshCount,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;
      setState(() {
        _similarItems.clear();
        _similarItems.addAll(res.items);
        _hasMoreSimilar = res.hasMore;
        _currentPage = 1;
        _isLoadingSimilar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingSimilar = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMoreSimilar() async {
    if (_isLoadingSimilar || _isLoadingMore || !_hasMoreSimilar) return;

    final subjectId = widget.bangumiId ?? widget.bangumiItem?.id ?? 0;
    if (subjectId <= 0) return;

    setState(() {
      _isLoadingMore = true;
    });

    final client = ref.read(bangumiClientProvider);
    final nextPage = _currentPage + 1;
    final rawTags = widget.bangumiItem?.tags.map((t) => t.name).toList();
    final isMovie = widget.bangumiItem != null
        ? (widget.bangumiItem!.totalEpisodes == 1 && widget.bangumiItem!.eps == 1) ||
            widget.bangumiItem!.name.contains('剧场版') ||
            widget.bangumiItem!.nameCn.contains('剧场版') ||
            widget.bangumiItem!.tags.any((t) => t.name.contains('剧场版') || t.name.contains('动画电影'))
        : null;

    try {
      final res = await client.getSimilarRecommendations(
        subjectId,
        tags: rawTags,
        isMovie: isMovie,
        page: nextPage,
        pageSize: 5,
        refreshIndex: _refreshCount,
        excludeIds: {
          if (_relationItem != null) _relationItem!.id,
          ..._similarItems.map((e) => e.id),
        },
      );

      if (!mounted) return;
      setState(() {
        _currentPage = nextPage;
        _similarItems.addAll(res.items);
        _hasMoreSimilar = res.hasMore;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final displayedItems = [
      ?_relationItem,
      ..._similarItems.where((it) => _relationItem == null || it.id != _relationItem!.id),
    ];

    final isAnyLoading = _isLoadingRelation || _isLoadingSimilar;
    final hasNoItems = displayedItems.isEmpty;

    // 当且仅当所有网络加载均已彻底结束，且没有报错、确实没有任何推荐条目时，才隐藏整个区域
    if (!isAnyLoading && _error == null && hasNoItems) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题与副标
          Row(
            children: [
              Container(
                width: 3.5,
                height: 14,
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '番剧推荐',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  fontFamily: 'MiSans',
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                ),
              ),
              const Spacer(),
              if (isAnyLoading && displayedItems.isEmpty)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: primaryColor.withValues(alpha: 0.7),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 骨架屏加载态（在尚无任何条目就绪且仍在加载时平滑呈现，防止组件闪烁与高度塌陷）
          if (hasNoItems && isAnyLoading)
            _buildSkeletonList(isDark)
          else if (_error != null && displayedItems.isEmpty)
            _buildErrorState(primaryColor)
          else ...[
            // 已有推荐卡片流
            _buildRecommendationsList(displayedItems, isDark, primaryColor, theme),

            // 续作已出、相似推荐尚未返回时的局部骨架屏占位
            if (_isLoadingSimilar && _similarItems.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _buildSkeletonList(isDark, count: 2),
              ),

            // 底部懒加载状态或触底指示器
            _buildBottomIndicator(primaryColor, theme),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomIndicator(Color primaryColor, ThemeData theme) {
    if (_isLoadingMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.8,
                  color: primaryColor.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '加载更多推荐中...',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                  fontFamily: 'MiSans',
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_hasMoreSimilar && _similarItems.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: GestureDetector(
            onTap: _loadMoreSimilar,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '下滑或点击加载更多',
                    style: TextStyle(
                      fontSize: 12,
                      color: primaryColor.withValues(alpha: 0.8),
                      fontWeight: FontWeight.w500,
                      fontFamily: 'MiSans',
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: primaryColor.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildSkeletonList(bool isDark, {int count = 4}) {
    return Column(
      children: List.generate(count, (index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 124,
                height: 70, // 16:9 比例标准宽幅封面 (124 * 70)
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 行 1: 标题骨架
                    Container(
                      width: 140,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 7),
                    // 行 2: 评分与徽章骨架
                    Container(
                      width: 80,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 7),
                    // 行 3: 年份与话数骨架
                    Container(
                      width: 100,
                      height: 11,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildErrorState(Color primaryColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          children: [
            Text(
              '推荐条目拉取暂不可用',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _fetchRecommendations(forceRefresh: true),
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: Text(
                '点击重试',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                  fontFamily: 'MiSans',
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationsList(
    List<BangumiRecommendationItem> items,
    bool isDark,
    Color primaryColor,
    ThemeData theme,
  ) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        return BouncingScaleCard(
          scaleDown: 0.98,
          immediateTap: true,
          onTap: () => widget.onTapItem?.call(item),
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8),
                width: 0.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 16:9 标准宽幅封面 (124 * 70) 解决画面过小问题
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 124,
                    height: 70,
                    color: isDark ? const Color(0xFF202026) : const Color(0xFFECECF0),
                    child: item.cover.isNotEmpty
                        ? CachedAnimeImage(
                            imageUrl: item.cover,
                            width: 124,
                            height: 70,
                            fit: BoxFit.cover,
                            alignment: const Alignment(0, -0.6), // 聚焦上半身特写
                          )
                        : Icon(
                            Icons.movie_outlined,
                            size: 24,
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.3),
                          ),
                  ),
                ),
                const SizedBox(width: 12),

                // 右侧文本信息：清晰呈现 3 行独立结构
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 第 1 行: 番剧主标题
                      Text(
                        item.displayName,
                        style: const TextStyle(
                          fontSize: 14.0,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),

                      // 第 2 行: 评分与关系徽章 (续作/前传/剧场版，使用 Wrap 自适应杜绝极窄视口溢出)
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 2,
                        children: [
                          if (item.score > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: Color(0xFFFFB300),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  item.score.toStringAsFixed(1),
                                  style: const TextStyle(
                                    fontSize: 12.0,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFFFB300),
                                    fontFamily: 'MiSans',
                                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                                  ),
                                ),
                              ],
                            ),
                          if (item.relationBadge != null && item.relationBadge!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: _resolveBadgeBgColor(item.relationBadge!, primaryColor),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.relationBadge!,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: _resolveBadgeTextColor(item.relationBadge!, primaryColor),
                                  fontFamily: 'MiSans',
                                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),

                      // 第 3 行: 播放年和全部话数
                      if (item.year.isNotEmpty || item.epsLabel.isNotEmpty)
                        Text(
                          item.year.isNotEmpty && item.epsLabel.isNotEmpty
                              ? '${item.year} · ${item.epsLabel}'
                              : (item.year.isNotEmpty ? item.year : item.epsLabel),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w400,
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.65),
                            fontFamily: 'MiSans',
                            fontFamilyFallback: FontManager.fallbackFontFamilies,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _resolveBadgeBgColor(String badge, Color primaryColor) {
    return switch (badge) {
      '续作' => const Color(0xFF10B981).withValues(alpha: 0.16),
      '前传' => const Color(0xFF0EA5E9).withValues(alpha: 0.16),
      '剧场版' => const Color(0xFF8B5CF6).withValues(alpha: 0.16),
      _ => primaryColor.withValues(alpha: 0.16),
    };
  }

  Color _resolveBadgeTextColor(String badge, Color primaryColor) {
    return switch (badge) {
      '续作' => const Color(0xFF10B981),
      '前传' => const Color(0xFF0EA5E9),
      '剧场版' => const Color(0xFF8B5CF6),
      _ => primaryColor,
    };
  }
}
