import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/controller/playback_state.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';
import 'package:zakoway/features/player/source/source_aggregator.dart';
import 'package:zakoway/features/player/source/utils/playable_slot_engine.dart';
import 'package:zakoway/core/services/watched_episodes_service.dart';
import 'package:zakoway/core/utils/font_manager.dart';
import 'package:zakoway/features/player/widgets/episode_picker_section.dart';
import 'package:zakoway/features/player/widgets/video_source_view.dart';
import 'controls/super_resolution_dialog_helper.dart';

/// 全屏侧边抽屉 Tab 枚举
enum PlayerSidePanelTab {
  episodes,
  sources,
  danmaku,
}

/// 全屏悬浮半透明侧边抽屉组件 (SidePanel)
/// 借鉴 Kazumi + animaku 交互规范：全屏看剧时，选集、切源、调弹幕绝不打断视频播放
class PlayerSidePanel extends StatefulWidget {
  const PlayerSidePanel({
    super.key,
    required this.isOpen,
    required this.initialTab,
    required this.onClose,
    this.bangumiId = 0,
    required this.episodeCount,
    this.currentEpisode,
    this.roads = const ['默认线路'],
    this.activeRoadIndex = 0,
    this.playingRoadIndex,
    this.episodeTitles = const [],
    required this.onSelectEpisode,
    this.onRoadSelected,
    this.onRefreshEpisodes,
    this.slots,
    this.onSelectSlot,
    required this.sources,
    required this.selectedSourceId,
    required this.onSourceSelected,
    this.onSelectHit,
    this.aggregator,
    this.danmakuController,
    this.controller,
    this.isLoadingEpisodes = false,
    this.resolveError,
  });

  final bool isOpen;
  final PlayerSidePanelTab initialTab;
  final VoidCallback onClose;
  final int bangumiId;

  // 选集相关
  final int episodeCount;
  final int? currentEpisode;
  final List<String> roads;
  final int activeRoadIndex;
  final int? playingRoadIndex;
  final List<String> episodeTitles;
  final List<PlayableSlot>? slots;
  final ValueChanged<int> onSelectEpisode;
  final ValueChanged<PlayableSlot>? onSelectSlot;
  final ValueChanged<int>? onRoadSelected;
  final VoidCallback? onRefreshEpisodes;
  final bool isLoadingEpisodes;
  final String? resolveError;

  // 视频源相关
  final List<VideoSourceItem> sources;
  final String selectedSourceId;
  final ValueChanged<VideoSourceItem> onSourceSelected;
  final SourceHitSelectCallback? onSelectHit;
  final SourceAggregator? aggregator;

  // 弹幕与播放控制
  final DanmakuController? danmakuController;
  final ZakowayPlaybackController? controller;

  @override
  State<PlayerSidePanel> createState() => _PlayerSidePanelState();
}

class _PlayerSidePanelState extends State<PlayerSidePanel> {
  late PlayerSidePanelTab _activeTab;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
  }

  @override
  void didUpdateWidget(covariant PlayerSidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen && !oldWidget.isOpen) {
      _activeTab = widget.initialTab;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final panelWidth =
            constraints.maxWidth < 360 ? constraints.maxWidth : 360.0;
        final isFullCover = constraints.maxWidth < 360;

        return Stack(
          children: [
            // 1. 半透明黑色遮罩（点击空白区域关闭侧边抽屉）
            IgnorePointer(
              ignoring: !widget.isOpen,
              child: AnimatedOpacity(
                opacity: widget.isOpen ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: widget.onClose,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),

            // 2. 右侧悬浮毛玻璃滑出抽屉 (Side Drawer，小屏下自适应视口宽度防截断)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: panelWidth,
              child: AnimatedSlide(
                offset: widget.isOpen ? Offset.zero : const Offset(1.0, 0.0),
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: ClipRRect(
                  borderRadius: isFullCover
                      ? BorderRadius.zero
                      : const BorderRadius.horizontal(left: Radius.circular(20)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xE6141418), // 深空高透毛玻璃
                        borderRadius: isFullCover
                            ? BorderRadius.zero
                            : const BorderRadius.horizontal(left: Radius.circular(20)),
                        border: isFullCover
                            ? null
                            : Border(
                                left: BorderSide(
                                  color: Colors.white.withValues(alpha: 0.16),
                                  width: 0.5,
                                ),
                              ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 24,
                            offset: const Offset(-4, 0),
                          ),
                        ],
                      ),
                      child: Theme(
                        data: ThemeData.dark().copyWith(
                          scaffoldBackgroundColor: Colors.transparent,
                          colorScheme: ColorScheme.dark(
                            primary: primaryColor,
                            surface: const Color(0xFF1E1E24),
                            onSurface: Colors.white,
                            onSurfaceVariant: Colors.white.withValues(alpha: 0.7),
                          ),
                          textTheme: const TextTheme(
                            bodyLarge: TextStyle(color: Colors.white, fontFamily: 'MiSans', fontFamilyFallback: FontManager.fallbackFontFamilies),
                            bodyMedium: TextStyle(color: Colors.white, fontFamily: 'MiSans', fontFamilyFallback: FontManager.fallbackFontFamilies),
                            bodySmall: TextStyle(color: Colors.white70, fontFamily: 'MiSans', fontFamilyFallback: FontManager.fallbackFontFamilies),
                            titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontFamily: 'MiSans', fontFamilyFallback: FontManager.fallbackFontFamilies),
                            titleSmall: TextStyle(color: Colors.white, fontFamily: 'MiSans', fontFamilyFallback: FontManager.fallbackFontFamilies),
                          ),
                        ),
                        child: SafeArea(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // 顶部导航与 Tab 切换头
                              _buildHeader(primaryColor),

                              const Divider(
                                color: Color(0x22FFFFFF),
                                height: 1,
                                thickness: 0.5,
                              ),

                              // 内容主体
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: _buildTabBody(primaryColor),
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
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(Color primaryColor) {
    const tabs = [
      (tab: PlayerSidePanelTab.episodes, label: '选集'),
      (tab: PlayerSidePanelTab.sources, label: '换源'),
      (tab: PlayerSidePanelTab.danmaku, label: '弹幕'),
    ];
    final activeIndex = PlayerSidePanelTab.values.indexOf(_activeTab).clamp(0, 2);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          // 3 个 Tab 切换胶囊（带底层物理弹性平滑滑动药丸）
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 0.5,
                ),
              ),
              child: Stack(
                children: [
                  // 丝滑平移的活动药丸指示器（带 easeOutBack 微过冲弹性）
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeOutBack,
                    alignment: AlignmentDirectional(
                      -1.0 + activeIndex * 1.0,
                      0.0,
                    ),
                    child: FractionallySizedBox(
                      widthFactor: 1 / 3,
                      child: Container(
                        height: 27,
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(13.5),
                          boxShadow: [
                            BoxShadow(
                              color: primaryColor.withValues(alpha: 0.45),
                              blurRadius: 6,
                              offset: const Offset(0, 1.5),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // 3 个 Tab 交互标签项
                  Row(
                    children: tabs.map((t) {
                      final isSelected = _activeTab == t.tab;
                      return Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (_activeTab != t.tab) {
                              HapticFeedback.selectionClick();
                              setState(() => _activeTab = t.tab);
                            }
                          },
                          child: Container(
                            alignment: Alignment.center,
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 180),
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.65),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                                fontFamily: 'MiSans',
                                fontFamilyFallback: FontManager.fallbackFontFamilies,
                              ),
                              child: Text(t.label),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 关闭按钮
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 18,
                ),
                onPressed: widget.onClose,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBody(Color primaryColor) {
    switch (_activeTab) {
      case PlayerSidePanelTab.episodes:
        return _buildEpisodesTab();
      case PlayerSidePanelTab.sources:
        return _buildSourcesTab();
      case PlayerSidePanelTab.danmaku:
        return _buildDanmakuTab(primaryColor);
    }
  }

  // -------------------------
  // 1. 选集 Tab
  // -------------------------
  Widget _buildEpisodesTab() {
    final theme = Theme.of(context);
    if (widget.isLoadingEpisodes) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.2),
            ),
            SizedBox(height: 12),
            Text(
              '正在加载分集列表...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.episodeCount <= 0) {
      final isError = widget.resolveError != null && widget.resolveError!.isNotEmpty;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isError ? Icons.error_outline_rounded : Icons.video_library_outlined,
              size: 42,
              color: isError ? Colors.amber : Colors.white54,
            ),
            const SizedBox(height: 12),
            Text(
              isError ? '分集解析失败' : '暂无可用分集',
              style: TextStyle(
                fontFamily: theme.textTheme.titleMedium?.fontFamily,
                fontFamilyFallback: theme.textTheme.titleMedium?.fontFamilyFallback,
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (isError) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: Text(
                  widget.resolveError!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: theme.textTheme.bodySmall?.fontFamily,
                    fontFamilyFallback: theme.textTheme.bodySmall?.fontFamilyFallback,
                    color: Colors.redAccent.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isError && widget.onRefreshEpisodes != null) ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('重试'),
                    onPressed: widget.onRefreshEpisodes,
                  ),
                  const SizedBox(width: 8),
                ],
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                  label: const Text('切换其他视频源'),
                  onPressed: () =>
                      setState(() => _activeTab = PlayerSidePanelTab.sources),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return ListenableBuilder(
      listenable: WatchedEpisodesService.instance,
      builder: (context, _) {
        final watched = WatchedEpisodesService.instance.getWatchedEpisodes(widget.bangumiId);
        return EpisodePickerSection(
          key: const ValueKey('side_panel_episodes'),
          episodeCount: widget.slots != null && widget.slots!.isNotEmpty
              ? widget.slots!.length
              : widget.episodeCount,
          currentEpisode: widget.currentEpisode,
          roads: widget.roads,
          activeRoadIndex: widget.activeRoadIndex,
          playingRoadIndex: widget.playingRoadIndex,
          episodeTitles: widget.episodeTitles,
          slots: widget.slots,
          watchedEpisodes: watched,
          isLoading: widget.isLoadingEpisodes,
          onRoadSelected: widget.onRoadSelected,
          onRefresh: widget.onRefreshEpisodes,
          onSelectEpisode: (ep) {
            widget.onSelectEpisode(ep);
          },
          onSelectSlot: widget.onSelectSlot,
        );
      },
    );
  }

  // -------------------------
  // 2. 换源 Tab
  // -------------------------
  Widget _buildSourcesTab() {
    return VideoSourceView(
      key: const ValueKey('side_panel_sources'),
      sources: widget.sources,
      selectedSourceId: widget.selectedSourceId,
      aggregator: widget.aggregator,
      onSourceSelected: (src) {
        widget.onSourceSelected(src);
        setState(() => _activeTab = PlayerSidePanelTab.episodes);
      },
      onSelectHit: (src, hit, [cachedRoads = const []]) {
        if (widget.onSelectHit != null) {
          widget.onSelectHit!(src, hit, cachedRoads);
        } else {
          widget.onSourceSelected(src);
        }
        setState(() => _activeTab = PlayerSidePanelTab.episodes);
      },
    );
  }

  // -------------------------
  // 3. 弹幕高级设置 Tab
  // -------------------------
  Widget _buildDanmakuTab(Color primaryColor) {
    final danmaku = widget.danmakuController;
    if (danmaku == null) {
      return const Center(
        child: Text(
          '当前播放器未挂载弹幕组件',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 13,
            fontFamily: 'MiSans',
            fontFamilyFallback: FontManager.fallbackFontFamilies,
          ),
        ),
      );
    }

    return ListenableBuilder(
      listenable: danmaku,
      builder: (context, _) {
        final cfg = danmaku.settings;

        return ListView(
          key: const ValueKey('side_panel_danmaku'),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 画幅与超分辨率 (Anime4K)
            if (widget.controller != null) ...[
              _buildSectionHeader('画面画幅比例'),
              ValueListenableBuilder<PlaybackCoreState>(
                valueListenable: widget.controller!.core,
                builder: (context, coreState, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            _buildFitChip(label: '默认 (16:9)', fit: BoxFit.contain, current: coreState.videoFit),
                            _buildFitChip(label: '铺满裁剪', fit: BoxFit.cover, current: coreState.videoFit),
                            _buildFitChip(label: '全屏拉伸', fit: BoxFit.fill, current: coreState.videoFit),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildSectionHeader('动漫超分辨率 (Anime4K)'),
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            _buildSrChip(label: '关闭', mode: SuperResolutionMode.off, current: coreState.superResolution),
                            _buildSrChip(label: '效率档', mode: SuperResolutionMode.efficiency, current: coreState.superResolution),
                            _buildSrChip(label: '质量档', mode: SuperResolutionMode.quality, current: coreState.superResolution),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
            ],

            _buildSectionHeader('弹幕基础开关'),

            // 弹幕总开关
            _buildSwitchTile(
              title: '显示弹幕',
              subtitle: '开启或关闭屏幕所有弹幕渲染',
              value: cfg.enabled,
              primaryColor: primaryColor,
              onChanged: (val) {
                danmaku.updateSettings(cfg.copyWith(enabled: val));
              },
            ),

            // 精简模式（智能防挡脸防刷屏）
            _buildSwitchTile(
              title: '精简模式',
              subtitle: '自动抑制短时间内重复刷屏与重叠弹幕',
              value: cfg.simplify,
              primaryColor: primaryColor,
              onChanged: (val) {
                danmaku.updateSettings(cfg.copyWith(simplify: val));
              },
            ),

            // 彩色弹幕统一转白
            _buildSwitchTile(
              title: '屏蔽彩色弹幕',
              subtitle: '将所有发光或彩色弹幕统一渲染为白色',
              value: cfg.hideColor,
              primaryColor: primaryColor,
              onChanged: (val) {
                danmaku.updateSettings(cfg.copyWith(hideColor: val));
              },
            ),

            const SizedBox(height: 12),
            _buildSectionHeader('显示范围与区域'),

            // 显示区域分段选择
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _buildAreaChip(label: '半屏 (50%)', areaVal: 0.5, current: cfg.area, danmaku: danmaku),
                  _buildAreaChip(label: '3/4屏', areaVal: 0.75, current: cfg.area, danmaku: danmaku),
                  _buildAreaChip(label: '全屏', areaVal: 1.0, current: cfg.area, danmaku: danmaku),
                ],
              ),
            ),

            const SizedBox(height: 12),
            _buildSectionHeader('视觉调节'),

            // 不透明度
            _buildSliderSetting(
              title: '不透明度',
              displayValue: '${(cfg.opacity * 100).round()}%',
              value: cfg.opacity,
              min: 0.2,
              max: 1.0,
              primaryColor: primaryColor,
              onChanged: (val) {
                danmaku.updateSettings(cfg.copyWith(opacity: val));
              },
            ),

            // 字号缩放
            _buildSliderSetting(
              title: '弹幕字号',
              displayValue: '${(cfg.fontSizeScale * 100).round()}%',
              value: cfg.fontSizeScale,
              min: 0.7,
              max: 1.4,
              primaryColor: primaryColor,
              onChanged: (val) {
                danmaku.updateSettings(cfg.copyWith(fontSizeScale: val));
              },
            ),

            // 飞行速度
            _buildSliderSetting(
              title: '飞行速度',
              displayValue: '${cfg.speed.toStringAsFixed(1)}x',
              value: cfg.speed.clamp(0.5, 2.0),
              min: 0.5,
              max: 2.0,
              primaryColor: primaryColor,
              onChanged: (val) {
                danmaku.updateSettings(cfg.copyWith(speed: val));
              },
            ),

            const SizedBox(height: 12),
            _buildSectionHeader('弹幕类型屏蔽'),

            // 屏蔽类型
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildFilterChip(
                  label: '滚动弹幕',
                  isFiltered: cfg.hideScroll,
                  primaryColor: primaryColor,
                  onSelected: (val) {
                    danmaku.updateSettings(cfg.copyWith(hideScroll: val));
                  },
                ),
                _buildFilterChip(
                  label: '顶部固定',
                  isFiltered: cfg.hideTop,
                  primaryColor: primaryColor,
                  onSelected: (val) {
                    danmaku.updateSettings(cfg.copyWith(hideTop: val));
                  },
                ),
                _buildFilterChip(
                  label: '底部固定',
                  isFiltered: cfg.hideBottom,
                  primaryColor: primaryColor,
                  onSelected: (val) {
                    danmaku.updateSettings(cfg.copyWith(hideBottom: val));
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.2,
          fontFamily: 'MiSans',
          fontFamilyFallback: FontManager.fallbackFontFamilies,
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required Color primaryColor,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'MiSans',
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontFamily: 'MiSans',
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: primaryColor,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildSliderSetting({
    required String title,
    required String displayValue,
    required double value,
    required double min,
    required double max,
    required Color primaryColor,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'MiSans',
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                ),
              ),
              Text(
                displayValue,
                style: TextStyle(
                  color: primaryColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontFamily: 'MiSans',
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3.5,
              activeTrackColor: primaryColor,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAreaChip({
    required String label,
    required double areaVal,
    required double current,
    required DanmakuController danmaku,
  }) {
    final isSelected = (current - areaVal).abs() < 0.05;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          danmaku.updateSettings(danmaku.settings.copyWith(area: areaVal));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontFamily: 'MiSans',
              fontFamilyFallback: FontManager.fallbackFontFamilies,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isFiltered,
    required Color primaryColor,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isFiltered ? Colors.white : Colors.white70,
          fontWeight: isFiltered ? FontWeight.bold : FontWeight.normal,
          fontFamily: 'MiSans',
          fontFamilyFallback: FontManager.fallbackFontFamilies,
        ),
      ),
      selected: isFiltered,
      labelStyle: TextStyle(
        fontSize: 12,
        color: isFiltered ? Colors.white : Colors.white70,
        fontWeight: isFiltered ? FontWeight.bold : FontWeight.normal,
        fontFamily: 'MiSans',
        fontFamilyFallback: FontManager.fallbackFontFamilies,
      ),
      backgroundColor: Colors.white.withValues(alpha: 0.1),
      selectedColor: primaryColor.withValues(alpha: 0.65),
      checkmarkColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isFiltered ? primaryColor : Colors.white.withValues(alpha: 0.15),
          width: 0.5,
        ),
      ),
      onSelected: onSelected,
    );
  }

  Widget _buildFitChip({
    required String label,
    required BoxFit fit,
    required BoxFit current,
  }) {
    final isSelected = current == fit;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.controller?.setVideoFit(fit),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontFamily: 'MiSans',
              fontFamilyFallback: FontManager.fallbackFontFamilies,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSrChip({
    required String label,
    required SuperResolutionMode mode,
    required SuperResolutionMode current,
  }) {
    final isSelected = current == mode;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final c = widget.controller;
          if (c == null) return;
          SuperResolutionDialogHelper.handleModeSelection(
            context: context,
            controller: c,
            mode: mode,
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withValues(alpha: 0.22) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.white60,
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontFamily: 'MiSans',
              fontFamilyFallback: FontManager.fallbackFontFamilies,
            ),
          ),
        ),
      ),
    );
  }
}
