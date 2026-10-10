import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 仿 iOS 实体卡片物理按压弹性微交互包装器：
/// 1. 采用“单向单状态机 + 操作序列号 (Action ID) + 最小下压时间锁 (Min-Hold Time)”机制；
/// 2. 彻底杜绝极速鼠标点击（10ms~30ms）或手势冲突导致的 Ticker 掐灭与卡死问题；
/// 3. 无论单击、长按还是在列表滚动划过（Cancel），终点唯一且绝对保证以 Curves.easeOutBack 回弹至 1.0。
class BouncingScaleCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;

  /// 是否在松手（TapUp）时立即无延迟触发 [onTap]，回弹动效在后台异步并发播放。
  /// 适用于页面跳转、功能按钮等需要 0ms 瞬间响应的场景。
  final bool immediateTap;

  const BouncingScaleCard({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.95,
    this.immediateTap = false,
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
      duration: const Duration(milliseconds: 90), // 下压 90ms，紧凑干脆
      reverseDuration: const Duration(milliseconds: 200), // 回弹 200ms，物理弹性
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

    if (widget.immediateTap) {
      // 0ms 瞬间响应：松手立刻触发触觉反馈与业务回调，回弹动画在后台非阻塞异步并发完成
      HapticFeedback.lightImpact();
      widget.onTap?.call();
      if (mounted) {
        _controller.reverse();
      }
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final heldDuration = now - _lastTapDownTime;

    // 核心保证：若按压时间不足 95ms（如 Windows 鼠标机械微动仅触发 10ms~20ms），
    // 强制等待剩余毫秒数，让下压动作在屏幕上完整渲染呈现，彻底消除“单点吃动效”问题
    const minHoldTime = 95;
    if (heldDuration < minHoldTime) {
      await Future.delayed(Duration(milliseconds: minHoldTime - heldDuration));
    }

    // 生命周期安全防护：若等待期间组件已卸载或用户触发了新的手势，则终止当前执行线
    if (!mounted || currentAction != _actionId) return;

    // 触发触觉反馈并 100% 坚决执行回弹
    HapticFeedback.lightImpact();
    await _controller.reverse();

    if (!mounted || currentAction != _actionId) return;

    // 回弹动作完整呈现定格后唤起业务回调，避免模态弹窗过早弹出遮挡回弹视效
    widget.onTap?.call();
  }

  void _handleTapCancel() async {
    final currentAction = ++_actionId;
    final now = DateTime.now().millisecondsSinceEpoch;
    final heldDuration = now - _lastTapDownTime;

    // 若用户在滚动列表中快速划过卡片（触发 Cancel），确保平滑恢复原状，不卡在缩小态
    if (heldDuration < 60) {
      await Future.delayed(Duration(milliseconds: 60 - heldDuration));
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
