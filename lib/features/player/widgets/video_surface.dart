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
                return const SizedBox.shrink();
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
          // 1. 职责彻底解耦：作为纯粹的 GPU 渲染纹理屏障，专注于遮挡切集时残留的上一集最后一帧画面与未出画黑屏；
          // 2. 剥离内部耦合的 CircularProgressIndicator，避免业务加载状态侵入物理防闪图层；
          // 3. 保持 duration: Duration.zero 零延迟瞬间生效与撤除，首帧出画时瞬间撤去，彻底消除黑屏拖泥带水。
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

          // 3. 统一播放加载/缓冲指示器与错误展示层
          // 特殊处理说明：
          // 1. 统一收敛内核未就绪 (videoController == null)、首帧未渲染 (!firstFrameRendered)、播放中途卡顿 (buffering)、资源加载 (loading)；
          // 2. 统一定位于弹幕层之上，确保转圈提示不会被底层遮罩剪裁或与弹幕错乱；
          // 3. 采用 180ms 平滑渐变淡出，消除加载瞬间与极速出画时的生硬闪跳，且自带 IgnorePointer 防止阻断屏幕点击交互。
          ValueListenableBuilder<VideoController?>(
            valueListenable: controller.videoControllerNotifier,
            builder: (context, videoController, _) {
              return ValueListenableBuilder<PlaybackCoreState>(
                valueListenable: controller.core,
                builder: (context, coreState, _) {
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

                  final isLoading = videoController == null ||
                      !coreState.firstFrameRendered ||
                      coreState.buffering ||
                      coreState.loading;

                  return IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: isLoading ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeInOut,
                      child: const Center(
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
                  );
                },
              );
            },
          ),

          // 4. 顶层：控制层 UI 浮层
          ?overlay,
        ],
      ),
    );
  }
}
