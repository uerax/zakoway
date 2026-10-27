import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/services/bangumi_oped_service.dart';
import '../../../../core/utils/font_manager.dart';
import '../../constants/player_ui_constants.dart';
import '../../controller/playback_controller.dart';
import '../../controller/playback_state.dart';
import '../../danmaku/danmaku.dart';
import '../../services/player_preferences_service.dart';
import '../controls/controls_top_bar.dart';
import '../controls/danmaku_settings_icon.dart';
import '../controls/panels/player_danmaku_panel.dart';
import '../controls/panels/player_floating_panel.dart';
import '../controls/panels/player_settings_panel.dart';
import '../controls/player_screenshot_feedback.dart';
import '../controls/popups/player_speed_popup.dart';
import '../controls/popups/player_vertical_volume_popup.dart';
import '../player_progress_bar.dart';
import '../player_scrim.dart';
import '../player_side_panel.dart';
import '../player_skip_toast.dart';
import 'desktop_player_gesture_layer.dart';
import 'desktop_shortcut_help_dialog.dart';

enum _DesktopActivePanel {
  none,
  settings,
  danmaku,
}

/// 桌面端专属播放器控制层：
/// 1. 深度适配键鼠：单击即刻播放暂停（无双击判定延迟）、鼠标静止 1.5s 自动隐藏光标与控件；
/// 2. 悬停展开音量滑槽，且仅在悬停区内允许滚轮微调音量；
/// 3. Popover 浮动面板：窗口与全屏模式下均在播放器内部右下角展开，彻底杜绝移动端 BottomSheet；
/// 4. 完备的键盘快捷键（Space/K, F/Enter, Esc, J/L, 方向键, [, ], <, >, 0-9, D, C, S, ?）。
class DesktopPlayerControls extends StatefulWidget {
  const DesktopPlayerControls({
    super.key,
    required this.controller,
    this.title = '',
    this.danmakuController,
    this.danmakuCoordinator,
    this.isFullscreen = false,
    this.isAppFullscreen = false,
    this.isTrueFullscreen = false,
    this.isTheaterMode = false,
    this.onToggleFullscreen,
    this.onToggleAppFullscreen,
    this.onToggleTrueFullscreen,
    this.onToggleTheaterMode,
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
  final bool isTheaterMode;
  final VoidCallback? onToggleFullscreen;
  final VoidCallback? onToggleAppFullscreen;
  final VoidCallback? onToggleTrueFullscreen;
  final VoidCallback? onToggleTheaterMode;
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
  State<DesktopPlayerControls> createState() => _DesktopPlayerControlsState();
}

class _DesktopPlayerControlsState extends State<DesktopPlayerControls> {
  bool _visible = true;
  Timer? _hideTimer;
  bool _isSeekingSlider = false;

  late final ValueNotifier<bool> _autoSkipOpedNotifier;
  late final ValueNotifier<bool> _autoPlayNextNotifier;
  bool _internalAutoPlayNext = false;
  _DesktopActivePanel _activePanel = _DesktopActivePanel.none;
  bool _showSpeedPopup = false;
  final GlobalKey _speedButtonKey = GlobalKey();

  // 音量悬停面板状态
  bool _isVolumeHovered = false;
  Timer? _volumeCloseTimer;
  final GlobalKey _volumeButtonKey = GlobalKey();

  late final FocusNode _keyboardFocusNode;

  // OP / ED 智能跳过状态
  bool _hasSkippedOp = false;
  bool _hasSkippedEd = false;
  bool _hasUndoneSkip = false;
  String _lastSkippedType = '';
  bool _skipToastVisible = false;
  String _skipToastMessage = '';
  Timer? _skipToastTimer;

  // 截图反馈状态
  Uint8List? _lastScreenshotBytes;
  bool _screenshotFeedbackVisible = false;
  Timer? _screenshotFeedbackTimer;

  @override
  void initState() {
    super.initState();
    _keyboardFocusNode = FocusNode();
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
    widget.controller.core.addListener(_onCoreStateChanged);
    _startHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureKeyboardFocus();
      }
    });
  }

  /// 焦点安全防护：非打字输入状态下确保播放器键盘焦点就位
  void _ensureKeyboardFocus() {
    if (!mounted) return;
    final primary = FocusManager.instance.primaryFocus?.context?.widget;
    if (primary is EditableText) return;
    if (!_keyboardFocusNode.hasFocus) {
      _keyboardFocusNode.requestFocus();
    }
  }

  void _onAutoSkipSettingChanged() {
    PlayerPreferencesService.instance
        .saveAutoSkipOped(_autoSkipOpedNotifier.value);
  }

  @override
  void didUpdateWidget(DesktopPlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.timeline.removeListener(_onTimelineTickForOped);
      oldWidget.controller.core.removeListener(_onCoreStateChanged);
      widget.controller.timeline.addListener(_onTimelineTickForOped);
      widget.controller.core.addListener(_onCoreStateChanged);
    }
    if (oldWidget.opedSegment != widget.opedSegment ||
        oldWidget.canonicalEpisode != widget.canonicalEpisode) {
      _hasSkippedOp = false;
      _hasSkippedEd = false;
      _hasUndoneSkip = false;
    }
    if (oldWidget.isFullscreen != widget.isFullscreen ||
        oldWidget.isTrueFullscreen != widget.isTrueFullscreen ||
        oldWidget.isAppFullscreen != widget.isAppFullscreen) {
      // 特殊处理说明：
      // 全屏/应用全屏切换时即刻关闭残留的悬停与浮层状态，避免跨布局重组时浮动面板漂移或残留活跃节点。
      _showSpeedPopup = false;
      _isVolumeHovered = false;
      _activePanel = _DesktopActivePanel.none;
      if (widget.controller.core.value.playing) {
        _startHideTimer();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _ensureKeyboardFocus();
        }
      });
    }
  }

  void _onCoreStateChanged() {
    if (!mounted) return;
    if (_visible) {
      _startHideTimer();
    } else if (!widget.controller.core.value.playing) {
      // 暂停时若控件处于隐藏状态，立刻唤醒展示以给予用户明确的状态反馈，并开启自动隐藏倒计时
      setState(() {
        _visible = true;
      });
      _startHideTimer();
    }
  }

  @override
  void dispose() {
    widget.controller.timeline.removeListener(_onTimelineTickForOped);
    widget.controller.core.removeListener(_onCoreStateChanged);
    _hideTimer?.cancel();
    _volumeCloseTimer?.cancel();
    _skipToastTimer?.cancel();
    _screenshotFeedbackTimer?.cancel();
    _keyboardFocusNode.dispose();
    _autoSkipOpedNotifier.removeListener(_onAutoSkipSettingChanged);
    _autoSkipOpedNotifier.dispose();
    if (_internalAutoPlayNext) {
      _autoPlayNextNotifier.dispose();
    }
    super.dispose();
  }

  void _onVolumeEnter() {
    _volumeCloseTimer?.cancel();
    if (!_isVolumeHovered) {
      setState(() => _isVolumeHovered = true);
    }
    _handleUserActivity();
  }

  void _onVolumeExit() {
    _volumeCloseTimer?.cancel();
    _volumeCloseTimer = Timer(const Duration(milliseconds: 280), () {
      if (mounted && _isVolumeHovered) {
        setState(() => _isVolumeHovered = false);
      }
    });
  }

  void _handleVolumeScroll(PointerScrollEvent event) {
    _handleUserActivity();
    final curVol = widget.controller.core.value.volume;
    final step = event.scrollDelta.dy < 0 ? 0.05 : -0.05;
    final nextVol = (curVol + step).clamp(0.0, 1.0);
    widget.controller.setVolume(nextVol);
  }

  double _calcSpeedPopupRight(double playerWidth, double popupWidth) {
    try {
      final btnBox =
          _speedButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final playerBox = context.findRenderObject() as RenderBox?;
      if (btnBox != null && playerBox != null && btnBox.hasSize) {
        final btnPos =
            playerBox.globalToLocal(btnBox.localToGlobal(Offset.zero));
        final btnCenterX = btnPos.dx + btnBox.size.width / 2;
        final candidateLeft = btnCenterX - popupWidth / 2;
        final clampedLeft =
            candidateLeft.clamp(8.0, math.max(8.0, playerWidth - popupWidth - 8.0));
        return math.max(0.0, playerWidth - clampedLeft - popupWidth);
      }
    } catch (_) {}
    return 140.0;
  }

  double _calcSpeedPopupBottom(double playerHeight) {
    try {
      final btnBox =
          _speedButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final playerBox = context.findRenderObject() as RenderBox?;
      if (btnBox != null && playerBox != null && btnBox.hasSize && playerBox.hasSize) {
        final btnPos =
            playerBox.globalToLocal(btnBox.localToGlobal(Offset.zero));
        return (playerHeight - btnPos.dy + 6.0)
            .clamp(0.0, math.max(0.0, playerHeight - 60.0));
      }
    } catch (_) {}
    return 46.0;
  }

  double _calcVolumePopupRight(double playerWidth) {
    try {
      final btnBox =
          _volumeButtonKey.currentContext?.findRenderObject() as RenderBox?;
      final playerBox = context.findRenderObject() as RenderBox?;
      if (btnBox != null && playerBox != null && btnBox.hasSize) {
        final btnPos =
            playerBox.globalToLocal(btnBox.localToGlobal(Offset.zero));
        final btnCenterX = btnPos.dx + btnBox.size.width / 2;
        final targetLeft = btnCenterX - 18.0; // 36 / 2
        return math.max(0.0, playerWidth - targetLeft - 36.0);
      }
    } catch (_) {}
    return 70.0;
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
      _triggerSkipToast('已自动跳过片头', duration: const Duration(seconds: 5));
      return;
    }
    if (seg.hasEd &&
        !_hasSkippedEd &&
        pos >= seg.edStart! &&
        pos < seg.edEnd!) {
      _hasSkippedEd = true;
      _lastSkippedType = 'ed';
      widget.controller.seek(Duration(seconds: seg.edEnd!));
      _triggerSkipToast('已自动跳过片尾', duration: const Duration(seconds: 5));
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

  void _triggerSkipToast(String msg, {Duration duration = const Duration(milliseconds: 2200)}) {
    setState(() {
      _skipToastVisible = true;
      _skipToastMessage = msg;
    });
    _skipToastTimer?.cancel();
    _skipToastTimer = Timer(duration, () {
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
    _hideTimer = Timer(PlayerUiConstants.desktopControlsAutoHideDelay, () {
      _hideTimer = null;
      if (mounted &&
          _visible &&
          !_isSeekingSlider &&
          _activePanel == _DesktopActivePanel.none &&
          !_showSpeedPopup &&
          !_isVolumeHovered) {
        setState(() {
          _visible = false;
        });
      }
    });
  }

  void _handleUserActivity() {
    if (!_visible) {
      setState(() {
        _visible = true;
      });
    }
    _startHideTimer();
  }

  void _hideControls() {
    if (_visible &&
        !_isSeekingSlider &&
        _activePanel == _DesktopActivePanel.none &&
        !_showSpeedPopup &&
        !_isVolumeHovered) {
      setState(() {
        _visible = false;
      });
    }
  }

  void _toggleSpeedPopup() {
    setState(() {
      _showSpeedPopup = !_showSpeedPopup;
      if (_showSpeedPopup) {
        _activePanel = _DesktopActivePanel.none;
      }
    });
    _startHideTimer();
  }

  void _togglePanel(_DesktopActivePanel panel) {
    if (widget.isFullscreen) {
      // 1. 全屏模式下：在播放器内侧右下角展开悬浮半透明卡片
      setState(() {
        _activePanel = _activePanel == panel ? _DesktopActivePanel.none : panel;
        _showSpeedPopup = false;
        if (_activePanel != _DesktopActivePanel.none) {
          _hideTimer?.cancel();
        } else {
          _startHideTimer();
        }
      });
    } else {
      // 2. 窗口模式下（非全屏）：以桌面端精致毛玻璃模态弹窗展开，彻底杜绝16:9窄高挤压出界
      _openDesktopDialog(panel);
    }
  }

  Future<void> _openDesktopDialog(_DesktopActivePanel panel) async {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final isSettings = panel == _DesktopActivePanel.settings;

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (dialogContext) {
        return Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                width: 440,
                constraints: const BoxConstraints(maxHeight: 560),
                decoration: BoxDecoration(
                  color: const Color(0xF216161E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.16),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.55),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 弹窗顶栏 (统一多媒体暗色沉浸质感)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 14, 12),
                        child: Row(
                          children: [
                            Icon(
                              isSettings
                                  ? Icons.tune_rounded
                                  : Icons.subtitles_rounded,
                              color: primaryColor,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              isSettings ? '播放设置' : '弹幕设置',
                              style: appTextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close_rounded,
                                  color: Colors.white70, size: 20),
                              splashRadius: 18,
                              onPressed: () => Navigator.of(dialogContext).pop(),
                            ),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                      // 弹窗内容流
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: isSettings
                              ? PlayerSettingsPanelBody(
                                  controller: widget.controller,
                                  primaryColor: primaryColor,
                                  autoSkipOpedNotifier: _autoSkipOpedNotifier,
                                  autoPlayNextNotifier: _autoPlayNextNotifier,
                                  opedSegment: widget.opedSegment,
                                  isCurrentlyInOp: _isCurrentlyInOp,
                                  isCurrentlyInEd: _isCurrentlyInEd,
                                  onSkipCurrentSegment: _skipCurrentSegment,
                                  onDismiss: () =>
                                      Navigator.of(dialogContext).pop(),
                                  onTriggerSkipToast: _triggerSkipToast,
                                )
                              : PlayerDanmakuPanelBody(
                                  danmakuController: widget.danmakuController ??
                                      widget.danmakuCoordinator
                                          ?.danmakuController,
                                  coordinator: widget.danmakuCoordinator,
                                  primaryColor: primaryColor,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
    if (mounted) {
      _ensureKeyboardFocus();
    }
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

  void _cycleDanmakuMode() {
    final controller =
        widget.danmakuController ?? widget.danmakuCoordinator?.danmakuController;
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

  void _stepPlaybackRate(bool faster) {
    final cur = widget.controller.core.value.playbackRate;
    const rates = [0.75, 1.0, 1.25, 1.5, 2.0];
    int idx = 1;
    for (int i = 0; i < rates.length; i++) {
      if ((rates[i] - cur).abs() < 0.1) {
        idx = i;
        break;
      }
    }
    final nextIdx = faster ? (idx + 1).clamp(0, rates.length - 1) : (idx - 1).clamp(0, rates.length - 1);
    final target = rates[nextIdx];
    widget.controller.setPlaybackRate(target);
    _triggerSkipToast('倍速：${target}x');
  }

  void _seekToPercent(double percent) {
    final total = widget.controller.timeline.value.duration;
    if (total <= Duration.zero) return;
    final targetMs = (total.inMilliseconds * percent).round();
    widget.controller.seek(Duration(milliseconds: targetMs));
    _triggerSkipToast('跳转至 ${(percent * 100).toInt()}%');
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    _handleUserActivity();

    // 1. 播放/暂停
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.keyK) {
      widget.controller.togglePlay();
      return KeyEventResult.handled;
    }

    // 2. 全屏切换 (F)
    if (key == LogicalKeyboardKey.keyF) {
      if (widget.onToggleTrueFullscreen != null) {
        widget.onToggleTrueFullscreen?.call();
      } else {
        widget.onToggleFullscreen?.call();
      }
      return KeyEventResult.handled;
    }

    // 2.1. 剧场模式切换 (T)
    if (key == LogicalKeyboardKey.keyT) {
      if (widget.onToggleTheaterMode != null && !widget.isFullscreen) {
        widget.onToggleTheaterMode?.call();
        _triggerSkipToast(widget.isTheaterMode ? '已退出剧场模式' : '已开启剧场模式');
        return KeyEventResult.handled;
      }
    }

    // 3. 快退/快进 5秒 (方向键) 与 10秒 (J/L)
    if (key == LogicalKeyboardKey.arrowLeft) {
      widget.controller.seekBy(const Duration(seconds: -5));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      widget.controller.seekBy(const Duration(seconds: 5));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyJ) {
      widget.controller.seekBy(const Duration(seconds: -10));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyL) {
      widget.controller.seekBy(const Duration(seconds: 10));
      return KeyEventResult.handled;
    }

    // 4. 音量调节 (方向键上下)
    if (key == LogicalKeyboardKey.arrowUp) {
      final curVol = widget.controller.core.value.volume;
      final nextVol = (curVol + 0.05).clamp(0.0, 1.0);
      widget.controller.setVolume(nextVol);
      _triggerSkipToast('音量：${(nextVol * 100).round()}%');
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      final curVol = widget.controller.core.value.volume;
      final nextVol = (curVol - 0.05).clamp(0.0, 1.0);
      widget.controller.setVolume(nextVol);
      _triggerSkipToast('音量：${(nextVol * 100).round()}%');
      return KeyEventResult.handled;
    }

    // 5. 静音切换
    if (key == LogicalKeyboardKey.keyM) {
      widget.controller.toggleMute();
      final isMuted = widget.controller.core.value.muted;
      _triggerSkipToast(isMuted ? '已静音' : '取消静音');
      return KeyEventResult.handled;
    }

    // 6. 快捷切集 ([ / ])
    if (key == LogicalKeyboardKey.bracketLeft) {
      if (widget.onPrevEpisode != null) {
        widget.onPrevEpisode?.call();
        _triggerSkipToast('正在切换至上一集');
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.bracketRight) {
      if (widget.onNextEpisode != null) {
        widget.onNextEpisode?.call();
        _triggerSkipToast('正在切换至下一集');
      }
      return KeyEventResult.handled;
    }

    // 7. 倍速增减 (< / >)
    if (key == LogicalKeyboardKey.comma) {
      _stepPlaybackRate(false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.period) {
      _stepPlaybackRate(true);
      return KeyEventResult.handled;
    }

    // 8. 数字键 0 ~ 9 百分比跳转
    if (key == LogicalKeyboardKey.digit0) {
      _seekToPercent(0.0);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit1) {
      _seekToPercent(0.1);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit2) {
      _seekToPercent(0.2);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit3) {
      _seekToPercent(0.3);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit4) {
      _seekToPercent(0.4);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit5) {
      _seekToPercent(0.5);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit6) {
      _seekToPercent(0.6);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit7) {
      _seekToPercent(0.7);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit8) {
      _seekToPercent(0.8);
      return KeyEventResult.handled;
    } else if (key == LogicalKeyboardKey.digit9) {
      _seekToPercent(0.9);
      return KeyEventResult.handled;
    }

    // 9. 截图 (C)
    if (key == LogicalKeyboardKey.keyC) {
      _handleScreenshot();
      return KeyEventResult.handled;
    }

    // 10. 弹幕循环切换 (D)
    if (key == LogicalKeyboardKey.keyD) {
      _cycleDanmakuMode();
      return KeyEventResult.handled;
    }

    // 11. 手动跳过片头片尾 (S)
    if (key == LogicalKeyboardKey.keyS) {
      if (_isCurrentlyInOp || _isCurrentlyInEd) {
        _skipCurrentSegment();
      }
      return KeyEventResult.handled;
    }

    // 12. 快捷键帮助指南 (?)
    if (key == LogicalKeyboardKey.slash &&
        HardwareKeyboard.instance.isShiftPressed) {
      DesktopShortcutHelpDialog.show(context).then((_) {
        if (mounted) _ensureKeyboardFocus();
      });
      return KeyEventResult.handled;
    }

    // 13. Esc 分级退出
    if (key == LogicalKeyboardKey.escape) {
      if (_showSpeedPopup ||
          _activePanel != _DesktopActivePanel.none ||
          _isVolumeHovered) {
        setState(() {
          _showSpeedPopup = false;
          _isVolumeHovered = false;
          _activePanel = _DesktopActivePanel.none;
        });
        return KeyEventResult.handled;
      }
      if (widget.isFullscreen) {
        if (widget.isTrueFullscreen && widget.onToggleTrueFullscreen != null) {
          widget.onToggleTrueFullscreen?.call();
        } else if (widget.isAppFullscreen &&
            widget.onToggleAppFullscreen != null) {
          widget.onToggleAppFullscreen?.call();
        } else {
          widget.onToggleFullscreen?.call();
        }
        return KeyEventResult.handled;
      }
      widget.onBackPressed?.call();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _buildBarButton({
    required Widget icon,
    required VoidCallback? onTap,
    required double size,
    Key? key,
  }) {
    return Material(
      key: key,
      color: Colors.transparent,
      child: InkResponse(
        radius: size * 0.58,
        highlightShape: BoxShape.circle,
        onTap: onTap == null
            ? null
            : () {
                _ensureKeyboardFocus();
                onTap();
              },
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: icon),
        ),
      ),
    );
  }

  static String _formatDuration(Duration duration, {bool showHours = false}) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    if (showHours || hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Focus(
      focusNode: _keyboardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) => _handleKeyEvent(event),
      child: ExcludeSemantics(
        child: LayoutBuilder(
        builder: (context, constraints) {
          final playerWidth = constraints.maxWidth;
          final playerHeight = constraints.maxHeight;
          final isNarrow = playerWidth < 640;
          final isUltraNarrow = playerWidth < 520;
          final speedPopupWidth = isUltraNarrow ? 82.0 : 86.0;
          final btnSpacing = isUltraNarrow ? 2.5 : (isNarrow ? 4.0 : 6.0);
          final barHorizontalPadding =
              isUltraNarrow ? 8.0 : (isNarrow ? 10.0 : 16.0);
          final mainBtnSize = isUltraNarrow ? 28.0 : 32.0;
          final mainIconSize = isUltraNarrow ? 18.0 : 20.0;

          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. 底层桌面端鼠标感知层 (单击即刻暂停/播放、1.5s 静止隐藏光标)
              Positioned.fill(
                child: DesktopPlayerGestureLayer(
                  controller: widget.controller,
                  onUserActivity: _handleUserActivity,
                  onHideControls: _hideControls,
                  isControlsVisible: _visible,
                  isPanelOpen: _activePanel != _DesktopActivePanel.none ||
                      _showSpeedPopup ||
                      _isVolumeHovered,
                  onRequestFocus: _ensureKeyboardFocus,
                ),
              ),

              // 2. 居中暂停水滴微光卡片（仅在真正暂停且控制栏可见时优雅淡入，避免遮挡暂停帧与画面细节）
              ValueListenableBuilder<PlaybackCoreState>(
                valueListenable: widget.controller.core,
                builder: (context, coreState, _) {
                  final isPaused = !coreState.playing &&
                      !coreState.buffering &&
                      !coreState.loading &&
                      coreState.firstFrameRendered;
                  final showPauseButton = isPaused && _visible;

                  return AnimatedOpacity(
                    opacity: showPauseButton ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 180),
                    child: IgnorePointer(
                      ignoring: !showPauseButton,
                      child: Center(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _ensureKeyboardFocus();
                            widget.controller.play();
                            _startHideTimer();
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(30),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                              child: Container(
                                width: 56,
                                height: 56,
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
                                    size: 36,
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

              // 3. 顶层主控制栏（淡入淡出动画）
              AnimatedOpacity(
                opacity: _visible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                child: IgnorePointer(
                  ignoring: !_visible,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 顶部渐变暗角（仅在全屏展示，桌面窗口模式保持画面通透）
                      if (widget.isFullscreen)
                        PlayerScrim.top(isFullscreen: widget.isFullscreen),

                      // 底部渐变暗角（非线性缓动衰减）
                      PlayerScrim.bottom(isFullscreen: widget.isFullscreen),

                      // 顶部悬浮导航条（桌面非全屏下去除返回按钮与标题，全屏时完整保留）
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
                          showBack: widget.isFullscreen,
                          showTitle: widget.isFullscreen,
                        ),
                      ),

                      // 底部控制行与全宽进度条
                      // 特殊处理说明：
                      // 最外层包裹 HitTestBehavior.opaque 的 GestureDetector 形成完整实体覆盖块，
                      // 吸收按钮间隙、Spacer 以及文本空白区域的点击并刷新交互状态，
                      // 严防误触穿透到底层 DesktopPlayerGestureLayer 导致非预期的视频暂停/播放。
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _ensureKeyboardFocus();
                            _handleUserActivity();
                          },
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                                barHorizontalPadding, 0, barHorizontalPadding, 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                              // 全宽进度条
                              ValueListenableBuilder<PlaybackTimelineState>(
                                valueListenable: widget.controller.timeline,
                                builder: (context, timelineState, _) {
                                  return PlayerProgressBar(
                                    position: timelineState.displayPosition,
                                    duration: timelineState.duration,
                                    buffer: timelineState.buffer,
                                    opedSegment: widget.opedSegment,
                                    officialDurationSeconds:
                                        widget.officialDurationSeconds,
                                    danmakuItems:
                                        widget.danmakuController?.items,
                                    primaryColor: primaryColor,
                                    onChangeStart: (dur) {
                                      _ensureKeyboardFocus();
                                      setState(() => _isSeekingSlider = true);
                                      _handleUserActivity();
                                    },
                                    onChanged: (dur) {
                                      _handleUserActivity();
                                      widget.controller.updateSeekPreview(dur);
                                    },
                                    onChangeEnd: (dur) {
                                      setState(() => _isSeekingSlider = false);
                                      _handleUserActivity();
                                      widget.controller.seek(dur);
                                    },
                                  );
                                },
                              ),

                              const SizedBox(height: 3),

                              // 控制通栏
                              Row(
                                children: [
                                  // 播放 / 暂停 (Space/K)
                                  ValueListenableBuilder<PlaybackCoreState>(
                                    valueListenable: widget.controller.core,
                                    builder: (context, coreState, _) {
                                      return _buildBarButton(
                                        icon: Icon(
                                          coreState.playing
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: mainIconSize + 2,
                                        ),
                                        size: mainBtnSize,
                                        onTap: () {
                                          _handleUserActivity();
                                          widget.controller.togglePlay();
                                        },
                                      );
                                    },
                                  ),

                                  // 上一集 / 下一集 (超窄小窗隐藏以防挤压)
                                  if (!isUltraNarrow &&
                                      widget.onPrevEpisode != null) ...[
                                    SizedBox(width: btnSpacing),
                                    _buildBarButton(
                                      icon: Icon(Icons.skip_previous_rounded,
                                          color: Colors.white,
                                          size: mainIconSize),
                                      size: mainBtnSize,
                                      onTap: () {
                                        _handleUserActivity();
                                        widget.onPrevEpisode?.call();
                                      },
                                    ),
                                  ],
                                  if (!isUltraNarrow &&
                                      widget.onNextEpisode != null) ...[
                                    SizedBox(width: btnSpacing),
                                    _buildBarButton(
                                      icon: Icon(Icons.skip_next_rounded,
                                          color: Colors.white,
                                          size: mainIconSize),
                                      size: mainBtnSize,
                                      onTap: () {
                                        _handleUserActivity();
                                        widget.onNextEpisode?.call();
                                      },
                                    ),
                                  ],

                                  SizedBox(
                                      width: isUltraNarrow ? 4.0 : 8.0),

                                  // 时间戳
                                  ValueListenableBuilder<PlaybackTimelineState>(
                                    valueListenable: widget.controller.timeline,
                                    builder: (context, timelineState, _) {
                                      final isDurationValid =
                                          timelineState.duration > Duration.zero;
                                      final effectiveDuration = isDurationValid
                                          ? timelineState.duration
                                          : Duration.zero;
                                      final effectivePosition = isDurationValid
                                          ? (timelineState.displayPosition >
                                                  effectiveDuration
                                              ? effectiveDuration
                                              : (timelineState.displayPosition <
                                                      Duration.zero
                                                  ? Duration.zero
                                                  : timelineState
                                                      .displayPosition))
                                          : Duration.zero;

                                      final hasHours =
                                          effectiveDuration.inHours > 0;
                                      final pos = _formatDuration(
                                          effectivePosition,
                                          showHours: hasHours);
                                      final total = _formatDuration(
                                          effectiveDuration,
                                          showHours: hasHours);

                                      return Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: pos,
                                              style: appTextStyle(
                                                color: Colors.white,
                                                fontSize: isUltraNarrow
                                                    ? 11.0
                                                    : 12.0,
                                                fontWeight: FontWeight.w600,
                                                fontFeatures: const [
                                                  FontFeature.tabularFigures()
                                                ],
                                              ),
                                            ),
                                            if (!isUltraNarrow)
                                              TextSpan(
                                                text: ' / $total',
                                                style: appTextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.65),
                                                  fontSize: 12.0,
                                                  fontWeight: FontWeight.w400,
                                                  fontFeatures: const [
                                                    FontFeature.tabularFigures()
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),

                                  const Spacer(),

                                  // 弹幕总开关与设置
                                  if (widget.danmakuController != null) ...[
                                    ListenableBuilder(
                                      listenable: widget.danmakuController!,
                                      builder: (context, _) {
                                        final isEnabled =
                                            widget.danmakuController!.settings.enabled;
                                        return _buildBarButton(
                                          icon: DanmakuToggleIcon(
                                            enabled: isEnabled,
                                            size: mainIconSize,
                                            color: Colors.white,
                                            checkColor: primaryColor,
                                          ),
                                          size: mainBtnSize,
                                          onTap: () {
                                            _handleUserActivity();
                                            final current =
                                                widget.danmakuController!.settings;
                                            widget.danmakuController!.updateSettings(
                                              current.copyWith(enabled: !isEnabled),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                    if (!isUltraNarrow) ...[
                                      SizedBox(width: btnSpacing),
                                      _buildBarButton(
                                        icon: DanmakuSettingsIcon(
                                          size: mainIconSize,
                                          color: _activePanel ==
                                                  _DesktopActivePanel.danmaku
                                              ? primaryColor
                                              : Colors.white,
                                        ),
                                        size: mainBtnSize,
                                        onTap: () =>
                                            _togglePanel(_DesktopActivePanel.danmaku),
                                      ),
                                    ],
                                    SizedBox(width: btnSpacing),
                                  ],

                                  // 倍速按钮
                                  ValueListenableBuilder<PlaybackCoreState>(
                                    valueListenable: widget.controller.core,
                                    builder: (context, coreState, _) {
                                      final rate = coreState.playbackRate;
                                      final rateLabel =
                                          rate == 1.0 ? '倍速' : '${rate}x';
                                      return Material(
                                        key: _speedButtonKey,
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          onTap: () {
                                            _ensureKeyboardFocus();
                                            _toggleSpeedPopup();
                                          },
                                          child: Container(
                                            height: isUltraNarrow ? 26 : 28,
                                            padding: EdgeInsets.symmetric(
                                                horizontal: isUltraNarrow ? 6 : 8,
                                                vertical: 2),
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: _showSpeedPopup
                                                  ? primaryColor
                                                      .withValues(alpha: 0.25)
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            child: Text(
                                              rateLabel,
                                              style: appTextStyle(
                                                color: _showSpeedPopup
                                                    ? primaryColor
                                                    : Colors.white,
                                                fontSize: isUltraNarrow
                                                    ? 11.0
                                                    : 12.0,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),

                                  SizedBox(width: btnSpacing),

                                  // 播放设置浮窗按钮
                                  _buildBarButton(
                                    icon: Icon(
                                      Icons.tune_rounded,
                                      color: _activePanel ==
                                              _DesktopActivePanel.settings
                                          ? primaryColor
                                          : Colors.white,
                                      size: mainIconSize,
                                    ),
                                    size: mainBtnSize,
                                    onTap: () => _togglePanel(
                                        _DesktopActivePanel.settings),
                                  ),

                                  SizedBox(width: btnSpacing),

                                  // 桌面专属：悬停展开音量按钮 (Hover 激活上方浮动面板，支持悬停区滚轮)
                                  MouseRegion(
                                    key: _volumeButtonKey,
                                    onEnter: (_) => _onVolumeEnter(),
                                    onExit: (_) => _onVolumeExit(),
                                    child: Listener(
                                      onPointerSignal: (event) {
                                        if (event is PointerScrollEvent) {
                                          _handleVolumeScroll(event);
                                        }
                                      },
                                      child: ValueListenableBuilder<PlaybackCoreState>(
                                        valueListenable: widget.controller.core,
                                        builder: (context, coreState, _) {
                                          final isMuted = coreState.muted ||
                                              coreState.volume <= 0.001;
                                          return _buildBarButton(
                                            icon: Icon(
                                              isMuted
                                                  ? Icons.volume_off_rounded
                                                  : (coreState.volume > 0.5
                                                      ? Icons.volume_up_rounded
                                                      : Icons.volume_down_rounded),
                                              color: isMuted
                                                  ? Colors.white54
                                                  : Colors.white,
                                              size: mainIconSize,
                                            ),
                                            size: mainBtnSize,
                                            onTap: () {
                                              _handleUserActivity();
                                              widget.controller.toggleMute();
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                  ),

                                  SizedBox(width: btnSpacing),

                                  // 剧场模式切换 (T，小窗时自适应隐藏以腾出弹性空间)
                                  if (widget.onToggleTheaterMode != null &&
                                      !widget.isFullscreen &&
                                      !isUltraNarrow) ...[
                                    _buildBarButton(
                                      icon: Icon(
                                        widget.isTheaterMode
                                            ? Icons.view_sidebar_rounded
                                            : Icons.rectangle_outlined,
                                        color: widget.isTheaterMode
                                            ? primaryColor
                                            : Colors.white,
                                        size: mainIconSize,
                                      ),
                                      size: mainBtnSize,
                                      onTap: () {
                                        _handleUserActivity();
                                        widget.onToggleTheaterMode?.call();
                                      },
                                    ),
                                    SizedBox(width: btnSpacing),
                                  ],

                                  // 全屏切换 (极窄小窗下折叠应用全屏，仅保留真全屏主入口)
                                  if (widget.onToggleAppFullscreen != null &&
                                      widget.onToggleTrueFullscreen != null) ...[
                                    if (!isUltraNarrow) ...[
                                      _buildBarButton(
                                        icon: Icon(
                                          widget.isAppFullscreen
                                              ? Icons.close_fullscreen_rounded
                                              : Icons.fit_screen_rounded,
                                          color: widget.isAppFullscreen
                                              ? primaryColor
                                              : Colors.white,
                                          size: mainIconSize,
                                        ),
                                        size: mainBtnSize,
                                        onTap: () {
                                          _handleUserActivity();
                                          widget.onToggleAppFullscreen?.call();
                                        },
                                      ),
                                      SizedBox(width: btnSpacing),
                                    ],
                                    _buildBarButton(
                                      icon: Icon(
                                        widget.isTrueFullscreen
                                            ? Icons.fullscreen_exit_rounded
                                            : Icons.fullscreen_rounded,
                                        color: Colors.white,
                                        size: mainIconSize,
                                      ),
                                      size: mainBtnSize,
                                      onTap: () {
                                        _handleUserActivity();
                                        widget.onToggleTrueFullscreen?.call();
                                      },
                                    ),
                                  ] else if (widget.onToggleFullscreen != null) ...[
                                    _buildBarButton(
                                      icon: Icon(
                                        widget.isFullscreen
                                            ? Icons.fullscreen_exit_rounded
                                            : Icons.fullscreen_rounded,
                                        color: Colors.white,
                                        size: mainIconSize,
                                      ),
                                      size: mainBtnSize,
                                      onTap: () {
                                        _handleUserActivity();
                                        widget.onToggleFullscreen?.call();
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ],
                  ),
                ),
              ),

              // 4. 倍速气泡浮层 (桌面定位)
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
                Positioned(
                  right: _calcSpeedPopupRight(playerWidth, speedPopupWidth),
                  bottom: _calcSpeedPopupBottom(playerHeight),
                  child: PlayerSpeedPopup(
                    controller: widget.controller,
                    primaryColor: primaryColor,
                    compact: isUltraNarrow,
                    onSelectSpeed: (speed) {
                      widget.controller.setPlaybackRate(speed);
                      setState(() => _showSpeedPopup = false);
                      _startHideTimer();
                    },
                  ),
                ),
              ],

              // 4.1 垂直音量浮动面板（悬停激活，完全位于最外层 Stack 视口内，HitTest 100% 畅通无盲区）
              if (_isVolumeHovered) ...[
                Positioned(
                  right: _calcVolumePopupRight(playerWidth),
                  bottom: 46,
                  child: MouseRegion(
                    onEnter: (_) => _onVolumeEnter(),
                    onExit: (_) => _onVolumeExit(),
                    child: Listener(
                      onPointerSignal: (event) {
                        if (event is PointerScrollEvent) {
                          _handleVolumeScroll(event);
                        }
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            width: 36,
                            height: 142,
                            padding: const EdgeInsets.symmetric(
                                vertical: 10, horizontal: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xEE16161C),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.16),
                                width: 0.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ValueListenableBuilder<PlaybackCoreState>(
                              valueListenable: widget.controller.core,
                              builder: (context, coreState, _) {
                                final vol =
                                    coreState.muted ? 0.0 : coreState.volume;
                                final volPercent = (vol * 100).round();
                                return Column(
                                  children: [
                                    Text(
                                      '$volPercent',
                                      style: appTextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Expanded(
                                      child: VerticalVolumeBar(
                                        volume: vol,
                                        activeColor: primaryColor,
                                        onChanged: (newVol) {
                                          _ensureKeyboardFocus();
                                          _handleUserActivity();
                                          widget.controller.setVolume(newVol);
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // 5. 全屏模式下专属 Popover 浮动面板（仅全屏高度充裕时使用，普通窗口走桌面模态弹窗）
              if (widget.isFullscreen &&
                  _activePanel != _DesktopActivePanel.none) ...[
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() => _activePanel = _DesktopActivePanel.none);
                      _startHideTimer();
                    },
                    child: const ColoredBox(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 46,
                  child: PlayerFloatingPanel(
                    title: _activePanel == _DesktopActivePanel.settings
                        ? '播放设置'
                        : '弹幕设置',
                    icon: _activePanel == _DesktopActivePanel.settings
                        ? Icons.tune_rounded
                        : Icons.subtitles_rounded,
                    primaryColor: primaryColor,
                    onClose: () {
                      setState(() => _activePanel = _DesktopActivePanel.none);
                      _startHideTimer();
                    },
                    child: _activePanel == _DesktopActivePanel.settings
                        ? PlayerSettingsPanelBody(
                            controller: widget.controller,
                            primaryColor: primaryColor,
                            autoSkipOpedNotifier: _autoSkipOpedNotifier,
                            autoPlayNextNotifier: _autoPlayNextNotifier,
                            opedSegment: widget.opedSegment,
                            isCurrentlyInOp: _isCurrentlyInOp,
                            isCurrentlyInEd: _isCurrentlyInEd,
                            onSkipCurrentSegment: _skipCurrentSegment,
                            onDismiss: () => setState(
                                () => _activePanel = _DesktopActivePanel.none),
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

              // 6. 截图成功微光浮窗反馈
              PlayerScreenshotFeedback(
                bytes: _lastScreenshotBytes,
                visible: _screenshotFeedbackVisible,
                isFullscreen: widget.isFullscreen,
              ),

              // 7. OP/ED 跳过浮标
              Positioned(
                left: 20,
                bottom: 60,
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
      ),
    ),
  );
  }
}
