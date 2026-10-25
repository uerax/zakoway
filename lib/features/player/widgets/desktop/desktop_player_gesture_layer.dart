import 'dart:async';
import 'package:flutter/material.dart';
import '../../constants/player_ui_constants.dart';
import '../../controller/playback_controller.dart';

/// 桌面端指针感知与交互层：
/// 1. 严格契合桌面键鼠直觉：单击画面即刻播放/暂停（无双击判定延迟）；
/// 2. 鼠标光标与控制栏智能隐藏：全屏或窗口播放中，鼠标静止超时后自动隐藏光标与控件；
/// 3. 彻底禁用移动端拖拽手势（避免鼠标误触屏幕亮度或横向拖动 Seek）。
class DesktopPlayerGestureLayer extends StatefulWidget {
  const DesktopPlayerGestureLayer({
    super.key,
    required this.controller,
    required this.onUserActivity,
    required this.onHideControls,
    required this.isControlsVisible,
    this.isPanelOpen = false,
    this.onRequestFocus,
  });

  final ZakowayPlaybackController controller;
  final VoidCallback onUserActivity;
  final VoidCallback onHideControls;
  final bool isControlsVisible;
  final bool isPanelOpen;
  final VoidCallback? onRequestFocus;

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
    widget.onRequestFocus?.call();
    widget.onUserActivity();
    _resetCursorHideTimer();
  }

  void _resetCursorHideTimer() {
    _cursorHideTimer?.cancel();
    // 只有在没有打开 Popover 面板时才自动隐藏光标与控件
    _cursorHideTimer = Timer(PlayerUiConstants.desktopCursorAutoHideDelay, () {
      if (!mounted) return;
      if (_isMouseInside && !widget.isPanelOpen) {
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
          widget.onRequestFocus?.call();
          _onPointerHover();
          widget.controller.togglePlay();
        },
      ),
    );
  }
}
