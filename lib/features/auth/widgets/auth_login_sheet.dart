import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/models/auth_credentials.dart';
import '../../../core/auth/models/auth_provider_type.dart';
import '../../../core/auth/providers/auth_providers.dart';
import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/font_manager.dart';
import '../../../core/utils/responsive.dart';
import '../../common/widgets/bouncing_scale_card.dart';

/// 统一登录与账号绑定面板：
/// 1. 响应式形态：大屏/桌面端居中模态卡片 (Dialog 420dp)，移动端平滑底部抽屉 (BottomSheet)；
/// 2. 多源提供商切换：当前激活 Bangumi 访问令牌，预留 Zakoway 官方账号入口；
/// 3. 内置获取 Token 引导卡片与一键复制申请链接；
/// 4. 支持系统剪贴板一键粘贴，实时去除首尾空白；
/// 5. 严格注入安全字体链，防止 Windows DirectWrite 跌入中易宋体。
class AuthLoginSheet extends ConsumerStatefulWidget {
  const AuthLoginSheet({super.key});

  /// 自适应多端拉起登录面板
  static Future<bool?> show(BuildContext context) {
    final isCompact = context.screenWidth < AppBreakpoints.compact;

    if (isCompact) {
      return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const AuthLoginSheet(),
      );
    } else {
      return showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (_) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: const Material(
              color: Colors.transparent,
              child: AuthLoginSheet(),
            ),
          ),
        ),
      );
    }
  }

  @override
  ConsumerState<AuthLoginSheet> createState() => _AuthLoginSheetState();
}

class _AuthLoginSheetState extends ConsumerState<AuthLoginSheet> {
  final TextEditingController _tokenController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  AuthProviderType _selectedProvider = AuthProviderType.bangumi;
  bool _isVerifying = false;
  String? _errorMessage;

  @override
  void dispose() {
    _tokenController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  TextStyle _safeStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: FontManager.instance.activeFontFamily,
      fontFamilyFallback: FontManager.fallbackFontFamilies,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  Future<void> _handlePaste() async {
    HapticFeedback.lightImpact();
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isNotEmpty) {
      setState(() {
        _tokenController.text = text;
        _errorMessage = null;
      });
      _focusNode.requestFocus();
    } else {
      _showToast('剪贴板中未检测到文本');
    }
  }

  Future<void> _copyDevUrl() async {
    HapticFeedback.lightImpact();
    const url = 'https://next.bgm.tv/demo/access-token';
    await Clipboard.setData(const ClipboardData(text: url));
    _showToast('已复制获取网址: $url');
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: _safeStyle(fontSize: 13, color: Colors.white),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _errorMessage = '请输入或粘贴 Bangumi Access Token';
      });
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    final notifier = ref.read(authControllerProvider.notifier);
    final success = await notifier.login(BangumiTokenCredentials(token));

    if (!mounted) return;

    if (success) {
      HapticFeedback.mediumImpact();
      _showToast('登录成功！已连接 Bangumi 账号 ( ╹▽╹ )');
      Navigator.of(context).pop(true);
    } else {
      HapticFeedback.heavyImpact();
      final err = ref.read(authControllerProvider).error;
      setState(() {
        _isVerifying = false;
        _errorMessage = err ?? '验证失败，请检查令牌是否正确或网络连通性';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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

    final cardBg = isDark
        ? const Color(0xFF1E1E22)
        : Colors.white.withValues(alpha: 0.96);

    return Container(
      margin: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部滑动条 (在移动端提示可拖拽)
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // 标题与说明
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '连接账号',
                        style: _safeStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '连接第三方或自有账号，开启云端同步与追番状态管理',
                        style: _safeStyle(
                          fontSize: 12.5,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: Icon(
                    Icons.close_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 登录源选择器 (当前支持 Bangumi，预留 Zakoway)
            Row(
              children: [
                // 1. Bangumi 令牌
                Expanded(
                  child: _ProviderTab(
                    label: 'Bangumi 令牌',
                    icon: Icons.key_rounded,
                    isActive: _selectedProvider == AuthProviderType.bangumi,
                    onTap: () {
                      setState(() {
                        _selectedProvider = AuthProviderType.bangumi;
                        _errorMessage = null;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),

                // 2. Zakoway 官方系统 (预留态，直观体现系统兼容扩展性)
                Expanded(
                  child: _ProviderTab(
                    label: 'Zakoway 账号',
                    icon: Icons.hub_rounded,
                    badge: '开发中',
                    isActive: _selectedProvider == AuthProviderType.zakoway,
                    isDisabled: true,
                    onTap: () {
                      _showToast('Zakoway 自建账号服务正在研发中，敬请期待！');
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 输入框卡片
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _errorMessage != null
                      ? theme.colorScheme.error
                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 1.0,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.vpn_key_outlined,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _tokenController,
                      focusNode: _focusNode,
                      style: _safeStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: '粘贴你的 Bangumi Access Token...',
                        hintStyle: _safeStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (_) {
                        if (_errorMessage != null) {
                          setState(() => _errorMessage = null);
                        }
                      },
                    ),
                  ),
                  // 一键粘贴 / 清空按钮
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _tokenController,
                    builder: (context, value, _) {
                      if (value.text.isNotEmpty) {
                        return IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          onPressed: () {
                            _tokenController.clear();
                            setState(() => _errorMessage = null);
                          },
                        );
                      }
                      return TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _handlePaste,
                        icon: const Icon(Icons.content_paste_rounded, size: 14),
                        label: Text(
                          '一键粘贴',
                          style: _safeStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // 错误提示提示条
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 16,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: _safeStyle(
                          fontSize: 12,
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),

            // 获取指南提示框 (大幅降低用户操作门槛)
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.lightbulb_outline_rounded, size: 16, color: Colors.amber),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '如何获取 Bangumi Access Token？',
                          style: _safeStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '1. 在浏览器登录 bgm.tv 后访问令牌生成页面；\n'
                    '2. 点击按钮生成个人访问令牌 (Access Token)；\n'
                    '3. 复制生成的密钥并粘贴至上方输入框即可。',
                    style: _safeStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 8),
                  BouncingScaleCard(
                    scaleDown: 0.95,
                    immediateTap: true,
                    onTap: _copyDevUrl,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.copy_rounded,
                            size: 13,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '一键复制 Token 获取网址',
                              style: _safeStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 提交主按钮
            BouncingScaleCard(
              scaleDown: 0.97,
              immediateTap: true,
              onTap: _isVerifying ? null : _handleSubmit,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: _isVerifying
                      ? theme.colorScheme.primary.withValues(alpha: 0.6)
                      : theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.28),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Center(
                  child: _isVerifying
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '正在连接服务器验证...',
                              style: _safeStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          '立即验证并连接',
                          style: _safeStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 登录提供商选择 Tab 组件
class _ProviderTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? badge;
  final bool isActive;
  final bool isDisabled;
  final VoidCallback onTap;

  const _ProviderTab({
    required this.label,
    required this.icon,
    this.badge,
    this.isActive = false,
    this.isDisabled = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontMgr = FontManager.instance;

    final bgColor = isActive
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.8)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);

    final borderColor = isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant.withValues(alpha: 0.2);

    final textColor = isDisabled
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45)
        : (isActive
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface);

    return BouncingScaleCard(
      scaleDown: 0.96,
      immediateTap: true,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: isActive ? 1.5 : 1.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: textColor,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: fontMgr.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  fontSize: 12.5,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (badge != null) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge!,
                  style: TextStyle(
                    fontFamily: fontMgr.activeFontFamily,
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                    fontSize: 9,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
