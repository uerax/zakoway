import 'package:flutter/material.dart';
import '../../../../core/models/bangumi/bangumi_item.dart';
import '../../../../core/models/bangumi/bangumi_recommendation_item.dart';
import '../../../../core/services/app_preferences.dart';
import '../../../../core/services/watched_episodes_service.dart';
import '../../source/models/source_models.dart';
import '../../source/source_aggregator.dart';
import '../../source/source_bundle_manager.dart';
import '../../source/utils/playable_slot_engine.dart';
import '../episode_picker_section.dart';
import '../video_player_layouts.dart';
import '../video_source_view.dart';
import '../watch_comments_section.dart';
import '../watch_meta_view.dart';
import '../watch_recommend_section.dart';

/// 桌面端专属双栏分块播放布局容器
class DesktopPlayContent extends StatelessWidget {
  const DesktopPlayContent({
    super.key,
    required this.title,
    required this.currentEpisode,
    required this.isTheaterMode,
    required this.onBackPressed,
    required this.playerWidget,
    required this.effectiveBangumiItem,
    required this.effectiveBangumiId,
    required this.isLoadingAuthorityDetails,
    required this.resolvedCoverUrl,
    required this.displayEpisodeCount,
    required this.rightTabController,
    required this.roadNames,
    required this.selectedRoadIndex,
    required this.playingRoadIndex,
    required this.mappedEpisodeTitles,
    required this.currentSlots,
    required this.isLoadingChapters,
    required this.selectedSourceName,
    required this.selectedSourceId,
    required this.chaptersError,
    required this.onSwitchSourceTab,
    required this.onRoadSelected,
    required this.onRefreshEpisodes,
    required this.onSelectEpisode,
    required this.onSelectSlot,
    required this.sources,
    required this.playingSourceId,
    required this.hasStartedPlayback,
    required this.onSourceSelected,
    required this.aggregator,
    required this.sourceNotice,
    required this.keywordOptions,
    required this.onUserAction,
    required this.onTapRecommendItem,
  });

  final String title;
  final int? currentEpisode;
  final bool isTheaterMode;
  final VoidCallback onBackPressed;
  final Widget playerWidget;
  final BangumiItem? effectiveBangumiItem;
  final int effectiveBangumiId;
  final bool isLoadingAuthorityDetails;
  final String resolvedCoverUrl;
  final int displayEpisodeCount;
  final TabController rightTabController;
  final List<String> roadNames;
  final int selectedRoadIndex;
  final int? playingRoadIndex;
  final List<String> mappedEpisodeTitles;
  final List<PlayableSlot> currentSlots;
  final bool isLoadingChapters;
  final String selectedSourceName;
  final String selectedSourceId;
  final String? chaptersError;
  final VoidCallback onSwitchSourceTab;
  final ValueChanged<int> onRoadSelected;
  final VoidCallback onRefreshEpisodes;
  final ValueChanged<int> onSelectEpisode;
  final ValueChanged<PlayableSlot> onSelectSlot;
  final List<VideoSourceItem> sources;
  final String? playingSourceId;
  final bool hasStartedPlayback;
  final void Function(VideoSourceItem src, [SourceSearchResult? hit, List<SourceChapterRoad>? roads]) onSourceSelected;
  final SourceAggregator aggregator;
  final String? sourceNotice;
  final List<String> keywordOptions;
  final VoidCallback onUserAction;
  final ValueChanged<BangumiRecommendationItem> onTapRecommendItem;

  @override
  Widget build(BuildContext context) {
    return VideoPlayerDesktopLayout(
      title: title,
      currentEpisode: currentEpisode,
      isTheaterMode: isTheaterMode,
      onBackPressed: onBackPressed,
      playerWidget: playerWidget,
      introSection: WatchMetaView(
        title: title,
        bangumiItem: effectiveBangumiItem,
        isLoadingDetails: isLoadingAuthorityDetails,
        coverUrl: resolvedCoverUrl,
        episodeCount: displayEpisodeCount,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
      ),
      commentsSection: WatchCommentsSection(
        bangumiId: effectiveBangumiId,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
      ),
      rightTabController: rightTabController,
      episodePickerSection: ListenableBuilder(
        listenable: WatchedEpisodesService.instance,
        builder: (context, _) {
          final watched =
              WatchedEpisodesService.instance.getWatchedEpisodes(effectiveBangumiId);
          return EpisodePickerSection(
            episodeCount: displayEpisodeCount,
            currentEpisode: currentEpisode,
            roads: roadNames,
            activeRoadIndex: selectedRoadIndex,
            playingRoadIndex: playingRoadIndex,
            episodeTitles: mappedEpisodeTitles,
            slots: currentSlots,
            watchedEpisodes: watched,
            isLoading: isLoadingChapters,
            loadingMessage: '正在从「$selectedSourceName」解析分集...',
            sourceName: selectedSourceName,
            errorMessage: chaptersError,
            onEnableServerMode: (!AppPreferences.isServerModeEnabled() &&
                    !SourceBundleManager.instance.runtime.isLocalSource(selectedSourceId))
                ? () => AppPreferences.setServerModeEnabled(true)
                : null,
            onSwitchSource: onSwitchSourceTab,
            onRoadSelected: onRoadSelected,
            onRefresh: onRefreshEpisodes,
            onSelectEpisode: onSelectEpisode,
            onSelectSlot: onSelectSlot,
            shrinkWrap: true,
          );
        },
      ),
      sourceViewSection: VideoSourceView(
        sources: sources,
        selectedSourceId: selectedSourceId,
        playingSourceId: playingSourceId,
        onSourceSelected: (src) => onSourceSelected(src),
        onSelectHit: (src, hit, [roads]) => onSourceSelected(src, hit, roads),
        aggregator: aggregator,
        hintMessage: sourceNotice,
        keywordOptions: keywordOptions,
        onUserAction: onUserAction,
        currentEpisodeNumber: currentEpisode,
      ),
      recommendSection: WatchRecommendSection(
        bangumiId: effectiveBangumiId,
        bangumiItem: effectiveBangumiItem,
        onTapItem: onTapRecommendItem,
      ),
    );
  }
}
