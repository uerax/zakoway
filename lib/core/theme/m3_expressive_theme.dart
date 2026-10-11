import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Material 3 Expressive 全局主题构建工厂
class M3ExpressiveTheme {
  const M3ExpressiveTheme._();

  /// 构建 M3 Expressive 主题配置
  static ThemeData build({
    required Color primaryColor,
    required Brightness brightness,
    required String? currentFont,
    required List<String> fontFallback,
  }) {
    final isDark = brightness == Brightness.dark;

    // 启用 M3 Expressive 动态配色算法构建基础衍生调色板
    final baseColorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.expressive,
    );

    // 特殊处理说明：打破 Google Material You HCT 算法强制篡改明度（Tone 40/80）与旋转色相的限制，
    // 强制锁定 primary 为用户在设置与调色盘中实际选定的物理真实色彩，做到 100%「所选即所得」；
    // 同时基于明度动态决策 WCAG AA 级高对比度 onPrimary 文本图标色。
    final isPrimaryLight = primaryColor.computeLuminance() > 0.55;
    final colorScheme = baseColorScheme.copyWith(
      primary: primaryColor,
      onPrimary: isPrimaryLight ? const Color(0xFF1A1A1A) : Colors.white,
    );

    // 优选 InkSparkle，若在特定平台不支持则安全降级至 InkRipple
    final InteractiveInkFeatureFactory splashFactory =
        (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS))
            ? InkSparkle.splashFactory
            : InkRipple.splashFactory;

    final textTheme = _buildTextTheme(
      colorScheme: colorScheme,
      brightness: brightness,
      currentFont: currentFont,
      fontFallback: fontFallback,
    );

    // 全局基础文字样式助手：确保所有按钮、气泡、输入框、菜单与弹窗严格绑定字体与回退链，
    // 绝不使用未指定字体的裸 TextStyle，彻底封杀 Windows DirectWrite 跌入中易宋体 (SimSun) 的漏洞
    TextStyle buildStyledText({
      required double fontSize,
      FontWeight fontWeight = FontWeight.normal,
      Color? color,
      double? height,
    }) {
      return TextStyle(
        fontFamily: currentFont,
        fontFamilyFallback: fontFallback,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
      );
    }

    final primaryBtnStyle = buildStyledText(fontSize: 14, fontWeight: FontWeight.w700);
    final secondaryBtnStyle = buildStyledText(fontSize: 14, fontWeight: FontWeight.w600);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      splashFactory: splashFactory,
      fontFamily: currentFont,
      fontFamilyFallback: fontFallback,
      textTheme: textTheme,
      scaffoldBackgroundColor: isDark ? colorScheme.surface : colorScheme.surfaceContainer,

      // 全平台统一采用 iOS 丝滑平滑推入视差转场（CupertinoPageTransitionsBuilder），移动端保留边缘右滑返回手势
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: CupertinoPageTransitionsBuilder(),
        },
      ),

      // 1. 卡片规范：20dp 圆角，对齐主流地台体系（浅色纯白 surfaceContainerLowest / 深色 surfaceContainerLow）
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        color: isDark ? colorScheme.surfaceContainerLow : colorScheme.surfaceContainerLowest,
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
      ),

      // 2. 模态弹窗规范：28dp 大圆角，surfaceContainerHigh 背景，全量注入字体链彻底消灭宋体
      dialogTheme: DialogThemeData(
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        backgroundColor: colorScheme.surfaceContainerHigh,
        titleTextStyle: buildStyledText(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
        contentTextStyle: buildStyledText(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),

      // 3. 底部抽屉规范：28dp 顶部圆角；关闭原生浮空把手，统一由各定制抽屉在卡片内部自绘把手
      bottomSheetTheme: BottomSheetThemeData(
        elevation: 2,
        showDragHandle: false,
        dragHandleColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        backgroundColor: isDark ? colorScheme.surfaceContainerLow : colorScheme.surfaceContainerLowest,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        clipBehavior: Clip.antiAlias,
      ),

      // 4. 底部导航栏规范：横向药丸活动指示器 (StadiumBorder)
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 76,
        backgroundColor: colorScheme.surfaceContainer,
        indicatorColor: colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.14),
        indicatorShape: const StadiumBorder(),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.primary, size: 24);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return buildStyledText(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          );
        }),
      ),

      // 5. 搜索栏规范：52dp 药丸形状 (StadiumBorder)
      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: WidgetStatePropertyAll(colorScheme.surfaceContainerHigh),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16)),
        textStyle: WidgetStatePropertyAll(
          buildStyledText(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: colorScheme.onSurface,
          ),
        ),
        hintStyle: WidgetStatePropertyAll(
          buildStyledText(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
      ),

      // 6. 标签与切片 Chips 规范：药丸形态，无边框
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        elevation: 0,
        pressElevation: 0,
        backgroundColor: colorScheme.surfaceContainerHigh,
        selectedColor: colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.14),
        labelStyle: buildStyledText(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        secondaryLabelStyle: buildStyledText(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: colorScheme.primary,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),

      // 7. 按钮组全量采用药丸或圆润弧线，全量注入字体链消除 Windows 按钮宋体降级
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: primaryBtnStyle,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 1,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: primaryBtnStyle,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          side: BorderSide(color: colorScheme.outline, width: 1.2),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: secondaryBtnStyle,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: secondaryBtnStyle,
        ),
      ),

      // 7.5 全局浮条提示 SnackBar 规范
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentTextStyle: buildStyledText(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Colors.white,
        ),
      ),

      // 7.6 全局弹出菜单 PopupMenu 规范
      popupMenuTheme: PopupMenuThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: buildStyledText(
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
        ),
      ),

      // 7.7 全局悬浮气泡 Tooltip 规范
      tooltipTheme: TooltipThemeData(
        textStyle: buildStyledText(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: colorScheme.onInverseSurface,
        ),
      ),

      // 8. 输入框规范：surfaceContainerHigh 填充，16dp 柔和圆角
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: buildStyledText(fontSize: 13, color: colorScheme.onSurfaceVariant),
        hintStyle: buildStyledText(fontSize: 13, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
      ),

      // 9. 顶栏 AppBar 规范：透明底衬，居中标题，文字统一
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1.5,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
        titleTextStyle: TextStyle(
          fontFamily: currentFont,
          fontFamilyFallback: fontFallback,
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: colorScheme.onSurface,
        ),
      ),

      // 10. 分割线规范：使用柔和的 outlineVariant 色彩阶梯
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        thickness: 0.8,
        space: 1,
      ),

      // 11. 开关 Switch 规范：开启状态更富表现力
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.onPrimary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.surfaceContainerHighest;
        }),
      ),
    );
  }

  /// 构建排版文字主题，结合活跃字体与字体回退，并绑定深浅色 M3 语义文字色彩
  static TextTheme _buildTextTheme({
    required ColorScheme colorScheme,
    required Brightness brightness,
    required String? currentFont,
    required List<String> fontFallback,
  }) {
    final isDark = brightness == Brightness.dark;
    final isWindows = !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
    final typography = Typography.material2021(
      platform: defaultTargetPlatform,
      colorScheme: colorScheme,
    );

    // 依据深浅模式分流，绑定 Material 3 的 onSurface 与 onSurfaceVariant 文字色系
    final baseText = (isDark ? typography.white : typography.black).apply(
      fontFamily: currentFont,
      fontFamilyFallback: fontFallback,
    );

    return baseText.copyWith(
      displayLarge: baseText.displayLarge?.copyWith(fontWeight: FontWeight.w700),
      displayMedium: baseText.displayMedium?.copyWith(fontWeight: FontWeight.w700),
      displaySmall: baseText.displaySmall?.copyWith(fontWeight: FontWeight.w700),
      headlineLarge: baseText.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
      headlineMedium: baseText.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      headlineSmall: baseText.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: baseText.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: baseText.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: baseText.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      // 桌面端针对缺少 ClearType 亚像素渲染进行字重补偿：
      // 正文提升至 Medium (w500)，微调极小字号下限，防止灰度抗锯齿导致笔画单薄发虚
      bodyLarge: isWindows
          ? baseText.bodyLarge?.copyWith(fontWeight: FontWeight.w500)
          : baseText.bodyLarge,
      bodyMedium: isWindows
          ? baseText.bodyMedium?.copyWith(fontWeight: FontWeight.w500)
          : baseText.bodyMedium,
      bodySmall: isWindows
          ? baseText.bodySmall?.copyWith(
              fontWeight: FontWeight.w500,
              fontSize: 12.5,
            )
          : baseText.bodySmall,
      labelLarge: baseText.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      labelMedium: baseText.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: baseText.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: isWindows ? 11.5 : null,
      ),
    );
  }
}
