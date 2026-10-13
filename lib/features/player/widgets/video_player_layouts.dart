import 'package:flutter/material.dart';
import 'desktop/desktop_video_player_layout.dart';
import 'mobile/mobile_video_player_layout.dart';

export 'desktop/desktop_video_player_layout.dart';
export 'mobile/mobile_video_player_layout.dart';

/// 全屏横屏布局（全宽播放器 + 浮层侧边抽屉面板）
class VideoPlayerFullscreenLayout extends StatelessWidget {
  const VideoPlayerFullscreenLayout({
    super.key,
    required this.playerWidget,
    required this.sidePanelWidget,
  });

  final Widget playerWidget;
  final Widget sidePanelWidget;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: playerWidget,
        ),
        sidePanelWidget,
      ],
    );
  }
}

/// 兼容类型别名（无缝过渡）
typedef VideoPlayerDesktopLayout = DesktopVideoPlayerLayout;
typedef VideoPlayerMobileLayout = MobileVideoPlayerLayout;
