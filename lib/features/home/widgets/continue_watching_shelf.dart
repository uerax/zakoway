import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/models/history/watch_history_item.dart';
import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/font_manager.dart';
import '../../../core/utils/responsive.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import '../../common/widgets/cached_anime_image.dart';

/// 播放进度记录实体（向后兼容封装，底层统一使用 core 层 WatchHistoryItem）：
class WatchProgressItem extends WatchHistoryItem {
  final String? _customPositionText;

  WatchProgressItem({
    required BangumiItem item,
    required int episodeNumber,
    required double progress,
    required String positionText,
    required DateTime lastWatchTime,
    super.pluginName = '默认源',
    super.road = 0,
    super.pageUrl = '',
  })  : _customPositionText = positionText,
        super(
          id: WatchHistoryItem.buildId(item.id, episodeNumber),
          bangumiId: item.id,
          title: item.preferredName,
          cover: item.thumbnailUrl.isNotEmpty ? item.thumbnailUrl : item.coverUrl,
          episode: episodeNumber,
          position: progress * 1440,
          duration: 1440,
          updatedAt: lastWatchTime.millisecondsSinceEpoch,
        );

  @override
  String get positionText => _customPositionText ?? super.positionText;
}

/// 首页“继续追番”模块（现代响应式静态平铺设计）：
/// 1. 数据驱动：当 records 为空时直接返回 SizedBox.shrink()，0 像素占位，零视觉副作用；
/// 2. 彻底消除横滑手势竞争：移除水平 ListView，采用响应式静态平铺 Row，杜绝移动端（特别是 iOS）垂直滚动误触；
/// 3. 多端阶梯列数：手机端展示前 2 部平铺一屏，平板端展示 3 部，PC 桌面大屏展示 4 部；
/// 4. 轻量化卡片设计：单张控制在 68px 高度，左侧 2:3 缩略微海报 + 右侧剧集名称/高亮视频源/纤细进度条；
/// 5. 支持点击直达播放/详情，右上角统一挂载「历史记录 >」入口引导。
class ContinueWatchingShelf extends StatelessWidget {
  final List<WatchHistoryItem> records;
  final ValueChanged<WatchHistoryItem>? onResumeWatch;
  final VoidCallback? onViewAllHistory;

  const ContinueWatchingShelf({
    super.key,
    required this.records,
    this.onResumeWatch,
    this.onViewAllHistory,
  });

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        // 依据屏幕宽度响应式决定展示卡片数量与列宽：
        // 极窄小窗 (< 250px)：展示最新 1 部，避免强制双列过度挤压卡片破排
        // 手机端 (250 ~ 599px)：平铺展示最新 2 部
        // 平板端 (600 ~ 839px)：平铺展示最新 3 部
        // 桌面标准大屏 (840 ~ 1279px)：平铺展示最新 4 部
        // 桌面宽屏 (1280 ~ 1599px)：平铺展示最新 5 部
        // 桌面超宽大屏 (>= 1600px)：平铺展示最新 6 部
        final int maxColumns = screenWidth >= 1600
            ? 6
            : (screenWidth >= 1280
                ? 5
                : (screenWidth >= AppBreakpoints.medium
                    ? 4
                    : (screenWidth >= AppBreakpoints.compact
                        ? 3
                        : (screenWidth < 250 ? 1 : 2))));

        final displayItems = records.take(maxColumns).toList();
        if (displayItems.isEmpty) return const SizedBox.shrink();

        final isDesktop = context.isDesktop;
        const double gap = 8.0;
        const double maxCardWidth = 280.0;
        const double cardHeight = 68.0;
        final double availableWidth = isDesktop ? screenWidth : screenWidth - 32.0;

        // 特殊处理说明：
        // 双向自适应宽度设计：
        // 1. 小屏/极窄小窗场景：以实际条目数均分可用空间 (slotWidth)，向下自由收缩，彻底杜绝 RenderFlex 溢出；
        // 2. 宽屏/单条记录场景：将单张卡片封顶在 280px (math.min)，防止在宽屏大显示器或历史条目少时被无限拉伸成超长横条。
        final double slotWidth = (availableWidth - gap * (displayItems.length - 1)) / displayItems.length;
        final double cardWidth = math.min(slotWidth.floorToDouble(), maxCardWidth);

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 标题行
              Padding(
                padding: EdgeInsets.fromLTRB(isDesktop ? 0 : 16, 2, isDesktop ? 0 : 16, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.play_circle_outline_rounded,
                      size: 16.5,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '继续追番',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                        color: theme.textTheme.titleMedium?.color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 特殊处理说明：查看历史按钮使用 Expanded + Align + FittedBox 弹性右对齐并自适应等比缩放，避免极窄窗口下两端挤爆
                    if (onViewAllHistory != null)
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Material(
                              color: theme.colorScheme.primary.withAlpha(isDark ? 36 : 20),
                              borderRadius: BorderRadius.circular(6),
                              child: InkWell(
                                onTap: onViewAllHistory,
                                borderRadius: BorderRadius.circular(6),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.history_rounded,
                                        size: 13,
                                        color: theme.colorScheme.primary,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        '历史记录',
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
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 响应式静态平铺行（零横向滚动，彻底杜绝手势竞争与误触）
              Padding(
                padding: EdgeInsets.symmetric(horizontal: isDesktop ? 0 : 16),
                child: Row(
                  children: [
                    for (var i = 0; i < displayItems.length; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      SizedBox(
                        width: cardWidth,
                        height: cardHeight,
                        child: _buildWatchCard(
                          context,
                          theme,
                          isDark,
                          displayItems[i],
                          cardHeight: cardHeight,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWatchCard(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    WatchHistoryItem record, {
    required double cardHeight,
  }) {
    final coverUrl = (record.cover != null && record.cover!.isNotEmpty)
        ? record.cover!
        : (record.item.thumbnailUrl.isNotEmpty ? record.item.thumbnailUrl : record.item.coverUrl);
    final displayTitle = record.title.isNotEmpty ? record.title : record.item.preferredName;

    return BouncingScaleCard(
      immediateTap: true,
      onTap: () => onResumeWatch?.call(record),
      child: Container(
        height: cardHeight,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: M3Surface.container(context, level: M3ContainerLevel.low),
          borderRadius: BorderRadius.circular(16),
          border: M3Surface.cardBorder(context),
          boxShadow: M3Surface.cardShadow(context),
        ),
        child: Row(
          children: [
            // 封面与播放微胶囊（紧凑 38x54 尺寸）
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 38,
                height: 54,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedAnimeImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                    ),
                    ColoredBox(color: Colors.black.withValues(alpha: 0.3)),
                    const Center(
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),

            // 信息、高亮视频源与轻量进度条
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: theme.textTheme.titleSmall?.color,
                    ),
                  ),
                  const SizedBox(height: 2.5),
                  Row(
                    children: [
                      Text(
                        '第 ${record.episode} 话',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (record.pluginName.isNotEmpty && record.pluginName != '默认源') ...[
                        Text(
                          ' · ',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            record.pluginName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 5),

                  // M3 圆润进度条与百分比（极窄小窗下自适应隐藏百分比文字，避免挤压溢出）
                  LayoutBuilder(
                    builder: (context, progressConstraints) {
                      final showText = progressConstraints.maxWidth > 35;
                      return Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: record.progress.clamp(0.0, 1.0),
                                minHeight: 3.5,
                                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                          if (showText) ...[
                            const SizedBox(width: 5),
                            Text(
                              '${(record.progress * 100).toInt()}%',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
