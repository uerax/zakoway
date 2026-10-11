import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/home/recommend_item.dart';
import '../../../core/theme/m3_surface.dart';
import '../../common/widgets/anime_card.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import '../../common/widgets/cached_anime_image.dart';

/// 移动端/窄屏专用的“今日推荐 · 算法推荐精选”大卡片：
/// 1. 杂志图文混排：左侧呈现标准 2:3 原始无畸变海报，右侧展示标题、评分与人话化推荐理由；
/// 2. 算法可解释性：显式渲染契合度百分比徽章与推荐来源逻辑；
/// 3. 支持“换一部 ↻”平滑切片动效与震动反馈。
class DailySpotlightCard extends StatefulWidget {
  final List<RecommendItem> recommendations;

  const DailySpotlightCard({
    super.key,
    required this.recommendations,
  });

  @override
  State<DailySpotlightCard> createState() => _DailySpotlightCardState();
}

class _DailySpotlightCardState extends State<DailySpotlightCard> {
  int _currentIndex = 0;

  void _switchNext() {
    if (widget.recommendations.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _currentIndex = (_currentIndex + 1) % widget.recommendations.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.recommendations.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final current = widget.recommendations[_currentIndex.clamp(0, widget.recommendations.length - 1)];
    final item = current.item;

    // 视觉舒适的琥珀金色阶：浅色模式采用深琥珀金 (amber-600) 避免白底刺眼，深色模式采用明朗金 (amber-400)
    final amberColor = isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    final amberBgColor = isDark ? const Color(0xFFFBBF24).withAlpha(35) : const Color(0xFFD97706).withAlpha(24);

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardAvailableWidth = constraints.maxWidth;
        // 特殊处理说明：当窗口拉伸至极窄小窗（< 280px）时，适度缩小左侧海报宽度并锁定右侧最小高度（116px），保证右侧标题、徽章、评分与推荐理由完全容纳且绝不发生垂直溢出
        final isNarrow = cardAvailableWidth < 280;
        final posterWidth = isNarrow ? 65.0 : 90.0;
        final posterHeight = isNarrow ? 116.0 : 126.0;
        final gap = isNarrow ? 8.0 : 12.0;
        final cardPadding = isNarrow ? 8.0 : 12.0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 头部标题与“换一部”微操作
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    '今日推荐',
                    style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                      color: theme.textTheme.titleMedium?.color,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withAlpha(isDark ? 36 : 22),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '算法精选',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (widget.recommendations.length > 1)
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          onTap: _switchNext,
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  size: 14,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  '换一部',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // 精选卡片主体
              BouncingScaleCard(
                onTap: () => navigateToVideoPlayer(context, item),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 280),
                  child: Container(
                    key: ValueKey('spotlight_${item.id}_$_currentIndex'),
                    padding: EdgeInsets.all(cardPadding),
                    decoration: BoxDecoration(
                      color: M3Surface.container(context, level: M3ContainerLevel.low),
                      borderRadius: BorderRadius.circular(20),
                      border: M3Surface.border(context),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 左侧：2:3 原始海报
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: posterWidth,
                            height: posterHeight,
                            child: CachedAnimeImage(
                              imageUrl: item.thumbnailUrl.isNotEmpty
                                  ? item.thumbnailUrl
                                  : item.coverUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        SizedBox(width: gap),

                        // 右侧：标题、标签、推荐理由与评分（锁定 posterHeight 高度并通过 Spacer 让理由气泡稳固置底）
                        Expanded(
                          child: SizedBox(
                            height: posterHeight,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 契合度与特色标签 (M3 Stadium 胶囊徽章，外层包裹 FittedBox 保证极窄小窗下等比微缩自适应)
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: amberBgColor,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.stars_rounded,
                                        size: 11,
                                        color: amberColor,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '${current.matchRate}% 契合',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: amberColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 5),
                                // 特殊处理说明：特色标签包裹 Flexible 并设置单行截断，防止窄屏或长标签（如 5 字符以上题材）引发横向 RenderFlex 溢出
                                Flexible(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      current.tag,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSecondaryContainer,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),

                          // 作品名
                          Text(
                            item.preferredName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: theme.textTheme.titleMedium?.color,
                            ),
                          ),
                          const SizedBox(height: 4),

                          // 评分（外层 FittedBox 保证极窄小窗下自适应微缩不溢出）
                          if (item.ratingScore > 0)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star_rounded, size: 14, color: amberColor),
                                  const SizedBox(width: 3),
                                  Text(
                                    item.ratingScore.toStringAsFixed(1),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: amberColor,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '(${item.votes}人评)',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // 核心：弹性填充间隙，将推荐理由气泡推至最底部与左侧海报底沿平齐
                          const Spacer(),

                          // 显式推荐理由气泡
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            // 特殊处理说明：采用 Text.rich 将装饰 Emoji 与推荐理由融合成单段文本排版，彻底避免 Row + Expanded 在极窄视口下因 Emoji 固有宽度触发 RenderFlex overflow
                            child: Text.rich(
                              TextSpan(
                                children: [
                                  const TextSpan(
                                    text: '💡 ',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                  TextSpan(
                                    text: current.reason,
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.35,
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
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
      },
    );
  }
}
