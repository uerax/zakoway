import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zakoway/core/services/bangumi_oped_service.dart';
import 'package:zakoway/features/player/constants/player_ui_constants.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/controller/playback_state.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';
import 'package:zakoway/features/player/widgets/player_gesture_layer.dart';
import 'package:zakoway/features/player/widgets/player_indicators.dart';
import 'package:zakoway/features/player/widgets/player_side_panel.dart';
import 'package:zakoway/features/player/widgets/player_skip_toast.dart';

import 'package:zakoway/features/player/services/player_preferences_service.dart';

import 'controls/controls_bottom_bar.dart';
import 'controls/controls_top_bar.dart';
import 'controls/panels/player_danmaku_panel.dart';
import 'controls/panels/player_floating_panel.dart';
import 'controls/panels/player_settings_panel.dart';
import 'controls/player_screenshot_feedback.dart';
import 'controls/popups/player_speed_popup.dart';
import 'controls/popups/player_vertical_volume_popup.dart';

/// 工业级多端自适应播放器交互控制浮层
/// 整合了手势感知层、毛玻璃 HUD 反馈层、桌面键盘快捷键与软硬件亮度/音量控制
class PlayerControls extends StatefulWidget {
  const PlayerControls({
    super.key,
    required this.controller,
    this.title = '',
    this.danmakuController,
    this.danmakuCoordinator,
    this.isFullscreen = false,
    this.isAppFullscreen = false,
    this.isTrueFullscreen = false,
    this.onToggleFullscreen,
    this.onToggleAppFullscreen,
    this.onToggleTrueFullscreen,
    this.onBackPressed,
    this.onOpenEpisodePicker,
    this.onNextEpisode,
    this.onPrevEpisode,
    this.onOpenSidePanel,
    this.opedSegment,
    this.autoSkipOped = true,
    this.autoPlayNextNotifier,
    this.bangumiId,
    this.canonicalEpisode,
    this.officialDurationSeconds,
  });

  final ZakowayPlaybackController controller;
  final String title;
  final DanmakuController? danmakuController;
  final DanmakuSessionCoordinator? danmakuCoordinator;
  final bool isFullscreen;
  final bool isAppFullscreen;
  final bool isTrueFullscreen;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onToggleAppFullscreen;
  final VoidCallback? onToggleTrueFullscreen;
  final VoidCallback? onBackPressed;
  final VoidCallback? onOpenEpisodePicker;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onPrevEpisode;
  final ValueChanged<PlayerSidePanelTab>? onOpenSidePanel;
  final EpisodeOpedSegment? opedSegment;
  final bool autoSkipOped;
  final ValueNotifier<bool>? autoPlayNextNotifier;
  final int? bangumiId;
  final int? canonicalEpisode;
  final int? officialDurationSeconds;

  @override
  State<PlayerControls> createState() => _PlayerControlsState();
}

enum _ActiveControlPanel {
  none,
  settings,
  danmaku,
}

class _PlayerControlsState extends State<PlayerControls> {
  bool _visible = true;
  bool _isLocked = false;
  bool _showLockButton = true;
  Timer? _hideTimer;
  Timer? _lockButtonHideTimer;
  bool _isSeekingSlider = false;
  bool _lastPlaying = false;

  late final ValueNotifier<bool> _autoSkipOpedNotifier;
  late final ValueNotifier<bool> _autoPlayNextNotifier;
  bool _internalAutoPlayNext = false;
  _ActiveControlPanel _activePanel = _ActiveControlPanel.none;
  bool _showVolumeSlider = false;
  bool _showSpeedPopup = false;
  bool _isOpeningModalSheet = false;
  final GlobalKey _speedButtonKey = GlobalKey();
  final GlobalKey _volumeButtonKey = GlobalKey();

  late final FocusNode _keyboardFocusNode;

  // 软件亮度状态（1.0 为正常原画亮度，向下滑动平滑变暗，最低 0.05）
  final ValueNotifier<double> _brightnessNotifier = ValueNotifier<double>(1.0);

  // HUD 状态
  double _verticalIndicatorValue = 0.0;
  bool _isVerticalBrightness = false;
  bool _verticalIndicatorVisible = false;

  Duration _seekIndicatorTarget = Duration.zero;
  Duration _seekIndicatorTotal = Duration.zero;
  int _seekIndicatorDelta = 0;
  bool _seekIndicatorVisible = false;

  double _speedIndicatorValue = 2.0;
  bool _speedIndicatorVisible = false;

  // OP / ED 智能跳过状态
  bool _hasSkippedOp = false;
  bool _hasSkippedEd = false;
  bool _hasUndoneSkip = false;
  String _lastSkippedType = '';
  bool _skipToastVisible = false;
  String _skipToastMessage = '';
  Timer? _skipToastTimer;

  // 视频帧截图状态
  Uint8List? _lastScreenshotBytes;
  bool _screenshotFeedbackVisible = false;
  Timer? _screenshotFeedbackTimer;

  @override
  void initState() {
    super.initState();
    _autoSkipOpedNotifier =
        ValueNotifier<bool>(PlayerPreferencesService.instance.autoSkipOped);
    _autoSkipOpedNotifier.addListener(_onAutoSkipSettingChanged);
    if (widget.autoPlayNextNotifier != null) {
      _autoPlayNextNotifier = widget.autoPlayNextNotifier!;
      _internalAutoPlayNext = false;
    } else {
      _autoPlayNextNotifier = ValueNotifier<bool>(
          PlayerPreferencesService.instance.autoPlayNext);
      _internalAutoPlayNext = true;
    }
    _keyboardFocusNode = FocusNode();
    _lastPlaying = widget.controller.core.value.playing;
    widget.controller.timeline.addListener(_checkAutoSkip);
    widget.controller.core.addListener(_onCoreStateChanged);
    _startHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _keyboardFocusNode.requestFocus();
    });
  }

  void _onAutoSkipSettingChanged() {
    PlayerPreferencesService.instance
        .saveAutoSkipOped(_autoSkipOpedNotifier.value);
  }

  void _onCoreStateChanged() {
    final isPlaying = widget.controller.core.value.playing;
    if (isPlaying != _lastPlaying) {
      _lastPlaying = isPlaying;
      if (isPlaying) {
        // 视频进入播放状态，立即调度自动隐藏，杜绝起播前未播放导致的永久停留
        _startHideTimer();
      }
    }
  }

  @override
  void didUpdateWidget(covariant PlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opedSegment != widget.opedSegment ||
        oldWidget.canonicalEpisode != widget.canonicalEpisode) {
      _hasSkippedOp = false;
      _hasSkippedEd = false;
      _hasUndoneSkip = false;
    }
    if (oldWidget.autoSkipOped != widget.autoSkipOped) {
      _autoSkipOpedNotifier.value = widget.autoSkipOped;
    }
    if (oldWidget.autoPlayNextNotifier != widget.autoPlayNextNotifier &&
        widget.autoPlayNextNotifier != null) {
      if (_internalAutoPlayNext) {
        _autoPlayNextNotifier.dispose();
        _internalAutoPlayNext = false;
      }
      _autoPlayNextNotifier = widget.autoPlayNextNotifier!;
    }
  }

  @override
  void dispose() {
    widget.controller.timeline.removeListener(_checkAutoSkip);
    widget.controller.core.removeListener(_onCoreStateChanged);
    _skipToastTimer?.cancel();
    _screenshotFeedbackTimer?.cancel();
    _hideTimer?.cancel();
    _lockButtonHideTimer?.cancel();
    _keyboardFocusNode.dispose();
    _brightnessNotifier.dispose();
    _autoSkipOpedNotifier.removeListener(_onAutoSkipSettingChanged);
    _autoSkipOpedNotifier.dispose();
    if (_internalAutoPlayNext) {
      _autoPlayNextNotifier.dispose();
    }
    super.dispose();
  }

  Future<void> _handleScreenshot() async {
    final bytes = await widget.controller.screenshot();
    if (bytes != null && mounted) {
      try {
        HapticFeedback.mediumImpact();
      } catch (_) {}
      setState(() {
        _lastScreenshotBytes = bytes;
        _screenshotFeedbackVisible = true;
      });
      _screenshotFeedbackTimer?.cancel();
      _screenshotFeedbackTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _screenshotFeedbackVisible = false);
      });
    }
  }

  void _checkAutoSkip() {
    final seg = widget.opedSegment;
    if (seg == null || !_autoSkipOpedNotifier.value || _hasUndoneSkip) return;
    if (!widget.controller.core.value.playing) return;

    final totalDuration = widget.controller.timeline.value.duration.inSeconds;
    if (totalDuration <= 0) return; // 视频尚未出画出时长

    // 容灾检查：Bangumi 官方片长比对，差距超过 10 秒直接熔断拦截
    final officialDur = widget.officialDurationSeconds ?? 0;
    if (officialDur > 0) {
      if ((totalDuration - officialDur).abs() > 10) {
        return; // 时长差距超过 10 秒，容灾熔断，禁用自动跳过
      }
    }

    final posSec = widget.controller.timeline.value.position.inSeconds;

    // OP 片头跳过
    if (seg.hasOp && !_hasSkippedOp) {
      if (posSec >= seg.opStart! && posSec <= seg.opStart! + 3) {
        _hasSkippedOp = true;
        _lastSkippedType = 'op';
        final dur = seg.opEnd! - seg.opStart!;
        widget.controller.seek(Duration(seconds: seg.opEnd!));
        _triggerSkipToast('已自动跳过片头 ${_formatSeconds(dur)}');
        return;
      }
    }

    // ED 片尾跳过
    if (seg.hasEd && !_hasSkippedEd) {
      if (posSec >= seg.edStart! && posSec <= seg.edStart! + 3) {
        _hasSkippedEd = true;
        _lastSkippedType = 'ed';
        final dur = seg.edEnd! - seg.edStart!;
        widget.controller.seek(Duration(seconds: seg.edEnd!));
        _triggerSkipToast('已自动跳过片尾 ${_formatSeconds(dur)}');
        return;
      }
    }
  }

  bool get _isCurrentlyInOp {
    final seg = widget.opedSegment;
    if (seg == null || !seg.hasOp) return false;
    final pos = widget.controller.timeline.value.position.inSeconds;
    return pos >= seg.opStart! && pos < seg.opEnd!;
  }

  bool get _isCurrentlyInEd {
    final seg = widget.opedSegment;
    if (seg == null || !seg.hasEd) return false;
    final pos = widget.controller.timeline.value.position.inSeconds;
    return pos >= seg.edStart! && pos < seg.edEnd!;
  }

  void _skipCurrentSegment() {
    final seg = widget.opedSegment;
    if (seg == null) return;
    if (_isCurrentlyInOp) {
      widget.controller.seek(Duration(seconds: seg.opEnd!));
      _triggerSkipToast('已跳过片头');
    } else if (_isCurrentlyInEd) {
      widget.controller.seek(Duration(seconds: seg.edEnd!));
      _triggerSkipToast('已跳过片尾');
    }
  }

  void _triggerSkipToast(String msg) {
    setState(() {
      _skipToastVisible = true;
      _skipToastMessage = msg;
    });
    _skipToastTimer?.cancel();
    _skipToastTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _skipToastVisible = false);
    });
  }

  void _handleUndoSkip() {
    _hasUndoneSkip = true;
    _skipToastTimer?.cancel();
    setState(() => _skipToastVisible = false);

    final seg = widget.opedSegment;
    if (seg == null) return;

    if (_lastSkippedType == 'op' && seg.hasOp) {
      widget.controller.seek(Duration(seconds: seg.opStart!));
    } else if (_lastSkippedType == 'ed' && seg.hasEd) {
      widget.controller.seek(Duration(seconds: seg.edStart!));
    }
  }

  static String _formatSeconds(int totalSeconds) {
    final m = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(PlayerUiConstants.mobileControlsAutoHideDelay, () {
      if (mounted &&
          _visible &&
          !_isSeekingSlider &&
          !_isLocked &&
          _activePanel == _ActiveControlPanel.none) {
        if (widget.controller.core.value.playing) {
          setState(() {
            _visible = false;
            _showLockButton = false;
            _showVolumeSlider = false;
            _showSpeedPopup = false;
          });
        }
      }
    });
  }

  void _handlePointerHover() {
    if (_isLocked) return;
    if (!_visible) {
      setState(() {
        _visible = true;
        _showLockButton = true;
      });
    }
    _startHideTimer();
  }

  void _toggleControls() {
    if (_isLocked) return;
    if (_showSpeedPopup || _showVolumeSlider) {
      setState(() {
        _showSpeedPopup = false;
        _showVolumeSlider = false;
      });
      _startHideTimer();
      return;
    }
    setState(() {
      _visible = !_visible;
      _showLockButton = _visible;
      if (!_visible) {
        _activePanel = _ActiveControlPanel.none;
        _showVolumeSlider = false;
        _showSpeedPopup = false;
      }
      if (_visible) {
        _startHideTimer();
        _keyboardFocusNode.requestFocus();
      } else {
        _hideTimer?.cancel();
      }
    });
  }

  void _handleShowLockedNotice() {
    // 锁屏状态下轻点屏幕，唤出锁形按钮供用户解锁
    setState(() => _showLockButton = true);
    _lockButtonHideTimer?.cancel();
    _lockButtonHideTimer = Timer(PlayerUiConstants.lockButtonAutoHideDelay, () {
      if (mounted && _isLocked) {
        setState(() => _showLockButton = false);
      }
    });
  }

  void _toggleLock() {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}

    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked) {
        _visible = false;
        _showLockButton = true;
        _activePanel = _ActiveControlPanel.none;
        _showVolumeSlider = false;
        _showSpeedPopup = false;
        _handleShowLockedNotice();
      } else {
        _visible = true;
        _showLockButton = true;
        _startHideTimer();
      }
    });
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (_isLocked) return KeyEventResult.ignored;

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      final key = event.logicalKey;

      if (key == LogicalKeyboardKey.space) {
        widget.controller.togglePlay();
        _startHideTimer();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        widget.controller.seekBy(const Duration(seconds: -5));
        _startHideTimer();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowRight) {
        widget.controller.seekBy(const Duration(seconds: 5));
        _startHideTimer();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowUp) {
        final curVol = widget.controller.core.value.volume;
        widget.controller.setVolume((curVol + 0.05).clamp(0.0, 1.0));
        _startHideTimer();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowDown) {
        final curVol = widget.controller.core.value.volume;
        widget.controller.setVolume((curVol - 0.05).clamp(0.0, 1.0));
        _startHideTimer();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.keyF) {
        if (widget.onToggleTrueFullscreen != null) {
          widget.onToggleTrueFullscreen?.call();
        } else {
          widget.onToggleFullscreen?.call();
        }
        _startHideTimer();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.keyM) {
        widget.controller.toggleMute();
        _startHideTimer();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.keyC) {
        _handleScreenshot();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.keyD) {
        _cycleDanmakuMode();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.escape) {
        // 特殊处理说明：桌面端 Esc 键分级退出规范
        // 1. 若当前有弹出的控制面板（弹幕/设置），先关闭面板；
        // 2. 若当前为全屏模式（真全屏或应用内全屏），退回常规窗口播放；
        // 3. 若为常规窗口播放，直接触发返回上一页（Pop），避免用户在长页面下必须滑回顶部才能返回。
        if (_activePanel != _ActiveControlPanel.none) {
          setState(() {
            _activePanel = _ActiveControlPanel.none;
          });
          return KeyEventResult.handled;
        }
        if (widget.isFullscreen) {
          if (widget.isTrueFullscreen && widget.onToggleTrueFullscreen != null) {
            widget.onToggleTrueFullscreen?.call();
          } else if (widget.isAppFullscreen && widget.onToggleAppFullscreen != null) {
            widget.onToggleAppFullscreen?.call();
          } else {
            widget.onToggleFullscreen?.call();
          }
        } else {
          widget.onBackPressed?.call();
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _cycleDanmakuMode() {
    final controller = widget.danmakuController ?? widget.danmakuCoordinator?.danmakuController;
    if (controller == null) return;
    final cfg = controller.settings;
    if (!cfg.enabled) {
      controller.updateSettings(cfg.copyWith(enabled: true, simplify: false));
      _triggerSkipToast('弹幕：全量开启');
    } else if (!cfg.simplify) {
      controller.updateSettings(cfg.copyWith(enabled: true, simplify: true));
      _triggerSkipToast('弹幕：智能精简');
    } else {
      controller.updateSettings(cfg.copyWith(enabled: false));
      _triggerSkipToast('弹幕：已关闭');
    }
  }

  void _openPanel(BuildContext context, Color primaryColor, _ActiveControlPanel panel) {
    if (widget.isFullscreen) {
      // 全屏模式下：在右下角以毛玻璃浮层卡片展开
      setState(() {
        _activePanel = _activePanel == panel ? _ActiveControlPanel.none : panel;
        _showVolumeSlider = false;
        _showSpeedPopup = false;
        if (_activePanel != _ActiveControlPanel.none) {
          _hideTimer?.cancel();
        } else {
          _startHideTimer();
        }
      });
    } else {
      // 非全屏模式下：展开到播放器外部，使用底部抽屉 (showModalBottomSheet)
      // 防重入保护：避免快速多次点击导致重复堆叠弹出多个 Modal 路由
      if (_isOpeningModalSheet) return;
      _isOpeningModalSheet = true;
      _hideTimer?.cancel();
      setState(() {
        _activePanel = _ActiveControlPanel.none;
        _showVolumeSlider = false;
        _showSpeedPopup = false;
      });

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (sheetContext) {
          final isSettings = panel == _ActiveControlPanel.settings;
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: 400,
                decoration: BoxDecoration(
                  color: const Color(0xF216161E),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.16),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
                      child: Row(
                        children: [
                          Icon(
                            isSettings ? Icons.tune_rounded : Icons.subtitles_rounded,
                            color: primaryColor,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isSettings ? '播放设置' : '弹幕设置',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: Colors.white70, size: 20),
                            onPressed: () => Navigator.of(sheetContext).pop(),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Color(0x22FFFFFF), height: 1, thickness: 0.5),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: isSettings
                            ? PlayerSettingsPanelBody(
                                controller: widget.controller,
                                primaryColor: primaryColor,
                                autoSkipOpedNotifier: _autoSkipOpedNotifier,
                                autoPlayNextNotifier: _autoPlayNextNotifier,
                                brightnessNotifier: _brightnessNotifier,
                                opedSegment: widget.opedSegment,
                                isCurrentlyInOp: _isCurrentlyInOp,
                                isCurrentlyInEd: _isCurrentlyInEd,
                                onSkipCurrentSegment: _skipCurrentSegment,
                                onDismiss: () => Navigator.of(sheetContext).pop(),
                                onTriggerSkipToast: _triggerSkipToast,
                              )
                            : PlayerDanmakuPanelBody(
                                danmakuController: widget.danmakuController,
                                coordinator: widget.danmakuCoordinator,
                                primaryColor: primaryColor,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ).then((_) {
        _isOpeningModalSheet = false;
        if (mounted) {
          _startHideTimer();
        }
      });
    }
  }

  Widget _buildAnchoredPopup({
    required GlobalKey anchorKey,
    required Widget child,
    required double popupWidth,
    required double playerWidth,
    required double playerHeight,
    required double fallbackRight,
    required double fallbackBottom,
  }) {
    final renderBox =
        anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final rootBox = context.findRenderObject() as RenderBox?;

    double left;
    double bottom;

    if (renderBox != null &&
        rootBox != null &&
        renderBox.hasSize &&
        rootBox.hasSize) {
      final offset = renderBox.localToGlobal(Offset.zero, ancestor: rootBox);
      final anchorSize = renderBox.size;
      final anchorCenterX = offset.dx + (anchorSize.width / 2.0);

      // 水平方向：严格以目标按钮中心对齐，并在左右两端保留 8px 安全边距（彻底防止窄屏被裁切）
      final idealLeft = anchorCenterX - (popupWidth / 2.0);
      final maxLeft = math.max(8.0, playerWidth - popupWidth - 8.0);
      left = idealLeft.clamp(8.0, maxLeft);

      // 垂直方向：精准锚定在按钮上方 6px 处
      final idealBottom = playerHeight - offset.dy + 6.0;
      bottom = idealBottom.clamp(0.0, math.max(0.0, playerHeight - 60.0));
    } else {
      // 降级兜底（未完成初次测量时）
      left = math.max(8.0, playerWidth - fallbackRight - popupWidth);
      bottom = fallbackBottom;
    }

    // 视口高度自适应：计算上方可用最大高度，防止矮屏被顶部导航栏裁剪
    final maxAvailableHeight = math.max(80.0, playerHeight - bottom - 42.0);

    return Positioned(
      left: left,
      bottom: bottom,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxAvailableHeight,
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return MouseRegion(
      cursor: (_visible || _isLocked || _activePanel != _ActiveControlPanel.none)
          ? SystemMouseCursors.basic
          : SystemMouseCursors.none,
      onHover: (_) => _handlePointerHover(),
      child: Focus(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: (node, event) => _handleKeyEvent(event),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final playerWidth = constraints.maxWidth;
            final playerHeight = constraints.maxHeight;
            final isShortScreen = playerHeight < 240.0;

            return Stack(
              fit: StackFit.expand,
              children: [
            // 0. 软件亮度滤镜遮罩（当亮度低于 1.0 时平滑暗化底层视频）
            ValueListenableBuilder<double>(
              valueListenable: _brightnessNotifier,
              builder: (context, brightness, _) {
                if (brightness >= 0.99) return const SizedBox.shrink();
                final darkAlpha = (1.0 - brightness).clamp(0.0, 0.88);
                return IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: darkAlpha),
                  ),
                );
              },
            ),

            // 1. 底层高敏手势感知层（三等分双击、水平 Seek、垂直音量亮度滑动、长按变速）
            Positioned.fill(
              child: PlayerGestureLayer(
                controller: widget.controller,
                isLocked: _isLocked,
                brightnessNotifier: _brightnessNotifier,
                onToggleControls: _toggleControls,
                onShowLockedNotice: _handleShowLockedNotice,
                onVerticalIndicatorUpdate: (val, isB, visible) {
                  setState(() {
                    _verticalIndicatorValue = val;
                    _isVerticalBrightness = isB;
                    _verticalIndicatorVisible = visible;
                  });
                },
                onSeekIndicatorUpdate: (target, total, delta, visible) {
                  setState(() {
                    _seekIndicatorTarget = target;
                    _seekIndicatorTotal = total;
                    _seekIndicatorDelta = delta;
                    _seekIndicatorVisible = visible;
                  });
                },
                onSpeedIndicatorUpdate: (speed, visible) {
                  setState(() {
                    _speedIndicatorValue = speed;
                    _speedIndicatorVisible = visible;
                  });
                },
              ),
            ),

            // 2. 屏幕中央/顶部 HUD 动态指示层
            // (1) 垂直亮度指示器（左半屏）
            if (_isVerticalBrightness)
              Positioned(
                left: 36,
                top: 0,
                bottom: 0,
                child: Center(
                  child: PlayerVerticalLevelIndicator(
                    value: _verticalIndicatorValue,
                    isBrightness: true,
                    visible: _verticalIndicatorVisible,
                  ),
                ),
              ),

            // (2) 垂直音量指示器（右半屏）
            if (!_isVerticalBrightness)
              Positioned(
                right: 36,
                top: 0,
                bottom: 0,
                child: Center(
                  child: PlayerVerticalLevelIndicator(
                    value: _verticalIndicatorValue,
                    isBrightness: false,
                    visible: _verticalIndicatorVisible,
                  ),
                ),
              ),

            // (3) 中央 Seek 预览卡片
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: PlayerSeekPreviewIndicator(
                    visible: _seekIndicatorVisible,
                    targetPosition: _seekIndicatorTarget,
                    totalDuration: _seekIndicatorTotal,
                    deltaSeconds: _seekIndicatorDelta,
                  ),
                ),
              ),
            ),

            // (4) 顶部长按 2x 极速微光卡片
            Positioned(
              top: 24,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: PlayerSpeedHoldIndicator(
                    visible: _speedIndicatorVisible,
                    speed: _speedIndicatorValue,
                  ),
                ),
              ),
            ),

            // (5) 屏幕中央居中暂停标识（暂停时优雅淡入呈现，点击直接继续播放）
            ValueListenableBuilder<PlaybackCoreState>(
              valueListenable: widget.controller.core,
              builder: (context, coreState, _) {
                final isPaused = !coreState.playing &&
                    !coreState.buffering &&
                    !coreState.loading &&
                    !_isLocked &&
                    coreState.firstFrameRendered;

                return AnimatedOpacity(
                  opacity: isPaused ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 180),
                  child: IgnorePointer(
                    ignoring: !isPaused,
                    child: Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          widget.controller.play();
                          _startHideTimer();
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(30),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.22),
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 38,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            // 3. 屏幕左侧防误触锁定浮动按钮（严格仅在全屏模式下显示）
            if (widget.isFullscreen)
              Positioned(
                left: 18,
                top: 0,
                bottom: 0,
                child: Center(
                  child: PlayerLockFloatingButton(
                    isLocked: _isLocked,
                    visible: _showLockButton,
                    onTap: _toggleLock,
                  ),
                ),
              ),

            // 4. 顶层主控制栏（顶部导航条 + 底部极简通栏控制条）
            AnimatedOpacity(
              opacity: (_visible && !_isLocked) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: IgnorePointer(
                ignoring: !_visible || _isLocked,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 顶部非线性自然暗角（加 IgnorePointer 避免吞掉触屏点击）
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: 88,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.65),
                                Colors.black.withValues(alpha: 0.42),
                                Colors.black.withValues(alpha: 0.20),
                                Colors.black.withValues(alpha: 0.06),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.28, 0.58, 0.82, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 底部非线性自然暗角（加 IgnorePointer 避免吞掉触屏点击）
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 100,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.70),
                                Colors.black.withValues(alpha: 0.46),
                                Colors.black.withValues(alpha: 0.22),
                                Colors.black.withValues(alpha: 0.07),
                                Colors.transparent,
                              ],
                              stops: const [0.0, 0.30, 0.60, 0.82, 1.0],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 顶部 iOS 悬浮导航岛（配合垂直位移滑入滑出微动效）
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedSlide(
                        offset: (_visible && !_isLocked) ? Offset.zero : const Offset(0, -0.20),
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: PlayerControlsTopBar(
                          title: widget.title,
                          isFullscreen: widget.isFullscreen,
                          isDesktopInline: !widget.isFullscreen && playerWidth >= 640,
                          onBackPressed: widget.onBackPressed,
                          onOpenEpisodePicker: widget.onOpenEpisodePicker,
                          onOpenSidePanel: widget.onOpenSidePanel,
                          onScreenshot: _handleScreenshot,
                          danmakuController: widget.danmakuController,
                        ),
                      ),
                    ),

                    // 底部播放控制与流体进度条（配合垂直位移滑入滑出微动效）
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: AnimatedSlide(
                        offset: (_visible && !_isLocked) ? Offset.zero : const Offset(0, 0.20),
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: PlayerControlsBottomBar(
                          controller: widget.controller,
                          primaryColor: primaryColor,
                          danmakuController: widget.danmakuController,
                          opedSegment: widget.opedSegment,
                          officialDurationSeconds: widget.officialDurationSeconds,
                          isFullscreen: widget.isFullscreen,
                          isAppFullscreen: widget.isAppFullscreen,
                          isTrueFullscreen: widget.isTrueFullscreen,
                          onToggleFullscreen: widget.onToggleFullscreen,
                          onToggleAppFullscreen: widget.onToggleAppFullscreen,
                          onToggleTrueFullscreen: widget.onToggleTrueFullscreen,
                          onSeekingSliderChanged: (val) =>
                              setState(() => _isSeekingSlider = val),
                          onUserInteraction: _startHideTimer,
                          showSpeedPopup: _showSpeedPopup,
                          onToggleSpeedPopup: () {
                            setState(() {
                              _showSpeedPopup = !_showSpeedPopup;
                              if (_showSpeedPopup) {
                                _showVolumeSlider = false;
                                _activePanel = _ActiveControlPanel.none;
                              }
                            });
                            _startHideTimer();
                          },
                          showVolumeSlider: _showVolumeSlider,
                          onToggleVolumeSlider: () {
                            setState(() {
                              _showVolumeSlider = !_showVolumeSlider;
                              if (_showVolumeSlider) {
                                _showSpeedPopup = false;
                                _activePanel = _ActiveControlPanel.none;
                              }
                            });
                            _startHideTimer();
                          },
                          isSettingsPanelActive:
                              _activePanel == _ActiveControlPanel.settings,
                          isDanmakuPanelActive:
                              _activePanel == _ActiveControlPanel.danmaku,
                          onOpenSettingsPanel: () => _openPanel(
                              context, primaryColor, _ActiveControlPanel.settings),
                          onOpenDanmakuPanel: () => _openPanel(
                              context, primaryColor, _ActiveControlPanel.danmaku),
                          speedButtonKey: _speedButtonKey,
                          volumeButtonKey: _volumeButtonKey,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 4.5 常态沉浸式微光极窄进度条 (Ambient Mini Progress Bar: 控件收起时保留 2.0px 优雅呼吸指示)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 2.0,
              child: AnimatedOpacity(
                opacity: (!_visible && !_isLocked) ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: IgnorePointer(
                  child: ValueListenableBuilder<PlaybackTimelineState>(
                    valueListenable: widget.controller.timeline,
                    builder: (context, timelineState, _) {
                      final dur = timelineState.duration;
                      final pos = timelineState.displayPosition;
                      final buf = timelineState.buffer;
                      final ratio = dur > Duration.zero
                          ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                          : 0.0;
                      final bufRatio = dur > Duration.zero
                          ? (buf.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
                          : 0.0;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: Colors.white.withValues(alpha: 0.12)),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: bufRatio,
                            child: ColoredBox(color: Colors.white.withValues(alpha: 0.28)),
                          ),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor: ratio,
                            child: ColoredBox(color: primaryColor.withValues(alpha: 0.85)),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),

            // 5. 自动跳过片头/片尾可撤销浮标 (放在控制栏之上，保证点击撤销可交互)
            Positioned(
              left: 20,
              bottom: widget.isFullscreen ? 90 : 70,
              child: PlayerSkipToast(
                visible: _skipToastVisible,
                message: _skipToastMessage,
                onUndo: _handleUndoSkip,
                onDismiss: () => setState(() => _skipToastVisible = false),
              ),
            ),

            // 6. 截图成功微光浮窗反馈 (带缩略图)
            PlayerScreenshotFeedback(
              bytes: _lastScreenshotBytes,
              visible: _screenshotFeedbackVisible,
              isFullscreen: widget.isFullscreen,
            ),

            // 7. 垂直音量调节面板（动态计算锚点，水平严格居中于音量键，自适应防溢出）
            if (_showVolumeSlider) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _showVolumeSlider = false);
                    _startHideTimer();
                  },
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              _buildAnchoredPopup(
                anchorKey: _volumeButtonKey,
                popupWidth: 36.0,
                playerWidth: playerWidth,
                playerHeight: playerHeight,
                fallbackRight: widget.onToggleFullscreen != null ? 38.0 : 10.0,
                fallbackBottom: 46.0,
                child: PlayerVerticalVolumePopup(
                  controller: widget.controller,
                  primaryColor: primaryColor,
                  onVolumeChanged: (val) {
                    _startHideTimer();
                    widget.controller.setVolume(val);
                  },
                ),
              ),
            ],

            // 8. 垂直倍速调节浮层面板（动态计算锚点，水平严格居中于倍速键，左右边界防溢出，高度自适应）
            if (_showSpeedPopup) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _showSpeedPopup = false);
                    _startHideTimer();
                  },
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              _buildAnchoredPopup(
                anchorKey: _speedButtonKey,
                popupWidth: isShortScreen ? 82.0 : 86.0,
                playerWidth: playerWidth,
                playerHeight: playerHeight,
                fallbackRight: widget.onToggleFullscreen != null ? 74.0 : 46.0,
                fallbackBottom: 46.0,
                child: PlayerSpeedPopup(
                  controller: widget.controller,
                  primaryColor: primaryColor,
                  compact: isShortScreen,
                  onSelectSpeed: (speed) {
                    widget.controller.setPlaybackRate(speed);
                    setState(() => _showSpeedPopup = false);
                    _startHideTimer();
                  },
                ),
              ),
            ],

            // 9. 全屏模式下内置悬浮「播放设置」与「弹幕设置」半透明毛玻璃浮层面板
            if (widget.isFullscreen &&
                _activePanel != _ActiveControlPanel.none) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _activePanel = _ActiveControlPanel.none);
                    _startHideTimer();
                  },
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 50,
                child: PlayerFloatingPanel(
                  title: _activePanel == _ActiveControlPanel.settings
                      ? '播放设置'
                      : '弹幕设置',
                  icon: _activePanel == _ActiveControlPanel.settings
                      ? Icons.tune_rounded
                      : Icons.subtitles_rounded,
                  primaryColor: primaryColor,
                  onClose: () {
                    setState(() => _activePanel = _ActiveControlPanel.none);
                    _startHideTimer();
                  },
                  child: _activePanel == _ActiveControlPanel.settings
                      ? PlayerSettingsPanelBody(
                          controller: widget.controller,
                          primaryColor: primaryColor,
                          autoSkipOpedNotifier: _autoSkipOpedNotifier,
                          autoPlayNextNotifier: _autoPlayNextNotifier,
                          brightnessNotifier: _brightnessNotifier,
                          opedSegment: widget.opedSegment,
                          isCurrentlyInOp: _isCurrentlyInOp,
                          isCurrentlyInEd: _isCurrentlyInEd,
                          onSkipCurrentSegment: _skipCurrentSegment,
                          onDismiss: () {
                            setState(
                                () => _activePanel = _ActiveControlPanel.none);
                            _startHideTimer();
                          },
                          onTriggerSkipToast: _triggerSkipToast,
                        )
                      : PlayerDanmakuPanelBody(
                          danmakuController: widget.danmakuController,
                          coordinator: widget.danmakuCoordinator,
                          primaryColor: primaryColor,
                        ),
                ),
              ),
            ],
          ],
        );
      },
    ),
  ),
);
  }
}
