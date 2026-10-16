import 'package:flutter/material.dart';
import '../utils/appearance_manager.dart';

/// M3 表面色阶枚举
enum M3ContainerLevel {
  lowest,
  low,
  standard,
  high,
  highest,
}

/// Material 3 Expressive 表面层级与壁纸自适应融合工具
class M3Surface {
  const M3Surface._();

  /// 解析指定色阶的 M3 表面颜色（未设置壁纸时为纯实色，激活壁纸时自动计算色调透明度以透出背景）
  static Color container(
    BuildContext context, {
    M3ContainerLevel level = M3ContainerLevel.low,
    String? pageKey,
    double? customAlphaFraction,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colorScheme = theme.colorScheme;

    // 特殊处理说明：M3 Expressive 色调表面融合系统。
    // 杜绝浅色模式下生硬刺眼的纯白塑料板，采用与主题环境色自然交融的色阶体系；
    // 浅色下 lowest / low 均融入当前主题的微弱色相 (Tinted Surface)，配合微透度带来通透轻盈的高级质感。
    final Color baseColor = switch (level) {
      M3ContainerLevel.lowest => isDark
          ? colorScheme.surfaceContainerLowest
          : colorScheme.surfaceContainerLow.withValues(alpha: 0.75),
      M3ContainerLevel.low => isDark
          ? colorScheme.surfaceContainerLow
          : colorScheme.surfaceContainerLow,
      M3ContainerLevel.standard => colorScheme.surfaceContainer,
      M3ContainerLevel.high => colorScheme.surfaceContainerHigh,
      M3ContainerLevel.highest => colorScheme.surfaceContainerHighest,
    };

    final hasWallpaper = AppearanceManager.instance.hasWallpaperForPage(pageKey);
    if (!hasWallpaper) {
      return baseColor;
    }

    // 壁纸激活状态：采用 Material You 色调融色方案，赋予 78%~84% 的色调通透度
    final double alphaFraction = customAlphaFraction ?? (isDark ? 0.80 : 0.85);
    return baseColor.withValues(alpha: alphaFraction);
  }

  /// 容器辅助微光边界轮廓（无论是否激活壁纸均提供轻盈的细微透光描边，强化卡片轻盈浮空感）
  static Border? border(
    BuildContext context, {
    String? pageKey,
    bool forceBorder = false,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasWallpaper = AppearanceManager.instance.hasWallpaperForPage(pageKey);
    final double alpha = hasWallpaper
        ? (isDark ? 0.28 : 0.22)
        : (isDark ? 0.18 : 0.15);

    return Border.all(
      color: theme.colorScheme.outlineVariant.withValues(alpha: alpha),
      width: 0.6,
    );
  }

  /// 统一卡片高光与微光描边（深色模式提供细致微光透光边框，浅色模式提供高光边缘，防止与背景混淆）
  static Border cardBorder(
    BuildContext context, {
    double width = 0.8,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Border.all(
      color: isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.90),
      width: width,
    );
  }

  /// 卡片立体双层柔光阴影（环境暗影 + 主题色微光晕，强化浮空质感并防止融于背景）
  static List<BoxShadow> cardShadow(
    BuildContext context, {
    double elevation = 1.0,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;

    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.04),
        blurRadius: 4 * elevation,
        offset: Offset(0, 1.5 * elevation),
      ),
      BoxShadow(
        color: primary.withValues(alpha: isDark ? 0.08 : 0.06),
        blurRadius: 10 * elevation,
        spreadRadius: -1,
        offset: Offset(0, 4 * elevation),
      ),
    ];
  }
}
