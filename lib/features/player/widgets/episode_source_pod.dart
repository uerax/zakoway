import 'package:flutter/material.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import '../../common/widgets/directional_tab_bar_view.dart';
import '../source/source_aggregator.dart';
import '../source/utils/playable_slot_engine.dart';
import 'episode_picker_section.dart';
import 'video_source_view.dart';

/// 律动音波小动画（iOS / M3 风格圆润微光音波指示器）
class _PodPlayingBarsAnimation extends StatefulWidget {
  const _PodPlayingBarsAnimation();

  @override
  State<_PodPlayingBarsAnimation> createState() => _PodPlayingBarsAnimationState();
}

class _PodPlayingBarsAnimationState extends State<_PodPlayingBarsAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, _) {
        final val = CurvedAnimation(
          parent: _animController,
          curve: Curves.easeInOut,
        ).value;
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _buildBar(3.0 + 5.0 * val),
            const SizedBox(width: 1.8),
            _buildBar(8.0 - 5.0 * val),
            const SizedBox(width: 1.8),
            _buildBar(4.0 + 4.5 * (1.0 - val)),
          ],
        );
      },
    );
  }

  Widget _buildBar(double height) {
    return Container(
      width: 2.0,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(1.2),
      ),
    );
  }
}

/// 选集与视频源深度融合舱 (Episode & Video Source Hybrid Pod)
///
/// 核心形态：
/// 1. 移动端/折叠态：自适应高度，包含源药丸 + 多线路滑轨 + 横向数字选集滑轨 + 异常自愈推荐；
/// 2. 展开抽屉态：点击药丸或「展开全部」时，拉起包含十几个源探活与完整选集大网格的专业面板；
/// 3. 桌面端内嵌态：右侧直接展示源选择器与完整 4 列选集网格。
class EpisodeSourcePod extends StatelessWidget {
  const EpisodeSourcePod({
    super.key,
    required this.selectedSourceId,
    required this.selectedSourceName,
    this.playingSourceId,
    required this.sources,
    required this.onSourceSelected,
    this.onSelectHit,
    this.aggregator,
    this.keywordOptions = const [],
    this.onUserAction,
    this.currentEpisode,
    this.playingRoadIndex,
    required this.isLoadingChapters,
    this.resolveError,
    required this.hasEpisodes,
    required this.currentSlots,
    required this.roadNames,
    required this.selectedRoadIndex,
    required this.mappedEpisodeTitles,
    required this.onRoadSelected,
    required this.onSelectEpisode,
    required this.onSelectSlot,
    required this.onRefreshEpisodes,
    this.isDesktopExpanded = false,
  });

  final String selectedSourceId;
  final String selectedSourceName;
  final String? playingSourceId;
  final List<VideoSourceItem> sources;
  final ValueChanged<VideoSourceItem> onSourceSelected;
  final SourceHitSelectCallback? onSelectHit;
  final SourceAggregator? aggregator;
  final List<String> keywordOptions;
  final VoidCallback? onUserAction;

  final int? currentEpisode;
  final int? playingRoadIndex;
  final bool isLoadingChapters;
  final String? resolveError;
  final bool hasEpisodes;
  final List<PlayableSlot> currentSlots;
  final List<String> roadNames;
  final int selectedRoadIndex;
  final List<String> mappedEpisodeTitles;
  final ValueChanged<int> onRoadSelected;
  final ValueChanged<int> onSelectEpisode;
  final ValueChanged<PlayableSlot> onSelectSlot;
  final VoidCallback onRefreshEpisodes;
  final bool isDesktopExpanded;

  /// 呼出全功能选集与视频源抽屉 (BottomSheet)
  void _openFullSheet(BuildContext context, {int initialTab = 0}) {
    onUserAction?.call();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: isDark ? 0.65 : 0.45),
      builder: (bottomSheetContext) {
        final screenHeight = MediaQuery.of(bottomSheetContext).size.height;
        return GestureDetector(
          // 点击半透明空白背景立即秒关
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(bottomSheetContext).pop(),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              // 拦截面板内部点击，防止冒泡触发关闭
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: SizedBox(
                height: screenHeight * 0.82,
                child: DefaultTabController(
                  length: 2,
                  initialIndex: initialTab.clamp(0, 1),
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
                        // 弹窗顶栏：Tab 切换 (选集大网格 vs 视频源看板)
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
                                    unselectedLabelStyle: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'MiSans',
                                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                                    ),
                                    tabs: const [
                                      Tab(text: '选集网格'),
                                      Tab(text: '切换视频源'),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () => Navigator.of(bottomSheetContext).pop(),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 12, thickness: 0.5),
                        Expanded(
                          child: DirectionalTabBarView(
                            children: [
                              // 1. 完整选集网格面板
                              EpisodePickerSection(
                                episodeCount: currentSlots.isNotEmpty ? currentSlots.length : 12,
                                currentEpisode: currentEpisode,
                                slots: currentSlots,
                                roads: roadNames,
                                activeRoadIndex: selectedRoadIndex,
                                playingRoadIndex: playingRoadIndex,
                                episodeTitles: mappedEpisodeTitles,
                                isLoading: isLoadingChapters,
                                loadingMessage: '正在从「$selectedSourceName」解析分集...',
                                onRoadSelected: onRoadSelected,
                                onSelectEpisode: (ep) {
                                  onSelectEpisode(ep);
                                  Navigator.of(bottomSheetContext).pop();
                                },
                                onSelectSlot: (slot) {
                                  onSelectSlot(slot);
                                  Navigator.of(bottomSheetContext).pop();
                                },
                                onRefresh: onRefreshEpisodes,
                              ),
                              // 2. 视频源与多源探活看板
                              VideoSourceView(
                                sources: sources,
                                selectedSourceId: selectedSourceId,
                                playingSourceId: playingSourceId,
                                aggregator: aggregator,
                                keywordOptions: keywordOptions,
                                onSourceSelected: (src) {
                                  onSourceSelected(src);
                                  Navigator.of(bottomSheetContext).pop();
                                },
                                onSelectHit: (src, hit, [roads]) {
                                  onSelectHit?.call(src, hit, roads);
                                  Navigator.of(bottomSheetContext).pop();
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    // 桌面端内嵌展开模式
    if (isDesktopExpanded) {
      return _buildDesktopLayout(context, isDark, primaryColor, theme);
    }

    // 移动端/折叠紧凑融合舱
    return _buildMobileCompactPod(context, isDark, primaryColor, theme);
  }

  /// 移动端紧凑舱
  Widget _buildMobileCompactPod(
    BuildContext context,
    bool isDark,
    Color primaryColor,
    ThemeData theme,
  ) {
    final totalEpisodes = currentSlots.isNotEmpty ? currentSlots.length : 0;
    final epLabel = totalEpisodes > 0 ? '全 $totalEpisodes 话' : '剧集列表';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 第一行：标题 + 当前源药丸胶囊 + 常驻全部
          Row(
            children: [
              Expanded(
                child: Text(
                  epLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    fontFamily: 'MiSans',
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              // 当前源药丸按钮（点击呼出视频源面板）
              BouncingScaleCard(
                scaleDown: 0.94,
                immediateTap: true,
                onTap: () => _openFullSheet(context, initialTab: 1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white.withAlpha(18) : Colors.black.withAlpha(12),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt_rounded,
                        size: 13,
                        color: primaryColor,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        selectedSourceName,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : primaryColor,
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                      ),
                      const SizedBox(width: 1),
                      Icon(
                        Icons.unfold_more_rounded,
                        size: 13,
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // 常驻全部入口按钮（随时可点，再也不用滑到最后）
              BouncingScaleCard(
                scaleDown: 0.94,
                immediateTap: true,
                onTap: () => _openFullSheet(context, initialTab: 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white.withAlpha(18) : Colors.black.withAlpha(12),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '全部',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.85),
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        Icons.grid_view_rounded,
                        size: 12,
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // 2. 多线路切换胶囊滑轨 (仅在有 2 条以上线路时展示)
          if (roadNames.length > 1) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(roadNames.length, (idx) {
                  final isRoadActive = idx == selectedRoadIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => onRoadSelected(idx),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 90),
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: isRoadActive
                              ? primaryColor.withValues(alpha: isDark ? 0.24 : 0.14)
                              : (isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isRoadActive
                                ? primaryColor.withValues(alpha: 0.45)
                                : Colors.transparent,
                            width: 0.5,
                          ),
                        ),
                        child: Text(
                          roadNames[idx],
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isRoadActive ? FontWeight.w700 : FontWeight.w500,
                            color: isRoadActive
                                ? (isDark ? Colors.white : primaryColor)
                                : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                            fontFamily: 'MiSans',
                            fontFamilyFallback: FontManager.fallbackFontFamilies,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],

          const SizedBox(height: 10),

          // 3. 核心分集区（加载中 / 异常自愈态 / 正常横向滑轨）
          if (isLoadingChapters) ...[
            Container(
              height: 44,
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      color: primaryColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '正在从「$selectedSourceName」解析分集...',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.textTheme.bodySmall?.color,
                      fontFamily: 'MiSans',
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (resolveError != null || !hasEpisodes) ...[
            // 未收录/解析空提示行
            _buildEmptyNotice(context, isDark, primaryColor, theme),
          ] else ...[
            // 正常横向选集数字滑轨
            _buildHorizontalEpisodeScroll(context, isDark, primaryColor, theme),
          ],
        ],
      ),
    );
  }

  /// 未收录或解析空提示行 (极简精致，融入卡片，一键直达切换视频源)
  Widget _buildEmptyNotice(
    BuildContext context,
    bool isDark,
    Color primaryColor,
    ThemeData theme,
  ) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: 15,
            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.65),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              resolveError ?? '当前视频源未收录此番剧',
              style: TextStyle(
                fontSize: 12,
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.75),
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          BouncingScaleCard(
            scaleDown: 0.94,
            immediateTap: true,
            onTap: () => _openFullSheet(context, initialTab: 1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
              decoration: BoxDecoration(
                color: primaryColor.withValues(alpha: isDark ? 0.22 : 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.4),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '切换视频源',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : primaryColor,
                      fontFamily: 'MiSans',
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: isDark ? Colors.white70 : primaryColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 移动端横向选集数字滑轨
  Widget _buildHorizontalEpisodeScroll(
    BuildContext context,
    bool isDark,
    Color primaryColor,
    ThemeData theme,
  ) {
    final slots = currentSlots;

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: slots.length,
        separatorBuilder: (_, _) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final slot = slots[index];
          // 特殊处理说明：
          // 线路与分集在播态严格由外部 playingRoadIndex 驱动；
          // 当 playingRoadIndex 为 null 时代表当前源未处于在播态，绝不盲目高亮。
          final isRoadPlaying = playingRoadIndex != null && playingRoadIndex == selectedRoadIndex;
          final isPlaying = isRoadPlaying && currentEpisode != null && slot.canonicalEp == currentEpisode;

          return BouncingScaleCard(
            scaleDown: 0.92,
            immediateTap: true,
            onTap: () => onSelectSlot(slot),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              decoration: BoxDecoration(
                color: isPlaying
                    ? primaryColor
                    : (isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8)),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isPlaying
                      ? primaryColor
                      : (isDark ? Colors.white.withAlpha(16) : Colors.black.withAlpha(10)),
                  width: 0.5,
                ),
                boxShadow: isPlaying
                    ? [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: isPlaying
                  ? const _PodPlayingBarsAnimation()
                  : Text(
                      '${slot.canonicalEp}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w600,
                        color: isPlaying
                            ? Colors.white
                            : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.9),
                        fontFamily: 'MiSans',
                        fontFamilyFallback: FontManager.fallbackFontFamilies,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  /// 桌面端内嵌双栏/选集源大面板
  Widget _buildDesktopLayout(
    BuildContext context,
    bool isDark,
    Color primaryColor,
    ThemeData theme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 桌面端顶栏：源切换下拉胶囊
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              const Text(
                '选集列表',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'MiSans',
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                ),
              ),
              const Spacer(),
              BouncingScaleCard(
                scaleDown: 0.95,
                onTap: () => _openFullSheet(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white.withAlpha(18) : Colors.black.withAlpha(12),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: primaryColor),
                      const SizedBox(width: 4),
                      Text(
                        selectedSourceName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : primaryColor,
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.arrow_drop_down_rounded, size: 16, color: primaryColor),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // 内嵌完整选集大网格
        Expanded(
          child: EpisodePickerSection(
            episodeCount: currentSlots.isNotEmpty ? currentSlots.length : 12,
            currentEpisode: currentEpisode,
            slots: currentSlots,
            roads: roadNames,
            activeRoadIndex: selectedRoadIndex,
            playingRoadIndex: playingRoadIndex,
            episodeTitles: mappedEpisodeTitles,
            onRoadSelected: onRoadSelected,
            onSelectEpisode: onSelectEpisode,
            onSelectSlot: onSelectSlot,
            onRefresh: onRefreshEpisodes,
          ),
        ),
      ],
    );
  }
}
