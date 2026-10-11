import 'package:flutter/material.dart';
import '../../../core/utils/font_manager.dart';

/// 全屏横屏布局（全宽播放器 + 浮层侧边抽屉面板）
class VideoPlayerFullscreenLayout extends StatelessWidget {
  const VideoPlayerFullscreenLayout({
    super.key,
    required this.playerWidget,
    required this.sidePanelWidget,
  });

  final Widget playerWidget;
  final Widget sidePanelWidget;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: playerWidget,
        ),
        sidePanelWidget,
      ],
    );
  }
}

/// 桌面端/宽屏分栏并排布局（左侧 16:9 播放器卡片，右侧分段 Tab 栏）
class VideoPlayerDesktopLayout extends StatelessWidget {
  const VideoPlayerDesktopLayout({
    super.key,
    required this.title,
    required this.onBackPressed,
    required this.playerWidget,
    required this.tabSection,
  });

  final String title;
  final VoidCallback onBackPressed;
  final Widget playerWidget;
  final Widget tabSection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
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
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final totalWidth = constraints.maxWidth;

          // 特殊处理说明：
          // 参照 animaku (DesktopWatchLayout 与 --kz-watch-rail-w: clamp(360px, 23vw, 420px))：
          // 桌面端右侧控制模块（选集/源/详情）所需黄金宽度为 360~420px，
          // 严禁使用粗暴的百分比 flex (如 40% 导致 1080p 占用 768px、2K 占用 1000px 的严重空间浪费)；
          // 将右侧栏锁定为自适应 clamp(360.0, 23vw, 420.0)，其余全部水平空间分配给左侧主播放器。
          final railWidth = (totalWidth * 0.23).clamp(360.0, 420.0);

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

                      // 16:9 纵向安全 Contain 适配：
                      // 在可用宽高的包围盒内等比缩放到最大的 16:9 尺寸，
                      // 既让播放器占满左侧可用空间，又彻底杜绝窗口过矮时出现底部 RenderFlex overflow。
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
                                  color: primaryColor.withValues(alpha: isDark ? 0.22 : 0.12),
                                  blurRadius: 28,
                                  spreadRadius: -2,
                                  offset: const Offset(0, 8),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.15),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            // 特殊处理说明：
                            // 必须显式指定 Clip.antiAliasWithSaveLayer，严禁使用默认的 Clip.antiAlias。
                            // 播放器在暂停或呼出控制条时，内部浮层（如居中暂停卡片、顶栏按钮等）包含 BackdropFilter 毛玻璃，
                            // 默认剪裁在遇到子级 BackdropFilter 时会被渲染管线击穿导致圆角退化为直角；
                            // 开启 antiAliasWithSaveLayer 强制分配独立离屏合成层，确保全生命周期严格保持 16px 圆角约束。
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
              SizedBox(
                width: railWidth,
                child: tabSection,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 移动端/窄屏流式上下布局（上方 16:9 播放器，下方分段 Tab 栏）
class VideoPlayerMobileLayout extends StatelessWidget {
  const VideoPlayerMobileLayout({
    super.key,
    required this.playerWidget,
    required this.tabSection,
  });

  final Widget playerWidget;
  final Widget tabSection;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: playerWidget,
          ),
          Expanded(
            child: tabSection,
          ),
        ],
      ),
    );
  }
}
