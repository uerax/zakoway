import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/utils/font_manager.dart';

/// 自动跳过片头/片尾时的可撤销 HUD 提示浮标
class PlayerSkipToast extends StatelessWidget {
  const PlayerSkipToast({
    super.key,
    required this.visible,
    required this.message,
    required this.onUndo,
    required this.onDismiss,
  });

  final bool visible;
  final String message;
  final VoidCallback onUndo;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final effectiveFontFamily = FontManager.instance.activeFontFamily ?? 'MiSans';
    const effectiveFallback = FontManager.fallbackFontFamilies;

    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 0.4),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: IgnorePointer(
          ignoring: !visible,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.fast_forward_rounded,
                      color: Color(0xFF65D1C5),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      message,
                      style: TextStyle(
                        fontFamily: effectiveFontFamily,
                        fontFamilyFallback: effectiveFallback,
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 撤销按钮
                    InkWell(
                      onTap: onUndo,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '撤销',
                          style: TextStyle(
                            fontFamily: effectiveFontFamily,
                            fontFamilyFallback: effectiveFallback,
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    // 关闭按钮
                    IconButton(
                      iconSize: 16,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 26, minHeight: 26),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white60,
                        size: 16,
                      ),
                      onPressed: onDismiss,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
