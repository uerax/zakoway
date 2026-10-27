import 'package:flutter/material.dart';
import '../../../common/widgets/desktop_floating_back_button.dart';
import '../../../common/widgets/directional_tab_bar_view.dart';
import '../video_play_tabs.dart';

export '../../../common/widgets/desktop_floating_back_button.dart';

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
    this.isTheaterMode = false,
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
  final bool isTheaterMode;

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

          // 1. 全新桌面端分块布局
          if (isNewDesktopDesign) {
            if (isTheaterMode) {
              // 方案 A 剧场模式：顶部全宽居中大屏播放器，下方双栏沉降（左简介/评论，右选集/换源）
              final maxPlayerH =
                  (constraints.maxHeight - 32.0).clamp(240.0, double.infinity) * 0.82;
              final maxPlayerW = totalWidth - 32.0;
              double targetW = maxPlayerW;
              double targetH = targetW / (16 / 9);
              if (targetH > maxPlayerH) {
                targetH = maxPlayerH;
                targetW = targetH * (16 / 9);
              }

              mainContent = SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 顶部居中 16:9 大屏播放器卡片
                    Center(
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
                    ),

                    const SizedBox(height: 16),

                    // 下方双栏沉降内容区（左侧简介+评论，右侧选集+换源/推荐）
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 左侧内容区：简介 + 吐槽评论
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ?introSection,
                              if (commentsSection != null) ...[
                                const SizedBox(height: 12),
                                commentsSection!,
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(width: 16),

                        // 右侧控制轨：选集 + 推荐 / 原版视频源看板
                        SizedBox(
                          width: railWidth,
                          child: rightTabController != null
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 胶囊分段切换栏
                                    VideoPlaySegmentedTabBar(
                                      tabController: rightTabController!,
                                      tabs: const ['选集', '视频源'],
                                      maxWidth: 220,
                                    ),
                                    const SizedBox(height: 8),
                                    ListenableBuilder(
                                      listenable: rightTabController!,
                                      builder: (context, _) {
                                        if (rightTabController!.index == 1) {
                                          return sourceViewSection ??
                                              const SizedBox.shrink();
                                        }
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            ?episodePickerSection,
                                            if (recommendSection != null) ...[
                                              const SizedBox(height: 12),
                                              recommendSection!,
                                            ],
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                )
                              : Column(
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
                      ],
                    ),
                  ],
                ),
              );
            } else {
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
                              child: DirectionalTabBarView(
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
              // 桌面主内容区（自动根据全局沉浸顶栏高度向下安全避让，绝不遮挡视频与选集）
              SafeArea(
                top: true,
                bottom: false,
                child: mainContent,
              ),
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

