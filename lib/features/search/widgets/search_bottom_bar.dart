import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/utils/font_manager.dart';

/// Material 3 Expressive 风格悬浮搜索栏（对齐首页悬浮底栏设计规范）：
/// 1. 左侧拉长输入胶囊：高透晶莹玻璃材质，集成单手返回键、沉浸式文本输入与一键清空圆钮；
/// 2. 右侧独立悬浮搜索圆钮：54x54 同材质高斯模糊玻璃圆钮，完全继承首页搜索圆钮位置与物理投影；
/// 3. 几何与触觉统一：高度严格锁定 54dp，圆角 27dp，底边距与首页一致，键盘弹起时自适应浮动。
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
    final primaryColor = theme.colorScheme.primary;

    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
    final isKeyboardOpen = viewInsetsBottom > 0;
    final bottomPadding = isKeyboardOpen ? 10.0 : (safeBottom < 10 ? 12.0 : safeBottom + 2.0);

    // 对齐首页 AppFloatingBottomBar 的微透高斯模糊与边框材质
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

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottomPadding),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. 左侧拉长的主输入胶囊（集成返回、输入区、清空键）
              Expanded(
                child: Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(dockRadius),
                    boxShadow: compoundShadow,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(dockRadius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
                      child: Container(
                        height: barHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                        decoration: BoxDecoration(
                          color: dockBg,
                          borderRadius: BorderRadius.circular(dockRadius),
                          border: dockBorder,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 单手返回轻触圆钮
                            Material(
                              color: Colors.transparent,
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  onBack();
                                },
                                splashColor: primaryColor.withValues(alpha: 0.15),
                                highlightColor: primaryColor.withValues(alpha: 0.08),
                                child: SizedBox(
                                  width: 38,
                                  height: 38,
                                  child: Center(
                                    child: Icon(
                                      Icons.arrow_back_rounded,
                                      size: 21,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),

                            // 沉浸式文本输入区域
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

                            // 文本一键清空圆钮
                            ListenableBuilder(
                              listenable: controller,
                              builder: (context, _) {
                                if (controller.text.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: GestureDetector(
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      onClear();
                                    },
                                    behavior: HitTestBehavior.opaque,
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.white.withValues(alpha: 0.22)
                                            : Colors.black.withValues(alpha: 0.18),
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
                  ),
                ),
              ),

              // 2. 右侧独立悬浮搜索圆钮（与首页搜索圆钮尺寸、材质、位置 100% 对齐）
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
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSearch();
                        },
                        splashColor: primaryColor.withValues(alpha: 0.15),
                        highlightColor: primaryColor.withValues(alpha: 0.08),
                        child: ListenableBuilder(
                          listenable: controller,
                          builder: (context, _) {
                            final hasText = controller.text.trim().isNotEmpty;
                            final iconColor = hasText
                                ? primaryColor
                                : (isDark ? Colors.white : theme.colorScheme.onSurfaceVariant);
                            return Center(
                              child: Icon(
                                Icons.search_rounded,
                                size: 23,
                                color: iconColor,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
