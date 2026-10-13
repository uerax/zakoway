import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 纵向手势优先的横向滚动防误触包装组件：
///
/// 特殊处理说明：
/// 1. 痛点根因：Flutter 默认的 Gesture Arena 中，横向与纵向的手势识别器阈值均采用默认的 kTouchSlop (18.0px)。
///    当用户在移动端单手刷页面时，由于手指生理弧度不可避免存在斜向分量，子级横向列表容易过早抢占手势仲裁，
///    导致外层页面纵向滚动被打断、横向列表被误触带跑；
/// 2. 解法机制：利用 Flutter 原生 [DeviceGestureSettings] 在当前子树中注入更高的横向 [touchSlop]（默认 36.0px，为纵向的 2 倍）。
///    当用户斜向滑动（偏角 > 26.5°）时，外层纵向滚动识别器（18.0px 阈值）必然先于横向识别器达到阈值并抢先胜出，
///    竞技场立即主动剔除子级横向识别器，实现 100% 顺滑纵向滚动；
/// 3. 只有当用户的滑动角度极平（偏角 <= 26.5°，即横向位移绝对主导）时，横向识别器才会激活；
/// 4. 在桌面端（PointerDeviceKind.mouse），Flutter 默认采用 [kPrecisePointerHitSlop]，
///    不受 touchSlop 影响，因此桌面鼠标拖拽依然保持 1 像素即时响应，零负面副作用。
class DirectionalHorizontalScroll extends StatelessWidget {
  final Widget child;

  /// 触屏端横向手势触发门槛（逻辑像素），默认 36.0。
  final double touchSlop;

  const DirectionalHorizontalScroll({
    super.key,
    required this.child,
    this.touchSlop = 36.0,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    return MediaQuery(
      data: mediaQuery.copyWith(
        gestureSettings: DeviceGestureSettings(touchSlop: touchSlop),
      ),
      child: child,
    );
  }
}
