import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef NavItemWidgetBuilder = Widget Function(
  BuildContext context,
  Color color,
  bool isSelected,
);

class AppFloatingNavItem {
  final IconData? unselectedIcon;
  final IconData? selectedIcon;
  final NavItemWidgetBuilder? builder;

  const AppFloatingNavItem({
    this.unselectedIcon,
    this.selectedIcon,
    this.builder,
  }) : assert(
          builder != null || (unselectedIcon != null && selectedIcon != null),
          'Either builder or both unselectedIcon and selectedIcon must be provided',
        );

  const AppFloatingNavItem.builder({
    required NavItemWidgetBuilder this.builder,
  })  : unselectedIcon = null,
        selectedIcon = null;

  Widget buildIcon(BuildContext context, Color color, bool isSelected) {
    if (builder != null) {
      return builder!(context, color, isSelected);
    }
    return Icon(
      isSelected ? selectedIcon : unselectedIcon,
      color: color,
      size: 24,
    );
  }
}

/// Material 3 Expressive & Telegram 动态悬浮底栏（对齐 [Image #6] 实机规范）：
/// 1. 左侧主胶囊：纯白高透晶莹玻璃（浅色）/ 深曜石微透（深色），配 0.8dp 物理发丝高光边框与双层景深投影；
/// 2. 右侧独立浮动搜索圆钮：同材质高斯模糊微透玻璃，直通搜索，解决单手大屏拇指黄金热区触达；
/// 3. 原生动效：完全恢复最新提交官方 AnimatedAlign(300ms Curves.easeOutBack) 与果冻弹簧微交互。
class AppFloatingBottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<AppFloatingNavItem> items;
  final VoidCallback? onSearchTap;

  const AppFloatingBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.onSearchTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    final dockBg = isDark
        ? const Color(0xFF1E1E22).withValues(alpha: 0.80)
        : Colors.white.withValues(alpha: 0.82);

    final dockBorder = Border.all(
      color: isDark
          ? Colors.white.withValues(alpha: 0.16)
          : theme.colorScheme.outlineVariant.withValues(alpha: 0.40),
      width: 0.8,
    );

    final compoundShadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
        blurRadius: 20,
        offset: const Offset(0, 6),
        spreadRadius: -1,
      ),
    ];

    const double barHeight = 54.0;
    const double dockRadius = 27.0;
    const double standardDockWidth = 220.0;

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          safeBottom < 10 ? 12 : safeBottom + 2,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasSearch = onSearchTap != null;
            final double searchExtra = hasSearch ? (10.0 + barHeight) : 0.0;
            // 响应式动态胶囊宽度：当小屏/窄分屏可用宽度不足以容纳原尺寸时平滑收缩，配合 FittedBox 彻底杜绝 RenderFlex 溢出
            final double effectiveDockWidth = (constraints.maxWidth - searchExtra)
                .clamp(160.0, standardDockWidth);

            return Center(
              heightFactor: 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // 1. 主导航胶囊（包含首页、分类、设置三大核心功能）
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(dockRadius),
                        boxShadow: compoundShadow,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(dockRadius),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                          child: Container(
                            width: effectiveDockWidth,
                            height: barHeight,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      decoration: BoxDecoration(
                        color: dockBg,
                        borderRadius: BorderRadius.circular(dockRadius),
                        border: dockBorder,
                      ),
                      child: Stack(
                        children: [
                          // 恢复原版 AnimatedAlign (300ms Curves.easeOutBack) 弹性滑块动效
                          AnimatedAlign(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutBack,
                            alignment: items.length > 1
                                ? AlignmentDirectional(
                                    -1 + 2 * currentIndex / (items.length - 1),
                                    0,
                                  )
                                : Alignment.center,
                            child: FractionallySizedBox(
                              widthFactor: 1 / items.length,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Container(
                                  height: 38,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(19),
                                    color: isDark
                                        ? primaryColor.withValues(alpha: 0.22)
                                        : primaryColor.withValues(alpha: 0.14),
                                    boxShadow: [
                                      BoxShadow(
                                        color: primaryColor.withValues(alpha: isDark ? 0.30 : 0.16),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // 各导航项图标（选中态 100% 呈现用户自定义的纯正 primary 主题色）
                          Row(
                            children: List.generate(items.length, (i) {
                              final isSelected = currentIndex == i;
                              final item = items[i];
                              final itemColor = isSelected
                                  ? primaryColor
                                  : theme.colorScheme.onSurfaceVariant;

                              return Expanded(
                                child: _BouncingNavItem(
                                  isSelected: isSelected,
                                  item: item,
                                  color: itemColor,
                                  onTap: () {
                                    if (currentIndex == i) return;
                                    HapticFeedback.lightImpact();
                                    onTap(i);
                                  },
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 2. 右侧独立悬浮搜索圆钮（对齐 [Image #6] Telegram 专属圆钮）
              if (onSearchTap != null) ...[
                const SizedBox(width: 10),
                Container(
                  width: barHeight,
                  height: barHeight,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: compoundShadow,
                  ),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                      child: Material(
                        color: dockBg,
                        shape: CircleBorder(side: dockBorder.top),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onSearchTap,
                          splashColor: primaryColor.withValues(alpha: 0.15),
                          highlightColor: primaryColor.withValues(alpha: 0.08),
                          child: Center(
                            child: Icon(
                              Icons.search_rounded,
                              size: 23,
                              color: isDark
                                  ? Colors.white
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  ),
),
    );
  }
}

/// 仿 iOS 经典物理触控弹簧动效组件：
/// 当 Tab 被选中激活时，执行“下压(0.88) -> 过冲放大(1.18) -> 弹性回落(1.0)”的三段式果冻动效，
/// 带来如同真实物理按钮一般的 Q 弹触感。
class _BouncingNavItem extends StatefulWidget {
  final bool isSelected;
  final AppFloatingNavItem item;
  final Color color;
  final VoidCallback onTap;

  const _BouncingNavItem({
    required this.isSelected,
    required this.item,
    required this.color,
    required this.onTap,
  });

  @override
  State<_BouncingNavItem> createState() => _BouncingNavItemState();
}

class _BouncingNavItemState extends State<_BouncingNavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    // 三段式弹簧曲线：瞬时轻压下陷 -> 弹性过冲冲起 -> 阻尼收敛回落
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.88)
            .chain(CurveTween(curve: Curves.easeOutQuad)),
        weight: 22,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.88, end: 1.18)
            .chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 48,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.18, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOutQuad)),
        weight: 30,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant _BouncingNavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从未选中切换为选中时，即刻触发弹性弹跳
    if (!oldWidget.isSelected && widget.isSelected) {
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Center(
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: widget.item.buildIcon(
            context,
            widget.color,
            widget.isSelected,
          ),
        ),
      ),
    );
  }
}
