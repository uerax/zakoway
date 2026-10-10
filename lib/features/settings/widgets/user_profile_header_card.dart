import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/app_preferences.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/bouncing_scale_card.dart';

/// 个人中心顶部用户身份卡片（单行水平并排居中规范）：
/// 1. 头像与 ID 同行横向排布（Row 布局），整体水平居中对称；
/// 2. 展示格式：“杂鱼<设备专属机器code>”，标识游客的唯一本地机器码；
/// 3. 配备精致多层立体高斯漫反射阴影，严防 Windows DirectWrite 跌入中易宋体。
class UserProfileHeaderCard extends StatelessWidget {
  final VoidCallback? onProfileTap;

  const UserProfileHeaderCard({
    super.key,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fontMgr = FontManager.instance;

    // 安全字体配置
    final effectiveFontFamily = fontMgr.activeFontFamily;
    const fallbackFonts = FontManager.fallbackFontFamilies;

    final avatarBg = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : Colors.white;

    // 获取当前设备唯一游客机器码
    final guestCode = AppPreferences.getGuestMachineCode();

    return BouncingScaleCard(
      scaleDown: 0.98,
      immediateTap: true,
      onTap: () {
        HapticFeedback.lightImpact();
        if (onProfileTap != null) {
          onProfileTap!();
        } else {
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '登录功能开发中，敬请期待 ( ╹▽╹ )',
                style: TextStyle(
                  fontFamily: effectiveFontFamily,
                  fontFamilyFallback: fallbackFonts,
                ),
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. 头像（58x58dp 适中体量 + 双层立体高斯漫反射阴影）
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: avatarBg,
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                    width: 1.0,
                  ),
                  boxShadow: [
                    // 主环境漫反射柔光阴影
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.36 : 0.08),
                      blurRadius: 18,
                      offset: const Offset(0, 5),
                      spreadRadius: 1,
                    ),
                    // 近场发丝微景深阴影
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 30,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // 2. 单行大字 ID（杂鱼<机器code>）
              Text(
                '杂鱼$guestCode',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: -0.2,
                  fontFamily: effectiveFontFamily,
                  fontFamilyFallback: fallbackFonts,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
