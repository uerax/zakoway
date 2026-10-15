import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/utils/font_manager.dart';
import '../video_play_tabs.dart';

/// 桌面端/宽屏分栏并排布局
///
/// 架构设计与空间分配规范：
/// 1. 沉浸式无顶栏：彻底去除顶部 AppBar 与播放器内重复的返回键与标题，把画面空间完全交还给视频；
/// 2. 左下角微光悬浮返回：在窗口左下角常驻半透明圆圈按钮，平时虚化融入背景，鼠标 hover/focus 时实体化高亮；
/// 3. 左栏（主内容区）：等比 16:9 播放器 -> 简介（正下方） -> 吐槽评论（简介正下方）流式排列；
/// 4. 右栏（控制与发现轨）：[选集 | 视频源] 胶囊控制器 -> Tab 0 选集面板与推荐 / Tab 1 原版完整视频源看板；
/// 5. 双栏独立滚动：左侧看剧评、右侧选集换源，互不影响；
/// 6. 黄金比例自适应：侧边轨锁定为 clamp(306, 19.55vw, 357px)，充分利用 1080P/2K/4K 视口。
class DesktopVideoPlayerLayout extends StatelessWidget {
  const DesktopVideoPlayerLayout({
    super.key,
    required this.title,
    this.currentEpisode,
    required this.onBackPressed,
    required this.playerWidget,
    this.tabSection,
    this.introSection,
    this.commentsSection,
    this.rightTabController,
    this.episodePickerSection,
    this.sourceViewSection,
    this.recommendSection,
  });

  final String title;
  final int? currentEpisode;
  final VoidCallback onBackPressed;
  final Widget playerWidget;
  final Widget? tabSection;
  final Widget? introSection;
  final Widget? commentsSection;
  final TabController? rightTabController;
  final Widget? episodePickerSection;
  final Widget? sourceViewSection;
  final Widget? recommendSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    // 优先采用全新分块设计的桌面端布局
    final isNewDesktopDesign = introSection != null;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;

          // 桌面端右侧控制模块宽度按要求在黄金宽度基准上削减 15% (x 0.85)：
          // 由原 clamp(360.0, 23vw, 420.0) 调整为 clamp(306.0, 19.55vw, 357.0)
          final railWidth = (totalWidth * 0.23).clamp(360.0, 420.0) * 0.85;

          final Widget mainContent;

          // 1. 全新桌面端分块布局（左右顶格水平对齐）
          if (isNewDesktopDesign) {
            mainContent = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 左侧主内容区：播放器 -> 简介（正下方） -> 吐槽评论（简介正下方）
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 16:9 播放器卡片
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withValues(
                                      alpha: isDark ? 0.22 : 0.12),
                                  blurRadius: 28,
                                  spreadRadius: -2,
                                  offset: const Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(
                                      alpha: isDark ? 0.35 : 0.15),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              clipBehavior: Clip.antiAliasWithSaveLayer,
                              child: playerWidget,
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // 简介（正位于播放器正下方）
                        ?introSection,

                        if (commentsSection != null) ...[
                          const SizedBox(height: 12),
                          // 评论（正位于简介下方）
                          commentsSection!,
                        ],
                      ],
                    ),
                  ),
                ),

                // 右侧控制轨：[选集 | 视频源] 胶囊切换栏 -> Tab 0 选集+推荐 / Tab 1 原版视频源看板
                SizedBox(
                  width: railWidth,
                  child: rightTabController != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 顶部 [选集 | 视频源] 极简滑动胶囊分段控制器 (与移动端同款)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 16.0, 16.0, 8.0),
                              child: VideoPlaySegmentedTabBar(
                                tabController: rightTabController!,
                                tabs: const ['选集', '视频源'],
                                maxWidth: 220,
                              ),
                            ),
                            // 标签页内容呈现区 (独立滚动)
                            Expanded(
                              child: TabBarView(
                                controller: rightTabController!,
                                children: [
                                  // Tab 0: 选集面板与番剧推荐
                                  SingleChildScrollView(
                                    padding: const EdgeInsets.fromLTRB(0, 0, 16.0, 24.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        ?episodePickerSection,
                                        if (recommendSection != null) ...[
                                          const SizedBox(height: 12),
                                          recommendSection!,
                                        ],
                                      ],
                                    ),
                                  ),
                                  // Tab 1: 原版完整视频源看板
                                  Padding(
                                    padding: const EdgeInsets.only(right: 16.0),
                                    child: sourceViewSection ?? const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(0, 16.0, 16.0, 24.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ?episodePickerSection,
                              if (recommendSection != null) ...[
                                const SizedBox(height: 12),
                                recommendSection!,
                              ],
                            ],
                          ),
                        ),
                ),
              ],
            );
          } else {
            // 2. 兼容旧版单一 tabSection 的降级分支
            mainContent = Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: LayoutBuilder(
                      builder: (context, playerBoxConstraints) {
                        final availableW = playerBoxConstraints.maxWidth;
                        final availableH = playerBoxConstraints.maxHeight;
                        if (availableW <= 0 || availableH <= 0) {
                          return const SizedBox.shrink();
                        }

                        double targetW = availableW;
                        double targetH = targetW / (16 / 9);
                        if (targetH > availableH) {
                          targetH = availableH;
                          targetW = targetH * (16 / 9);
                        }

                        return Align(
                          alignment: Alignment.topCenter,
                          child: SizedBox(
                            width: targetW,
                            height: targetH,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: primaryColor.withValues(
                                        alpha: isDark ? 0.22 : 0.12),
                                    blurRadius: 28,
                                    spreadRadius: -2,
                                    offset: const Offset(0, 8),
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                        alpha: isDark ? 0.35 : 0.15),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                clipBehavior: Clip.antiAliasWithSaveLayer,
                                child: playerWidget,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                if (tabSection != null)
                  SizedBox(
                    width: railWidth,
                    child: tabSection!,
                  ),
              ],
            );
          }

          return Stack(
            children: [
              mainContent,
              // 左下角半透明悬浮返回圆圈按钮（平时虚化，鼠标 hover/focus 时实体化）
              Positioned(
                left: 24,
                bottom: 24,
                child: DesktopFloatingBackButton(
                  onPressed: onBackPressed,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 桌面端左下角悬浮半透明微光返回圆圈按钮
///
/// 特性与规范：
/// 1. 平时虚化：半透明磨砂（opacity 0.38），微弱融入页面背景，完全不抢视觉、不干扰阅读与观影；
/// 2. 悬停/聚焦实体化：鼠标 hover 或键盘 focus 时立即实体化（opacity 1.0, 实体背景+微光阴影+微动效）；
/// 3. 严格遵循 Windows 字体保护规范（注入 fontFamily 与 fontFamilyFallback，杜绝宋体）；
/// 4. 独立于左栏与右栏滚动容器，无论内容如何滚动，左下角随时可退出。
class DesktopFloatingBackButton extends StatefulWidget {
  const DesktopFloatingBackButton({
    super.key,
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  State<DesktopFloatingBackButton> createState() =>
      _DesktopFloatingBackButtonState();
}

class _DesktopFloatingBackButtonState extends State<DesktopFloatingBackButton> {
  bool _isHovered = false;
  bool _isFocused = false;

  bool get _isActive => _isHovered || _isFocused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Focus(
        onFocusChange: (focused) => setState(() => _isFocused = focused),
        child: Tooltip(
          message: '返回 (Esc)',
          textStyle: const TextStyle(
            fontSize: 12,
            color: Colors.white,
            fontFamily: 'MiSans',
            fontFamilyFallback: FontManager.fallbackFontFamilies,
          ),
          waitDuration: const Duration(milliseconds: 300),
          child: AnimatedScale(
            scale: _isActive ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: AnimatedOpacity(
              opacity: _isActive ? 1.0 : 0.38,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isActive
                          ? (isDark
                              ? const Color(0xFF202026).withValues(alpha: 0.92)
                              : Colors.white.withValues(alpha: 0.94))
                          : (isDark
                              ? Colors.black.withValues(alpha: 0.35)
                              : Colors.black.withValues(alpha: 0.18)),
                      border: Border.all(
                        color: _isActive
                            ? primaryColor.withValues(alpha: 0.65)
                            : (isDark
                                ? Colors.white.withValues(alpha: 0.16)
                                : Colors.black.withValues(alpha: 0.10)),
                        width: _isActive ? 1.2 : 0.8,
                      ),
                      boxShadow: _isActive
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(
                                    alpha: isDark ? 0.45 : 0.18),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                              BoxShadow(
                                color: primaryColor.withValues(
                                    alpha: isDark ? 0.30 : 0.20),
                                blurRadius: 10,
                              ),
                            ]
                          : const [],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(22),
                        onTap: widget.onPressed,
                        child: Center(
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: _isActive
                                ? (isDark ? Colors.white : Colors.black87)
                                : (isDark ? Colors.white70 : Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
