import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zakoway/core/models/bangumi/bangumi_item.dart';
import 'package:zakoway/core/services/watched_episodes_service.dart';
import 'package:zakoway/core/utils/font_manager.dart';
import 'package:zakoway/features/common/widgets/bouncing_scale_card.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/source_aggregator.dart';
import 'package:zakoway/features/player/source/utils/playable_slot_engine.dart';
import 'episode_picker_section.dart';
import 'video_source_view.dart';
import 'watch_meta_view.dart';

/// iOS / M3 风格极简精致滑动胶囊分段控制器
class VideoPlaySegmentedTabBar extends StatelessWidget {
  const VideoPlaySegmentedTabBar({
    super.key,
    required this.tabController,
  });

  final TabController tabController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
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
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
              tabs: const [
                Tab(height: 32, text: '番剧详情'),
                Tab(height: 32, text: '视频源'),
                Tab(height: 32, text: '选集'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 播放页核心 3-Tab 内容切换视图（详情、源列表、选集）
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

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: tabController,
      children: [
        WatchMetaView(
          title: title,
          bangumiItem: bangumiItem,
          isLoadingDetails: isLoadingAuthorityDetails,
          coverUrl: coverUrl,
          episodeCount: episodeCount,
        ),
        VideoSourceView(
          sources: sources,
          selectedSourceId: selectedSourceId,
          onSourceSelected: onSourceSelected,
          onSelectHit: (src, hit, [List<SourceChapterRoad>? cachedRoads]) =>
              onSourceSelected(src, hit, cachedRoads),
          aggregator: aggregator,
          hintMessage: sourceNotice,
          keywordOptions: keywordOptions,
          onUserAction: onUserAction,
          currentEpisodeNumber: currentEpisode,
        ),
        _buildEpisodeSection(context),
      ],
    );
  }

  Widget _buildEpisodeSection(BuildContext context) {
    if (isLoadingChapters) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupertinoActivityIndicator(radius: 12),
            const SizedBox(height: 12),
            Text(
              '正在加载并校准分集信息...',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12.5,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      );
    }

    if (!hasEpisodes) {
      final isError = resolveError != null && resolveError!.isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isError ? Icons.error_outline_rounded : Icons.search_off_rounded,
                size: 48,
                color: isError ? Colors.amber : Colors.grey,
              ),
              const SizedBox(height: 12),
              Text(
                isError
                    ? '「$selectedSourceName」分集解析失败'
                    : '「$selectedSourceName」暂未检索到该番剧分集',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: Theme.of(context).textTheme.titleSmall?.fontFamily,
                  fontFamilyFallback: Theme.of(context).textTheme.titleSmall?.fontFamilyFallback,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isError
                    ? resolveError!
                    : '建议切换到其他备用视频源查找资源',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
                  fontFamilyFallback: Theme.of(context).textTheme.bodySmall?.fontFamilyFallback,
                  fontSize: 12,
                  color: isError ? Colors.redAccent.withValues(alpha: 0.85) : Colors.grey,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isError) ...[
                    BouncingScaleCard(
                      scaleDown: 0.95,
                      onTap: onRefreshEpisodes,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.refresh_rounded, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '重试',
                              style: TextStyle(
                                fontFamily: Theme.of(context).textTheme.labelMedium?.fontFamily,
                                fontFamilyFallback: Theme.of(context).textTheme.labelMedium?.fontFamilyFallback,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  BouncingScaleCard(
                    scaleDown: 0.95,
                    onTap: () {
                      onUserAction();
                      tabController.animateTo(1);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.swap_horiz_rounded, size: 17, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            '前往「视频源」选择',
                            style: TextStyle(
                              fontFamily: Theme.of(context).textTheme.labelMedium?.fontFamily,
                              fontFamilyFallback: Theme.of(context).textTheme.labelMedium?.fontFamilyFallback,
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
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
        ),
      );
    }

    return ListenableBuilder(
      listenable: WatchedEpisodesService.instance,
      builder: (context, _) {
        final watched = WatchedEpisodesService.instance.getWatchedEpisodes(bangumiItem?.id ?? 0);
        return EpisodePickerSection(
          episodeCount: currentSlots.isNotEmpty ? currentSlots.length : episodeCount,
          currentEpisode: currentEpisode,
          roads: roadNames,
          activeRoadIndex: selectedRoadIndex,
          playingRoadIndex: playingRoadIndex,
          episodeTitles: mappedEpisodeTitles,
          slots: currentSlots,
          watchedEpisodes: watched,
          onRoadSelected: onRoadSelected,
          onRefresh: onRefreshEpisodes,
          onSelectEpisode: onSelectEpisode,
          onSelectSlot: onSelectSlot,
        );
      },
    );
  }
}
