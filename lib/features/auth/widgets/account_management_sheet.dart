import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/models/auth_user.dart';
import '../../../core/auth/providers/auth_providers.dart';
import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/font_manager.dart';
import '../../../core/utils/responsive.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import 'auth_login_sheet.dart';

/// 已登录账号管理与详情抽屉：
/// 1. 展示当前登录账号详细资料（大头像、昵称、UID、个性签名、连接状态）；
/// 2. 提供快捷操作：刷新个人资料、更新 Token、退出登录；
/// 3. 严格遵循 Windows 平台字体保护规范，杜绝 DirectWrite 宋体降级。
class AccountManagementSheet extends ConsumerStatefulWidget {
  final AuthUser user;

  const AccountManagementSheet({super.key, required this.user});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _AccountManagementDialogWrapper(),
    );
  }

  @override
  ConsumerState<AccountManagementSheet> createState() =>
      _AccountManagementSheetState();
}

class _AccountManagementDialogWrapper extends ConsumerWidget {
  const _AccountManagementDialogWrapper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isCompact = context.screenWidth < AppBreakpoints.compact;

    if (isCompact) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            color: Colors.transparent,
            child: AccountManagementSheet(user: user),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: Colors.transparent,
          child: AccountManagementSheet(user: user),
        ),
      ),
    );
  }
}

class _AccountManagementSheetState
    extends ConsumerState<AccountManagementSheet> {
  bool _isRefreshing = false;

  TextStyle _safeStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
    FontStyle? fontStyle,
  }) {
    return TextStyle(
      fontFamily: FontManager.instance.activeFontFamily,
      fontFamilyFallback: FontManager.fallbackFontFamilies,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontStyle: fontStyle,
    );
  }

  Future<void> _handleRefresh() async {
    HapticFeedback.lightImpact();
    setState(() => _isRefreshing = true);
    await ref.read(authControllerProvider.notifier).refreshUserInfo();
    if (!mounted) return;
    setState(() => _isRefreshing = false);
    AppToast.success('个人信息已更新 ( ╹▽╹ )', context: context);
  }

  Future<void> _handleLogout() async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '退出当前账号？',
          style: _safeStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '退出后将断开与当前 Bangumi 账号的连接，并回退至设备游客模式。',
          style: _safeStyle(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('取消', style: _safeStyle(color: Colors.grey)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('退出登录', style: _safeStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(authControllerProvider.notifier).logout();
      if (!mounted) return;
      Navigator.of(context).pop();
      AppToast.info('已安全退出，当前已恢复为游客模式', context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final user = widget.user;

    final containerColor = M3Surface.container(
      context,
      level: M3ContainerLevel.high,
      pageKey: 'settings',
    );
    final borderColor = M3Surface.border(
      context,
      pageKey: 'settings',
      forceBorder: true,
    );

    final avatarBg = isDark
        ? theme.colorScheme.surfaceContainerHigh
        : Colors.white;

    final rawUid = user.id.replaceFirst('bgm_', '');

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(24),
        border: borderColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头部：关闭按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '账号详情与服务',
                style: _safeStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(
                  Icons.close_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 用户身份核心卡片
          Center(
            child: Column(
              children: [
                // 1. 头像（带 BGM 角标）
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: avatarBg,
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: user.avatarUrl!,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Center(
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 36,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                                errorWidget: (context, url, error) => Center(
                                  child: Icon(
                                    Icons.person_rounded,
                                    size: 36,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.person_rounded,
                                size: 36,
                                color: theme.colorScheme.primary,
                              ),
                      ),
                    ),
                    // 平台胶囊标 (BGM)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF06292),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          'BGM',
                          style: _safeStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 2. 昵称
                Text(
                  user.nickname,
                  style: _safeStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),

                // 3. 用户名与 UID
                Text(
                  '@${user.username ?? ''} · UID: $rawUid',
                  style: _safeStyle(
                    fontSize: 12.5,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                ),

                // 4. 个性签名（若有）
                if (user.sign != null && user.sign!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      user.sign!,
                      style: _safeStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 22),

          // 操作按钮组
          Row(
            children: [
              // 1. 刷新资料
              Expanded(
                child: BouncingScaleCard(
                  scaleDown: 0.96,
                  immediateTap: true,
                  onTap: _isRefreshing ? null : _handleRefresh,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Center(
                      child: _isRefreshing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  size: 16,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '刷新资料',
                                  style: _safeStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // 2. 更新 Token
              Expanded(
                child: BouncingScaleCard(
                  scaleDown: 0.96,
                  immediateTap: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    AuthLoginSheet.show(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.key_rounded,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '更换令牌',
                            style: _safeStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3. 退出登录红字按钮
          BouncingScaleCard(
            scaleDown: 0.98,
            immediateTap: true,
            onTap: _handleLogout,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.2),
                ),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '退出登录并恢复游客',
                      style: _safeStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
