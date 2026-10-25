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
            // 手机竖屏下 16:9 播放器位于屏幕上半部，外层 SafeArea(top: true) 已避让顶部状态栏，
            // 播放器本身既不接触物理顶边也不接触物理底边。
            // 必须使用 removeTop: true 与 removeBottom: true 彻底剥离系统 safeArea，
            // 避免内部顶部返回/标题栏与底部控制栏产生错位或异常悬空。
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
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
