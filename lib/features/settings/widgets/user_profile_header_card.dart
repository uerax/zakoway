import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/providers/auth_providers.dart';
import '../../../core/utils/font_manager.dart';
import '../../auth/widgets/account_management_sheet.dart';
import '../../auth/widgets/auth_login_sheet.dart';
import '../../common/widgets/bouncing_scale_card.dart';

/// 个人中心顶部用户身份卡片：
/// 1. 游客态：单行水平并排居中“杂鱼<机器code>”，提示点击登录 Bangumi；
/// 2. 已登录态：呈现网络大头像 + BGM平台徽章 + 昵称与UID，点击呼出账号管理与服务；
/// 3. 配备精致多层立体高斯漫反射阴影，严格注入安全字体链防宋体回退。
class UserProfileHeaderCard extends ConsumerWidget {
  final VoidCallback? onProfileTap;

  const UserProfileHeaderCard({
    super.key,
    this.onProfileTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fontMgr = FontManager.instance;

    // 安全字体配置
    final effectiveFontFamily = fontMgr.activeFontFamily;
    const fallbackFonts = FontManager.fallbackFontFamilies;

    final avatarBg = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : Colors.white;

    // 从全局 Riverpod 读取当前用户领域实体
    final currentUser = ref.watch(currentUserProvider);
    final isGuest = currentUser.isGuest;

    return BouncingScaleCard(
      scaleDown: 0.98,
      immediateTap: true,
      onTap: () {
        HapticFeedback.lightImpact();
        if (onProfileTap != null) {
          onProfileTap!();
        } else {
          if (isGuest) {
            AuthLoginSheet.show(context);
          } else {
            AccountManagementSheet.show(context);
          }
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
              Stack(
                clipBehavior: Clip.none,
                children: [
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
                    child: ClipOval(
                      child: (!isGuest &&
                              currentUser.avatarUrl != null &&
                              currentUser.avatarUrl!.isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: currentUser.avatarUrl!,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Center(
                                child: Icon(
                                  Icons.person_rounded,
                                  size: 30,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              errorWidget: (context, url, error) => Center(
                                child: Icon(
                                  Icons.person_outline_rounded,
                                  size: 30,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.85),
                                ),
                              ),
                            )
                          : Center(
                              child: Icon(
                                Icons.person_outline_rounded,
                                size: 30,
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.85),
                              ),
                            ),
                    ),
                  ),
                  // 已连接 Bangumi 标识徽章
                  if (!isGuest)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF06292),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: Text(
                          'BGM',
                          style: TextStyle(
                            fontFamily: effectiveFontFamily,
                            fontFamilyFallback: fallbackFonts,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),

              // 2. 文字区域
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 主标题：昵称
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            currentUser.nickname,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 21,
                              letterSpacing: -0.2,
                              fontFamily: effectiveFontFamily,
                              fontFamilyFallback: fallbackFonts,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!isGuest) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '已连接',
                              style: TextStyle(
                                fontFamily: effectiveFontFamily,
                                fontFamilyFallback: fallbackFonts,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),

                    // 副标题：游客引导或账号 UID
                    Text(
                      isGuest
                          ? '点击登录'
                          : '@${currentUser.username ?? ''} · UID: ${currentUser.id.replaceFirst('bgm_', '')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        fontFamily: effectiveFontFamily,
                        fontFamilyFallback: fallbackFonts,
                        color: isGuest
                            ? theme.colorScheme.primary.withValues(alpha: 0.9)
                            : theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.75),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
