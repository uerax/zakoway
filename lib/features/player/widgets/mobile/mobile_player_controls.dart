import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/bangumi_oped_service.dart';
import '../../../../core/utils/font_manager.dart';
import '../../controller/playback_controller.dart';
import '../../controller/playback_state.dart';
import '../../danmaku/danmaku.dart';
import '../../services/player_preferences_service.dart';
import '../controls/controls_bottom_bar.dart';
import '../controls/controls_top_bar.dart';
import '../controls/panels/player_danmaku_panel.dart';
import '../controls/panels/player_floating_panel.dart';
import '../controls/panels/player_settings_panel.dart';
import '../controls/player_screenshot_feedback.dart';
import '../controls/popups/player_speed_popup.dart';
import '../controls/popups/player_vertical_volume_popup.dart';
import '../player_indicators.dart';
import '../player_side_panel.dart';
import '../player_skip_toast.dart';
import 'mobile_player_gesture_layer.dart';

enum _MobileActiveControlPanel {
  none,
  settings,
  danmaku,
}

/// 移动端专用自适应播放器交互控制浮层：
/// 整合触控手势感知层、毛玻璃 HUD 反馈层、双侧滑屏（亮度/音量）、全屏防误触锁与长按动态倍速
class MobilePlayerControls extends StatefulWidget {
  const MobilePlayerControls({
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
  State<MobilePlayerControls> createState() => _MobilePlayerControlsState();
}

class _MobilePlayerControlsState extends State<MobilePlayerControls> {
  bool _visible = true;
  bool _isLocked = false;
  bool _showLockButton = true;
  Timer? _hideTimer;
  Timer? _lockButtonHideTimer;
  bool _isSeekingSlider = false;

  late final ValueNotifier<bool> _autoSkipOpedNotifier;
  late final ValueNotifier<bool> _autoPlayNextNotifier;
  bool _internalAutoPlayNext = false;
  _MobileActiveControlPanel _activePanel = _MobileActiveControlPanel.none;
  bool _showVolumeSlider = false;
  bool _showSpeedPopup = false;
  bool _isOpeningModalSheet = false;
  final GlobalKey _speedButtonKey = GlobalKey();
  final GlobalKey _volumeButtonKey = GlobalKey();

  // 软件亮度状态
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

  // OP / ED 跳过
  bool _hasSkippedOp = false;
  bool _hasSkippedEd = false;
  bool _hasUndoneSkip = false;
  String _lastSkippedType = '';
  bool _skipToastVisible = false;
  String _skipToastMessage = '';
  Timer? _skipToastTimer;

  // 截图反馈
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
    } else {
      _internalAutoPlayNext = true;
      _autoPlayNextNotifier =
          ValueNotifier<bool>(PlayerPreferencesService.instance.autoPlayNext);
    }
    widget.controller.timeline.addListener(_onTimelineTickForOped);
    _startHideTimer();
  }

  void _onAutoSkipSettingChanged() {
    PlayerPreferencesService.instance
        .saveAutoSkipOped(_autoSkipOpedNotifier.value);
  }

  @override
  void didUpdateWidget(MobilePlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.opedSegment != widget.opedSegment ||
        oldWidget.canonicalEpisode != widget.canonicalEpisode) {
      _hasSkippedOp = false;
      _hasSkippedEd = false;
      _hasUndoneSkip = false;
    }
  }

  @override
  void dispose() {
    widget.controller.timeline.removeListener(_onTimelineTickForOped);
    _hideTimer?.cancel();
    _lockButtonHideTimer?.cancel();
    _skipToastTimer?.cancel();
    _screenshotFeedbackTimer?.cancel();
    _brightnessNotifier.dispose();
    _autoSkipOpedNotifier.removeListener(_onAutoSkipSettingChanged);
    _autoSkipOpedNotifier.dispose();
    if (_internalAutoPlayNext) {
      _autoPlayNextNotifier.dispose();
    }
    super.dispose();
  }

  void _onTimelineTickForOped() {
    if (!mounted) return;
    final seg = widget.opedSegment;
    if (seg == null) return;

    final totalDuration = widget.controller.timeline.value.duration.inSeconds;
    if (totalDuration <= 0) return; // 视频尚未出画出时长

    // 容灾检查：Bangumi 官方片长比对，差距超过 10 秒直接熔断拦截
    final officialDur = widget.officialDurationSeconds ?? 0;
    if (officialDur > 0) {
      if ((totalDuration - officialDur).abs() > 10) {
        return; // 时长差距超过 10 秒，容灾熔断，禁用自动跳过
      }
    }

    final autoSkip = _autoSkipOpedNotifier.value;
    if (!autoSkip || _hasUndoneSkip) return;

    final pos = widget.controller.timeline.value.position.inSeconds;

    if (seg.hasOp &&
        !_hasSkippedOp &&
        pos >= seg.opStart! &&
        pos < seg.opEnd!) {
      _hasSkippedOp = true;
      _lastSkippedType = 'op';
      widget.controller.seek(Duration(seconds: seg.opEnd!));
      _triggerSkipToast('已自动跳过片头');
      return;
    }
    if (seg.hasEd &&
        !_hasSkippedEd &&
        pos >= seg.edStart! &&
        pos < seg.edEnd!) {
      _hasSkippedEd = true;
      _lastSkippedType = 'ed';
      widget.controller.seek(Duration(seconds: seg.edEnd!));
      _triggerSkipToast('已自动跳过片尾');
      return;
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

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted &&
          _visible &&
          !_isSeekingSlider &&
          !_isLocked &&
          _activePanel == _MobileActiveControlPanel.none) {
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
        _activePanel = _MobileActiveControlPanel.none;
        _showVolumeSlider = false;
        _showSpeedPopup = false;
      }
      if (_visible) {
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
      }
    });
  }

  void _handleShowLockedNotice() {
    setState(() => _showLockButton = true);
    _lockButtonHideTimer?.cancel();
    _lockButtonHideTimer = Timer(const Duration(seconds: 3), () {
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
        _activePanel = _MobileActiveControlPanel.none;
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

  Future<void> _handleScreenshot() async {
    try {
      final bytes = await widget.controller.screenshot();
      if (bytes != null && mounted) {
        setState(() {
          _lastScreenshotBytes = bytes;
          _screenshotFeedbackVisible = true;
        });
        _screenshotFeedbackTimer?.cancel();
        _screenshotFeedbackTimer = Timer(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() => _screenshotFeedbackVisible = false);
          }
        });
      }
    } catch (_) {}
  }

  void _openPanel(
      BuildContext context, Color primaryColor, _MobileActiveControlPanel panel) {
    if (widget.isFullscreen) {
      setState(() {
        _activePanel = _activePanel == panel ? _MobileActiveControlPanel.none : panel;
        _showVolumeSlider = false;
        _showSpeedPopup = false;
        if (_activePanel != _MobileActiveControlPanel.none) {
          _hideTimer?.cancel();
        } else {
          _startHideTimer();
        }
      });
    } else {
      if (_isOpeningModalSheet) return;
      _isOpeningModalSheet = true;
      _hideTimer?.cancel();
      setState(() {
        _activePanel = _MobileActiveControlPanel.none;
        _showVolumeSlider = false;
        _showSpeedPopup = false;
      });

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (sheetContext) {
          final isSettings = panel == _MobileActiveControlPanel.settings;
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: 400,
                decoration: BoxDecoration(
                  color: const Color(0xF216161E),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(22)),
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
                            isSettings
                                ? Icons.tune_rounded
                                : Icons.subtitles_rounded,
                            color: primaryColor,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isSettings ? '播放设置' : '弹幕设置',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'MiSans',
                              fontFamilyFallback:
                                  FontManager.fallbackFontFamilies,
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
                    const Divider(color: Colors.white12, height: 1),
                    Expanded(
                      child: SingleChildScrollView(
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
                                onDismiss: () =>
                                    Navigator.of(sheetContext).pop(),
                                onTriggerSkipToast: _triggerSkipToast,
                              )
                            : PlayerDanmakuPanelBody(
                                danmakuController: widget.danmakuController ??
                                    widget.danmakuCoordinator?.danmakuController,
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
      ).whenComplete(() {
        _isOpeningModalSheet = false;
        if (mounted) _startHideTimer();
      });
    }
  }

  Widget _buildAnchoredPopup({
    required GlobalKey anchorKey,
    required double popupWidth,
    required double playerWidth,
    required double playerHeight,
    required double fallbackRight,
    required double fallbackBottom,
    required Widget child,
  }) {
    double? resolvedRight = fallbackRight;
    double? resolvedBottom = fallbackBottom;

    try {
      final renderBox =
          anchorKey.currentContext?.findRenderObject() as RenderBox?;
      final playerBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null && playerBox != null && renderBox.hasSize) {
        final btnPos =
            playerBox.globalToLocal(renderBox.localToGlobal(Offset.zero));
        final btnCenterX = btnPos.dx + renderBox.size.width / 2;
        final candidateLeft = btnCenterX - popupWidth / 2;
        final clampedLeft =
            candidateLeft.clamp(8.0, math.max(8.0, playerWidth - popupWidth - 8.0));
        resolvedRight = math.max(0.0, playerWidth - clampedLeft - popupWidth);
        resolvedBottom = math.max(
            8.0, playerHeight - btnPos.dy + 8.0);
      }
    } catch (_) {}

    return Positioned(
      right: resolvedRight,
      bottom: resolvedBottom,
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final playerWidth = constraints.maxWidth;
        final playerHeight = constraints.maxHeight;
        final isShortScreen = playerHeight < 360;

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. 软件亮度遮罩层
            ValueListenableBuilder<double>(
              valueListenable: _brightnessNotifier,
              builder: (context, brightness, _) {
                if (brightness >= 0.99) return const SizedBox.shrink();
                final alpha = ((1.0 - brightness) * 0.92).clamp(0.0, 0.92);
                return IgnorePointer(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: alpha),
                  ),
                );
              },
            ),

            // 2. 移动端触屏手势感知层
            Positioned.fill(
              child: MobilePlayerGestureLayer(
                controller: widget.controller,
                isLocked: _isLocked,
                brightnessNotifier: _brightnessNotifier,
                onToggleControls: _toggleControls,
                onShowLockedNotice: _handleShowLockedNotice,
                onVerticalIndicatorUpdate: (val, isBrightness, visible) {
                  setState(() {
                    _verticalIndicatorValue = val;
                    _isVerticalBrightness = isBrightness;
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

            // HUD 反馈层
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
              )
            else
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

            // 居中暂停水滴卡片
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

            // 屏幕左侧防误触锁屏按钮（仅全屏）
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

            // 顶层主控制栏
            AnimatedOpacity(
              opacity: (_visible && !_isLocked) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: IgnorePointer(
                ignoring: !_visible || _isLocked,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: PlayerControlsTopBar(
                        title: widget.title,
                        isFullscreen: widget.isFullscreen,
                        isDesktopInline:
                            !widget.isFullscreen && playerWidth >= 640,
                        onBackPressed: widget.onBackPressed,
                        onOpenEpisodePicker: widget.onOpenEpisodePicker,
                        onOpenSidePanel: widget.onOpenSidePanel,
                        onScreenshot: _handleScreenshot,
                        danmakuController: widget.danmakuController,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
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
                              _activePanel = _MobileActiveControlPanel.none;
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
                              _activePanel = _MobileActiveControlPanel.none;
                            }
                          });
                          _startHideTimer();
                        },
                        isSettingsPanelActive:
                            _activePanel == _MobileActiveControlPanel.settings,
                        isDanmakuPanelActive:
                            _activePanel == _MobileActiveControlPanel.danmaku,
                        onOpenSettingsPanel: () => _openPanel(context,
                            primaryColor, _MobileActiveControlPanel.settings),
                        onOpenDanmakuPanel: () => _openPanel(context,
                            primaryColor, _MobileActiveControlPanel.danmaku),
                        speedButtonKey: _speedButtonKey,
                        volumeButtonKey: _volumeButtonKey,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 音量与倍速弹窗
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

            // 全屏悬浮设置
            if (widget.isFullscreen &&
                _activePanel != _MobileActiveControlPanel.none) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    setState(() => _activePanel = _MobileActiveControlPanel.none);
                    _startHideTimer();
                  },
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              Positioned(
                right: 14,
                bottom: 50,
                child: PlayerFloatingPanel(
                  title: _activePanel == _MobileActiveControlPanel.settings
                      ? '播放设置'
                      : '弹幕设置',
                  icon: _activePanel == _MobileActiveControlPanel.settings
                      ? Icons.tune_rounded
                      : Icons.subtitles_rounded,
                  primaryColor: primaryColor,
                  onClose: () {
                    setState(() => _activePanel = _MobileActiveControlPanel.none);
                    _startHideTimer();
                  },
                  child: _activePanel == _MobileActiveControlPanel.settings
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
                          onDismiss: () => setState(
                              () => _activePanel = _MobileActiveControlPanel.none),
                          onTriggerSkipToast: _triggerSkipToast,
                        )
                      : PlayerDanmakuPanelBody(
                          danmakuController: widget.danmakuController ??
                              widget.danmakuCoordinator?.danmakuController,
                          coordinator: widget.danmakuCoordinator,
                          primaryColor: primaryColor,
                        ),
                ),
              ),
            ],

            // 截图与跳过
            PlayerScreenshotFeedback(
              bytes: _lastScreenshotBytes,
              visible: _screenshotFeedbackVisible,
              isFullscreen: widget.isFullscreen,
            ),

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
          ],
        );
      },
    );
  }
}
