import 'package:flutter/material.dart';

/// 通用 UI 组件保活包装容器：
///
/// 特殊处理说明：
/// 1. 基于 Flutter 原生 [AutomaticKeepAliveClientMixin] 实现，向父级 [SliverWithKeepAliveWidget]
///    （如 [TabBarView]、[PageView]、懒加载视口）派发 [KeepAliveNotification]；
/// 2. 确保子组件切出可视视口时不被底层销毁（不触发 dispose 与 Element 卸载），
///    100% 保持内部滚动位置 (Scroll Offset)、输入状态与已有渲染布局树；
/// 3. 彻底消除多 Tab 切换导致的反复网络重新拉取（如评论区重刷）与视觉跳动。
class KeepAliveWrapper extends StatefulWidget {
  final Widget child;
  final bool keepAlive;

  const KeepAliveWrapper({
    super.key,
    required this.child,
    this.keepAlive = true,
  });

  @override
  State<KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keepAlive;

  @override
  void didUpdateWidget(covariant KeepAliveWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keepAlive != widget.keepAlive) {
      updateKeepAlive();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
