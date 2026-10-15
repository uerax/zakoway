import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zakoway/core/utils/font_manager.dart';
import 'package:zakoway/features/common/widgets/bouncing_scale_card.dart';
import 'package:zakoway/features/common/widgets/cached_anime_image.dart';

/// 播放器未起播海报占位组件 (沉浸式影院级 Hero 展台与毛玻璃大播放核)
class VideoPlayerInitialPlaceholder extends StatelessWidget {
  const VideoPlayerInitialPlaceholder({
    super.key,
    required this.coverUrl,
    required this.title,
    required this.isLoadingChapters,
    required this.selectedSourceName,
    required this.hasEpisodes,
    required this.onBackPressed,
    this.onPlayPressed,
    this.showBackAndTitle = true,
  });

  final String coverUrl;
  final String title;
  final bool isLoadingChapters;
  final String selectedSourceName;
  final bool hasEpisodes;
  final VoidCallback onBackPressed;
  final VoidCallback? onPlayPressed;
  final bool showBackAndTitle;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. 底层：超大半径环境高斯散焦流光 (Ambient Backdrop Glow)
        if (coverUrl.isNotEmpty) ...[
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 42, sigmaY: 42),
              child: Transform.scale(
                scale: 1.15,
                child: CachedAnimeImage(
                  imageUrl: coverUrl,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          // 2. 中层：主体清晰封面配合柔和景深微光
          Positioned.fill(
            child: CachedAnimeImage(
              imageUrl: coverUrl,
              fit: BoxFit.cover,
            ),
          ),
        ] else
          const ColoredBox(color: Color(0xFF0F0F14)),

        // 3. 电影级非线性自然渐变暗角 (Non-linear Scrim Gradients 杜绝色带断层)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.68),
                  Colors.black.withValues(alpha: 0.35),
                  Colors.black.withValues(alpha: 0.42),
                  Colors.black.withValues(alpha: 0.82),
                ],
                stops: const [0.0, 0.30, 0.65, 1.0],
              ),
            ),
          ),
        ),

        // 4. 顶部返回与标题（仅在允许时展示，桌面非全屏下隐藏以保持极简）
        if (showBackAndTitle)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                            width: 0.5,
                          ),
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.arrow_back_ios_new_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          onPressed: onBackPressed,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                        fontFamily: 'MiSans',
                        fontFamilyFallback: FontManager.fallbackFontFamilies,
                        shadows: [
                          Shadow(
                            color: Colors.black54,
                            blurRadius: 6,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 5. 底部沉浸式磨砂提示胶囊条 (带按压交互与微光边界)
        Positioned(
          bottom: 14,
          left: 16,
          right: 16,
          child: Center(
            child: BouncingScaleCard(
              scaleDown: 0.96,
              onTap: onPlayPressed,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.48),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.18),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLoadingChapters)
                          const Padding(
                            padding: EdgeInsets.only(right: 7),
                            child: CupertinoActivityIndicator(
                              color: Colors.white70,
                              radius: 6.5,
                            ),
                          )
                        else
                          const Icon(
                            Icons.touch_app_outlined,
                            color: Colors.white70,
                            size: 14,
                          ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            isLoadingChapters
                                ? '正在同步「$selectedSourceName」分集...'
                                : (hasEpisodes
                                    ? '分集已就绪 · 请在下方选择集数开始播放'
                                    : '请在下方选择播放源或选集'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              letterSpacing: -0.1,
                              fontFamily: 'MiSans',
                              fontFamilyFallback: FontManager.fallbackFontFamilies,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 人性化提炼网络与播放异常提示，杜绝整篇技术调试长文直接暴露给用户
String cleanErrorMessage(dynamic error, {String prefix = ''}) {
  if (error == null) return '';
  final str = error.toString();
  final lower = str.toLowerCase();

  String message;
  if (lower.contains('403') || lower.contains('forbidden')) {
    message = '视频源请求被拒绝 (HTTP 403)，可能是防盗链拦截或链接已失效';
  } else if (lower.contains('404') || lower.contains('not found')) {
    message = '视频资源未找到 (HTTP 404)，可能已被源站下架';
  } else if (lower.contains('500') ||
      lower.contains('502') ||
      lower.contains('503') ||
      lower.contains('bad gateway')) {
    message = '视频源站服务异常，请稍后重试或尝试切换视频源';
  } else if (lower.contains('timeout') || lower.contains('timed out')) {
    message = '连接视频源超时，请检查网络或切换视频源';
  } else if (lower.contains('connection refused') ||
      lower.contains('socketexception') ||
      lower.contains('network is unreachable')) {
    message = '网络连接失败，请检查网络状态';
  } else if (str.contains('DioException')) {
    final match = RegExp(r'message:\s*([^,\n]+)').firstMatch(str);
    if (match != null &&
        match.group(1) != null &&
        match.group(1)!.trim().isNotEmpty) {
      message = match.group(1)!.trim();
    } else {
      message = '网络请求异常，请尝试切换视频源';
    }
  } else {
    message = str
        .replaceFirst(RegExp(r'^(Exception|Error|ClientException):\s*'), '')
        .trim();
    if (message.length > 120) {
      final firstLine = message.split('\n').first.trim();
      message =
          firstLine.length > 100 ? '${firstLine.substring(0, 97)}...' : firstLine;
    }
  }

  return prefix.isNotEmpty ? '$prefix: $message' : message;
}

/// iOS 风格解析失败提示磨砂卡片（带竖屏防溢出保护与常驻操作按钮）
class VideoPlayerResolveErrorCard extends StatelessWidget {
  const VideoPlayerResolveErrorCard({
    super.key,
    required this.errorText,
    required this.primaryColor,
    required this.onRetry,
    required this.onSwitchSource,
  });

  final String errorText;
  final Color primaryColor;
  final VoidCallback onRetry;
  final VoidCallback onSwitchSource;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 小窗/竖屏紧凑模式（高度 < 260dp），收敛边距与尺寸防止溢出
        final isCompact = constraints.maxHeight < 260;
        final cardMaxHeight = (constraints.maxHeight - 20).clamp(120.0, 340.0);
        final cardMaxWidth = (constraints.maxWidth - 32).clamp(200.0, 480.0);

        final iconSize = isCompact ? 26.0 : 34.0;
        final vPadding = isCompact ? 10.0 : 16.0;
        final hPadding = isCompact ? 14.0 : 20.0;
        final gap1 = isCompact ? 6.0 : 10.0;
        final gap2 = isCompact ? 10.0 : 14.0;

        return Container(
          color: Colors.black.withValues(alpha: 0.55),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: cardMaxHeight,
                  maxWidth: cardMaxWidth,
                ),
                padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: vPadding),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Colors.amber,
                      size: iconSize,
                    ),
                    SizedBox(height: gap1),
                    // 中间可滚动弹性文本区：彻底防止超长堆栈文本溢出撑爆布局引发 OVERFLOW
                    Flexible(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Text(
                          cleanErrorMessage(errorText),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isCompact ? 12.0 : 13.0,
                            fontWeight: FontWeight.w500,
                            letterSpacing: -0.2,
                            height: 1.35,
                            fontFamily: 'MiSans',
                            fontFamilyFallback: FontManager.fallbackFontFamilies,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: gap2),
                    // 底部固定的操作按钮行：保证在任何屏幕尺寸下 100% 完整可见且随时可点击
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        BouncingScaleCard(
                          scaleDown: 0.94,
                          immediateTap: true,
                          onTap: onRetry,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 12.0 : 14.0,
                              vertical: isCompact ? 6.0 : 7.0,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 0.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  color: Colors.white,
                                  size: isCompact ? 14 : 15,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '重试',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isCompact ? 11.5 : 12.5,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'MiSans',
                                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: isCompact ? 8.0 : 12.0),
                        BouncingScaleCard(
                          scaleDown: 0.94,
                          immediateTap: true,
                          onTap: onSwitchSource,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: isCompact ? 12.0 : 14.0,
                              vertical: isCompact ? 6.0 : 7.0,
                            ),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.swap_horiz_rounded,
                                  color: Colors.white,
                                  size: isCompact ? 15 : 16,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '切换视频源',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: isCompact ? 11.5 : 12.5,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'MiSans',
                                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 顶部悬浮微光 HUD Toast 提示胶囊
class VideoPlayerHudToast extends StatelessWidget {
  const VideoPlayerHudToast({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 20,
      left: 20,
      right: 20,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    message,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
