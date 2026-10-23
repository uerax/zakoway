import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/font_manager.dart';
import '../../../core/utils/responsive.dart';
import '../../common/widgets/anime_card.dart';
import '../../common/widgets/shimmer_loading.dart';
import '../controllers/category_controller.dart';
import '../controllers/category_state.dart';

class CategoryContentView extends ConsumerWidget {
  final CategoryInitialArgs initialArgs;

  const CategoryContentView({
    super.key,
    this.initialArgs = const CategoryInitialArgs(),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isLoading = ref.watch(
      categoryControllerProvider(initialArgs).select((s) => s.isLoading),
    );
    final errorMessage = ref.watch(
      categoryControllerProvider(initialArgs).select((s) => s.errorMessage),
    );
    final items = ref.watch(
      categoryControllerProvider(initialArgs).select((s) => s.items),
    );
    final controller = ref.read(categoryControllerProvider(initialArgs).notifier);

    // 1. 仅在冷启动且当前内存中完全无数据时：呈现原生 SliverGrid 骨架屏
    // 特殊处理说明：采用原生 SliverGrid 单趟排版，彻底消除 GridView(shrinkWrap: true) 双重排版测算反模式
    if (isLoading && items.isEmpty) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.crossAxisExtent;
            final count = AppBreakpoints.gridColumns(width);
            final skeletonCount = count * 2;
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
    if (errorMessage != null && items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                '获取番剧列表失败',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                errorMessage,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.redAccent),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: controller.fetchFirstPage,
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

    // 3. 空结果状态
    if (items.isEmpty) {
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
                  shape: BoxShape.circle,
                  color: isDark ? Colors.white.withAlpha(16) : Colors.black.withAlpha(10),
                ),
                child: Icon(
                  Icons.inbox_rounded,
                  size: 36,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '未找到匹配的番剧条目',
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                '可尝试放宽年份或切换为其他题材分类',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: controller.resetToDefault,
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('恢复默认'),
              ),
            ],
          ),
        ),
      );
    }

    // 4. 正常数据呈现：自适应 3 列（移动端推荐）/ 4~6 列（宽屏）网格瀑布流
    // 特殊处理说明：当切换分类加载中时施加 0.72 柔和透明度反馈，不销毁列表，新数据就绪后无缝替换，保障视觉连贯性
    return SliverAnimatedOpacity(
      opacity: isLoading ? 0.72 : 1.0,
      duration: const Duration(milliseconds: 180),
      sliver: SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
                  final row = index ~/ count;
                  // 对齐 Animaku 资源调度策略：
                  // 1. 前 2 个核心卡片 (index < 2) 0ms 独占带宽极速直出，让首屏顶部瞬时点亮；
                  // 2. 其余卡片先保持干净置白骨架占位，避免全屏 10+ 张封面同时并发请求争抢网络带宽导致整体卡顿；
                  // 3. 随后按排次梯度错峰加载（首排剩余 100ms，后续每排递增 130ms，上限 600ms），逐排平滑淡入刷出。
                  final int delayMs;
                  if (index < 2) {
                    delayMs = 0;
                  } else if (row == 0) {
                    delayMs = 100;
                  } else {
                    delayMs = (100 + row * 130).clamp(0, 600);
                  }

                  return AnimeCard(
                    key: ValueKey('anime_cat_${item.id}'),
                    item: item,
                    compact: true,
                    loadDelayMs: delayMs,
                  );
                },
                childCount: items.length,
                addAutomaticKeepAlives: false,
                addRepaintBoundaries: true,
              ),
            );
          },
        ),
      ),
    );
  }
}
