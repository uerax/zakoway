import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:zakoway/core/services/bangumi_oped_service.dart';
import 'package:zakoway/core/utils/responsive.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';
import 'desktop/desktop_player_controls.dart';
import 'mobile/mobile_player_controls.dart';
import 'player_side_panel.dart';
import 'video_player_placeholder.dart';
import 'video_surface.dart';

/// 播放器带控制层、解析错误浮层与 HUD 的完整视频视口组件
class VideoPlayerSurfaceWithControls extends StatelessWidget {
  const VideoPlayerSurfaceWithControls({
    super.key,
    required this.controller,
    required this.title,
    this.danmakuController,
    this.danmakuCoordinator,
    this.isFullscreen = false,
    this.isAppFullscreen = false,
    this.isTrueFullscreen = false,
    this.isDesktop,
    required this.onToggleFullscreen,
    this.onToggleAppFullscreen,
    this.onToggleTrueFullscreen,
    required this.onBackPressed,
    this.onOpenEpisodePicker,
    this.onOpenSidePanel,
    this.onNextEpisode,
    this.onPrevEpisode,
    this.opedSegment,
    this.hudToast,
    this.hudToastListenable,
    this.resolveError,
    required this.primaryColor,
    required this.onRetryResolve,
    required this.onSwitchSource,
    this.autoPlayNextNotifier,
    this.bangumiId,
    this.canonicalEpisode,
    this.officialDurationSeconds,
  });

  final ZakowayPlaybackController controller;
  final String title;
  final DanmakuController? danmakuController;
  final DanmakuSessionCoordinator? danmakuCoordinator;
  final bool isFullscreen;
  final bool isAppFullscreen;
  final bool isTrueFullscreen;
  final bool? isDesktop;
  final VoidCallback onToggleFullscreen;
  final VoidCallback? onToggleAppFullscreen;
  final VoidCallback? onToggleTrueFullscreen;
  final VoidCallback onBackPressed;
  final VoidCallback? onOpenEpisodePicker;
  final ValueChanged<PlayerSidePanelTab>? onOpenSidePanel;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onPrevEpisode;
  final EpisodeOpedSegment? opedSegment;
  final String? hudToast;
  final ValueListenable<String?>? hudToastListenable;
  final String? resolveError;
  final Color primaryColor;
  final VoidCallback onRetryResolve;
  final VoidCallback onSwitchSource;
  final ValueNotifier<bool>? autoPlayNextNotifier;
  final int? bangumiId;
  final int? canonicalEpisode;
  final int? officialDurationSeconds;

  @override
  Widget build(BuildContext context) {
    final useDesktopControls = isDesktop ?? AppPlatform.isDesktop;

    final Widget controlsWidget = useDesktopControls
        ? DesktopPlayerControls(
            controller: controller,
            title: title,
            danmakuController: danmakuController,
            danmakuCoordinator: danmakuCoordinator,
            isFullscreen: isFullscreen,
            isAppFullscreen: isAppFullscreen,
            isTrueFullscreen: isTrueFullscreen,
            onToggleFullscreen: onToggleFullscreen,
            onToggleAppFullscreen: onToggleAppFullscreen,
            onToggleTrueFullscreen: onToggleTrueFullscreen,
            onBackPressed: onBackPressed,
            onOpenEpisodePicker: onOpenEpisodePicker,
            onOpenSidePanel: onOpenSidePanel,
            onNextEpisode: onNextEpisode,
            onPrevEpisode: onPrevEpisode,
            opedSegment: opedSegment,
            autoPlayNextNotifier: autoPlayNextNotifier,
            bangumiId: bangumiId,
            canonicalEpisode: canonicalEpisode,
            officialDurationSeconds: officialDurationSeconds,
          )
        : MobilePlayerControls(
            controller: controller,
            title: title,
            danmakuController: danmakuController,
            danmakuCoordinator: danmakuCoordinator,
            isFullscreen: isFullscreen,
            isAppFullscreen: isAppFullscreen,
            isTrueFullscreen: isTrueFullscreen,
            onToggleFullscreen: onToggleFullscreen,
            onToggleAppFullscreen: onToggleAppFullscreen,
            onToggleTrueFullscreen: onToggleTrueFullscreen,
            onBackPressed: onBackPressed,
            onOpenEpisodePicker: onOpenEpisodePicker,
            onOpenSidePanel: onOpenSidePanel,
            onNextEpisode: onNextEpisode,
            onPrevEpisode: onPrevEpisode,
            opedSegment: opedSegment,
            autoPlayNextNotifier: autoPlayNextNotifier,
            bangumiId: bangumiId,
            canonicalEpisode: canonicalEpisode,
            officialDurationSeconds: officialDurationSeconds,
          );

    return Stack(
      children: [
        VideoSurface(
          controller: controller,
          danmakuController: danmakuController,
          overlay: controlsWidget,
        ),

        // HUD Toast 悬浮提示胶囊 (优先使用局部 ValueListenable 驱动，0 全页 Rebuild)
        if (hudToastListenable != null)
          ValueListenableBuilder<String?>(
            valueListenable: hudToastListenable!,
            builder: (context, msg, _) {
              if (msg == null || msg.isEmpty) return const SizedBox.shrink();
              return VideoPlayerHudToast(message: msg);
            },
          )
        else if (hudToast != null)
          VideoPlayerHudToast(message: hudToast!),

        // iOS 风格解析失败提示磨砂卡片
        if (resolveError != null)
          VideoPlayerResolveErrorCard(
            errorText: resolveError!,
            primaryColor: primaryColor,
            onRetry: onRetryResolve,
            onSwitchSource: onSwitchSource,
          ),
      ],
    );
  }
}
