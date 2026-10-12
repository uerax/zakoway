import 'package:flutter/material.dart';
import 'package:zakoway/core/services/bangumi_oped_service.dart';
import 'package:zakoway/core/utils/font_manager.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/controller/playback_state.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';
import 'package:zakoway/features/player/services/player_preferences_service.dart';
import 'package:zakoway/features/player/widgets/player_progress_bar.dart';
import 'danmaku_settings_icon.dart';

/// 底部控制栏响应式尺寸度量规范
class _BottomBarMetrics {
  const _BottomBarMetrics({
    required this.buttonSize,
    required this.iconSize,
    required this.playIconSize,
    required this.danmakuToggleSize,
    required this.timeFontSize,
    required this.speedFontSize,
    required this.speedPadding,
    required this.spacing,
    required this.leftSpacing,
    required this.bottomPadding,
    required this.horizontalPadding,
  });

  final double buttonSize;
  final double iconSize;
  final double playIconSize;
  final double danmakuToggleSize;
  final double timeFontSize;
  final double speedFontSize;
  final EdgeInsets speedPadding;
  final double spacing;
  final double leftSpacing;
  final double bottomPadding;
  final double horizontalPadding;

  factory _BottomBarMetrics.resolve({
    required PlayerControlBarScale scalePreference,
    required double totalWidth,
    required TargetPlatform platform,
  }) {
    // 宽屏/平板/桌面端（宽度 >= 600dp 时具备充裕空间容纳大号舒适控制条）
    final isWideOrTablet = totalWidth >= 600;

    final effectiveScale = scalePreference != PlayerControlBarScale.auto
        ? scalePreference
        : (isWideOrTablet
            ? PlayerControlBarScale.standard
            : PlayerControlBarScale.compact);

    switch (effectiveScale) {
      case PlayerControlBarScale.compact:
        final isNarrow = totalWidth < 380;
        return _BottomBarMetrics(
          buttonSize: isNarrow ? 21.0 : 26.0,
          iconSize: isNarrow ? 14.5 : 16.5,
          playIconSize: isNarrow ? 15.5 : 18.5,
          danmakuToggleSize: isNarrow ? 15.0 : 18.0,
          timeFontSize: isNarrow ? 9.5 : 11.0,
          speedFontSize: isNarrow ? 10.0 : 11.0,
          speedPadding: EdgeInsets.symmetric(horizontal: isNarrow ? 2.5 : 4.0, vertical: 2.0),
          spacing: isNarrow ? 1.5 : 3.0,
          leftSpacing: isNarrow ? 4.0 : 6.0,
          bottomPadding: 6.0,
          horizontalPadding: isNarrow ? 3.0 : (totalWidth < 400 ? 6.0 : 12.0),
        );
      case PlayerControlBarScale.standard:
        return _BottomBarMetrics(
          buttonSize: 32.0,
          iconSize: 20.0,
          playIconSize: 22.0,
          danmakuToggleSize: 22.0,
          timeFontSize: 12.0,
          speedFontSize: 12.0,
          speedPadding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
          spacing: 6.0,
          leftSpacing: 8.0,
          bottomPadding: 10.0,
          horizontalPadding: totalWidth < 600 ? 10.0 : 16.0,
        );
      case PlayerControlBarScale.large:
        return _BottomBarMetrics(
          buttonSize: 38.0,
          iconSize: 24.0,
          playIconSize: 26.0,
          danmakuToggleSize: 26.0,
          timeFontSize: 13.5,
          speedFontSize: 13.5,
          speedPadding: const EdgeInsets.symmetric(horizontal: 7.0, vertical: 4.0),
          spacing: 8.0,
          leftSpacing: 10.0,
          bottomPadding: 12.0,
          horizontalPadding: totalWidth < 600 ? 12.0 : 20.0,
        );
      case PlayerControlBarScale.auto:
        return const _BottomBarMetrics(
          buttonSize: 32.0,
          iconSize: 20.0,
          playIconSize: 22.0,
          danmakuToggleSize: 22.0,
          timeFontSize: 12.0,
          speedFontSize: 12.0,
          speedPadding: EdgeInsets.symmetric(horizontal: 6.0, vertical: 3.0),
          spacing: 6.0,
          leftSpacing: 8.0,
          bottomPadding: 10.0,
          horizontalPadding: 16.0,
        );
    }
  }
}

/// 播放器底部控制通栏（包含全宽流体进度条与主流对齐的经典通栏控制行）
class PlayerControlsBottomBar extends StatelessWidget {
  const PlayerControlsBottomBar({
    super.key,
    required this.controller,
    required this.primaryColor,
    this.danmakuController,
    this.opedSegment,
    this.isFullscreen = false,
    this.isAppFullscreen = false,
    this.isTrueFullscreen = false,
    this.onToggleFullscreen,
    this.onToggleAppFullscreen,
    this.onToggleTrueFullscreen,
    this.onSeekingSliderChanged,
    required this.onUserInteraction,
    this.showSpeedPopup = false,
    required this.onToggleSpeedPopup,
    this.showVolumeSlider = false,
    required this.onToggleVolumeSlider,
    this.isSettingsPanelActive = false,
    this.isDanmakuPanelActive = false,
    required this.onOpenSettingsPanel,
    required this.onOpenDanmakuPanel,
    this.speedButtonKey,
    this.volumeButtonKey,
  });

  final ZakowayPlaybackController controller;
  final Color primaryColor;
  final DanmakuController? danmakuController;
  final EpisodeOpedSegment? opedSegment;
  final bool isFullscreen;
  final bool isAppFullscreen;
  final bool isTrueFullscreen;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onToggleAppFullscreen;
  final VoidCallback? onToggleTrueFullscreen;
  final ValueChanged<bool>? onSeekingSliderChanged;
  final VoidCallback onUserInteraction;

  final bool showSpeedPopup;
  final VoidCallback onToggleSpeedPopup;
  final bool showVolumeSlider;
  final VoidCallback onToggleVolumeSlider;
  final bool isSettingsPanelActive;
  final bool isDanmakuPanelActive;
  final VoidCallback onOpenSettingsPanel;
  final VoidCallback onOpenDanmakuPanel;
  final GlobalKey? speedButtonKey;
  final GlobalKey? volumeButtonKey;

  static String _formatDuration(Duration duration, {bool showHours = false}) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    if (showHours || hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildBarButton({
    required Widget icon,
    required VoidCallback? onTap,
    required double size,
    Key? key,
    String? tooltip,
  }) {
    final button = Material(
      key: key,
      color: Colors.transparent,
      child: InkResponse(
        radius: size * 0.58,
        highlightShape: BoxShape.circle,
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: icon),
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PlayerPreferencesService.instance,
      builder: (context, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final metrics = _BottomBarMetrics.resolve(
              scalePreference: PlayerPreferencesService.instance.controlBarScale,
              totalWidth: totalWidth,
              platform: Theme.of(context).platform,
            );

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  metrics.horizontalPadding,
                  0,
                  metrics.horizontalPadding,
                  metrics.bottomPadding,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. 复合型全宽进度条（弹幕高能雾光波形 + OP/ED 彩色区间 + 缓冲条 + 悬停流体滑块）
                    ValueListenableBuilder<PlaybackTimelineState>(
                      valueListenable: controller.timeline,
                      builder: (context, timelineState, _) {
                        return PlayerProgressBar(
                          position: timelineState.displayPosition,
                          duration: timelineState.duration,
                          buffer: timelineState.buffer,
                          opedSegment: opedSegment,
                          danmakuItems: danmakuController?.items,
                          primaryColor: primaryColor,
                          onChangeStart: (dur) {
                            onSeekingSliderChanged?.call(true);
                            onUserInteraction();
                          },
                          onChanged: (dur) {
                            onUserInteraction();
                            controller.updateSeekPreview(dur);
                          },
                          onChangeEnd: (dur) {
                            onSeekingSliderChanged?.call(false);
                            onUserInteraction();
                            controller.seek(dur);
                          },
                        );
                      },
                    ),

                    const SizedBox(height: 2),

                    // 2. 现代经典通栏控制行：左侧 2 个元素（播放键 + 时间）靠左，其余全部靠右
                    Row(
                      children: [
                        // (1) 播放 / 暂停按钮（左1，与右侧按钮视觉重量完全一致的干净透明交互键）
                        ValueListenableBuilder<PlaybackCoreState>(
                          valueListenable: controller.core,
                          builder: (context, coreState, _) {
                            return _buildBarButton(
                              icon: Icon(
                                coreState.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                key: ValueKey(coreState.playing),
                                color: Colors.white,
                                size: metrics.playIconSize,
                              ),
                              size: metrics.buttonSize,
                              tooltip: coreState.playing ? '暂停 (Space)' : '播放 (Space)',
                              onTap: () {
                                onUserInteraction();
                                controller.togglePlay();
                              },
                            );
                          },
                        ),

                        SizedBox(width: metrics.leftSpacing),

                        // (2) 时间戳展示：当前时间(加粗纯白) / 总时长(柔和白)（左2）
                        ValueListenableBuilder<PlaybackTimelineState>(
                          valueListenable: controller.timeline,
                          builder: (context, timelineState, _) {
                            // 特殊处理说明：
                            // 在媒体总时长未就绪（duration <= 0）时，强制归零展示为 00:00 / 00:00，
                            // 杜绝任何极端弱网或断点起播阶段冒出如「04:26 / 00:00」的严重时间倒挂视觉错误；
                            // 时长就绪后，将当前显示进度严格钳制在 [0, effectiveDuration] 范围内。
                            final isDurationValid = timelineState.duration > Duration.zero;
                            final effectiveDuration = isDurationValid ? timelineState.duration : Duration.zero;
                            final effectivePosition = isDurationValid
                                ? (timelineState.displayPosition > effectiveDuration
                                    ? effectiveDuration
                                    : (timelineState.displayPosition < Duration.zero
                                        ? Duration.zero
                                        : timelineState.displayPosition))
                                : Duration.zero;

                            final hasHours = effectiveDuration.inHours > 0;
                            final pos = _formatDuration(effectivePosition, showHours: hasHours);
                            final total = _formatDuration(effectiveDuration, showHours: hasHours);
                            return Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: pos,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: metrics.timeFontSize,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.2,
                                      fontFamily: 'MiSans',
                                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                      shadows: const [
                                        Shadow(
                                          color: Colors.black54,
                                          blurRadius: 4,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' / $total',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.68),
                                      fontSize: metrics.timeFontSize,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: -0.2,
                                      fontFamily: 'MiSans',
                                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                      shadows: const [
                                        Shadow(
                                          color: Colors.black54,
                                          blurRadius: 4,
                                          offset: Offset(0, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        // 中间弹性空间，把后面全部元素顶到最右端
                        const Spacer(),

                        // (3) 猫耳弹幕开关 [开启带主题色微光小对勾，关闭带状态斜线]
                        if (danmakuController != null) ...[
                          ListenableBuilder(
                            listenable: danmakuController!,
                            builder: (context, _) {
                              final isEnabled =
                                  danmakuController!.settings.enabled;
                              return _buildBarButton(
                                icon: DanmakuToggleIcon(
                                  enabled: isEnabled,
                                  size: metrics.danmakuToggleSize,
                                  color: Colors.white,
                                  checkColor: primaryColor,
                                ),
                                size: metrics.buttonSize,
                                tooltip: isEnabled ? '关闭弹幕 (D)' : '开启弹幕 (D)',
                                onTap: () {
                                  onUserInteraction();
                                  final current = danmakuController!.settings;
                                  danmakuController!.updateSettings(
                                    current.copyWith(enabled: !isEnabled),
                                  );
                                },
                              );
                            },
                          ),
                          SizedBox(width: metrics.spacing),

                          // (4) 猫耳弹幕设置面板按钮 [带高精工六角倒角螺母]
                          _buildBarButton(
                            icon: DanmakuSettingsIcon(
                              size: metrics.danmakuToggleSize,
                              color: Colors.white,
                            ),
                            size: metrics.buttonSize,
                            tooltip: '弹幕设置',
                            onTap: onOpenDanmakuPanel,
                          ),
                          SizedBox(width: metrics.spacing),
                        ],

                        // (5) 倍速选择 [1x / 1.25x ... 圆润微光胶囊]
                        ValueListenableBuilder<PlaybackCoreState>(
                          valueListenable: controller.core,
                          builder: (context, coreState, _) {
                            final isSpeedHighlighted =
                                showSpeedPopup || coreState.playbackRate != 1.0;

                            return Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: onToggleSpeedPopup,
                                child: Container(
                                  key: speedButtonKey,
                                  padding: metrics.speedPadding,
                                  decoration: BoxDecoration(
                                    color: isSpeedHighlighted
                                        ? Colors.white.withValues(alpha: 0.20)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    coreState.playbackRate == 1.0
                                        ? '1x'
                                        : '${coreState.playbackRate}x',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: metrics.speedFontSize,
                                      fontWeight: isSpeedHighlighted
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      letterSpacing: -0.2,
                                      fontFamily: 'MiSans',
                                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                                      fontFeatures: const [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        SizedBox(width: metrics.spacing),

                        // (6) 播放设置按钮 [统一 Rounded 圆润风格]
                        _buildBarButton(
                          icon: Icon(
                            Icons.settings_rounded,
                            color: Colors.white,
                            size: metrics.iconSize,
                          ),
                          size: metrics.buttonSize,
                          tooltip: '播放设置',
                          onTap: onOpenSettingsPanel,
                        ),

                        SizedBox(width: metrics.spacing),

                        // (7) 竖式音量控制按钮 [🔊]
                        ValueListenableBuilder<PlaybackCoreState>(
                          valueListenable: controller.core,
                          builder: (context, coreState, _) {
                            final isMuted =
                                coreState.muted || coreState.volume <= 0.001;
                            return _buildBarButton(
                              key: volumeButtonKey,
                              icon: Icon(
                                isMuted
                                    ? Icons.volume_off_rounded
                                    : (coreState.volume > 0.5
                                        ? Icons.volume_up_rounded
                                        : Icons.volume_down_rounded),
                                color: isMuted ? Colors.white54 : Colors.white,
                                size: metrics.iconSize,
                              ),
                              size: metrics.buttonSize,
                              tooltip: isMuted ? '取消静音 (M)' : '音量调节',
                              onTap: onToggleVolumeSlider,
                            );
                          },
                        ),

                        // (8) 全屏切换按钮
                        if (onToggleAppFullscreen != null && onToggleTrueFullscreen != null) ...[
                          // 桌面端支持：应用全屏 + 真全屏 双模式
                          SizedBox(width: metrics.spacing),
                          _buildBarButton(
                            icon: Icon(
                              isAppFullscreen
                                  ? Icons.close_fullscreen_rounded
                                  : Icons.fit_screen_rounded,
                              color: isAppFullscreen ? primaryColor : Colors.white,
                              size: metrics.iconSize,
                            ),
                            size: metrics.buttonSize,
                            tooltip: isAppFullscreen ? '退出应用全屏' : '应用全屏',
                            onTap: () {
                              onUserInteraction();
                              onToggleAppFullscreen?.call();
                            },
                          ),
                          SizedBox(width: metrics.spacing),
                          _buildBarButton(
                            icon: Icon(
                              isTrueFullscreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              color: Colors.white,
                              size: metrics.iconSize,
                            ),
                            size: metrics.buttonSize,
                            tooltip: isTrueFullscreen ? '退出全屏 (F)' : '全屏 (F)',
                            onTap: () {
                              onUserInteraction();
                              onToggleTrueFullscreen?.call();
                            },
                          ),
                        ] else if (onToggleFullscreen != null) ...[
                          // 移动端单模式：原生全屏
                          SizedBox(width: metrics.spacing),
                          _buildBarButton(
                            icon: Icon(
                              isFullscreen
                                  ? Icons.fullscreen_exit_rounded
                                  : Icons.fullscreen_rounded,
                              color: Colors.white,
                              size: metrics.iconSize,
                            ),
                            size: metrics.buttonSize,
                            tooltip: isFullscreen ? '退出全屏' : '全屏',
                            onTap: () {
                              onUserInteraction();
                              onToggleFullscreen?.call();
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
