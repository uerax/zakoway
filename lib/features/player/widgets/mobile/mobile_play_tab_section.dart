import 'package:flutter/material.dart';
import '../../../../core/models/bangumi/bangumi_item.dart';
import '../../../../core/models/bangumi/bangumi_recommendation_item.dart';
import '../../source/models/source_models.dart';
import '../../source/source_aggregator.dart';
import '../../source/utils/playable_slot_engine.dart';
import '../video_play_tabs.dart';
import '../video_source_view.dart';

/// 移动端专用下方分段内容面板（包含 Tab 头部与 Tab 容器）
class MobilePlayTabSection extends StatelessWidget {
  const MobilePlayTabSection({
    super.key,
    required this.tabController,
    required this.title,
    required this.effectiveBangumiItem,
    required this.isLoadingAuthorityDetails,
    required this.resolvedCoverUrl,
    required this.displayEpisodeCount,
    required this.sources,
    required this.selectedSourceId,
    required this.selectedSourceName,
    required this.playingSourceId,
    required this.onSourceSelected,
    required this.aggregator,
    required this.sourceNotice,
    required this.keywordOptions,
    required this.onUserAction,
    required this.activeEpisode,
    required this.playingRoadIndex,
    required this.isLoadingChapters,
    required this.chaptersError,
    required this.hasEpisodes,
    required this.currentSlots,
    required this.roadNames,
    required this.selectedRoadIndex,
    required this.mappedEpisodeTitles,
    required this.onRoadSelected,
    required this.onRefreshEpisodes,
    required this.onSelectEpisode,
    required this.onSelectSlot,
    required this.onTapRecommendItem,
  });

  final TabController tabController;
  final String title;
  final BangumiItem? effectiveBangumiItem;
  final bool isLoadingAuthorityDetails;
  final String resolvedCoverUrl;
  final int displayEpisodeCount;
  final List<VideoSourceItem> sources;
  final String selectedSourceId;
  final String selectedSourceName;
  final String? playingSourceId;
  final void Function(VideoSourceItem src, [SourceSearchResult? hit, List<SourceChapterRoad>? roads]) onSourceSelected;
  final SourceAggregator aggregator;
  final String? sourceNotice;
  final List<String> keywordOptions;
  final VoidCallback onUserAction;
  final int? activeEpisode;
  final int? playingRoadIndex;
  final bool isLoadingChapters;
  final String? chaptersError;
  final bool hasEpisodes;
  final List<PlayableSlot> currentSlots;
  final List<String> roadNames;
  final int selectedRoadIndex;
  final List<String> mappedEpisodeTitles;
  final ValueChanged<int> onRoadSelected;
  final VoidCallback onRefreshEpisodes;
  final ValueChanged<int> onSelectEpisode;
  final ValueChanged<PlayableSlot> onSelectSlot;
  final ValueChanged<BangumiRecommendationItem> onTapRecommendItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        VideoPlaySegmentedTabBar(tabController: tabController),
        Expanded(
          child: VideoPlayTabContentView(
            tabController: tabController,
            title: title,
            bangumiItem: effectiveBangumiItem,
            isLoadingAuthorityDetails: isLoadingAuthorityDetails,
            coverUrl: resolvedCoverUrl,
            episodeCount: displayEpisodeCount,
            sources: sources,
            selectedSourceId: selectedSourceId,
            selectedSourceName: selectedSourceName,
            playingSourceId: playingSourceId,
            onSourceSelected: onSourceSelected,
            aggregator: aggregator,
            sourceNotice: sourceNotice,
            keywordOptions: keywordOptions,
            onUserAction: onUserAction,
            currentEpisode: activeEpisode,
            playingRoadIndex: playingRoadIndex,
            isLoadingChapters: isLoadingChapters,
            resolveError: chaptersError,
            hasEpisodes: hasEpisodes,
            currentSlots: currentSlots,
            roadNames: roadNames,
            selectedRoadIndex: selectedRoadIndex,
            mappedEpisodeTitles: mappedEpisodeTitles,
            onRoadSelected: onRoadSelected,
            onRefreshEpisodes: onRefreshEpisodes,
            onSelectEpisode: onSelectEpisode,
            onSelectSlot: onSelectSlot,
            onTapRecommendItem: onTapRecommendItem,
          ),
        ),
      ],
    );
  }
}
