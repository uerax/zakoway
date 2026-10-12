import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:zakoway/core/utils/font_manager.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';
import 'package:zakoway/features/player/widgets/player_side_panel.dart';

/// 顶部药丸微光按钮
class PlayerPillButton extends StatelessWidget {
  const PlayerPillButton({
    super.key,
    required this.icon,
    this.label,
    required this.onTap,
    this.iconOnly = false,
  });

  final IconData icon;
  final String? label;
  final VoidCallback onTap;
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final showText = !iconOnly && label != null && label!.isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          height: 28,
          padding: EdgeInsets.symmetric(horizontal: showText ? 7.5 : 7.0),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.16),
              width: 0.5,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: Colors.white,
                    size: 14,
                  ),
                  if (showText) ...[
                    const SizedBox(width: 3.5),
                    Text(
                      label!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'MiSans',
                        fontFamilyFallback: FontManager.fallbackFontFamilies,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 播放器顶部导航栏（包含返回键、标题、选集、换源、弹幕侧栏、截图按钮）
class PlayerControlsTopBar extends StatelessWidget {
  const PlayerControlsTopBar({
    super.key,
    required this.title,
    this.isFullscreen = false,
    this.isDesktopInline = false,
    this.onBackPressed,
    this.onOpenEpisodePicker,
    this.onOpenSidePanel,
    this.onScreenshot,
    this.danmakuController,
  });

  final String title;
  final bool isFullscreen;
  final bool isDesktopInline;
  final VoidCallback? onBackPressed;
  final VoidCallback? onOpenEpisodePicker;
  final ValueChanged<PlayerSidePanelTab>? onOpenSidePanel;
  final VoidCallback? onScreenshot;
  final DanmakuController? danmakuController;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompact = constraints.maxWidth < 720;
            const btnSpacing = 4.0;

            return Row(
              children: [
                if (onBackPressed != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                            width: 0.5,
                          ),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 15,
                          ),
                          onPressed: onBackPressed,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14.0,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      fontFamily: 'MiSans',
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
                if (onOpenEpisodePicker != null || onOpenSidePanel != null) ...[
                  const SizedBox(width: 6),
                  PlayerPillButton(
                    icon: Icons.video_library_rounded,
                    label: '选集',
                    onTap: () {
                      if (onOpenSidePanel != null) {
                        onOpenSidePanel!(PlayerSidePanelTab.episodes);
                      } else {
                        onOpenEpisodePicker?.call();
                      }
                    },
                  ),
                  if (isFullscreen && onOpenSidePanel != null) ...[
                    const SizedBox(width: btnSpacing),
                    PlayerPillButton(
                      icon: Icons.swap_horiz_rounded,
                      label: '换源',
                      onTap: () {
                        onOpenSidePanel!(PlayerSidePanelTab.sources);
                      },
                    ),
                    if (danmakuController != null) ...[
                      const SizedBox(width: btnSpacing),
                      PlayerPillButton(
                        icon: Icons.tune_rounded,
                        label: '弹幕',
                        onTap: () {
                          onOpenSidePanel!(PlayerSidePanelTab.danmaku);
                        },
                      ),
                    ],
                  ],
                  if (onScreenshot != null) ...[
                    const SizedBox(width: btnSpacing),
                    PlayerPillButton(
                      icon: Icons.camera_alt_outlined,
                      label: '截图',
                      iconOnly: isCompact,
                      onTap: onScreenshot!,
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
