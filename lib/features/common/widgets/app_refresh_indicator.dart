import 'dart:async';

import 'package:flutter/foundation.dart' show clampDouble;
import 'package:flutter/material.dart';

import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/responsive.dart';

// 指示器拉动行程比例系数
const double _kDragSizeFactorLimit = 1.5;

// 刷新指示器收起与弹出动画时长
const Duration _kIndicatorSnapDuration = Duration(milliseconds: 150);
const Duration _kIndicatorScaleDuration = Duration(milliseconds: 200);

/// 自定义防误触下拉刷新组件 (AppRefreshIndicator)：
///
/// 特殊处理说明：
/// 1. 痛点根因：
///    - Flutter 原生 [RefreshIndicator] 内部将触发阈值与容器视口高度绑定（containerExtent * 0.25），
///      且 armed 系数仅为 1.0 / 1.5 ≈ 0.667。对于普通屏幕或局部嵌套滚动，只要下拉几十像素即进入就绪；
///    - 更致命的是：在使用了 [BouncingScrollPhysics] 的页面或 iOS 平台上，只要状态一进入 armed，
///      列表弹性回弹时派发的 [ScrollUpdateNotification]（dragDetails == null）会立即强制触发 [_show()] 刷新，
///      导致用户仅仅是不小心轻滑、斜向滑过横向卡片、或微幅下拉查看回弹动效时，就频繁误触全量刷新；
///    - 原生组件未提供 [triggerDistance] 物理像素阈值与下拉阻尼调节能力。
///
/// 2. 核心防误触保护机制：
///    - [triggerDistance] 绝对物理像素门槛（默认 105.0px）：脱离视口百分比不确定性，必须下拉达到扎实的物理距离；
///    - [dragDamping] 手势物理阻尼（默认 0.70）：对用户下拉的位移施加阻尼衰减，轻微滑动的位移被大幅缓冲吸收；
///    - 杜绝回弹偷跑：严格要求下拉动画完全拉满（_positionController.value >= 1.0）且用户手指真正离屏（ScrollEndNotification）
///      时才触发刷新；若未完全拉满便回弹，一律平滑取消并收回，绝不抢跑；
///    - 桌面端（Windows/macOS/Linux）滚轮保护：过滤鼠标滚轮向上滚动产生的微小过滚动，杜绝桌面端滚轮误触发。
class AppRefreshIndicator extends StatefulWidget {
  final Widget child;
  final RefreshCallback onRefresh;

  /// 指示器停靠时距离边缘的位移（默认 40.0）
  final double displacement;

  /// 指示器起始出现的边缘偏移量（默认 0.0）
  final double edgeOffset;

  /// 触发刷新所需的物理下拉像素距离（默认 105.0px，有效防止无意轻滑误触）
  final double triggerDistance;

  /// 下拉位移阻尼系数（0.0 ~ 1.0，默认 0.70，使下拉手感更扎实、前段滑动更不易冒进）
  final double dragDamping;

  /// 指示器圆环颜色，默认使用当前主题的 primary
  final Color? color;

  /// 指示器背景色，默认使用 M3Surface 高阶容器色
  final Color? backgroundColor;

  /// 滚动通知过滤谓词
  final ScrollNotificationPredicate notificationPredicate;

  /// 圆环描边宽度
  final double strokeWidth;

  /// 投影高度
  final double elevation;

  /// 触发模式
  final RefreshIndicatorTriggerMode triggerMode;

  const AppRefreshIndicator({
    super.key,
    required this.child,
    required this.onRefresh,
    this.displacement = 40.0,
    this.edgeOffset = 0.0,
    this.triggerDistance = 105.0,
    this.dragDamping = 0.70,
    this.color,
    this.backgroundColor,
    this.notificationPredicate = defaultScrollNotificationPredicate,
    this.strokeWidth = 2.5,
    this.elevation = 2.0,
    this.triggerMode = RefreshIndicatorTriggerMode.onEdge,
  })  : assert(triggerDistance > 0),
        assert(dragDamping > 0 && dragDamping <= 1.0),
        assert(elevation >= 0.0);

  @override
  State<AppRefreshIndicator> createState() => AppRefreshIndicatorState();
}

class AppRefreshIndicatorState extends State<AppRefreshIndicator>
    with TickerProviderStateMixin<AppRefreshIndicator> {
  late AnimationController _positionController;
  late AnimationController _scaleController;
  late Animation<double> _positionFactor;
  late Animation<double> _scaleFactor;
  late Animation<double> _value;
  late Animation<Color?> _valueColor;

  RefreshIndicatorStatus? _status;
  late Future<void> _pendingRefreshFuture;
  bool? _isIndicatorAtTop;
  double? _dragOffset;

  static final Animatable<double> _threeQuarterTween =
      Tween<double>(begin: 0.0, end: 0.75);
  static final Animatable<double> _kDragSizeFactorLimitTween =
      Tween<double>(begin: 0.0, end: _kDragSizeFactorLimit);
  static final Animatable<double> _oneToZeroTween =
      Tween<double>(begin: 1.0, end: 0.0);

  @override
  void initState() {
    super.initState();
    _positionController = AnimationController(vsync: this);
    _positionFactor = _positionController.drive(_kDragSizeFactorLimitTween);
    _value = _positionController.drive(_threeQuarterTween);

    _scaleController = AnimationController(vsync: this);
    _scaleFactor = _scaleController.drive(_oneToZeroTween);
  }

  @override
  void didChangeDependencies() {
    _setupColorTween();
    super.didChangeDependencies();
  }

  @override
  void didUpdateWidget(covariant AppRefreshIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.color != widget.color) {
      _setupColorTween();
    }
  }

  @override
  void dispose() {
    _positionController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _setupColorTween() {
    final effectiveColor =
        widget.color ?? Theme.of(context).colorScheme.primary;
    if ((effectiveColor.a * 255).round() == 0) {
      _valueColor = AlwaysStoppedAnimation<Color>(effectiveColor);
    } else {
      _valueColor = _positionController.drive(
        ColorTween(
          begin: effectiveColor.withValues(alpha: 0),
          end: effectiveColor,
        ).chain(
          CurveTween(
            curve: const Interval(0.0, 1.0 / _kDragSizeFactorLimit),
          ),
        ),
      );
    }
  }

  bool _shouldStart(ScrollNotification notification) {
    final DragStartDetails? startDragDetails = notification is ScrollStartNotification ? notification.dragDetails : null;
    final DragUpdateDetails? updateDragDetails = notification is ScrollUpdateNotification ? notification.dragDetails : null;
    final bool hasDragDetails = startDragDetails != null || updateDragDetails != null;

    // 桌面端保护：若是桌面平台（Windows/macOS/Linux）且无拖拽手势详情（如纯鼠标滚轮回滚触发的过滚动），一律忽略
    if (AppPlatform.isDesktop && !hasDragDetails) {
      return false;
    }

    return ((startDragDetails != null) ||
            (updateDragDetails != null &&
                widget.triggerMode == RefreshIndicatorTriggerMode.anywhere)) &&
        ((notification.metrics.axisDirection == AxisDirection.up &&
                notification.metrics.extentAfter == 0.0) ||
            (notification.metrics.axisDirection == AxisDirection.down &&
                notification.metrics.extentBefore == 0.0)) &&
        _status == null &&
        _start(notification.metrics.axisDirection);
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (!widget.notificationPredicate(notification)) {
      return false;
    }

    if (_shouldStart(notification)) {
      setState(() {
        _status = RefreshIndicatorStatus.drag;
      });
      return false;
    }

    final bool? indicatorAtTopNow =
        switch (notification.metrics.axisDirection) {
      AxisDirection.down || AxisDirection.up => true,
      AxisDirection.left || AxisDirection.right => null,
    };

    if (indicatorAtTopNow != _isIndicatorAtTop) {
      if (_status == RefreshIndicatorStatus.drag ||
          _status == RefreshIndicatorStatus.armed) {
        _dismiss(RefreshIndicatorStatus.canceled);
      }
    } else if (notification is ScrollUpdateNotification) {
      if (_status == RefreshIndicatorStatus.drag ||
          _status == RefreshIndicatorStatus.armed) {
        // 关键：对物理下拉位移施加阻尼，使前段轻微晃动被大幅衰减，阻绝误触
        final rawDelta = notification.scrollDelta ?? 0.0;
        final dampedDelta = rawDelta * widget.dragDamping;

        if (notification.metrics.axisDirection == AxisDirection.down) {
          _dragOffset = _dragOffset! - dampedDelta;
        } else if (notification.metrics.axisDirection == AxisDirection.up) {
          _dragOffset = _dragOffset! + dampedDelta;
        }

        // 若用户往回推导致偏离顶部（列表开始向下滚动）或偏移归零，平滑收起并取消
        if (_dragOffset! <= 0 && notification.metrics.extentBefore > 0) {
          _dismiss(RefreshIndicatorStatus.canceled);
          return false;
        }

        _checkDragOffset();
      }

      // 特殊处理说明：
      // 在 BouncingScrollPhysics 下用户松手进入回弹阶段时（dragDetails == null）：
      // 只有当用户确实拉满设定的物理阈值（_positionController.value >= 1.0 且处于 armed）时才执行 _show()；
      // 若拉动不足（中途放弃、轻微滑动或往回推），直接平滑取消，彻底杜绝回弹偷跑。
      if (_status == RefreshIndicatorStatus.armed &&
          notification.dragDetails == null) {
        if (_positionController.value >= 1.0) {
          _show();
        } else {
          _dismiss(RefreshIndicatorStatus.canceled);
        }
      } else if (_status == RefreshIndicatorStatus.drag &&
          notification.dragDetails == null) {
        // 未就绪便松手回弹，立即取消
        _dismiss(RefreshIndicatorStatus.canceled);
      }
    } else if (notification is OverscrollNotification) {
      if (_status == RefreshIndicatorStatus.drag ||
          _status == RefreshIndicatorStatus.armed) {
        final rawOverscroll = notification.overscroll;
        final dampedOverscroll = rawOverscroll * widget.dragDamping;

        if (notification.metrics.axisDirection == AxisDirection.down) {
          _dragOffset = _dragOffset! - dampedOverscroll;
        } else if (notification.metrics.axisDirection == AxisDirection.up) {
          _dragOffset = _dragOffset! + dampedOverscroll;
        }
        _checkDragOffset();
      }
    } else if (notification is ScrollEndNotification) {
      switch (_status) {
        case RefreshIndicatorStatus.armed:
          // 严格防误触保护：必须拉满整个行程（>= 1.0）才触发刷新，未拉满一律判定为用户放弃并平滑取消
          if (_positionController.value < 1.0) {
            _dismiss(RefreshIndicatorStatus.canceled);
          } else {
            _show();
          }
        case RefreshIndicatorStatus.drag:
          _dismiss(RefreshIndicatorStatus.canceled);
        case RefreshIndicatorStatus.canceled:
        case RefreshIndicatorStatus.done:
        case RefreshIndicatorStatus.refresh:
        case RefreshIndicatorStatus.snap:
        case null:
          break;
      }
    }
    return false;
  }

  bool _handleIndicatorNotification(
      OverscrollIndicatorNotification notification) {
    if (notification.depth != 0 || !notification.leading) {
      return false;
    }
    if (_status == RefreshIndicatorStatus.drag) {
      notification.disallowIndicator();
      return true;
    }
    return false;
  }

  bool _start(AxisDirection direction) {
    assert(_status == null);
    assert(_isIndicatorAtTop == null);
    assert(_dragOffset == null);
    switch (direction) {
      case AxisDirection.down:
      case AxisDirection.up:
        _isIndicatorAtTop = true;
      case AxisDirection.left:
      case AxisDirection.right:
        _isIndicatorAtTop = null;
        return false;
    }
    _dragOffset = 0.0;
    _scaleController.value = 0.0;
    _positionController.value = 0.0;
    return true;
  }

  void _checkDragOffset() {
    assert(_status == RefreshIndicatorStatus.drag ||
        _status == RefreshIndicatorStatus.armed);

    // 基于配置的 triggerDistance 物理像素门槛计算拉动进度，彻底摆脱屏幕高度百分比带来的不确定性
    final effectiveTarget = widget.triggerDistance;
    final double progress = _dragOffset! / effectiveTarget;
    final double clampedProgress = clampDouble(progress, 0.0, 1.0);
    _positionController.value = clampedProgress;

    // 只有当拉满设定的物理阈值（value >= 1.0）时，才切换为 armed 状态；
    // 若用户中途向上推回，自动撤回 armed 状态，允许反悔取消
    if (clampedProgress >= 1.0) {
      _status = RefreshIndicatorStatus.armed;
    } else {
      _status = RefreshIndicatorStatus.drag;
    }
  }

  Future<void> _dismiss(RefreshIndicatorStatus newMode) async {
    await Future<void>.value();
    assert(newMode == RefreshIndicatorStatus.canceled ||
        newMode == RefreshIndicatorStatus.done);
    if (!mounted) return;
    setState(() {
      _status = newMode;
    });
    switch (_status!) {
      case RefreshIndicatorStatus.done:
        await _scaleController.animateTo(1.0,
            duration: _kIndicatorScaleDuration);
      case RefreshIndicatorStatus.canceled:
        await _positionController.animateTo(0.0,
            duration: _kIndicatorScaleDuration);
      default:
        break;
    }
    if (mounted && _status == newMode) {
      _dragOffset = null;
      _isIndicatorAtTop = null;
      setState(() {
        _status = null;
      });
    }
  }

  void _show() {
    assert(_status != RefreshIndicatorStatus.refresh);
    assert(_status != RefreshIndicatorStatus.snap);
    final completer = Completer<void>();
    _pendingRefreshFuture = completer.future;
    _status = RefreshIndicatorStatus.snap;
    _positionController
        .animateTo(1.0 / _kDragSizeFactorLimit,
            duration: _kIndicatorSnapDuration)
        .then<void>((_) {
      if (mounted && _status == RefreshIndicatorStatus.snap) {
        setState(() {
          _status = RefreshIndicatorStatus.refresh;
        });

        final Future<void> refreshResult = widget.onRefresh();
        refreshResult.whenComplete(() {
          if (mounted && _status == RefreshIndicatorStatus.refresh) {
            completer.complete();
            _dismiss(RefreshIndicatorStatus.done);
          }
        });
      }
    });
  }

  /// 编程式触发刷新
  Future<void> show({bool atTop = true}) {
    if (_status != RefreshIndicatorStatus.refresh &&
        _status != RefreshIndicatorStatus.snap) {
      if (_status == null) {
        _start(atTop ? AxisDirection.down : AxisDirection.up);
      }
      _show();
    }
    return _pendingRefreshFuture;
  }

  @override
  Widget build(BuildContext context) {
    final Widget child = NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: NotificationListener<OverscrollIndicatorNotification>(
        onNotification: _handleIndicatorNotification,
        child: widget.child,
      ),
    );

    final bool showIndeterminateIndicator =
        _status == RefreshIndicatorStatus.refresh ||
            _status == RefreshIndicatorStatus.done;

    final defaultBgColor = M3Surface.container(context,
        level: M3ContainerLevel.high, pageKey: 'common');

    return Stack(
      children: <Widget>[
        child,
        if (_status != null)
          Positioned(
            top: _isIndicatorAtTop! ? widget.edgeOffset : null,
            bottom: !_isIndicatorAtTop! ? widget.edgeOffset : null,
            left: 0.0,
            right: 0.0,
            child: SizeTransition(
              alignment:
                  AlignmentDirectional(-1.0, _isIndicatorAtTop! ? 1.0 : -1.0),
              sizeFactor: _positionFactor,
              child: Padding(
                padding: _isIndicatorAtTop!
                    ? EdgeInsets.only(top: widget.displacement)
                    : EdgeInsets.only(bottom: widget.displacement),
                child: Align(
                  alignment: _isIndicatorAtTop!
                      ? Alignment.topCenter
                      : Alignment.bottomCenter,
                  child: ScaleTransition(
                    scale: _scaleFactor,
                    child: AnimatedBuilder(
                      animation: _positionController,
                      builder: (BuildContext context, Widget? child) {
                        return RefreshProgressIndicator(
                          value: showIndeterminateIndicator
                              ? null
                              : _value.value,
                          valueColor: _valueColor,
                          backgroundColor:
                              widget.backgroundColor ?? defaultBgColor,
                          strokeWidth: widget.strokeWidth,
                          elevation: widget.elevation,
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
