import 'package:flutter/material.dart';
import '../../../../core/services/app_preferences.dart';
import '../../../../core/utils/font_manager.dart';
import '../../source/models/source_models.dart';
import '../../source/source_aggregator.dart';
import '../../source/source_bundle_manager.dart';
import '../../source/utils/playable_slot_engine.dart';
import '../episode_picker_section.dart';
import '../video_source_view.dart';

/// 移动端全功能选集与多视频源看板抽屉 (BottomSheet)
///
/// 架构设计与交互规范：
/// 1. 支持双 Tab 快速切换（Tab 0: 选集网格，Tab 1: 视频源看板）；
/// 2. 高度锁定在屏幕高度的 82%，顶部留白可透出底层播放器画面；
/// 3. 与 SourceAggregator 展开状态受控绑定，在打开时激活探活队列，关闭时安全休眠。
class MobileEpisodeSourceSheet extends StatelessWidget {
  const MobileEpisodeSourceSheet({
    super.key,
    required this.bangumiId,
    required this.displayEpisodeCount,
    required this.currentEpisode,
    required this.currentSlots,
    required this.roadNames,
    required this.selectedRoadIndex,
    required this.playingRoadIndex,
    required this.mappedEpisodeTitles,
    required this.isLoadingChapters,
    required this.selectedSourceName,
    required this.chaptersError,
    required this.selectedSourceId,
    required this.playingSourceId,
    required this.hasStartedPlayback,
    required this.sources,
    required this.aggregator,
    required this.keywordOptions,
    required this.onSelectEpisode,
    required this.onSelectSlot,
    required this.onRoadSelected,
    required this.onRefresh,
    required this.onSourceSelected,
    required this.onSelectHit,
    this.initialTabIndex = 1,
  });

  final int bangumiId;
  final int displayEpisodeCount;
  final int? currentEpisode;
  final List<PlayableSlot> currentSlots;
  final List<String> roadNames;
  final int selectedRoadIndex;
  final int? playingRoadIndex;
  final List<String> mappedEpisodeTitles;
  final bool isLoadingChapters;
  final String selectedSourceName;
  final String? chaptersError;
  final String selectedSourceId;
  final String? playingSourceId;
  final bool hasStartedPlayback;
  final List<VideoSourceItem> sources;
  final SourceAggregator aggregator;
  final List<String> keywordOptions;
  final ValueChanged<int> onSelectEpisode;
  final ValueChanged<PlayableSlot> onSelectSlot;
  final ValueChanged<int> onRoadSelected;
  final VoidCallback onRefresh;
  final ValueChanged<VideoSourceItem> onSourceSelected;
  final void Function(VideoSourceItem, SourceSearchResult, [List<SourceChapterRoad>?]) onSelectHit;
  final int initialTabIndex;

  static Future<void> show(
    BuildContext context, {
    required int bangumiId,
    required int displayEpisodeCount,
    required int? currentEpisode,
    required List<PlayableSlot> currentSlots,
    required List<String> roadNames,
    required int selectedRoadIndex,
    required int? playingRoadIndex,
    required List<String> mappedEpisodeTitles,
    required bool isLoadingChapters,
    required String selectedSourceName,
    required String? chaptersError,
    required String selectedSourceId,
    required String? playingSourceId,
    required bool hasStartedPlayback,
    required List<VideoSourceItem> sources,
    required SourceAggregator aggregator,
    required List<String> keywordOptions,
    required ValueChanged<int> onSelectEpisode,
    required ValueChanged<PlayableSlot> onSelectSlot,
    required ValueChanged<int> onRoadSelected,
    required VoidCallback onRefresh,
    required ValueChanged<VideoSourceItem> onSourceSelected,
    required void Function(VideoSourceItem, SourceSearchResult, [List<SourceChapterRoad>?]) onSelectHit,
    int initialTabIndex = 1,
  }) {
    aggregator.setOpen(true);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.65 : 0.45),
      builder: (bottomSheetContext) {
        return MobileEpisodeSourceSheet(
          bangumiId: bangumiId,
          displayEpisodeCount: displayEpisodeCount,
          currentEpisode: currentEpisode,
          currentSlots: currentSlots,
          roadNames: roadNames,
          selectedRoadIndex: selectedRoadIndex,
          playingRoadIndex: playingRoadIndex,
          mappedEpisodeTitles: mappedEpisodeTitles,
          isLoadingChapters: isLoadingChapters,
          selectedSourceName: selectedSourceName,
          chaptersError: chaptersError,
          selectedSourceId: selectedSourceId,
          playingSourceId: playingSourceId,
          hasStartedPlayback: hasStartedPlayback,
          sources: sources,
          aggregator: aggregator,
          keywordOptions: keywordOptions,
          onSelectEpisode: onSelectEpisode,
          onSelectSlot: onSelectSlot,
          onRoadSelected: onRoadSelected,
          onRefresh: onRefresh,
          onSourceSelected: onSourceSelected,
          onSelectHit: onSelectHit,
          initialTabIndex: initialTabIndex,
        );
      },
    ).whenComplete(() {
      aggregator.setOpen(false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenHeight = MediaQuery.of(context).size.height;

    return GestureDetector(
      // 点击半透明空白背景立即秒关
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          // 阻断内容区点击冒泡
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: SizedBox(
            height: screenHeight * 0.82,
            child: DefaultTabController(
              length: 2,
              initialIndex: initialTabIndex,
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
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 36,
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: TabBar(
                                splashFactory: NoSplash.splashFactory,
                                overlayColor: WidgetStateProperty.all(Colors.transparent),
                                dividerColor: Colors.transparent,
                                indicatorSize: TabBarIndicatorSize.tab,
                                indicator: BoxDecoration(
                                  color: isDark ? Colors.white.withValues(alpha: 0.16) : Colors.white,
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                labelColor: isDark ? Colors.white : Theme.of(context).colorScheme.primary,
                                unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
                                labelStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'MiSans',
                                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                                ),
                                tabs: const [
                                  Tab(text: '选集列表'),
                                  Tab(text: '切换视频源'),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 12, thickness: 0.5),
                    Expanded(
                      child: TabBarView(
                        children: [
                          EpisodePickerSection(
                            episodeCount: displayEpisodeCount,
                            currentEpisode: currentEpisode,
                            slots: currentSlots,
                            roads: roadNames,
                            activeRoadIndex: selectedRoadIndex,
                            playingRoadIndex: playingRoadIndex,
                            episodeTitles: mappedEpisodeTitles,
                            isLoading: isLoadingChapters,
                            sourceName: selectedSourceName,
                            errorMessage: chaptersError,
                            onEnableServerMode: (!AppPreferences.isServerModeEnabled() &&
                                    !SourceBundleManager.instance.runtime.isLocalSource(selectedSourceId))
                                ? () => AppPreferences.setServerModeEnabled(true)
                                : null,
                            onSwitchSource: () {
                              DefaultTabController.of(context).animateTo(1);
                            },
                            onRoadSelected: onRoadSelected,
                            onSelectEpisode: (ep) {
                              onSelectEpisode(ep);
                              Navigator.of(context).pop();
                            },
                            onSelectSlot: (slot) {
                              onSelectSlot(slot);
                              Navigator.of(context).pop();
                            },
                            onRefresh: onRefresh,
                          ),
                          VideoSourceView(
                            sources: sources,
                            selectedSourceId: selectedSourceId,
                            playingSourceId: playingSourceId,
                            aggregator: aggregator,
                            keywordOptions: keywordOptions,
                            onSourceSelected: (src) {
                              onSourceSelected(src);
                              Navigator.of(context).pop();
                            },
                            onSelectHit: (src, hit, [roads]) {
                              onSelectHit(src, hit, roads);
                              Navigator.of(context).pop();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
