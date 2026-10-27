import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/font_manager.dart';

/// iOS Safari 风格底部悬浮搜索栏（包含返回、胶囊输入框、清空小圆钮与搜索操作键）
class SearchBottomBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSearch;
  final VoidCallback onClear;
  final VoidCallback onBack;

  const SearchBottomBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSearch,
    required this.onClear,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final barBg = isDark
        ? const Color(0xFF1E1E22).withValues(alpha: 0.86)
        : Colors.white.withValues(alpha: 0.88);

    final inputBg = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65);

    return Container(
      decoration: BoxDecoration(
        color: barBg,
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.12)
                : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Row(
                children: [
                  // 1. iOS Safari 式轻量单手返回按钮
                  IconButton(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onBack();
                    },
                    icon: Icon(
                      Icons.arrow_back_rounded,
                      size: 22,
                      color: theme.colorScheme.onSurface,
                    ),
                    tooltip: '返回',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(40, 40),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                  const SizedBox(width: 4),

                  // 2. 居中一体化 iOS Safari 大胶囊搜索条
                  Expanded(
                    child: Container(
                      height: 42,
                      decoration: BoxDecoration(
                        color: inputBg,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : theme.colorScheme.outlineVariant.withValues(alpha: 0.28),
                          width: 0.8,
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(
                            Icons.search_rounded,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: controller,
                              focusNode: focusNode,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) {
                                HapticFeedback.selectionClick();
                                onSearch();
                              },
                              style: TextStyle(
                                fontSize: 14.5,
                                color: theme.colorScheme.onSurface,
                                fontFamily: FontManager.instance.activeFontFamily ?? 'MiSans',
                                fontFamilyFallback: FontManager.fallbackFontFamilies,
                              ),
                              decoration: InputDecoration(
                                hintText: '搜索番剧、剧场版…',
                                hintStyle: TextStyle(
                                  fontSize: 14.5,
                                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                                  fontFamily: FontManager.instance.activeFontFamily ?? 'MiSans',
                                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          // 清空输入文本按钮
                          ListenableBuilder(
                            listenable: controller,
                            builder: (context, _) {
                              if (controller.text.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return GestureDetector(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  onClear();
                                },
                                behavior: HitTestBehavior.opaque,
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.25)
                                          : Colors.black.withValues(alpha: 0.22),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close_rounded,
                                      size: 13,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // 3. 右侧搜索操作按钮（Safari 风格紧凑胶囊）
                  FilledButton.tonal(
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      onSearch();
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      minimumSize: const Size(58, 40),
                      shape: const StadiumBorder(),
                      textStyle: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        fontFamily: FontManager.instance.activeFontFamily ?? 'MiSans',
                        fontFamilyFallback: FontManager.fallbackFontFamilies,
                      ),
                    ),
                    child: const Text('搜索'),
                  ),
                ],
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
