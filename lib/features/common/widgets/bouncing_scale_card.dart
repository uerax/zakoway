import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 仿 iOS 实体卡片物理按压弹性微交互包装器：
/// 1. 采用“单向单状态机 + 操作序列号 (Action ID) + 最小下压时间锁 (Min-Hold Time)”机制；
/// 2. 彻底杜绝极速鼠标点击（10ms~30ms）或手势冲突导致的 Ticker 掐灭与卡死问题；
/// 3. 终点唯一且以 Curves.easeOutBack 回弹至 1.0，兼顾清脆物理质感与敏捷响应。
class BouncingScaleCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;

  /// 是否开启敏捷跳转模式。
  ///
  /// 特殊处理说明：
  /// 默认开启 (true)。松手时启动物理 Q 弹回弹，并在微延迟感知窗口 [tapDelayMs]（默认 70ms）后触发 [onTap]。
  /// 既消除旧版等待 200ms+ 全量动画的发粘迟缓感，又彻底解决 0ms 秒切导致动效被 100% 吞没的问题。
  /// 若特定弹窗场景确实必须等卡片完全回弹定格后再弹出，可显式指定为 false。
  final bool immediateTap;

  /// 单独覆盖松手微延迟时长（毫秒），为 null 时使用全局默认值 [defaultTapDelayMs]
  final int? tapDelayMs;

  /// 单独覆盖极速点击最小下压保底时长（毫秒），为 null 时使用全局默认值 [defaultMinHoldMs]
  final int? minHoldMs;

  // ==============================================================================
  // 🎯【微交互物理动效 & 延迟微调参数集中配置区】
  // 方便针对不同手感偏好直接修改以下数值进行测试微调：
  // ==============================================================================

  /// 1. 【核心】松手后到触发跳转的微延迟窗口 (毫秒)
  /// - 作用：松手瞬间立即启动 Q 弹回弹，在此微延迟结束后触发 onTap 路由跳转。
  /// - 0ms: 原先逻辑（秒切，动画在桌面端 0 帧被覆盖，完全看不到动效）；
  /// - 60ms ~ 75ms【推荐默认值 70ms】：黄金平衡点，人脑感知为瞬时响应，但肉眼能清晰捕捉到 Q 弹爆发过冲；
  /// - 100ms+: 会开始产生可感知的停顿粘手感。
  static const int defaultTapDelayMs = 70;

  /// 2. 极速点击最小下压保底时间 (毫秒)
  /// - 作用：鼠标机械微动或触控极快抬起（如 10ms~20ms）时，强制等待补齐的时间，
  ///   确保卡片在屏幕上有充分的物理下压形变，消除“单点吃动效”问题。
  /// - 推荐：35ms ~ 55ms【推荐默认值 45ms】
  static const int defaultMinHoldMs = 45;

  /// 3. 紧凑下压动画时长 (毫秒)
  /// - 作用：卡片从 1.0 缩放到 scaleDown 的动画耗时。
  /// - 推荐：50ms ~ 70ms【推荐默认值 60ms】（越短越清脆利落）
  static const int defaultPressDurationMs = 60;

  /// 4. 物理弹性回弹总时长 (毫秒)
  /// - 作用：Curves.easeOutBack Q 弹回弹曲线的完整周期时长。
  /// - 推荐：120ms ~ 150ms【推荐默认值 140ms】
  static const int defaultReverseDurationMs = 140;

  /// 5. 快速滑动判定阈值 (毫秒)
  /// - 作用：在列表滚动中手指掠过卡片触发 Cancel 时，平滑复原的等待阈值。
  /// - 推荐：50ms ~ 70ms【推荐默认值 60ms】
  static const int defaultCancelHoldMs = 60;

  /// 6. 默认按压缩放系数
  /// - 作用：按下时卡片缩放到的比例（1.0 -> 0.95）。
  /// - 推荐：0.92 ~ 0.96【推荐默认值 0.95】
  static const double defaultScaleDown = 0.95;

  const BouncingScaleCard({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = defaultScaleDown,
    this.immediateTap = true,
    this.tapDelayMs,
    this.minHoldMs,
  });

  @override
  State<BouncingScaleCard> createState() => _BouncingScaleCardState();
}

class _BouncingScaleCardState extends State<BouncingScaleCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  // 记录按下的绝对时间点，用于计算是否满足最小下压视觉停留时间
  int _lastTapDownTime = 0;
  // 递增的操作序列号，防止连续狂点时的时序错乱
  int _actionId = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: BouncingScaleCard.defaultPressDurationMs),
      reverseDuration: const Duration(milliseconds: BouncingScaleCard.defaultReverseDurationMs),
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleDown,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutBack, // 松手回弹时带 Q 弹过冲
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 路由安全保护：当从子页面返回激活本页面时，若控制器此前被挂起处于非 0 状态，强制重置归零，防止二次补播
    if (_controller.value != 0.0) {
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails _) {
    _actionId++;
    _lastTapDownTime = DateTime.now().millisecondsSinceEpoch;
    // 立即启动下压
    _controller.forward();
  }

  void _handleTapUp(TapUpDetails _) async {
    final currentAction = ++_actionId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final heldDuration = now - _lastTapDownTime;

    // 1. 保底下压形变：若按压时间极短（如 Windows 鼠标快速轻点仅 10ms~20ms），
    // 强制等待补齐最小下压时间，让缩放形变在屏幕上能被视觉清晰捕捉
    final minHold = widget.minHoldMs ?? BouncingScaleCard.defaultMinHoldMs;
    if (heldDuration < minHold) {
      await Future.delayed(Duration(milliseconds: minHold - heldDuration));
      if (!mounted || currentAction != _actionId) return;
    }

    // 2. 0ms 瞬间触发触觉反馈
    HapticFeedback.lightImpact();

    // 3. 坚决启动回弹动效（Curves.easeOutBack Q 弹过冲）
    _controller.reverse();

    if (widget.immediateTap) {
      // 4. 【微延迟跳转窗口】：让回弹动效在屏幕上释放出黄金过冲段（默认 70ms）
      final delayMs = widget.tapDelayMs ?? BouncingScaleCard.defaultTapDelayMs;
      if (delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs));
        if (!mounted || currentAction != _actionId) return;
      }

      // 5. 唤起业务回调（如路由跳转）
      widget.onTap?.call();

      if (!mounted) return;

      // 6. 路由感知检查：若跳转打开了新页面，静默重置控制器，防止从新页面返回时处于中间状态
      final route = ModalRoute.of(context);
      if (route != null && !route.isCurrent) {
        _controller.reset();
      }
      return;
    }

    // 传统全量等待模式 (immediateTap == false)：等待完整回弹定格
    await _controller.reverse();
    if (!mounted || currentAction != _actionId) return;
    widget.onTap?.call();
  }

  void _handleTapCancel() async {
    final currentAction = ++_actionId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final heldDuration = now - _lastTapDownTime;

    // 若用户在滚动列表中快速划过卡片（触发 Cancel），确保平滑恢复原状，不卡在缩小态
    final cancelHold = BouncingScaleCard.defaultCancelHoldMs;
    if (heldDuration < cancelHold) {
      await Future.delayed(Duration(milliseconds: cancelHold - heldDuration));
    }

    if (!mounted || currentAction != _actionId) return;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) {
      return widget.child;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _handleTapDown,
        onTapUp: _handleTapUp,
        onTapCancel: _handleTapCancel,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: widget.child,
        ),
      ),
    );
  }
}
