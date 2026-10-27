import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
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
                      style: appTextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
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
    this.showBack = true,
    this.showTitle = true,
  });

  final String title;
  final bool isFullscreen;
  final bool isDesktopInline;
  final VoidCallback? onBackPressed;
  final VoidCallback? onOpenEpisodePicker;
  final ValueChanged<PlayerSidePanelTab>? onOpenSidePanel;
  final VoidCallback? onScreenshot;
  final DanmakuController? danmakuController;
  final bool showBack;
  final bool showTitle;

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

            final hasBack = showBack && onBackPressed != null;
            final hasTitle = showTitle && title.isNotEmpty;
            final hasRightButtons = onOpenEpisodePicker != null ||
                onOpenSidePanel != null ||
                onScreenshot != null;

            // 若既无返回键、无标题、亦无右侧操作，直接收缩不占位
            if (!hasBack && !hasTitle && !hasRightButtons) {
              return const SizedBox.shrink();
            }

            final isDesktop = !kIsWeb &&
                (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

            final Widget titleWidget = hasTitle
                ? Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appTextStyle(
                      color: Colors.white,
                      fontSize: 14.0,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      shadows: const [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 6,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.expand();

            // 特殊处理说明：
            // 桌面端无边框窗口全屏模式下，系统原生标题栏已被隐藏；
            // 将播放器顶部控制栏的标题与留白区域注入 DragToMoveArea，支持鼠标直接拖拽移动窗口与双击最大化/还原。
            final Widget middleSection = Expanded(
              child: isDesktop
                  ? DragToMoveArea(
                      child: Container(
                        height: 32,
                        color: Colors.transparent,
                        alignment: Alignment.centerLeft,
                        child: titleWidget,
                      ),
                    )
                  : (hasTitle ? titleWidget : const Spacer()),
            );

            Widget topBarContent = Row(
              children: [
                if (hasBack) ...[
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
                middleSection,
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

            if (isDesktop) {
              topBarContent = Stack(
                children: [
                  const Positioned.fill(
                    child: DragToMoveArea(
                      child: SizedBox.expand(),
                    ),
                  ),
                  topBarContent,
                ],
              );
            }

            return topBarContent;
          },
        ),
      ),
    );
  }
}
