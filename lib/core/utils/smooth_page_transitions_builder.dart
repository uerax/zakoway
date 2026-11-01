import 'package:flutter/cupertino.dart';

/// 移动端高性能轻快转场（针对 120Hz 高刷屏与手势交互专项调优）：
///
/// 特殊处理说明：
/// 1. 【时长收紧（280ms 黄金窗口）】：Flutter 官方内置的 [CupertinoPageTransitionsBuilder]
///    硬编码了 500ms（前 100ms 冲刺、后 400ms 龟速爬行）。在 120Hz 手机上，单次点击后手指脱手，
///    手机系统（尤其是 LTPO 屏幕）会在脱手后 100~150ms 内将物理刷新率迅速下调到 60Hz 甚至更低省电，
///    导致官方转场的后 300ms 完全是在 60Hz 慢速蠕动，产生强烈的卡顿与拖影感。
///    收紧至 280ms（返回 240ms）后，动画在系统脱手降频前干净利落定格，手感媲美大厂原生 App。
/// 2. 【图层隔离（RepaintBoundary）】：在转场 [child] 外层自动注入 [RepaintBoundary]，
///    将新页面作为独立的 GPU 图层进行平移矩阵变换，避免在 120Hz 极严苛的 8.33ms 帧预算下，
///    转场的每一帧都深层遍历两整页组件树重新 Paint。
/// 3. 【完整保留原生手势】：底层完全继承并委托给 [CupertinoRouteTransitionMixin.buildPageTransitions]，
///    100% 完整保留 iOS/Android 边缘右滑返回手势（PopGesture）与视差阴影过渡。
class SmoothCupertinoPageTransitionsBuilder extends PageTransitionsBuilder {
  const SmoothCupertinoPageTransitionsBuilder({
    this.transitionDuration = const Duration(milliseconds: 280),
    this.reverseTransitionDuration = const Duration(milliseconds: 240),
  });

  @override
  final Duration transitionDuration;

  @override
  final Duration reverseTransitionDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      CupertinoPageTransition.delegatedTransition;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return CupertinoRouteTransitionMixin.buildPageTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      RepaintBoundary(child: child),
    );
  }
}
