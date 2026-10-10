import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/bouncing_scale_card.dart';

/// 个人中心顶部用户身份卡片（垂直居中对称排版规范）：
/// 1. 顶部 64dp 圆形用户头像居中呈现（适中体量 + 双层立体高斯漫反射阴影）；
/// 2. 下方文字全部水平居中对齐，彻底消除右侧空白不对称感；
/// 3. 严防 Windows DirectWrite 跌入中易宋体，显式注入系统安全字体回退链。
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 1. 居中：64x64 圆形用户头像（双层高漫反射立体阴影）
              Container(
                width: 64,
                height: 64,
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
                      color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                      spreadRadius: 1,
                    ),
                    // 近场发丝微景深阴影
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 34,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 2. 居中大字昵称
              Text(
                '杂口杂口',
                textAlign: TextAlign.center,
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
