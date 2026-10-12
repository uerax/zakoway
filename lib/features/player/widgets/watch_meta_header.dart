import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/providers/auth_providers.dart';
import '../../../core/collection/providers/collection_providers.dart';
import '../../../core/models/bangumi/bangumi_collection.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import 'watch_meta_view.dart';

/// 播放页移动端/桌面端统一番剧信息精炼头部 (Title, Rating, Quick Collect, Details Entry)
class WatchMetaHeader extends ConsumerWidget {
  const WatchMetaHeader({
    super.key,
    required this.title,
    this.bangumiItem,
    this.coverUrl,
    this.episodeCount = 12,
    this.onOpenDetails,
  });

  final String title;
  final BangumiItem? bangumiItem;
  final String? coverUrl;
  final int episodeCount;
  final VoidCallback? onOpenDetails;

  static const List<CollectType> _collectTypes = [
    CollectType.planToWatch,
    CollectType.watching,
    CollectType.watched,
    CollectType.onHold,
    CollectType.abandoned,
  ];

  BangumiItem get _effectiveItem =>
      bangumiItem ??
      BangumiItem(
        id: title.hashCode.abs(),
        type: 2,
        name: title,
        nameCn: title,
        summary: '',
        airDate: '',
        airWeekday: 0,
        rank: 0,
        images: coverUrl != null && coverUrl!.isNotEmpty
            ? {'large': coverUrl!, 'common': coverUrl!}
            : const {},
        tags: const [],
        alias: const [],
        ratingScore: 0.0,
        votes: 0,
        eps: episodeCount,
        totalEpisodes: episodeCount,
      );

  void _showCollectMenu(BuildContext context, WidgetRef ref) {
    final item = _effectiveItem;
    CollectType currentType = CollectType.none;
    dynamic notifier;
    bool isLoggedIn = false;
    try {
      currentType = ref.read(collectionTypeForSubjectProvider(item.id));
      notifier = ref.read(collectionControllerProvider.notifier);
      isLoggedIn = ref.read(isLoggedInProvider);
    } catch (_) {}
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (bottomSheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E22) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '标记追番状态',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'MiSans',
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                    ),
                  ),
                  if (currentType != CollectType.none)
                    TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        notifier.removeStatus(item.id);
                        Navigator.of(bottomSheetContext).pop();
                      },
                      child: Text(
                        '取消追番',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.error,
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _collectTypes.map((type) {
                  final isSelected = currentType == type;
                  final primaryColor = Theme.of(context).colorScheme.primary;
                  return BouncingScaleCard(
                    scaleDown: 0.95,
                    immediateTap: true,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      notifier.updateStatus(
                        bangumiItem: item,
                        type: type,
                      );
                      Navigator.of(bottomSheetContext).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? primaryColor.withValues(alpha: isDark ? 0.28 : 0.14)
                            : (isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8)),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isSelected
                              ? primaryColor
                              : (isDark ? Colors.white.withAlpha(16) : Colors.black.withAlpha(12)),
                          width: isSelected ? 1.0 : 0.5,
                        ),
                      ),
                      child: Text(
                        type.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? (isDark ? Colors.white : primaryColor)
                              : Theme.of(context).textTheme.bodyMedium?.color,
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (isLoggedIn) ...[
                const SizedBox(height: 12),
                Text(
                  '已登录 Bangumi，操作将自动实时同步至云端',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                    fontFamily: 'MiSans',
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showDetailsBottomSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.65 : 0.45),
      builder: (ctx) {
        final screenHeight = MediaQuery.of(ctx).size.height;
        return GestureDetector(
          // 点击半透明空白背景立即秒关
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(ctx).pop(),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              // 阻断内容区点击冒泡
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: SizedBox(
                height: screenHeight * 0.78,
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF16161A) : Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white24 : Colors.black12,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Expanded(
                        child: WatchMetaView(
                          title: title,
                          bangumiItem: bangumiItem,
                          coverUrl: coverUrl,
                          episodeCount: episodeCount,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final item = bangumiItem;
    final effectiveItem = _effectiveItem;
    final displayName = item?.preferredName ?? title;
    final score = (item?.ratingScore ?? 0.0);
    CollectType currentCollectType = CollectType.none;
    try {
      currentCollectType = ref.watch(collectionTypeForSubjectProvider(effectiveItem.id));
    } catch (_) {
      // 当处于非 ProviderScope 上下文（如独立 WidgetTest 预览）时安全降级
    }
    final hasCollect = currentCollectType != CollectType.none;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题与“详情 >”入口
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  displayName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.4,
                    height: 1.25,
                    fontFamily: 'MiSans',
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              // 详情 > 入口药丸
              BouncingScaleCard(
                scaleDown: 0.94,
                immediateTap: true,
                onTap: onOpenDetails ?? () => _showDetailsBottomSheet(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white.withAlpha(16) : Colors.black.withAlpha(10),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '详情',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // 评分信息与追番胶囊按钮
          Row(
            children: [
              Expanded(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (score > 0.0) ...[
                      const Icon(
                        Icons.star_rounded,
                        size: 15,
                        color: Color(0xFFFFB300),
                      ),
                      const SizedBox(width: 2.5),
                      Text(
                        score.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFFFB300),
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '·',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.4),
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        item?.airDate != null && item!.airDate.isNotEmpty
                            ? '${item.airDate} 放送'
                            : '全 $episodeCount 话',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.75),
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 追番状态胶囊
              BouncingScaleCard(
                scaleDown: 0.94,
                immediateTap: true,
                onTap: () => _showCollectMenu(context, ref),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasCollect
                        ? primaryColor.withValues(alpha: isDark ? 0.24 : 0.14)
                        : (isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: hasCollect
                          ? primaryColor.withValues(alpha: 0.4)
                          : (isDark ? Colors.white.withAlpha(16) : Colors.black.withAlpha(10)),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasCollect ? Icons.bookmark_added_rounded : Icons.bookmark_add_outlined,
                        size: 14,
                        color: hasCollect ? primaryColor : theme.textTheme.bodyMedium?.color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        hasCollect ? currentCollectType.label : '追番',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: hasCollect ? FontWeight.w700 : FontWeight.w500,
                          color: hasCollect
                              ? (isDark ? Colors.white : primaryColor)
                              : theme.textTheme.bodyMedium?.color,
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
        ],
      ),
    );
  }
}
