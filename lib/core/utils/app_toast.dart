import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'font_manager.dart';

/// 全局统一应用通知反馈门面 (iOS / HUD 风格深邃微晶亚克力悬浮胶囊)
///
/// 特殊处理说明：
/// 1. 统一管理全工程所有轻量级提示（成功、错误、警告、常规），彻底终结零散手写 SnackBar 导致的样式割裂；
/// 2. 内部强制触发 clearSnackBars()，防止用户连续操作时消息在队列中长时间堆叠延迟；
/// 3. 采用深邃高透微晶亚克力材质（BackdropFilter 28px 强漫反射 + 60% 半透明晶透底板 + 微白高光描边），
///    在浅色页面、深色页面或彩色壁纸/视频上方均能呈现通透纯净的水晶悬浮质感，杜绝死黑生硬感；
/// 4. 严格注入 FontManager 字体回退链，严防 Windows DirectWrite 跌入中易宋体 (SimSun)；
/// 5. 桌面端自适应最大宽度 420px 居中收拢，移动端保持标准双侧间距；
/// 6. 提供全局静态 scaffoldMessengerKey，支持无 context 或在 Sheet/Dialog 内部跨层级唤起。
class AppToast {
  AppToast._();

  /// 全局根脚手架消息控制器 Key，供 MaterialApp 注入
  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// 成功类通知（翡翠绿勾选指示）
  static void success(
    String message, {
    BuildContext? context,
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    HapticFeedback.lightImpact();
    _show(
      message: message,
      context: context,
      icon: Icons.check_circle_rounded,
      iconColor: const Color(0xFF30D158),
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// 错误与异常类通知（珊瑚红感叹号指示，停留时间稍长）
  static void error(
    String message, {
    BuildContext? context,
    Duration duration = const Duration(milliseconds: 2800),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    HapticFeedback.heavyImpact();
    _show(
      message: message,
      context: context,
      icon: Icons.error_rounded,
      iconColor: const Color(0xFFFF453A),
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// 警告与提示类通知（琥珀橙警告指示）
  static void warning(
    String message, {
    BuildContext? context,
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    HapticFeedback.mediumImpact();
    _show(
      message: message,
      context: context,
      icon: Icons.warning_amber_rounded,
      iconColor: const Color(0xFFFF9F0A),
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// 常规信息通知（宝石蓝/主题信息指示）
  static void info(
    String message, {
    BuildContext? context,
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    HapticFeedback.selectionClick();
    _show(
      message: message,
      context: context,
      icon: Icons.info_outline_rounded,
      iconColor: const Color(0xFF0A84FF),
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// 基础展示底层调度方法
  static void _show({
    required String message,
    BuildContext? context,
    required IconData icon,
    required Color iconColor,
    required Duration duration,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    ScaffoldMessengerState? messenger;
    if (context != null && context.mounted) {
      try {
        messenger = ScaffoldMessenger.maybeOf(context);
      } catch (_) {
        // context 处于卸载或异常阶段时平滑回退至全局 Key
      }
    }
    messenger ??= scaffoldMessengerKey.currentState;
    if (messenger == null) return;

    // 1. 防排队：先立即清理掉当前或排队中的旧通知
    messenger.clearSnackBars();

    // 2. 获取防宋体字体安全链
    final activeFont = FontManager.instance.activeFontFamily;
    const fontFallback = FontManager.fallbackFontFamilies;

    // 3. 构建高质感深邃微晶亚克力悬浮胶囊
    final snackBar = SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      duration: duration,
      margin: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
      padding: EdgeInsets.zero,
      content: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              messenger?.hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  // 60% 高透微晶基底，让底层色彩与壁纸产生柔美漫反射光晕
                  color: const Color(0x99101018),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.20),
                    width: 0.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.32),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                      spreadRadius: -2,
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: iconColor,
                    ),
                    const SizedBox(width: 11),
                    Flexible(
                      child: Text(
                        message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                          height: 1.35,
                          fontFamily: activeFont,
                          fontFamilyFallback: fontFallback,
                        ),
                      ),
                    ),
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          foregroundColor: iconColor,
                        ),
                        onPressed: () {
                          scaffoldMessengerKey.currentState?.hideCurrentSnackBar();
                          onAction();
                        },
                        child: Text(
                          actionLabel,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            fontFamily: activeFont,
                            fontFamilyFallback: fontFallback,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  messenger.showSnackBar(snackBar);
  }
}
