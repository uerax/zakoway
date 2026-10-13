import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import '../../controller/playback_controller.dart';

enum _ActiveVerticalGesture {
  none,
  brightness,
  volume,
}

Duration _clampDuration(Duration val, Duration min, Duration max) {
  if (val < min) return min;
  if (max > Duration.zero && val > max) return max;
  return val;
}

/// 移动端专用多功能手势感知与分发层：
/// 支持：三等分双击、双侧垂直滑动（左亮度/右音量）、水平滑动 Seek Preview、长按动态变速与误触锁定
class MobilePlayerGestureLayer extends StatefulWidget {
  const MobilePlayerGestureLayer({
    super.key,
    required this.controller,
    required this.isLocked,
    required this.brightnessNotifier,
    required this.onToggleControls,
    required this.onShowLockedNotice,
    required this.onVerticalIndicatorUpdate,
    required this.onSeekIndicatorUpdate,
    required this.onSpeedIndicatorUpdate,
  });

  final ZakowayPlaybackController controller;
  final bool isLocked;
  final ValueNotifier<double> brightnessNotifier;
  final VoidCallback onToggleControls;
  final VoidCallback onShowLockedNotice;

  /// (value, isBrightness, visible)
  final void Function(double value, bool isBrightness, bool visible)
      onVerticalIndicatorUpdate;

  /// (targetPosition, totalDuration, deltaSeconds, visible)
  final void Function(
          Duration target, Duration total, int deltaSeconds, bool visible)
      onSeekIndicatorUpdate;

  /// (speed, visible)
  final void Function(double speed, bool visible) onSpeedIndicatorUpdate;

  @override
  State<MobilePlayerGestureLayer> createState() =>
      _MobilePlayerGestureLayerState();
}

class _MobilePlayerGestureLayerState extends State<MobilePlayerGestureLayer> {
  _ActiveVerticalGesture _verticalGesture = _ActiveVerticalGesture.none;
  Timer? _verticalHideTimer;

  // 垂直调节基底值
  double _initialVerticalValue = 0.0;

  // 水平滑动 Seek 状态
  Duration _horizontalSeekStartPos = Duration.zero;
  int _horizontalSeekDeltaSeconds = 0;
  bool _isHorizontalSeeking = false;

  // 长按倍速状态
  bool _isLongPressing = false;
  double _savedSpeedBeforeLongPress = 1.0;
  double _currentHoldSpeed = 2.0;

  @override
  void initState() {
    super.initState();
    try {
      FlutterVolumeController.updateShowSystemUI(false);
    } catch (_) {}
  }

  @override
  void dispose() {
    _verticalHideTimer?.cancel();
    super.dispose();
  }

  void _triggerHaptic() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  void _handleTap() {
    if (widget.isLocked) {
      widget.onShowLockedNotice();
    } else {
      widget.onToggleControls();
    }
  }

  void _handleDoubleTap() {
    if (widget.isLocked) {
      widget.onShowLockedNotice();
      return;
    }
    _triggerHaptic();
    widget.controller.togglePlay();
  }

  void _handleVerticalDragStart(DragStartDetails details, double screenWidth) {
    if (widget.isLocked) return;

    final x = details.localPosition.dx;
    final isLeft = x < screenWidth / 2;

    _verticalGesture = isLeft
        ? _ActiveVerticalGesture.brightness
        : _ActiveVerticalGesture.volume;

    _initialVerticalValue = isLeft
        ? widget.brightnessNotifier.value
        : widget.controller.core.value.volume;

    _verticalHideTimer?.cancel();
    widget.onVerticalIndicatorUpdate(
      _initialVerticalValue,
      isLeft,
      true,
    );
  }

  void _handleVerticalDragUpdate(
      DragUpdateDetails details, double screenHeight) {
    if (widget.isLocked || _verticalGesture == _ActiveVerticalGesture.none) return;

    final deltaNormalized = -details.delta.dy / (screenHeight * 0.65);
    final isBrightness = _verticalGesture == _ActiveVerticalGesture.brightness;

    if (isBrightness) {
      final current = widget.brightnessNotifier.value;
      final next = (current + deltaNormalized).clamp(0.05, 1.0);
      widget.brightnessNotifier.value = next;
      widget.onVerticalIndicatorUpdate(next, true, true);
    } else {
      final current = widget.controller.core.value.volume;
      final next = (current + deltaNormalized).clamp(0.0, 1.0);
      widget.controller.setVolume(next);
      try {
        FlutterVolumeController.setVolume(next);
      } catch (_) {}
      widget.onVerticalIndicatorUpdate(next, false, true);
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_verticalGesture == _ActiveVerticalGesture.none) return;
    final isBrightness = _verticalGesture == _ActiveVerticalGesture.brightness;
    final val = isBrightness
        ? widget.brightnessNotifier.value
        : widget.controller.core.value.volume;

    _verticalGesture = _ActiveVerticalGesture.none;
    _verticalHideTimer?.cancel();
    _verticalHideTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        widget.onVerticalIndicatorUpdate(val, isBrightness, false);
      }
    });
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (widget.isLocked) return;

    _isHorizontalSeeking = true;
    _horizontalSeekStartPos = widget.controller.timeline.value.position;
    _horizontalSeekDeltaSeconds = 0;
  }

  void _handleHorizontalDragUpdate(
      DragUpdateDetails details, double screenWidth) {
    if (widget.isLocked || !_isHorizontalSeeking) return;

    final timeline = widget.controller.timeline.value;
    final totalDur = timeline.duration;
    final totalSeconds = totalDur.inSeconds > 0 ? totalDur.inSeconds : 1440;

    final maxSeekSpan = totalSeconds.clamp(90, 600) * 0.35;
    final stepPerPixel = maxSeekSpan / screenWidth;

    _horizontalSeekDeltaSeconds += (details.delta.dx * stepPerPixel).round();

    final target = _clampDuration(
      _horizontalSeekStartPos + Duration(seconds: _horizontalSeekDeltaSeconds),
      Duration.zero,
      totalDur,
    );

    widget.controller.updateSeekPreview(target);
    widget.onSeekIndicatorUpdate(
      target,
      totalDur,
      _horizontalSeekDeltaSeconds,
      true,
    );
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    if (!_isHorizontalSeeking) return;
    _isHorizontalSeeking = false;

    final timeline = widget.controller.timeline.value;
    final target = timeline.displayPosition;

    widget.controller.endSeekPreview();
    widget.onSeekIndicatorUpdate(
      target,
      timeline.duration,
      _horizontalSeekDeltaSeconds,
      false,
    );
    _horizontalSeekDeltaSeconds = 0;
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    if (widget.isLocked || !widget.controller.core.value.playing) return;

    _isLongPressing = true;
    _savedSpeedBeforeLongPress = widget.controller.core.value.playbackRate;
    _currentHoldSpeed = 2.0;

    _triggerHaptic();
    widget.controller.setPlaybackRate(_currentHoldSpeed);
    widget.onSpeedIndicatorUpdate(_currentHoldSpeed, true);
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    if (!_isLongPressing) return;
    _isLongPressing = false;

    widget.controller.setPlaybackRate(_savedSpeedBeforeLongPress);
    widget.onSpeedIndicatorUpdate(_savedSpeedBeforeLongPress, false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          onDoubleTap: _handleDoubleTap,
          onVerticalDragStart: (d) => _handleVerticalDragStart(d, w),
          onVerticalDragUpdate: (d) => _handleVerticalDragUpdate(d, h),
          onVerticalDragEnd: _handleVerticalDragEnd,
          onHorizontalDragStart: _handleHorizontalDragStart,
          onHorizontalDragUpdate: (d) => _handleHorizontalDragUpdate(d, w),
          onHorizontalDragEnd: _handleHorizontalDragEnd,
          onLongPressStart: _handleLongPressStart,
          onLongPressEnd: _handleLongPressEnd,
          child: const SizedBox.expand(),
        );
      },
    );
  }
}
