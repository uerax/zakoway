import 'dart:async';
import 'package:flutter/material.dart';
import '../../controller/playback_controller.dart';

/// 桌面端指针感知与交互层：
/// 1. 严格契合桌面键鼠直觉：单击画面即刻播放/暂停，双击画面即刻进入/退出全屏；
/// 2. 鼠标光标与控制栏智能隐藏：全屏或窗口播放中，鼠标静止超过 2.5 秒后自动隐藏光标与控件；
/// 3. 彻底禁用移动端拖拽手势（避免鼠标误触屏幕亮度或横向拖动 Seek）。
class DesktopPlayerGestureLayer extends StatefulWidget {
  const DesktopPlayerGestureLayer({
    super.key,
    required this.controller,
    required this.onToggleFullscreen,
    required this.onUserActivity,
    required this.onHideControls,
    required this.isControlsVisible,
    this.isPanelOpen = false,
  });

  final ZakowayPlaybackController controller;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onUserActivity;
  final VoidCallback onHideControls;
  final bool isControlsVisible;
  final bool isPanelOpen;

  @override
  State<DesktopPlayerGestureLayer> createState() =>
      _DesktopPlayerGestureLayerState();
}

class _DesktopPlayerGestureLayerState extends State<DesktopPlayerGestureLayer> {
  Timer? _cursorHideTimer;
  MouseCursor _cursor = SystemMouseCursors.basic;
  bool _isMouseInside = false;

  @override
  void dispose() {
    _cursorHideTimer?.cancel();
    super.dispose();
  }

  void _onPointerHover() {
    _isMouseInside = true;
    if (_cursor != SystemMouseCursors.basic) {
      setState(() {
        _cursor = SystemMouseCursors.basic;
      });
    }
    widget.onUserActivity();
    _resetCursorHideTimer();
  }

  void _resetCursorHideTimer() {
    _cursorHideTimer?.cancel();
    // 只有在视频播放中、且没有打开 Popover 面板时才自动隐藏光标
    _cursorHideTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      final isPlaying = widget.controller.core.value.playing;
      if (_isMouseInside && isPlaying && !widget.isPanelOpen) {
        setState(() {
          _cursor = SystemMouseCursors.none;
        });
        widget.onHideControls();
      }
    });
  }

  void _onPointerExit() {
    _isMouseInside = false;
    _cursorHideTimer?.cancel();
    if (_cursor != SystemMouseCursors.basic) {
      setState(() {
        _cursor = SystemMouseCursors.basic;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _cursor,
      onHover: (_) => _onPointerHover(),
      onEnter: (_) => _onPointerHover(),
      onExit: (_) => _onPointerExit(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _onPointerHover();
          widget.controller.togglePlay();
        },
        onDoubleTap: () {
          _onPointerHover();
          widget.onToggleFullscreen();
        },
      ),
    );
  }
}
