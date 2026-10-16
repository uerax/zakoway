import 'package:flutter/material.dart';
import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/font_manager.dart';

/// 设置分组标题（支持轻量或强调字重，并显式注入安全字体）
class M3SettingsSectionHeader extends StatelessWidget {
  final String title;
  final FontWeight fontWeight;

  const M3SettingsSectionHeader({
    super.key,
    required this.title,
    this.fontWeight = FontWeight.w600,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontMgr = FontManager.instance;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
          fontWeight: fontWeight,
          fontSize: 13.5,
          letterSpacing: -0.1,
          fontFamily: fontMgr.activeFontFamily,
          fontFamilyFallback: FontManager.fallbackFontFamilies,
        ),
      ),
    );
  }
}

/// Telegram/iOS Inset Grouped 风格设置分组卡片（16dp 紧凑圆角、支持底部注脚）
class M3SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final String? footerText;
  final Widget? footer;

  const M3SettingsCard({
    super.key,
    required this.children,
    this.footerText,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final containerColor = M3Surface.container(
      context,
      level: M3ContainerLevel.low,
      pageKey: 'settings',
    );
    final border = M3Surface.cardBorder(context);
    final shadow = M3Surface.cardShadow(context);
    final radius = BorderRadius.circular(16);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: containerColor,
            borderRadius: radius,
            border: border,
            boxShadow: shadow,
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
        if (footerText != null || footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
            child: footer ??
                Text(
                  footerText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                    fontSize: 12.5,
                    height: 1.35,
                    fontWeight: FontWeight.normal,
                  ),
                ),
          ),
      ],
    );
  }
}

/// Telegram/iOS 风格 30dp 彩色平滑圆角图标方块
class M3SettingsIconBox extends StatelessWidget {
  final IconData icon;
  final Color? bg;
  final Color? iconColor;
  final double size;

  const M3SettingsIconBox({
    super.key,
    required this.icon,
    this.bg,
    this.iconColor,
    this.size = 30,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveBg = bg ?? theme.colorScheme.primary;
    final effectiveIconColor = iconColor ?? Colors.white;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: effectiveBg,
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        color: effectiveIconColor,
        size: size * 0.58,
      ),
    );
  }
}

/// Telegram/iOS 风格列表设置项（常规非粗体排版、内缩避开图标的精准分割线）
class M3SettingsTile extends StatelessWidget {
  final Widget? leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  const M3SettingsTile({
    super.key,
    this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: theme.colorScheme.primary.withValues(alpha: 0.10),
        highlightColor: theme.colorScheme.primary.withValues(alpha: 0.05),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              child: Row(
                children: [
                  if (leading != null) ...[
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: Center(child: leading!),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.normal,
                            fontSize: 15.5,
                            letterSpacing: -0.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                              fontSize: 12.5,
                              fontWeight: FontWeight.normal,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
            if (showDivider)
              Padding(
                // 特殊处理说明：内缩 60dp（16dp 外边距 + 30dp 图标 + 14dp 间距），
                // 确保分割线避开左侧彩色图标，从文本起点起笔，严格对齐 Telegram/iOS 规范。
                padding: EdgeInsets.only(left: leading != null ? 60 : 16),
                child: Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.black.withValues(alpha: 0.08),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
