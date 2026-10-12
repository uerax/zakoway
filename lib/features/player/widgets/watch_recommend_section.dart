import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/models/bangumi/bangumi_recommendation_item.dart';
import '../../../core/providers/bangumi_providers.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import '../../common/widgets/cached_anime_image.dart';

/// 播放页视频推荐区组件 (1:1 复刻 animaku 自适应分桶与 Slot 0 判定算法)
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
  bool _isLoading = false;
  String? _error;
  List<BangumiRecommendationItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _fetchRecommendations();
  }

  @override
  void didUpdateWidget(covariant WatchRecommendSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bangumiId != widget.bangumiId ||
        (oldWidget.bangumiItem == null && widget.bangumiItem != null) ||
        ((oldWidget.bangumiItem?.tags.isEmpty ?? true) &&
            (widget.bangumiItem?.tags.isNotEmpty ?? false))) {
      _fetchRecommendations();
    }
  }

  Future<void> _fetchRecommendations({bool forceRefresh = false}) async {
    final subjectId = widget.bangumiId ?? widget.bangumiItem?.id ?? 0;
    if (subjectId <= 0) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = ref.read(bangumiClientProvider);
      final rawTags = widget.bangumiItem?.tags.map((t) => t.name).toList();
      final isMovie = widget.bangumiItem != null
          ? (widget.bangumiItem!.totalEpisodes == 1 && widget.bangumiItem!.eps == 1) ||
              widget.bangumiItem!.name.contains('剧场版') ||
              widget.bangumiItem!.nameCn.contains('剧场版') ||
              widget.bangumiItem!.tags.any((t) => t.name.contains('剧场版') || t.name.contains('动画电影'))
          : null;

      final results = await client.getRecommendations(
        subjectId,
        tags: rawTags,
        isMovie: isMovie,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;
      setState(() {
        _items = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    if (!_isLoading && _error == null && _items.isEmpty) {
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
              const SizedBox(width: 6),
              Text(
                _items.isNotEmpty
                    ? '(${_items.length} 部精选)'
                    : '· 同类题材与高分精选',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                  fontFamily: 'MiSans',
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                ),
              ),
              const Spacer(),
              if (_isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: primaryColor.withValues(alpha: 0.7),
                  ),
                )
              else if (_items.isNotEmpty)
                GestureDetector(
                  onTap: () => _fetchRecommendations(forceRefresh: true),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.refresh_rounded,
                          size: 13,
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '换一批',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                            fontFamily: 'MiSans',
                            fontFamilyFallback: FontManager.fallbackFontFamilies,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // 骨架屏加载态
          if (_isLoading && _items.isEmpty)
            _buildSkeletonList(isDark)
          else if (_error != null && _items.isEmpty)
            _buildErrorState(primaryColor)
          else
            _buildRecommendationsList(isDark, primaryColor, theme),
        ],
      ),
    );
  }

  Widget _buildSkeletonList(bool isDark) {
    return Column(
      children: List.generate(4, (index) {
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

  Widget _buildRecommendationsList(bool isDark, Color primaryColor, ThemeData theme) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = _items[index];
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

                      // 第 2 行: 评分与关系徽章 (续作/前传/剧场版)
                      Row(
                        children: [
                          if (item.score > 0) ...[
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
                            const SizedBox(width: 8),
                          ],
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
