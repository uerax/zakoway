import 'package:flutter/material.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import 'watch_meta_view.dart';

/// 播放页移动端/桌面端统一番剧信息精炼头部 (Title, Rating, Details Entry)
class WatchMetaHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final item = bangumiItem;
    final displayName = item?.preferredName ?? title;
    final score = (item?.ratingScore ?? 0.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行（全宽展示）
          Text(
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
          const SizedBox(height: 6),
          // 评分与详情入口药丸（放于原追番位置，避免与详情内追番控制器重复）
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
              // 详情 > 入口药丸（放置于原追番位置）
              BouncingScaleCard(
                scaleDown: 0.94,
                immediateTap: true,
                onTap: onOpenDetails ?? () => _showDetailsBottomSheet(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
                    borderRadius: BorderRadius.circular(14),
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
                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.85),
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
        ],
      ),
    );
  }
}
