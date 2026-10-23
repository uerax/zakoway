import 'package:flutter/material.dart';
import 'package:zakoway/core/models/bangumi/bangumi_item.dart';
import 'package:zakoway/core/models/bangumi/bangumi_recommendation_item.dart';
import 'package:zakoway/core/utils/font_manager.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/source_aggregator.dart';
import 'package:zakoway/features/player/source/utils/playable_slot_engine.dart';
import 'episode_source_pod.dart';
import 'video_source_view.dart';
import 'watch_comments_section.dart';
import 'watch_meta_header.dart';
import 'watch_recommend_section.dart';

/// iOS / M3 风格极简精致滑动胶囊分段控制器 (全新 2-Tab: 简介 / 评论)
class VideoPlaySegmentedTabBar extends StatelessWidget {
  const VideoPlaySegmentedTabBar({
    super.key,
    required this.tabController,
    this.tabs = const ['简介', '评论'],
    this.maxWidth = 260,
  });

  final TabController tabController;
  final List<String> tabs;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            height: 38,
            padding: const EdgeInsets.all(3.0),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8),
              borderRadius: BorderRadius.circular(19),
              border: Border.all(
                color: isDark ? Colors.white.withAlpha(18) : Colors.black.withAlpha(12),
                width: 0.5,
              ),
            ),
            child: TabBar(
              controller: tabController,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              dividerColor: Colors.transparent,
              padding: EdgeInsets.zero,
              labelPadding: EdgeInsets.zero,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.16) : Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              labelColor: isDark ? Colors.white : primaryColor,
              unselectedLabelColor: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.65),
              labelStyle: const TextStyle(
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
              tabs: tabs.map((t) => Tab(height: 32, text: t)).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

/// 播放页双主 Tab 内容视图
///
/// Tab 0 [简介]: 垂直流式排列（番剧精简头部 -> 选集选源融合舱 -> 视频推荐卡片流）
/// Tab 1 [评论]: 纵向长流式吐槽与讨论区
class VideoPlayTabContentView extends StatelessWidget {
  const VideoPlayTabContentView({
    super.key,
    required this.tabController,
    required this.title,
    required this.bangumiItem,
    this.isLoadingAuthorityDetails = false,
    required this.coverUrl,
    required this.episodeCount,
    required this.sources,
    required this.selectedSourceId,
    required this.selectedSourceName,
    this.playingSourceId,
    required this.onSourceSelected,
    required this.aggregator,
    required this.sourceNotice,
    required this.keywordOptions,
    required this.onUserAction,
    required this.currentEpisode,
    this.playingRoadIndex,
    required this.isLoadingChapters,
    this.resolveError,
    required this.hasEpisodes,
    required this.currentSlots,
    required this.roadNames,
    required this.selectedRoadIndex,
    required this.mappedEpisodeTitles,
    required this.onRoadSelected,
    required this.onRefreshEpisodes,
    required this.onSelectEpisode,
    required this.onSelectSlot,
    this.onTapRecommendItem,
  });

  final TabController tabController;
  final String title;
  final BangumiItem? bangumiItem;
  final bool isLoadingAuthorityDetails;
  final String coverUrl;
  final int episodeCount;

  final List<VideoSourceItem> sources;
  final String selectedSourceId;
  final String selectedSourceName;
  final String? playingSourceId;
  final void Function(VideoSourceItem src, [SourceSearchResult? hit, List<SourceChapterRoad>? cachedRoads]) onSourceSelected;
  final SourceAggregator aggregator;
  final String? sourceNotice;
  final List<String> keywordOptions;
  final VoidCallback onUserAction;
  final int? currentEpisode;
  final int? playingRoadIndex;

  final bool isLoadingChapters;
  final String? resolveError;
  final bool hasEpisodes;
  final List<PlayableSlot> currentSlots;
  final List<String> roadNames;
  final int selectedRoadIndex;
  final List<String>? mappedEpisodeTitles;
  final ValueChanged<int> onRoadSelected;
  final VoidCallback onRefreshEpisodes;
  final ValueChanged<int> onSelectEpisode;
  final ValueChanged<PlayableSlot> onSelectSlot;
  final ValueChanged<BangumiRecommendationItem>? onTapRecommendItem;

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: tabController,
      children: [
        // Tab 0: 简介垂直流 (信息头部 + 选集选源融合舱 + 推荐列表)
        ListView(
          padding: EdgeInsets.zero,
          children: [
            // 1. 番剧头部 (标题 + 评分 + 追番 + 详情入口)
            WatchMetaHeader(
              title: title,
              bangumiItem: bangumiItem,
              coverUrl: coverUrl,
              episodeCount: episodeCount,
            ),
            const SizedBox(height: 4),

            // 2. 选集与视频源融合舱 (源药丸 + 线路胶囊 + 横向选集滑轨)
            EpisodeSourcePod(
              selectedSourceId: selectedSourceId,
              selectedSourceName: selectedSourceName,
              playingSourceId: playingSourceId,
              sources: sources,
              onSourceSelected: onSourceSelected,
              onSelectHit: (src, hit, [roads]) => onSourceSelected(src, hit, roads),
              aggregator: aggregator,
              keywordOptions: keywordOptions,
              onUserAction: onUserAction,
              currentEpisode: currentEpisode,
              playingRoadIndex: playingRoadIndex,
              isLoadingChapters: isLoadingChapters,
              resolveError: resolveError,
              hasEpisodes: hasEpisodes,
              currentSlots: currentSlots,
              roadNames: roadNames,
              selectedRoadIndex: selectedRoadIndex,
              mappedEpisodeTitles: mappedEpisodeTitles ?? const [],
              onRoadSelected: onRoadSelected,
              onSelectEpisode: onSelectEpisode,
              onSelectSlot: onSelectSlot,
              onRefreshEpisodes: onRefreshEpisodes,
            ),

            // 3. 视频推荐区 (1:1 复刻 animaku 推荐算法卡片流)
            WatchRecommendSection(
              bangumiId: bangumiItem?.id,
              bangumiItem: bangumiItem,
              onTapItem: onTapRecommendItem,
            ),
          ],
        ),

        // Tab 1: 评论讨论区长列表 (独立滚动)
        WatchCommentsSection(
          bangumiId: bangumiItem?.id,
        ),
      ],
    );
  }
}
