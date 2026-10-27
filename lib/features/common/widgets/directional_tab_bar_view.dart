import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../core/utils/responsive.dart';
import 'keep_alive_wrapper.dart';

/// 纵向手势优先的 TabBarView 包装组件：
///
/// 特殊处理说明：
/// 1. 痛点根因：Flutter 默认的 Gesture Arena 中，横向手势与纵向手势识别器阈值均采用默认的 kTouchSlop (18.0px)。
///    当 TabBarView 内嵌套纵向长列表（如番剧简介垂直流、评论列表、选集大网格、多视频源看板等）时，
///    用户在移动端带弧度上下滑动或 Windows 触控板/触屏滑动时，极易因轻微横向偏移抢先达到 18px 而误触发左右切页；
/// 2. 差异化阈值守卫机制：
///    - 在外层 TabBarView 作用域注入较高的横向 [horizontalTouchSlop]（默认 48.0px，为系统默认值的约 2.67 倍）；
///    - 关键步骤：在每个子页面 [children] 的外层，显式将 [touchSlop] 恢复回系统标准值（18.0px）；
///    - 使得纵向滚动识别器在 18.0px 必然先于横向识别器（48.0px）达到阈值并抢先胜出，手势竞技场立即剔除外层横向识别器，
///      彻底杜绝上下滑动长列表时左右误切；只有当水平滑动幅度大、偏角极平时才触发切页；
/// 3. 桌面端 (Windows/macOS/Linux) 体验保障：
///    - 桌面端键鼠与高精度触控板下，用户更依赖顶部 Tab 按钮精准点击切换。
///    - 当开启 [disableDesktopDrag]（默认 true）且检测到运行于桌面平台时，自动将物理滚动机制切换为
///      [NeverScrollableScrollPhysics]，彻底杜绝在桌面端使用鼠标滚轮或双指触控板纵向翻动网格时被误带跑；
///    - 在移动端（Android/iOS），保留平滑横向拖拽切页能力。
class DirectionalTabBarView extends StatelessWidget {
  final List<Widget> children;
  final TabController? controller;
  final ScrollPhysics? physics;
  final DragStartBehavior dragStartBehavior;
  final double viewportFraction;
  final Clip clipBehavior;

  /// 触屏端横向手势触发门槛（逻辑像素），默认 48.0。
  final double horizontalTouchSlop;

  /// 是否在桌面端（Windows/macOS/Linux）禁用手势拖拽滑动（仅通过点击 Tab 切换）
  final bool disableDesktopDrag;

  /// 是否对每个 Tab 子视图进行状态保活（默认 true）。
  /// 开启后，左右切换 Tab 时子页面不会被销毁重建，保留滚动偏移行程、输入状态，杜绝重复网络请求。
  final bool keepAlive;

  const DirectionalTabBarView({
    super.key,
    required this.children,
    this.controller,
    this.physics,
    this.dragStartBehavior = DragStartBehavior.start,
    this.viewportFraction = 1.0,
    this.clipBehavior = Clip.hardEdge,
    this.horizontalTouchSlop = 48.0,
    this.disableDesktopDrag = true,
    this.keepAlive = true,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isDesktop = AppPlatform.isDesktop;

    final effectivePhysics = (isDesktop && disableDesktopDrag)
        ? const NeverScrollableScrollPhysics()
        : physics;

    // 关键：在每个 child 外层将 touchSlop 恢复回系统默认 18.0px，
    // 确保内部垂直滚动长列表在 18px 时先达标胜出并锁定垂直方向。
    // 同时接入 KeepAliveWrapper，保证子 Tab 切出视口时不被底层销毁。
    final guardedChildren = children.map((child) {
      Widget guarded = MediaQuery(
        data: mediaQuery.copyWith(
          gestureSettings: const DeviceGestureSettings(touchSlop: kTouchSlop),
        ),
        child: child,
      );
      if (keepAlive) {
        guarded = KeepAliveWrapper(child: guarded);
      }
      return guarded;
    }).toList();

    return MediaQuery(
      data: mediaQuery.copyWith(
        gestureSettings: DeviceGestureSettings(touchSlop: horizontalTouchSlop),
      ),
      child: TabBarView(
        controller: controller,
        physics: effectivePhysics,
        dragStartBehavior: dragStartBehavior,
        viewportFraction: viewportFraction,
        clipBehavior: clipBehavior,
        children: guardedChildren,
      ),
    );
  }
}
