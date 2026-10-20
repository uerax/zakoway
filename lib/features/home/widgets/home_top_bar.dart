import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/appearance_manager.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/responsive.dart';

/// 现代响应式顶部导航栏：
/// 1. 桌面/宽屏端（≥840px）：常驻吸顶（Sticky Header，绝不收起隐藏），采用“左品牌 + 居中 440px 搜索台 (带快捷键提示) + 右侧头像”；
/// 2. 移动端（<840px）：B站式通栏 Quick-Return 架构，采用“左头像 + 右侧通栏搜索条”，下滑阅读时自动上收让出视口，上滑微动时快速召回；
/// 3. 自屏幕顶端（top: 0）全宽延伸，自然包裹状态栏，彻底杜绝四周漏风与图文重叠打架；
/// 4. 支持桌面端快捷键绑定（Ctrl+K / ⌘K）直达搜索。
class HomeTopBar extends StatelessWidget {
  final bool isVisible;
  final ValueListenable<double>? scrollOffsetNotifier;
  final VoidCallback? onSearchTap;
  final VoidCallback? onAvatarTap;

  const HomeTopBar({
    super.key,
    this.isVisible = true,
    this.scrollOffsetNotifier,
    this.onSearchTap,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDesktop = context.isDesktop;

    // 桌面端无条件常驻吸顶 (Offset.zero)，移动端按滑动意图平滑收起 (-1.0) 或唤出 (0.0)
    final effectiveOffset = isDesktop
        ? Offset.zero
        : (isVisible ? Offset.zero : const Offset(0, -1));

    Widget buildBar(double offset) {
      final progress = (offset / 30.0).clamp(0.0, 1.0);

      Widget barContent = AnimatedSlide(
        // Quick-Return 动画：1:1 参考 B 站移动端实机约 200ms 敏捷平滑升降动画与 easeOutCubic 阻尼收敛
        offset: effectiveOffset,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: theme.scaffoldBackgroundColor.withValues(alpha: 0.88 * progress),
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.22 * progress),
                width: 0.8,
              ),
            ),
          ),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: 18 * progress,
                sigmaY: 18 * progress,
              ),
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 46,
                  child: isDesktop
                      ? _buildDesktopContent(context, theme, isDark)
                      : _buildMobileContent(context, theme, isDark),
                ),
              ),
            ),
          ),
        ),
      );

      // 桌面端支持 Ctrl+K / ⌘K 全局搜索快捷键
      if (isDesktop) {
        barContent = CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
              onSearchTap?.call();
            },
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
              onSearchTap?.call();
            },
          },
          child: Focus(
            autofocus: false,
            child: barContent,
          ),
        );
      }

      return barContent;
    }

    if (scrollOffsetNotifier != null) {
      return ValueListenableBuilder<double>(
        valueListenable: scrollOffsetNotifier!,
        builder: (context, offset, _) => buildBar(offset),
      );
    }

    return buildBar(0.0);
  }

  /// 桌面端 Hero 顶部排版：左品牌 + 居中 440px 搜索台 + 右侧用户头像
  Widget _buildDesktopContent(BuildContext context, ThemeData theme, bool isDark) {
    final isMac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    final shortcutText = isMac ? '⌘ K' : 'Ctrl K';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxContentWidth),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              // 左侧：精致应用品牌 Logo（自适应圆角微光投影与个性化图标即时联动）
              ListenableBuilder(
                listenable: AppearanceManager.instance,
                builder: (context, _) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(isDark ? 50 : 16),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: AppearanceManager.instance.buildAppLogoWidget(
                      size: 32,
                      borderRadius: 8,
                    ),
                  );
                },
              ),
              const Spacer(),

              // 中间：居中 440px 胶囊搜索控制台
              SizedBox(
                width: 440,
                child: _buildSearchBar(
                  theme: theme,
                  isDark: isDark,
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      shortcutText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSearchTap?.call();
                  },
                ),
              ),
              const Spacer(),

              // 右侧：用户登录头像插槽（包裹 44×44pt 规范触控热区）
              _buildUserAvatar(
                context: context,
                theme: theme,
                isDark: isDark,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 移动端顶部排版：1:1 参考 B 站实机（左头像 + 右侧通栏胶囊搜索条）
  Widget _buildMobileContent(BuildContext context, ThemeData theme, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          // 左侧：用户登录头像插槽（包裹 44×44pt 规范触控热区，36×36 视觉圆形）
          _buildUserAvatar(
            context: context,
            theme: theme,
            isDark: isDark,
          ),
          const SizedBox(width: 10),

          // 右侧：横向撑满的胶囊形搜索条
          Expanded(
            child: _buildSearchBar(
              theme: theme,
              isDark: isDark,
              onTap: () {
                HapticFeedback.selectionClick();
                onSearchTap?.call();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// M3 表现力胶囊搜索栏：等高 38px，与左侧头像精细对齐
  Widget _buildSearchBar({
    required ThemeData theme,
    required bool isDark,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.12),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 19,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '搜索番剧、剧场版、特别篇...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: theme.textTheme.bodyMedium?.fontFamily ?? 'MiSans',
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 6),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUserAvatar({
    required BuildContext context,
    required ThemeData theme,
    required bool isDark,
  }) {
    return Tooltip(
      message: '个人中心',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            if (onAvatarTap != null) {
              onAvatarTap!();
            } else {
              AppToast.info('用户登录功能暂未开放', context: context);
            }
          },
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surfaceContainerHigh,
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                    width: 1.0,
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.person_rounded,
                    size: 19,
                    color: theme.colorScheme.onSurfaceVariant,
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
