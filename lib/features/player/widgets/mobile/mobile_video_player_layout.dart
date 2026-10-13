import 'package:flutter/material.dart';

/// 移动端/窄屏流式上下布局（上方 16:9 播放器，下方分段 Tab 栏）
class MobileVideoPlayerLayout extends StatelessWidget {
  const MobileVideoPlayerLayout({
    super.key,
    required this.playerWidget,
    required this.tabSection,
  });

  final Widget playerWidget;
  final Widget tabSection;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: playerWidget,
          ),
          Expanded(
            child: tabSection,
          ),
        ],
      ),
    );
  }
}
