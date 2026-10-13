import 'package:flutter/material.dart';
import '../../../../core/utils/font_manager.dart';
import '../video_play_tabs.dart';

/// 桌面端/宽屏分栏并排布局
///
/// 架构设计与空间分配规范：
/// 1. 顶部紧凑导航条：左对齐返回键与番剧标题及在播集数徽标，彻底告别居中大标题的笨拙与空旷；
/// 2. 左栏（主内容区）：等比 16:9 播放器 -> 简介（正下方） -> 吐槽评论（简介正下方）流式排列；
/// 3. 右栏（控制与发现轨）：[选集 | 视频源] 胶囊控制器 -> Tab 0 选集面板与推荐 / Tab 1 原版完整视频源看板；
/// 4. 双栏独立滚动：左侧看剧评、右侧选集换源，互不影响；
/// 5. 黄金比例自适应：侧边轨锁定为 clamp(306, 19.55vw, 357px)，充分利用 1080P/2K/4K 视口。
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

    final PreferredSizeWidget? appBar = isNewDesktopDesign
        ? null
        : AppBar(
            title: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
            ),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
              onPressed: onBackPressed,
            ),
          );

    return Scaffold(
      appBar: appBar,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;

          // 桌面端右侧控制模块宽度按要求在黄金宽度基准上削减 15% (x 0.85)：
          // 由原 clamp(360.0, 23vw, 420.0) 调整为 clamp(306.0, 19.55vw, 357.0)
          final railWidth = (totalWidth * 0.23).clamp(360.0, 420.0) * 0.85;

          // 1. 全新桌面端分块布局（左右顶格水平对齐）
          if (isNewDesktopDesign) {
            return Row(
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
          }

          // 2. 兼容旧版单一 tabSection 的降级分支
          return Row(
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
        },
      ),
    );
  }
}
