import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 高性能极速原地下拉菜单组件：
/// 1. 规避原生 PopupMenuButton 的路由 push 延迟与全量同步 layout 掉帧；
/// 2. 采用纯 OverlayEntry 原位弹窗 + 定高 ListView.builder 懒加载 (O(1) 绘制)，大量选项秒开无卡顿；
/// 3. 支持自动定位到当前选中项的滚动偏移，点击外部瞬间移除。
class InstantDropdownButton<T> extends StatefulWidget {
  final Widget child;
  final List<T> items;
  final T selectedValue;
  final ValueChanged<T> onSelected;
  final Widget Function(BuildContext context, T value, bool isSelected) itemBuilder;
  final double menuWidth;
  final double maxMenuHeight;
  final bool alignRight;

  const InstantDropdownButton({
    super.key,
    required this.child,
    required this.items,
    required this.selectedValue,
    required this.onSelected,
    required this.itemBuilder,
    this.menuWidth = 136,
    this.maxMenuHeight = 280,
    this.alignRight = false,
  });

  @override
  State<InstantDropdownButton<T>> createState() => _InstantDropdownButtonState<T>();
}

class _InstantDropdownButtonState<T> extends State<InstantDropdownButton<T>>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _scaleAnim = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _closeMenu(immediately: true);
    _animController.dispose();
    super.dispose();
  }

  void _closeMenu({bool immediately = false}) {
    if (_overlayEntry == null) return;
    if (immediately) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    } else {
      _animController.reverse().then((_) {
        _overlayEntry?.remove();
        _overlayEntry = null;
      });
    }
  }

  void _toggleMenu() {
    if (_overlayEntry != null) {
      _closeMenu();
      return;
    }

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    // 特殊处理说明：必须使用 OverlayState 自身的 RenderBox 作为祖先坐标锚点进行归一化。
    // 在桌面端存在沉浸式标题栏（AppDesktopTitleBar: 44px）时，全局物理坐标会高出 44px，
    // 若直接使用 localToGlobal(Offset.zero) 会导致菜单向下多偏移 44px 产生巨大真空空隙；
    // 指定 ancestor: overlayRenderBox 可绝对精确地消除任何外层嵌套容器导致的垂直与水平位移偏差。
    final overlayState = Overlay.of(context);
    final overlayRenderBox = overlayState.context.findRenderObject() as RenderBox?;
    if (overlayRenderBox == null) return;

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero, ancestor: overlayRenderBox);

    final overlaySize = overlayRenderBox.size;
    final screenWidth = overlaySize.width;
    final screenHeight = overlaySize.height;

    double left = widget.alignRight
        ? (offset.dx + size.width - widget.menuWidth)
        : offset.dx;

    // 屏幕边缘安全间距
    if (left < 10) left = 10;
    if (left + widget.menuWidth > screenWidth - 10) {
      left = screenWidth - widget.menuWidth - 10;
    }

    final actualMenuHeight = math.min(
      widget.items.length * 38.0 + 8.0,
      widget.maxMenuHeight,
    );

    double top = offset.dy + size.height + 4;
    bool isPoppingUp = false;

    // 特殊处理说明：当底部剩余空间不足时触发向上弹出，必须基于 actualMenuHeight 精确测算，
    // 严禁直接扣除固定的 maxMenuHeight，否则在选项较少（如只有3-5项）时会导致菜单底部悬浮在按钮上方数十像素处。
    if (top + actualMenuHeight > screenHeight - 60) {
      top = offset.dy - actualMenuHeight - 4;
      isPoppingUp = true;
    }

    final selectedIndex = widget.items.indexOf(widget.selectedValue);
    final initialOffset = selectedIndex > 0
        ? (selectedIndex * 38.0).clamp(0.0, widget.items.length * 38.0)
        : 0.0;
    final scrollController = ScrollController(
      initialScrollOffset: initialOffset > 80 ? initialOffset - 38.0 : 0.0,
    );

    final theme = Theme.of(context);
    final scaleAlignment = isPoppingUp
        ? (widget.alignRight ? Alignment.bottomRight : Alignment.bottomLeft)
        : (widget.alignRight ? Alignment.topRight : Alignment.topLeft);

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // 全屏透明遮罩，点击外部瞬间关闭
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _closeMenu(),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: widget.menuWidth,
              child: FadeTransition(
                opacity: _fadeAnim,
                child: ScaleTransition(
                  scale: _scaleAnim,
                  alignment: scaleAlignment,
                  child: Material(
                    elevation: 6,
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      constraints: BoxConstraints(maxHeight: widget.maxMenuHeight),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                          width: 0.8,
                        ),
                      ),
                      child: ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: widget.items.length,
                        itemExtent: 38,
                        itemBuilder: (context, index) {
                          final item = widget.items[index];
                          final isSelected = item == widget.selectedValue;
                          return InkWell(
                            onTap: () {
                              _closeMenu();
                              widget.onSelected(item);
                            },
                            child: widget.itemBuilder(context, item, isSelected),
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
      },
    );

    overlayState.insert(_overlayEntry!);
    _animController.forward(from: 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleMenu,
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}
