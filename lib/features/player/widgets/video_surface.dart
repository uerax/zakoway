import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zakoway/core/utils/font_manager.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/controller/playback_state.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';

/// 纯视频画面与弹幕复合渲染表面
/// 严格使用 RepaintBoundary 对视频画面和弹幕图层进行独立光栅化隔离
class VideoSurface extends StatelessWidget {
  const VideoSurface({
    super.key,
    required this.controller,
    this.danmakuController,
    this.overlay,
  });

  final ZakowayPlaybackController controller;
  final DanmakuController? danmakuController;
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 底层：mpv 视频渲染层
          ValueListenableBuilder<VideoController?>(
            valueListenable: controller.videoControllerNotifier,
            builder: (context, videoController, _) {
              if (videoController == null) {
                return const Center(
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white70,
                    ),
                  ),
                );
              }

              return ValueListenableBuilder<PlaybackCoreState>(
                valueListenable: controller.core,
                builder: (context, coreState, _) {
                  return RepaintBoundary(
                    child: Video(
                      controller: videoController,
                      controls: NoVideoControls, // 使用完全自研的高定制控制条
                      fit: coreState.videoFit,
                      // 特殊处理说明：
                      // 切后台自动暂停 (选项 A 规范)：
                      // 1. 进入后台时自动暂停播放，避免移动端无前台服务被系统直接 SIGKILL 强杀或后台偷跑流量耗电；
                      // 2. 回到前台时不盲目自动起播，避免打扰用户当前环境。
                      pauseUponEnteringBackgroundMode: true,
                      resumeUponEnteringForegroundMode: false,
                      // 特殊处理说明：
                      // 显式禁用 Flutter 上层的纯文本 SubtitleView（visible: false），
                      // 彻底解决屏幕翻译（Sign/Screen/门牌）被剥离为死板纯文本堆积在底部的严重干扰问题；
                      // 全权交由底层 Native MPV (libass) 渲染原生原汁原味、精准位置与高颜值的特效圆体字幕。
                      subtitleViewConfiguration: const SubtitleViewConfiguration(visible: false),
                    ),
                  );
                },
              );
            },
          ),

          // 1.5 首帧感知防闪遮罩：在起播或切集新视频首帧未就绪前，以纯黑底色覆盖底层残留的旧视频帧
          // 特殊处理说明：
          // 切集时底层 GPU Texture 仍保留前一集最后一帧，若无遮罩会在新视频加载中暴露旧画面；
          // 当 firstFrameRendered 为 false 时瞬间以 0 延迟纯黑覆盖并在中央显示加载转圈；
          // 首帧判据已严格对齐底层 video-params 真实出画事件，首帧就绪后遮罩以 0 延迟瞬间撤去，彻底消除黑屏拖泥带水。
          ValueListenableBuilder<PlaybackCoreState>(
            valueListenable: controller.core,
            builder: (context, coreState, _) {
              final showCover = !coreState.firstFrameRendered && !coreState.hasError;
              return IgnorePointer(
                child: AnimatedOpacity(
                  opacity: showCover ? 1.0 : 0.0,
                  duration: Duration.zero,
                  child: const ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.8,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),

          // 2. 中层：纯 Flutter 原生高性能 Canvas 弹幕层
          if (danmakuController != null)
            Positioned.fill(
              child: DanmakuView(
                controller: danmakuController!,
                fontFamily: FontManager.instance.activeFontFamily ?? 'MiSans',
                anime4kStatusProvider: () => controller.core.value.superResolution.label,
              ),
            ),

          // 3. 播放中途常规卡顿缓冲指示器（仅在首帧已就绪、正常播放中途遭遇网络抖动时呈现）
          ValueListenableBuilder<PlaybackCoreState>(
            valueListenable: controller.core,
            builder: (context, coreState, _) {
              if (coreState.buffering && coreState.firstFrameRendered && !coreState.loading) {
                return const Center(
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.0,
                      color: Colors.white,
                    ),
                  ),
                );
              }
              if (coreState.hasError) {
                return Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      coreState.errorMessage!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontFamily: 'MiSans',
                        fontFamilyFallback: FontManager.fallbackFontFamilies,
                      ),
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
          ),

          // 4. 顶层：控制层 UI 浮层
          ?overlay,
        ],
      ),
    );
  }
}
