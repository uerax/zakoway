import 'package:flutter/material.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/adaptive_page_route.dart';
import '../../../core/utils/responsive.dart';
import '../../player/player.dart';
import 'bouncing_scale_card.dart';
import 'cached_anime_image.dart';

/// 跳转至视频播放页面
void navigateToVideoPlayer(
  BuildContext context,
  BangumiItem item, {
  Duration? initialPosition,
  int? currentEpisode,
}) {
  Navigator.of(context).push(
    AdaptivePageRoute.build<void>(
      context,
      builder: (context) => VideoPlayPage(
        title: item.preferredName,
        bangumiItem: item,
        coverUrl: item.coverUrl,
        episodeCount: item.eps > 0 ? item.eps : 12,
        currentEpisode: currentEpisode,
        initialPosition: initialPosition,
      ),
    ),
  );
}

class AnimeCard extends StatelessWidget {
  final BangumiItem item;
  final VoidCallback? onTap;
  final bool compact;
  final int loadDelayMs;

  const AnimeCard({
    super.key,
    required this.item,
    this.onTap,
    this.compact = false,
    this.loadDelayMs = 0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomStat = _resolveBottomStat();
    final cardRadius = BorderRadius.circular(compact ? 12 : 16);
    final cardBg = M3Surface.container(context, level: M3ContainerLevel.low);
    final cardBorder = M3Surface.cardBorder(context);
    final cardShadow = M3Surface.cardShadow(context, elevation: compact ? 0.85 : 1.0);

    return BouncingScaleCard(
      immediateTap: true,
      onTap: onTap ?? () => navigateToVideoPlayer(context, item),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: cardRadius,
          color: cardBg,
          border: cardBorder,
          boxShadow: cardShadow,
        ),
        child: ClipRRect(
          borderRadius: cardRadius,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedAnimeImage(
                    imageUrl: item.thumbnailUrl.isNotEmpty
                        ? item.thumbnailUrl
                        : item.coverUrl,
                    fit: BoxFit.cover,
                    loadDelayMs: loadDelayMs,
                  ),
                  // 封面底部暗色渐变遮罩
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: compact ? 28 : 38,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.72),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 右上角评分角标 (M3 Stadium 胶囊徽标)
                  if (item.ratingScore > 0)
                    Positioned(
                      top: compact ? 4 : 6,
                      right: compact ? 4 : 6,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 6 : 8,
                          vertical: compact ? 2 : 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star_rounded,
                              size: compact ? 11 : 13,
                              color: Colors.amber,
                            ),
                            SizedBox(width: compact ? 2 : 2.5),
                            Text(
                              '${item.ratingScore}',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 9.5 : 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // 左下角状态/已看/在看/热度角标 (M3 Stadium 胶囊徽标)
                  if (bottomStat != null)
                    Positioned(
                      bottom: compact ? 4 : 5,
                      left: compact ? 4 : 6,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 6 : 7,
                          vertical: compact ? 2 : 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.60),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              bottomStat.count,
                              style: TextStyle(
                                color: bottomStat.color,
                                fontSize: compact ? 8.5 : 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: compact ? 2 : 2.5),
                            Text(
                              bottomStat.label,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.85),
                                fontSize: compact ? 8 : 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: compact
                  ? const EdgeInsets.symmetric(horizontal: 6.0, vertical: 5.0)
                  : const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.preferredName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: compact ? 11.5 : 12.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: compact ? 9 : 10,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }

  ({String count, String label, Color color})? _resolveBottomStat() {
    if (item.collect != null && item.collect! > 0) {
      return (
        count: formatCompactCount(item.collect),
        label: '已看',
        color: const Color(0xFF34D399), // 翡翠翠绿 (Animaku 规范: emerald-400)
      );
    }
    if (item.doing != null && item.doing! > 0) {
      return (
        count: formatCompactCount(item.doing),
        label: '在看',
        color: const Color(0xFFFBBF24), // 琥珀金黄 (Animaku 规范: amber-400)
      );
    }
    if (item.heat != null && item.heat! > 0) {
      return (
        count: formatCompactCount(item.heat),
        label: '热度',
        color: const Color(0xFFFB7185), // 玫瑰火红 (Animaku 规范: rose-400)
      );
    }
    return null;
  }
}

/// 自适应弹出番剧详情：
/// 1. 桌面/宽屏端（>= 840dp）：居中毛玻璃卡片模态弹窗（Dialog，最大宽度 560px），配备右上角关闭键；
/// 2. 移动端/窄屏端（< 840dp）：保持标准抽屉底部弹窗（Modal Bottom Sheet + Draggable）。
void showAnimeDetailSheet(BuildContext context, BangumiItem item) {
  if (context.isDesktop) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Dialog(
          backgroundColor: isDark ? const Color(0xFF1E1E22) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppBreakpoints.maxDialogWidth,
              maxHeight: 650,
            ),
            child: Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: _AnimeDetailContent(item: item),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return;
  }

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            child: _AnimeDetailContent(item: item),
          );
        },
      );
    },
  );
}

class _AnimeDetailContent extends StatelessWidget {
  final BangumiItem item;

  const _AnimeDetailContent({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 100,
                height: 140,
                child: CachedAnimeImage(
                  imageUrl: item.thumbnailUrl.isNotEmpty
                      ? item.thumbnailUrl
                      : item.coverUrl,
                  width: 100,
                  height: 140,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.preferredName,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.name,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (item.ratingScore > 0)
                        Chip(
                          avatar: const Icon(Icons.star, size: 14, color: Colors.amber),
                          label: Text('${item.ratingScore}分 (${item.votes}人评)'),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (item.rank > 0)
                        Chip(
                          label: Text('Rank #${item.rank}'),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (item.airDate.isNotEmpty)
                        Chip(
                          label: Text('首播: ${item.airDate}'),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Divider(),
        const Text('剧情简介', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          item.summary.isNotEmpty ? item.summary : '暂无剧情简介。',
          style: const TextStyle(height: 1.5, fontSize: 13),
        ),
        if (item.tags.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('标签', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: item.tags.take(12).map((tag) {
              return Chip(
                label: Text(tag.name, style: const TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: FilledButton.icon(
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: const Text('立即播放', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.of(context).pop();
              navigateToVideoPlayer(context, item);
            },
          ),
        ),
      ],
    );
  }
}
