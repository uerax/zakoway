import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:zakoway/core/utils/instant_page_route.dart';
import 'package:zakoway/core/utils/responsive.dart';

/// 按平台与窗口宽度选择页面转场（用于全屏页，如播放页、搜索页）。
///
/// 设计原则：全程不透明，不做淡入淡出、不做缩放。
/// 带 Texture 视频或复杂毛玻璃图层的整页做透明度动画需要整页离屏合成，成本高，
/// 而且淡出时会透出首页，观感像两张图叠化。
///
/// 选择规则（在 push 时按当时的窗口宽度决定，分屏 / 旋转后下一次 push 生效）：
/// - iOS：系统默认转场（右侧滑入滑出，自带边缘滑动返回手势），手机与 iPad 一致；
/// - Android 手机（宽度 < 600）：系统默认转场（含系统返回手势）；
/// - Android 平板竖屏 / 折叠屏（600 ~ 839）：整屏右侧滑入，时长略短；
/// - Android 大屏横屏（>= 840）以及 Windows / macOS / Linux：直接切换，无动画。
///
/// 说明：不透明页面如果只位移一小段就结束，动画末尾页面会“啪”地消失，
/// 所以只有整屏位移的滑动才成立；大屏上整屏位移太长，直接切换更干净。
abstract final class AdaptivePageRoute {
  static Route<T> build<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    RouteSettings? settings,
  }) {
    final width = MediaQuery.sizeOf(context).width;

    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return MaterialPageRoute<T>(builder: builder, settings: settings);
      case TargetPlatform.android:
        if (width < AppBreakpoints.compact) {
          return MaterialPageRoute<T>(builder: builder, settings: settings);
        }
        if (width < AppBreakpoints.medium) {
          return _SlideFromRightRoute<T>(builder: builder, settings: settings);
        }
        return InstantPageRoute<T>(builder: builder, settings: settings);
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return InstantPageRoute<T>(builder: builder, settings: settings);
    }
  }
}

/// 平板用的整屏右侧滑入滑出（不透明，仅位移）。
class _SlideFromRightRoute<T> extends PageRouteBuilder<T> {
  _SlideFromRightRoute({
    required WidgetBuilder builder,
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionDuration: const Duration(milliseconds: 240),
          reverseTransitionDuration: const Duration(milliseconds: 200),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: animation.drive(
                Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
                    .chain(CurveTween(curve: Curves.easeInOutCubic)),
              ),
              child: child,
            );
          },
        );
}
