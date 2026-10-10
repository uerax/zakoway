import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/adaptive_page_route.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import '../../history/pages/history_page.dart';

/// 个人中心核心快捷控制栏（1:1 参考截图规范）：
/// 包含 4 个等分弹性胶囊按钮：
/// 1. 观看历史 (浅蓝) - 点击直达播放历史时间轴
/// 2. 我的追番 (浅粉) - 追番进度与收藏入口
/// 3. 离线缓存 (浅绿) - 离线下载与本地缓存管理
/// 4. 交流吹水 (浅青) - 社区与交流反馈入口
class UserActionControlBar extends StatelessWidget {
  final VoidCallback? onHistoryTap;
  final VoidCallback? onCollectionTap;
  final VoidCallback? onDownloadTap;
  final VoidCallback? onCommunityTap;

  const UserActionControlBar({
    super.key,
    this.onHistoryTap,
    this.onCollectionTap,
    this.onDownloadTap,
    this.onCommunityTap,
  });

  void _showTip(BuildContext context, String message) {
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(
            fontFamily: FontManager.instance.activeFontFamily,
            fontFamilyFallback: FontManager.fallbackFontFamilies,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final containerColor = M3Surface.container(
      context,
      level: M3ContainerLevel.low,
      pageKey: 'settings',
    );
    final border = M3Surface.border(
      context,
      pageKey: 'settings',
      forceBorder: true,
    );

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(22),
        border: border,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      child: Row(
        children: [
          // 1. 观看历史
          Expanded(
            child: _ActionItem(
              title: '观看历史',
              icon: Icons.history_rounded,
              bgColor: isDark
                  ? const Color(0xFF1565C0).withValues(alpha: 0.28)
                  : const Color(0xFFE3F2FD),
              iconColor: isDark
                  ? const Color(0xFF64B5F6)
                  : const Color(0xFF1976D2),
              onTap: onHistoryTap ??
                  () {
                    Navigator.of(context).push(
                      AdaptivePageRoute.build<void>(
                        context,
                        builder: (_) => const HistoryPage(),
                      ),
                    );
                  },
            ),
          ),

          // 2. 我的追番
          Expanded(
            child: _ActionItem(
              title: '我的追番',
              icon: Icons.favorite_rounded,
              bgColor: isDark
                  ? const Color(0xFFC2185B).withValues(alpha: 0.28)
                  : const Color(0xFFFCE4EC),
              iconColor: isDark
                  ? const Color(0xFFF48FB1)
                  : const Color(0xFFE91E63),
              onTap: onCollectionTap ??
                  () => _showTip(context, '登录后即可同步追番进度 ( ╹▽╹ )'),
            ),
          ),

          // 3. 离线缓存
          Expanded(
            child: _ActionItem(
              title: '离线缓存',
              icon: Icons.download_rounded,
              bgColor: isDark
                  ? const Color(0xFF2E7D32).withValues(alpha: 0.28)
                  : const Color(0xFFE8F5E9),
              iconColor: isDark
                  ? const Color(0xFF81C784)
                  : const Color(0xFF388E3C),
              onTap: onDownloadTap ??
                  () => _showTip(context, '暂无离线缓存任务'),
            ),
          ),

          // 4. 交流吹水
          Expanded(
            child: _ActionItem(
              title: '交流吹水',
              icon: Icons.groups_rounded,
              bgColor: isDark
                  ? const Color(0xFF00838F).withValues(alpha: 0.28)
                  : const Color(0xFFE0F7FA),
              iconColor: isDark
                  ? const Color(0xFF4DD0E1)
                  : const Color(0xFF00838F),
              onTap: onCommunityTap ??
                  () => _showTip(context, '交流社区建设中，欢迎在 GitHub 提交反馈~'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color bgColor;
  final Color iconColor;
  final VoidCallback onTap;

  const _ActionItem({
    required this.title,
    required this.icon,
    required this.bgColor,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontMgr = FontManager.instance;

    return BouncingScaleCard(
      scaleDown: 0.92,
      immediateTap: true,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 彩色微圆底图标
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
            ),
            child: Center(
              child: Icon(
                icon,
                color: iconColor,
                size: 24,
              ),
            ),
          ),
          const SizedBox(height: 7),

          // 底部粗体标题文字（带 Windows 字体保护）
          Text(
            title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              letterSpacing: -0.2,
              fontFamily: fontMgr.activeFontFamily,
              fontFamilyFallback: FontManager.fallbackFontFamilies,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.90),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
