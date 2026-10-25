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
            // 特殊处理说明：
            // 手机竖屏下 16:9 播放器位于屏幕上半部，不接触屏幕底部物理边缘。
            // 必须使用 removeBottom: true 剥离手机底部常驻手势横条或虚拟键的 safeArea，
            // 避免内部控制栏 (MobilePlayerBottomBar) 被误垫高产生下部大段空隙。
            child: MediaQuery.removePadding(
              context: context,
              removeBottom: true,
              child: playerWidget,
            ),
          ),
          Expanded(
            child: tabSection,
          ),
        ],
      ),
    );
  }
}
