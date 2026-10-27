import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/font_manager.dart';
import '../../../../core/utils/responsive.dart';

/// 桌面端左下角悬浮半透明微光返回圆圈按钮
///
/// 特性与规范：
/// 1. 平时虚化：半透明磨砂（opacity 0.38），微弱融入页面背景，完全不抢视觉、不干扰阅读与观影；
/// 2. 悬停/聚焦实体化：鼠标 hover 或键盘 focus 时立即实体化（opacity 1.0, 实体背景+微光阴影+微动效）；
/// 3. 严格遵循 Windows 字体保护规范（注入 fontFamily 与 fontFamilyFallback，杜绝宋体）；
/// 4. 独立于主内容滚动容器，无论内容如何滚动，左下角随时可退出；
/// 5. 提供统一的 [DesktopBackShortcutScope] 快捷键作用域，支持全平台桌面端按 Esc 优雅退出。
class DesktopFloatingBackButton extends StatefulWidget {
  const DesktopFloatingBackButton({
    super.key,
    required this.onPressed,
    this.tooltip = '返回 (Esc)',
  });

  final VoidCallback onPressed;
  final String tooltip;

  @override
  State<DesktopFloatingBackButton> createState() =>
      _DesktopFloatingBackButtonState();
}

class _DesktopFloatingBackButtonState extends State<DesktopFloatingBackButton> {
  bool _isHovered = false;
  bool _isFocused = false;

  bool get _isActive => _isHovered || _isFocused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Focus(
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        child: Tooltip(
          message: widget.tooltip,
          textStyle: appTextStyle(
            fontSize: 12,
            color: Colors.white,
          ),
          waitDuration: const Duration(milliseconds: 300),
          child: AnimatedScale(
            scale: _isActive ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _isActive ? 1.0 : 0.38,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isActive
                          ? (isDark
                              ? const Color(0xFF202026).withValues(alpha: 0.92)
                              : Colors.white.withValues(alpha: 0.94))
                          : (isDark
                              ? Colors.black.withValues(alpha: 0.35)
                              : Colors.black.withValues(alpha: 0.18)),
                      border: Border.all(
                        color: _isActive
                            ? primaryColor.withValues(alpha: 0.65)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.16)
                                : Colors.black.withValues(alpha: 0.10)),
                        width: _isActive ? 1.2 : 0.8,
                      ),
                      boxShadow: _isActive
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(
                                    alpha: isDark ? 0.45 : 0.18),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: primaryColor.withValues(
                                    alpha: isDark ? 0.30 : 0.20),
                                blurRadius: 10,
                              ),
                            ]
                          : const [],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: widget.onPressed,
                        child: Center(
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: _isActive
                                ? (isDark ? Colors.white : Colors.black87)
                                : (isDark ? Colors.white70 : Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 桌面端 Esc 快捷键与返回生命周期守护容器
///
/// 1. 在桌面系统运行时捕获 Esc 按键；
/// 2. 若当前焦点在可编辑文本框内，先失焦退出打字态，再次按 Esc 触发返回，防止误触；
/// 3. 非桌面环境时静默透传子树。
class DesktopBackShortcutScope extends StatelessWidget {
  const DesktopBackShortcutScope({
    super.key,
    required this.child,
    required this.onBack,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onBack;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (!enabled || !AppPlatform.isDesktop) {
      return child;
    }

    return Focus(
      autofocus: true,
      canRequestFocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          final primaryWidget =
              FocusManager.instance.primaryFocus?.context?.widget;
          if (primaryWidget is EditableText) {
            FocusManager.instance.primaryFocus?.unfocus();
            return KeyEventResult.handled;
          }
          onBack();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
