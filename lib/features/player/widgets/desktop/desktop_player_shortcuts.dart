import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../controller/playback_controller.dart';
import '../../danmaku/danmaku.dart';

/// 桌面端全局页面级播放键盘快捷键分发器
///
/// 架构设计与特殊处理说明：
/// 1. 焦点单向冒泡守护：
///    Flutter 的 KeyEvent 是从当前聚焦节点沿父级树单向冒泡。当用户点击选集网格、线路 Tab 或页面空白处时，
///    焦点会离开视频 Surface。使用页面级 Focus 挂载在根节点，并在未聚焦于 EditableText 打字态时全局截获；
/// 2. 移动端直接透传：
///    在 Android / iOS 纯触屏移动平台运行时，直接返回 child，跳过键盘事件监听，零开销；
/// 3. 分级返回（Esc）：全屏退出全屏，常规窗口返回上一页；
/// 4. 常用按键映射：
///    - Space / K: 播放 / 暂停
///    - 方向键左右 / J / L: 快退 / 快进
///    - 方向键上下: 音量调节
///    - M: 静音切换
///    - F: 全屏切换
///    - T: 剧场模式切换
///    - [ / ]: 上一集 / 下一集
///    - D: 弹幕切换（开启 / 精简 / 关闭）
///    - 0 ~ 9: 10% ~ 90% 进度百分比瞬间跳转
class DesktopPlayerShortcuts extends StatelessWidget {
  const DesktopPlayerShortcuts({
    super.key,
    required this.child,
    required this.playbackController,
    required this.danmakuController,
    required this.hasStartedPlayback,
    required this.isFullscreen,
    required this.onBackPressed,
    required this.onToggleFullscreen,
    required this.onToggleTheaterMode,
    required this.onSeekToPercent,
    required this.onShowHudToast,
    this.onPreviousEpisode,
    this.onNextEpisode,
  });

  final Widget child;
  final ZakowayPlaybackController playbackController;
  final DanmakuController danmakuController;
  final bool hasStartedPlayback;
  final bool isFullscreen;
  final VoidCallback onBackPressed;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleTheaterMode;
  final ValueChanged<double> onSeekToPercent;
  final ValueChanged<String> onShowHudToast;
  final VoidCallback? onPreviousEpisode;
  final VoidCallback? onNextEpisode;

  @override
  Widget build(BuildContext context) {
    // 移动端原生环境下不消耗键盘事件路由，直接呈现子节点
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      return child;
    }

    return Focus(
      autofocus: true,
      canRequestFocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }

        final primaryWidget =
            FocusManager.instance.primaryFocus?.context?.widget;
        if (primaryWidget is EditableText) {
          return KeyEventResult.ignored;
        }

        final key = event.logicalKey;

        // 1. Esc 优先分级退出（全屏退出全屏，常规窗口返回上一页）
        if (key == LogicalKeyboardKey.escape) {
          onBackPressed();
          return KeyEventResult.handled;
        }

        // 未起播占位态下，不劫持播放控制键
        if (!hasStartedPlayback) {
          return KeyEventResult.ignored;
        }

        // 2. 播放 / 暂停 (Space / K)
        if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
          playbackController.togglePlay();
          return KeyEventResult.handled;
        }

        // 3. 快退 / 快进 (左右方向键 5秒，J / L 10秒)
        if (key == LogicalKeyboardKey.arrowLeft) {
          playbackController.seekBy(const Duration(seconds: -5));
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowRight) {
          playbackController.seekBy(const Duration(seconds: 5));
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyJ) {
          playbackController.seekBy(const Duration(seconds: -10));
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.keyL) {
          playbackController.seekBy(const Duration(seconds: 10));
          return KeyEventResult.handled;
        }

        // 4. 音量调节 (上下方向键)
        if (key == LogicalKeyboardKey.arrowUp) {
          final curVol = playbackController.core.value.volume;
          final nextVol = (curVol + 0.05).clamp(0.0, 1.0);
          playbackController.setVolume(nextVol);
          onShowHudToast('音量：${(nextVol * 100).round()}%');
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          final curVol = playbackController.core.value.volume;
          final nextVol = (curVol - 0.05).clamp(0.0, 1.0);
          playbackController.setVolume(nextVol);
          onShowHudToast('音量：${(nextVol * 100).round()}%');
          return KeyEventResult.handled;
        }

        // 5. 静音切换 (M)
        if (key == LogicalKeyboardKey.keyM) {
          playbackController.toggleMute();
          final isMuted = playbackController.core.value.muted;
          onShowHudToast(isMuted ? '已静音' : '取消静音');
          return KeyEventResult.handled;
        }

        // 6. 全屏切换 (F)
        if (key == LogicalKeyboardKey.keyF) {
          onToggleFullscreen();
          return KeyEventResult.handled;
        }

        // 6.1. 剧场模式切换 (T)
        if (key == LogicalKeyboardKey.keyT) {
          if (!isFullscreen) {
            onToggleTheaterMode();
            return KeyEventResult.handled;
          }
        }

        // 7. 切集 ([ / ])
        if (key == LogicalKeyboardKey.bracketLeft) {
          onPreviousEpisode?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.bracketRight) {
          onNextEpisode?.call();
          return KeyEventResult.handled;
        }

        // 8. 弹幕状态切换 (D)
        if (key == LogicalKeyboardKey.keyD) {
          final cfg = danmakuController.settings;
          if (!cfg.enabled) {
            danmakuController.updateSettings(
                cfg.copyWith(enabled: true, simplify: false));
            onShowHudToast('弹幕：全量开启');
          } else if (!cfg.simplify) {
            danmakuController.updateSettings(
                cfg.copyWith(enabled: true, simplify: true));
            onShowHudToast('弹幕：智能精简');
          } else {
            danmakuController.updateSettings(cfg.copyWith(enabled: false));
            onShowHudToast('弹幕：已关闭');
          }
          return KeyEventResult.handled;
        }

        // 9. 百分比跳转 (0 ~ 9)
        if (key == LogicalKeyboardKey.digit0) {
          onSeekToPercent(0.0);
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.digit1) {
          onSeekToPercent(0.1);
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.digit2) {
          onSeekToPercent(0.2);
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.digit3) {
          onSeekToPercent(0.3);
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.digit4) {
          onSeekToPercent(0.4);
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.digit5) {
          onSeekToPercent(0.5);
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.digit6) {
          onSeekToPercent(0.6);
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.digit7) {
          onSeekToPercent(0.7);
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.digit8) {
          onSeekToPercent(0.8);
          return KeyEventResult.handled;
        } else if (key == LogicalKeyboardKey.digit9) {
          onSeekToPercent(0.9);
          return KeyEventResult.handled;
        }

        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
