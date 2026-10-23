import 'package:flutter/material.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/utils/font_manager.dart';
import '../../../core/utils/responsive.dart';
import '../../common/widgets/anime_card.dart';
import '../../common/widgets/shimmer_loading.dart';
import '../models/search_types.dart';

/// 搜索结果网格、骨架屏、空状态与跨分类智能引导
class SearchResultView extends StatelessWidget {
  final bool isLoading;
  final String? errorMessage;
  final List<BangumiItem> items;
  final String keyword;
  final SearchFilterType currentFilter;
  final int allCount;
  final int nonAnimeCount;
  final VoidCallback onRetry;
  final ValueChanged<SearchFilterType> onSwitchFilter;

  const SearchResultView({
    super.key,
    required this.isLoading,
    required this.errorMessage,
    required this.items,
    required this.keyword,
    required this.currentFilter,
    required this.allCount,
    required this.nonAnimeCount,
    required this.onRetry,
    required this.onSwitchFilter,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // 1. 加载中状态：呈现骨架屏
    if (isLoading) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.crossAxisExtent;
            final count = AppBreakpoints.gridColumns(width);
            final skeletonCount = count * 3;
            return SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: count,
                childAspectRatio: 0.58,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => const ShimmerAnimeCard(),
                childCount: skeletonCount,
              ),
            );
          },
        ),
      );
    }

    // 2. 异常失败状态
    if (errorMessage != null) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                '搜索失败',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.redAccent),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(
                  '重新尝试',
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

    // 3. 空结果状态（包含 Animaku 规范的跨分类智能引导）
    if (items.isEmpty) {
      // 场景 A：当前在“动漫”分类且无结果，但在“非动漫”中有匹配条目
      if (currentFilter == SearchFilterType.anime && nonAnimeCount > 0) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: 32,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '当前搜索结果暂无动漫内容',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '在非动漫分类中找到了 $nonAnimeCount 条相关结果',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton(
                      onPressed: () => onSwitchFilter(SearchFilterType.nonAnime),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text('查看非动漫 ($nonAnimeCount)'),
                    ),
                    if (allCount > 0) ...[
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => onSwitchFilter(SearchFilterType.all),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: Text('查看全部 ($allCount)'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      }

      // 场景 B：全部分类均无结果
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_rounded,
                  size: 32,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '未找到与「$keyword」相关的结果',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '可以尝试更换关键词、检查错别字或精简搜索词',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(180),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 4. 有结果列表：响应式网格呈现
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final count = AppBreakpoints.gridColumns(width);
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: count,
              childAspectRatio: 0.58,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = items[index];
                return AnimeCard(
                  key: ValueKey(item.id),
                  item: item,
                );
              },
              childCount: items.length,
            ),
          );
        },
      ),
    );
  }
}
