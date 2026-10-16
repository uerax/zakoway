import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 跨平台运行环境识别工具：
/// 区分操作系统原生形态（Windows / macOS / Linux vs Android / iOS）
class AppPlatform {
  AppPlatform._();

  /// 是否运行在桌面操作系统（Windows / macOS / Linux）
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// 是否运行在移动操作系统（Android / iOS）
  static bool get isMobile =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 是否为 Web 环境
  static bool get isWeb => kIsWeb;
}

/// 全局多端响应式断点与布局工具：
/// 1. 严格参照 Flutter 与 Material 3 Adaptive 规范体系；
/// 2. compact: < 600（手机竖屏，紧凑单栏流）；
/// 3. medium: 600 ~ 839（大折叠屏、平板竖屏，过渡形态）；
/// 4. expanded: >= 840（平板横屏、PC/桌面端、大屏显示器，宽屏分栏/矩阵形态）；
/// 5. 统一网格跨轴阶梯列数计算（<500: 3, <750: 4, <1000: 5, >=1000: 6）。
class AppBreakpoints {
  AppBreakpoints._();

  /// 紧凑与中等屏幕分界（手机 vs 平板竖屏/折叠屏）
  static const double compact = 600.0;

  /// 宽屏与桌面端分界（平板横屏 / 桌面端）
  static const double medium = 840.0;

  /// 全局大屏主要内容流最大限制宽度
  static const double maxContentWidth = 1200.0;

  /// 桌面端 Hero 大屏横幅展示的最佳视觉限制宽度（防止超宽带鱼屏下海报严重扁平变形）
  static const double maxHeroWidth = 1440.0;

  /// 设置页等列表型页面在大屏上的收拢宽度
  static const double maxSettingsWidth = 800.0;

  /// 居中详情模态弹窗的最大宽度
  static const double maxDialogWidth = 560.0;

  /// 统一计算动漫卡片网格阶梯列数：
  /// - width < 500: 3 列（移动端标准）
  /// - width < 750: 4 列（小平板/折叠屏）
  /// - width < 1000: 5 列（平板横屏/中等窗口）
  /// - width >= 1000: 6 列（桌面大屏）
  static int gridColumns(double width) {
    if (width < 500) return 3;
    if (width < 750) return 4;
    if (width < 1000) return 5;
    return 6;
  }

  /// 计算分类/搜索等网格瀑布流在不同端型下的最优单次分页拉取数量：
  /// - 手机端 (<600): 12 部 (3列 x 4行整除，轻量省流响应快)
  /// - 平板端 (600 ~ 839): 20 部 (4列 x 5行 或 5列 x 4行，公倍数整除不破排)
  /// - 桌面端 (>=840): 24 部 (6列 x 4行整除，铺满大屏视口)
  static int responsivePageSize(double width) {
    if (width < compact) return 12;
    if (width < medium) return 20;
    return 24;
  }
}

/// 响应式 Context 扩展，方便在 Widget 中快速获取断点状态
extension ResponsiveContext on BuildContext {
  /// 屏幕宽度
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// 屏幕高度
  double get screenHeight => MediaQuery.sizeOf(this).height;

  /// 是否为宽屏/桌面端布局（>= 840dp）
  bool get isDesktop => screenWidth >= AppBreakpoints.medium;

  /// 是否为小屏紧凑模式（< 600dp）
  bool get isCompact => screenWidth < AppBreakpoints.compact;

  /// 是否为中等平板模式（600dp ~ 839dp）
  bool get isMedium =>
      screenWidth >= AppBreakpoints.compact && screenWidth < AppBreakpoints.medium;
}
