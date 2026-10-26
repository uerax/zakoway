import 'package:flutter/material.dart';

/// 播放器渐变暗角方向
enum PlayerScrimDirection {
  /// 顶部向下渐变暗角（用于保护返回键、标题、清晰度等控件）
  top,

  /// 底部向上渐变暗角（用于保护进度条、播放按钮、时间戳等控件）
  bottom,
}

/// 播放器通用渐变暗角组件 (Player Scrim)
///
/// 采用非线性多阶缓动曲线（仿自然 Ease 衰减），压暗视频画面的同时保持画面通透与质感，
/// 避免白色或高亮背景与控制条（白字、白图标、全宽进度条）融合导致控件隐形。
///
/// 内部自带 [IgnorePointer] 与 [Positioned]，置于控制层 [Stack] 的底层即可。
class PlayerScrim extends StatelessWidget {
  const PlayerScrim({
    super.key,
    required this.direction,
    this.height,
    this.isFullscreen = false,
  });

  /// 顶部向下渐变暗角
  const PlayerScrim.top({
    super.key,
    this.height,
    this.isFullscreen = false,
  }) : direction = PlayerScrimDirection.top;

  /// 底部向上渐变暗角
  const PlayerScrim.bottom({
    super.key,
    this.height,
    this.isFullscreen = false,
  }) : direction = PlayerScrimDirection.bottom;

  /// 渐变暗角方向
  final PlayerScrimDirection direction;

  /// 自定义高度。若为空，则根据 [direction] 和 [isFullscreen] 自动匹配最佳度量
  final double? height;

  /// 是否处于全屏模式（全屏下拥有更充裕的纵向空间，渐变拉长以提供更柔和的通透视效）
  final bool isFullscreen;

  // 顶部渐变色阶（非线性缓动衰减）
  static const List<Color> _topColors = [
    Color(0xA6000000), // ~65% alpha 纯黑
    Color(0x6B000000), // ~42%
    Color(0x33000000), // ~20%
    Color(0x0F000000), // ~6%
    Colors.transparent,
  ];

  static const List<double> _topStops = [0.0, 0.28, 0.58, 0.82, 1.0];

  // 底部渐变色阶（最底端约 72% 纯黑，为白色文字、图标与进度条提供坚实对比基底）
  static const List<Color> _bottomColors = [
    Color(0xB8000000), // ~72% alpha 纯黑
    Color(0x7A000000), // ~48%
    Color(0x3D000000), // ~24%
    Color(0x12000000), // ~7%
    Colors.transparent,
  ];

  static const List<double> _bottomStops = [0.0, 0.30, 0.60, 0.82, 1.0];

  @override
  Widget build(BuildContext context) {
    final isTop = direction == PlayerScrimDirection.top;

    final double effectiveHeight = height ??
        (isTop
            ? (isFullscreen ? 92.0 : 68.0)
            : (isFullscreen ? 128.0 : 92.0));

    return Positioned(
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      left: 0,
      right: 0,
      height: effectiveHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: isTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: isTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: isTop ? _topColors : _bottomColors,
              stops: isTop ? _topStops : _bottomStops,
            ),
          ),
        ),
      ),
    );
  }
}
