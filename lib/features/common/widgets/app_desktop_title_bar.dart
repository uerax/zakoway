import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../../../../core/utils/appearance_manager.dart';

/// 桌面端全局沉浸式窗口骨架
///
/// 架构设计与规范：
/// 1. 深度集成 window_manager 隐藏操作系统传统非客户区标题栏，使 Flutter 画布 100% 通顶沉浸；
/// 2. 自动区分 Windows 与 macOS：
///    - Windows: 左侧放置 32x32 官方品牌 Logo，中间大片留白拖拽区，右侧放置 Windows 现代极简三按键；
///    - macOS: 左侧保留 78px 避让原生系统红绿灯，中间大片留白拖拽区，右侧放置 32x32 官方品牌 Logo；
///    - 两端均不显示文字标题与搜索栏，形成高雅的视觉平衡；
/// 3. 动态监听全屏状态：在播放器进入全屏模式时自动收缩隐藏，退出全屏后平滑恢复。
class AppDesktopWindowFrame extends StatefulWidget {
  const AppDesktopWindowFrame({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<AppDesktopWindowFrame> createState() => _AppDesktopWindowFrameState();
}

class _AppDesktopWindowFrameState extends State<AppDesktopWindowFrame>
    with WindowListener {
  bool _isFullScreen = false;

  @override
  void initState() {
    super.initState();
    _checkInitialFullScreenState();
  }

  Future<void> _checkInitialFullScreenState() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        windowManager.addListener(this);
        final full = await windowManager.isFullScreen();
        if (mounted && full != _isFullScreen) {
          setState(() => _isFullScreen = full);
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        windowManager.removeListener(this);
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  void onWindowEnterFullScreen() {
    if (mounted) setState(() => _isFullScreen = true);
  }

  @override
  void onWindowLeaveFullScreen() {
    if (mounted) setState(() => _isFullScreen = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktopPlatform = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);

    if (!isDesktopPlatform) {
      return widget.child;
    }

    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Column(
        children: [
          // 0. 桌面端自适应沉浸顶栏（与当前全局主题 100% 融合底色，全屏时自动收缩隐藏）
          if (!_isFullScreen) const AppDesktopTitleBar(),
          // 1. 页面内容呈现区：滚动视图严格在此边界内裁剪，绝对不向上穿透重叠
          Expanded(child: widget.child),
        ],
      ),
    );
  }
}

/// 桌面端平台自适应沉浸顶栏
class AppDesktopTitleBar extends StatefulWidget {
  const AppDesktopTitleBar({
    super.key,
    this.height = 44.0,
  });

  final double height;

  @override
  State<AppDesktopTitleBar> createState() => _AppDesktopTitleBarState();
}

class _AppDesktopTitleBarState extends State<AppDesktopTitleBar> with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _checkMaximized();
  }

  Future<void> _checkMaximized() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        windowManager.addListener(this);
        final max = await windowManager.isMaximized();
        if (mounted && max != _isMaximized) {
          setState(() => _isMaximized = max);
        }
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      try {
        windowManager.removeListener(this);
      } catch (_) {}
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    if (mounted) setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (mounted) setState(() => _isMaximized = false);
  }

  @override
  Widget build(BuildContext context) {
    final isMac = !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 官方 32x32 高清品牌 Logo 挂件
    final logoWidget = ListenableBuilder(
      listenable: AppearanceManager.instance,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: AppearanceManager.instance.buildAppLogoWidget(
            size: 32,
            borderRadius: 8,
          ),
        );
      },
    );

    return Container(
      height: widget.height,
      color: theme.scaffoldBackgroundColor,
      child: Material(
        color: Colors.transparent,
        child: Row(
          children: [
            if (isMac) ...[
              // macOS 左侧：78px 原生红绿灯安全避让区
              const SizedBox(width: 78),
            ] else ...[
              // Windows 左侧：高清官方品牌 Logo
              Padding(
                padding: const EdgeInsets.only(left: 14.0),
                child: logoWidget,
              ),
            ],

            // 中间：大片纯净留白窗口拖拽区（支持双击最大化/还原，按住移动窗口）
            Expanded(
              child: DragToMoveArea(
                child: Container(
                  height: widget.height,
                  color: Colors.transparent,
                ),
              ),
            ),

            if (isMac) ...[
              // macOS 右侧：高清官方品牌 Logo（与左侧红绿灯形成绝妙平衡）
              Padding(
                padding: const EdgeInsets.only(right: 14.0),
                child: logoWidget,
              ),
            ] else ...[
              // Windows 右侧：现代 Fluent 极简三按键组
              _WindowsTitleBarButtons(
                isMaximized: _isMaximized,
                height: widget.height,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Windows 原生 Fluent 风格极简三按键组合
class _WindowsTitleBarButtons extends StatelessWidget {
  const _WindowsTitleBarButtons({
    required this.isMaximized,
    required this.height,
  });

  final bool isMaximized;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. 最小化
        _WindowsCaptionButton(
          height: height,
          semanticLabel: '最小化',
          onTap: () async {
            try {
              await windowManager.minimize();
            } catch (_) {}
          },
          painter: const _MinimizeIconPainter(),
        ),

        // 2. 最大化 / 还原
        _WindowsCaptionButton(
          height: height,
          semanticLabel: isMaximized ? '还原' : '最大化',
          onTap: () async {
            try {
              if (isMaximized) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            } catch (_) {}
          },
          painter: isMaximized
              ? const _RestoreIconPainter()
              : const _MaximizeIconPainter(),
        ),

        // 3. 关闭
        _WindowsCaptionButton(
          height: height,
          isClose: true,
          semanticLabel: '关闭',
          onTap: () async {
            try {
              await windowManager.close();
            } catch (_) {}
          },
          painter: const _CloseIconPainter(),
        ),
      ],
    );
  }
}

class _WindowsCaptionButton extends StatefulWidget {
  const _WindowsCaptionButton({
    required this.onTap,
    required this.painter,
    this.isClose = false,
    this.semanticLabel,
    required this.height,
  });

  final VoidCallback onTap;
  final CustomPainter painter;
  final bool isClose;
  final String? semanticLabel;
  final double height;

  @override
  State<_WindowsCaptionButton> createState() => _WindowsCaptionButtonState();
}

class _WindowsCaptionButtonState extends State<_WindowsCaptionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Color bgColor = Colors.transparent;
    Color iconColor = isDark
        ? Colors.white.withValues(alpha: 0.82)
        : Colors.black.withValues(alpha: 0.75);

    if (_isHovered) {
      if (widget.isClose) {
        bgColor = const Color(0xFFE81123);
        iconColor = Colors.white;
      } else {
        bgColor = isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.08);
      }
    }

    Widget button = MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: widget.height,
          color: bgColor,
          alignment: Alignment.center,
          child: CustomPaint(
            size: const Size(10, 10),
            painter: _TintedCustomPainter(
              basePainter: widget.painter,
              color: iconColor,
            ),
          ),
        ),
      ),
    );

    if (widget.semanticLabel != null) {
      button = Semantics(
        label: widget.semanticLabel,
        button: true,
        child: button,
      );
    }

    return button;
  }
}

class _TintedCustomPainter extends CustomPainter {
  const _TintedCustomPainter({
    required this.basePainter,
    required this.color,
  });

  final CustomPainter basePainter;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (basePainter is _TintablePainter) {
      (basePainter as _TintablePainter).paintWithColor(canvas, size, color);
    }
  }

  @override
  bool shouldRepaint(_TintedCustomPainter oldDelegate) =>
      color != oldDelegate.color || basePainter != oldDelegate.basePainter;
}

abstract class _TintablePainter {
  void paintWithColor(Canvas canvas, Size size, Color color);
}

class _MinimizeIconPainter extends CustomPainter implements _TintablePainter {
  const _MinimizeIconPainter();

  @override
  void paintWithColor(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    // 居中水平横线 10px
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), paint);
  }

  @override
  void paint(Canvas canvas, Size size) => paintWithColor(canvas, size, Colors.white);

  @override
  bool shouldRepaint(_MinimizeIconPainter oldDelegate) => false;
}

class _MaximizeIconPainter extends CustomPainter implements _TintablePainter {
  const _MaximizeIconPainter();

  @override
  void paintWithColor(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    // 单矩形线框 10x10
    canvas.drawRect(Rect.fromLTWH(0.5, 0.5, size.width - 1.0, size.height - 1.0), paint);
  }

  @override
  void paint(Canvas canvas, Size size) => paintWithColor(canvas, size, Colors.white);

  @override
  bool shouldRepaint(_MaximizeIconPainter oldDelegate) => false;
}

class _RestoreIconPainter extends CustomPainter implements _TintablePainter {
  const _RestoreIconPainter();

  @override
  void paintWithColor(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // 前景小框 8x8
    canvas.drawRect(Rect.fromLTWH(0.5, 2.5, size.width - 2.5, size.height - 2.5), paint);
    // 后景框顶边与右边
    canvas.drawLine(const Offset(2.5, 2.5), const Offset(2.5, 0.5), paint);
    canvas.drawLine(const Offset(2.5, 0.5), Offset(size.width - 0.5, 0.5), paint);
    canvas.drawLine(Offset(size.width - 0.5, 0.5), Offset(size.width - 0.5, size.height - 2.5), paint);
    canvas.drawLine(Offset(size.width - 0.5, size.height - 2.5), Offset(size.width - 2.5, size.height - 2.5), paint);
  }

  @override
  void paint(Canvas canvas, Size size) => paintWithColor(canvas, size, Colors.white);

  @override
  bool shouldRepaint(_RestoreIconPainter oldDelegate) => false;
}

class _CloseIconPainter extends CustomPainter implements _TintablePainter {
  const _CloseIconPainter();

  @override
  void paintWithColor(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(0.5, 0.5), Offset(size.width - 0.5, size.height - 0.5), paint);
    canvas.drawLine(Offset(size.width - 0.5, 0.5), Offset(0.5, size.height - 0.5), paint);
  }

  @override
  void paint(Canvas canvas, Size size) => paintWithColor(canvas, size, Colors.white);

  @override
  bool shouldRepaint(_CloseIconPainter oldDelegate) => false;
}
