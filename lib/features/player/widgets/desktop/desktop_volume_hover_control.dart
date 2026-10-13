import 'dart:async';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../../../core/utils/font_manager.dart';
import '../../controller/playback_controller.dart';
import '../../controller/playback_state.dart';
import '../controls/popups/player_vertical_volume_popup.dart';

/// 桌面端音量悬停展开与滚轮专属调节组件：
/// 1. 鼠标悬停在音量按钮上方时平滑展开垂直滑槽；
/// 2. 只有在展开且鼠标处于悬停区域内时，滚轮滚动才调整音量，杜绝全局滚轮误触；
/// 3. 单击音量图标直接切换静音/取消静音。
class DesktopVolumeHoverControl extends StatefulWidget {
  const DesktopVolumeHoverControl({
    super.key,
    required this.controller,
    required this.primaryColor,
    required this.iconSize,
    required this.buttonSize,
    required this.onUserActivity,
  });

  final ZakowayPlaybackController controller;
  final Color primaryColor;
  final double iconSize;
  final double buttonSize;
  final VoidCallback onUserActivity;

  @override
  State<DesktopVolumeHoverControl> createState() =>
      _DesktopVolumeHoverControlState();
}

class _DesktopVolumeHoverControlState extends State<DesktopVolumeHoverControl> {
  bool _isHovered = false;
  Timer? _closeTimer;

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _onEnter() {
    _closeTimer?.cancel();
    if (!_isHovered) {
      setState(() {
        _isHovered = true;
      });
    }
    widget.onUserActivity();
  }

  void _onExit() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 320), () {
      if (mounted && _isHovered) {
        setState(() {
          _isHovered = false;
        });
      }
    });
  }

  void _handleScroll(PointerScrollEvent event) {
    if (!_isHovered) return;
    widget.onUserActivity();
    final curVol = widget.controller.core.value.volume;
    // 向上滚动 dy < 0 音量增加，向下滚动 dy > 0 音量减少
    final step = event.scrollDelta.dy < 0 ? 0.05 : -0.05;
    final nextVol = (curVol + step).clamp(0.0, 1.0);
    widget.controller.setVolume(nextVol);
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onEnter(),
      onExit: (_) => _onExit(),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            _handleScroll(event);
          }
        },
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            // 1. 悬停展开的毛玻璃垂直音量调节面板
            Positioned(
              bottom: widget.buttonSize + 8,
              child: AnimatedOpacity(
                opacity: _isHovered ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: AnimatedScale(
                  scale: _isHovered ? 1.0 : 0.88,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  child: IgnorePointer(
                    ignoring: !_isHovered,
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
                              final vol = coreState.muted ? 0.0 : coreState.volume;
                              final volPercent = (vol * 100).round();
                              return Column(
                                children: [
                                  Text(
                                    '$volPercent',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'MiSans',
                                      fontFamilyFallback:
                                          FontManager.fallbackFontFamilies,
                                      fontFeatures: [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Expanded(
                                    child: VerticalVolumeBar(
                                      volume: vol,
                                      activeColor: widget.primaryColor,
                                      onChanged: (newVol) {
                                        widget.onUserActivity();
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
            ),

            // 2. 音量按钮本身（单击切换静音）
            ValueListenableBuilder<PlaybackCoreState>(
              valueListenable: widget.controller.core,
              builder: (context, coreState, _) {
                final isMuted = coreState.muted || coreState.volume <= 0.001;
                return Tooltip(
                  message: isMuted ? '取消静音 (M)' : '静音 (M) / 悬停调音量',
                  child: Material(
                    color: Colors.transparent,
                    child: InkResponse(
                      radius: widget.buttonSize * 0.58,
                      highlightShape: BoxShape.circle,
                      onTap: () {
                        widget.onUserActivity();
                        widget.controller.toggleMute();
                      },
                      child: SizedBox(
                        width: widget.buttonSize,
                        height: widget.buttonSize,
                        child: Center(
                          child: Icon(
                            isMuted
                                ? Icons.volume_off_rounded
                                : (coreState.volume > 0.5
                                    ? Icons.volume_up_rounded
                                    : Icons.volume_down_rounded),
                            color: isMuted ? Colors.white54 : Colors.white,
                            size: widget.iconSize,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
