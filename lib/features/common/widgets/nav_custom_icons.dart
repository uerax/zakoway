import 'package:flutter/material.dart';

/// 首页果冻图标组件（Jelly Icon）
///
/// 提取自应用专属吉祥物（泡面碗角色头顶的 Q 弹果冻）：
/// - 未选中态：2.0 粗细圆角线框外轮廓 + 实心圆点双眼；
/// - 选中态：实心填充主体 + 负空间镂空双眼 + 右上方晶莹高光切口，呈现晶莹剔透与 Q 弹质感。
class JellyNavIcon extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final double size;

  const JellyNavIcon({
    super.key,
    required this.color,
    required this.isSelected,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: JellyIconPainter(
        color: color,
        isSelected: isSelected,
      ),
    );
  }
}

/// 分类企鹅图标组件（Penguin Icon）
///
/// 专为分类导航设计的极简萌系企鹅剪影：
/// - 未选中态：圆润身躯、微张小翅膀与脚蹼轮廓线 + 肚皮弧线与小嘴喙；
/// - 选中态：实心身躯与脚蹼 + 经典企鹅负空间白色大肚皮 + 镂空双眼与小三角嘴，层级分明且在小屏上极具辨识度。
class PenguinNavIcon extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final double size;

  const PenguinNavIcon({
    super.key,
    required this.color,
    required this.isSelected,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: PenguinIconPainter(
        color: color,
        isSelected: isSelected,
      ),
    );
  }
}

/// 果冻图标 CustomPainter
class JellyIconPainter extends CustomPainter {
  final Color color;
  final bool isSelected;

  const JellyIconPainter({
    required this.color,
    required this.isSelected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;

    Offset p(double x, double y) => Offset(x * sx, y * sy);

    // 构建果冻外轮廓（圆润宽底 + 头顶两只萌系小凸起耳朵）
    final bodyPath = Path()
      ..moveTo(p(5.0, 19.2).dx, p(5.0, 19.2).dy)
      // 底部平缓微弧基线
      ..quadraticBezierTo(p(12.0, 20.0).dx, p(12.0, 20.0).dy, p(19.0, 19.2).dx, p(19.0, 19.2).dy)
      // 右下圆角过渡
      ..cubicTo(p(20.4, 19.2).dx, p(20.4, 19.2).dy, p(20.8, 17.8).dx, p(20.8, 17.8).dy, p(20.0, 16.2).dx, p(20.0, 16.2).dy)
      // 右侧向上微微内收的腰身
      ..cubicTo(p(19.2, 14.2).dx, p(19.2, 14.2).dy, p(18.2, 10.8).dx, p(18.2, 10.8).dy, p(18.2, 8.5).dx, p(18.2, 8.5).dy)
      // 右耳小尖角与弧顶
      ..cubicTo(p(18.2, 6.2).dx, p(18.2, 6.2).dy, p(17.4, 4.5).dx, p(17.4, 4.5).dy, p(16.2, 4.5).dx, p(16.2, 4.5).dy)
      // 右耳内侧过渡到底凹中心
      ..cubicTo(p(15.0, 4.5).dx, p(15.0, 4.5).dy, p(13.8, 6.5).dx, p(13.8, 6.5).dy, p(12.0, 7.2).dx, p(12.0, 7.2).dy)
      // 底凹中心向左耳过渡
      ..cubicTo(p(10.2, 6.5).dx, p(10.2, 6.5).dy, p(9.0, 4.5).dx, p(9.0, 4.5).dy, p(7.8, 4.5).dx, p(7.8, 4.5).dy)
      // 左耳外侧向左侧腰身过渡
      ..cubicTo(p(6.6, 4.5).dx, p(6.6, 4.5).dy, p(5.8, 6.2).dx, p(5.8, 6.2).dy, p(5.8, 8.5).dx, p(5.8, 8.5).dy)
      // 左侧向下延展腰身
      ..cubicTo(p(5.8, 10.8).dx, p(5.8, 10.8).dy, p(4.8, 14.2).dx, p(4.8, 14.2).dy, p(4.0, 16.2).dx, p(4.0, 16.2).dy)
      // 左下圆角过渡
      ..cubicTo(p(3.2, 17.8).dx, p(3.2, 17.8).dy, p(3.6, 19.2).dx, p(3.6, 19.2).dy, p(5.0, 19.2).dx, p(5.0, 19.2).dy)
      ..close();

    if (!isSelected) {
      // 未选中态：统一 2.0 像素圆角线框
      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * sx
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(bodyPath, strokePaint);

      // 双眼实心圆点
      final eyePaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawCircle(p(9.3, 13.0), 1.1 * sx, eyePaint);
      canvas.drawCircle(p(14.7, 13.0), 1.1 * sx, eyePaint);
    } else {
      // 选中态：主体实心填充，眼睛与右上高光采用负空间差集镂空（支持任意背景通透折射）
      final eyesAndHighlight = Path()
        ..addOval(Rect.fromCircle(center: p(9.3, 13.0), radius: 1.15 * sx))
        ..addOval(Rect.fromCircle(center: p(14.7, 13.0), radius: 1.15 * sx))
        ..addRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: p(14.8, 8.8), width: 2.4 * sx, height: 1.2 * sy),
          Radius.circular(0.6 * sx),
        ));

      final filledJelly = Path.combine(PathOperation.difference, bodyPath, eyesAndHighlight);

      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawPath(filledJelly, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant JellyIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isSelected != isSelected;
}

/// 企鹅图标 CustomPainter
class PenguinIconPainter extends CustomPainter {
  final Color color;
  final bool isSelected;

  const PenguinIconPainter({
    required this.color,
    required this.isSelected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;

    Offset p(double x, double y) => Offset(x * sx, y * sy);

    // 企鹅身体轮廓（圆润头部 + 两侧微张鳍肢小翅膀 + 丰满底身）
    final bodyPath = Path()
      ..moveTo(p(12.0, 4.0).dx, p(12.0, 4.0).dy)
      // 头部右侧圆弧
      ..cubicTo(p(14.8, 4.0).dx, p(14.8, 4.0).dy, p(16.5, 5.5).dx, p(16.5, 5.5).dy, p(16.5, 8.0).dx, p(16.5, 8.0).dy)
      // 头部向右翅膀过渡
      ..cubicTo(p(16.5, 9.8).dx, p(16.5, 9.8).dy, p(17.5, 11.5).dx, p(17.5, 11.5).dy, p(18.2, 12.8).dx, p(18.2, 12.8).dy)
      // 右翅膀外展并收尖
      ..cubicTo(p(19.6, 14.2).dx, p(19.6, 14.2).dy, p(20.4, 15.8).dx, p(20.4, 15.8).dy, p(19.8, 16.8).dx, p(19.8, 16.8).dy)
      // 右翅膀底部回归身躯
      ..cubicTo(p(19.2, 17.5).dx, p(19.2, 17.5).dy, p(18.0, 17.2).dx, p(18.0, 17.2).dy, p(17.0, 16.0).dx, p(17.0, 16.0).dy)
      // 右侧身躯到底部
      ..cubicTo(p(16.8, 17.8).dx, p(16.8, 17.8).dy, p(14.8, 18.8).dx, p(14.8, 18.8).dy, p(12.0, 18.8).dx, p(12.0, 18.8).dy)
      // 左侧身躯从底部起
      ..cubicTo(p(9.2, 18.8).dx, p(9.2, 18.8).dy, p(7.2, 17.8).dx, p(7.2, 17.8).dy, p(7.0, 16.0).dx, p(7.0, 16.0).dy)
      // 左翅膀底部向外延展
      ..cubicTo(p(6.0, 17.2).dx, p(6.0, 17.2).dy, p(4.8, 17.5).dx, p(4.8, 17.5).dy, p(4.2, 16.8).dx, p(4.2, 16.8).dy)
      // 左翅膀外展尖端
      ..cubicTo(p(3.6, 15.8).dx, p(3.6, 15.8).dy, p(4.4, 14.2).dx, p(4.4, 14.2).dy, p(5.8, 12.8).dx, p(5.8, 12.8).dy)
      // 左翅膀向左头部过渡
      ..cubicTo(p(6.5, 11.5).dx, p(6.5, 11.5).dy, p(7.5, 9.8).dx, p(7.5, 9.8).dy, p(7.5, 8.0).dx, p(7.5, 8.0).dy)
      // 头部左侧圆弧回归头顶
      ..cubicTo(p(7.5, 5.5).dx, p(7.5, 5.5).dy, p(9.2, 4.0).dx, p(9.2, 4.0).dy, p(12.0, 4.0).dx, p(12.0, 4.0).dy)
      ..close();

    // 左右脚蹼
    final leftFoot = RRect.fromRectAndRadius(
      Rect.fromLTWH(8.5 * sx, 18.2 * sy, 2.4 * sx, 1.8 * sy),
      Radius.circular(0.9 * sx),
    );
    final rightFoot = RRect.fromRectAndRadius(
      Rect.fromLTWH(13.1 * sx, 18.2 * sy, 2.4 * sx, 1.8 * sy),
      Radius.circular(0.9 * sx),
    );

    if (!isSelected) {
      // 未选中态：线框风格
      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * sx
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(bodyPath, strokePaint);

      // 脚蹼轻量线描
      canvas.drawRRect(leftFoot, strokePaint);
      canvas.drawRRect(rightFoot, strokePaint);

      // 双眼实心圆点
      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p(9.8, 8.8), 0.9 * sx, fillPaint);
      canvas.drawCircle(p(14.2, 8.8), 0.9 * sx, fillPaint);

      // 小嘴喙（小倒三角）
      final beakPath = Path()
        ..moveTo(p(11.0, 10.2).dx, p(11.0, 10.2).dy)
        ..lineTo(p(13.0, 10.2).dx, p(13.0, 10.2).dy)
        ..lineTo(p(12.0, 11.8).dx, p(12.0, 11.8).dy)
        ..close();
      canvas.drawPath(beakPath, fillPaint);

      // 肚皮弧线（微描边）
      final bellyLine = Path()
        ..moveTo(p(9.2, 14.5).dx, p(9.2, 14.5).dy)
        ..quadraticBezierTo(p(12.0, 17.5).dx, p(12.0, 17.5).dy, p(14.8, 14.5).dx, p(14.8, 14.5).dy);
      final thinStroke = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3 * sx
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(bellyLine, thinStroke);
    } else {
      // 选中态：身体与脚蹼实心填充，企鹅标志性白色肚皮与眼睛、嘴喙负空间镂空
      final completeBody = Path()
        ..addPath(bodyPath, Offset.zero)
        ..addRRect(leftFoot)
        ..addRRect(rightFoot);

      final bellyAndFaceCutout = Path()
        // 眼睛镂空
        ..addOval(Rect.fromCircle(center: p(9.8, 8.8), radius: 0.95 * sx))
        ..addOval(Rect.fromCircle(center: p(14.2, 8.8), radius: 0.95 * sx))
        // 嘴喙镂空
        ..moveTo(p(11.0, 10.2).dx, p(11.0, 10.2).dy)
        ..lineTo(p(13.0, 10.2).dx, p(13.0, 10.2).dy)
        ..lineTo(p(12.0, 11.8).dx, p(12.0, 11.8).dy)
        ..close()
        // 经典企鹅圆弧大肚皮镂空
        ..addOval(Rect.fromCenter(
          center: p(12.0, 15.0),
          width: 6.8 * sx,
          height: 5.6 * sy,
        ));

      final filledPenguin = Path.combine(PathOperation.difference, completeBody, bellyAndFaceCutout);

      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawPath(filledPenguin, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant PenguinIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isSelected != isSelected;
}

/// 用户/我的笑脸图标组件（User / Smile Icon）
///
/// 专为个人中心设计的极简萌系笑脸轮廓：
/// - 未选中态：2.0 像素圆角线框外轮廓 + 实心圆点双眼 + 弧形微笑嘴；
/// - 选中态：实心圆形主体 + 负空间镂空双眼与微笑嘴，呈现灵动可爱的萌系表情。
class UserNavIcon extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final double size;

  const UserNavIcon({
    super.key,
    required this.color,
    required this.isSelected,
    this.size = 24.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: UserIconPainter(
        color: color,
        isSelected: isSelected,
      ),
    );
  }
}

/// 用户笑脸图标 CustomPainter
class UserIconPainter extends CustomPainter {
  final Color color;
  final bool isSelected;

  const UserIconPainter({
    required this.color,
    required this.isSelected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 24.0;
    final sy = size.height / 24.0;

    Offset p(double x, double y) => Offset(x * sx, y * sy);

    final center = p(12.0, 12.0);
    final radius = 8.5 * sx;

    // 头部外轮廓
    final facePath = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));

    // 双眼与微笑嘴
    final eyeRadius = 1.05 * sx;
    final leftEyeCenter = p(8.8, 10.5);
    final rightEyeCenter = p(15.2, 10.5);

    final smilePath = Path()
      ..moveTo(p(8.5, 13.8).dx, p(8.5, 13.8).dy)
      ..quadraticBezierTo(
        p(12.0, 17.2).dx,
        p(12.0, 17.2).dy,
        p(15.5, 13.8).dx,
        p(15.5, 13.8).dy,
      );

    if (!isSelected) {
      // 未选中态：外轮廓 2.0 描边，双眼实心，微笑线 1.8 描边
      final strokePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * sx
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      canvas.drawPath(facePath, strokePaint);

      final eyePaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      canvas.drawCircle(leftEyeCenter, eyeRadius, eyePaint);
      canvas.drawCircle(rightEyeCenter, eyeRadius, eyePaint);

      final smilePaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8 * sx
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(smilePath, smilePaint);
    } else {
      // 选中态：实心圆形面部，双眼与微笑弧线镂空
      final smileCutout = Path()
        ..moveTo(p(8.5, 13.8).dx, p(8.5, 13.8).dy)
        ..quadraticBezierTo(
          p(12.0, 17.5).dx,
          p(12.0, 17.5).dy,
          p(15.5, 13.8).dx,
          p(15.5, 13.8).dy,
        )
        ..quadraticBezierTo(
          p(12.0, 19.0).dx,
          p(12.0, 19.0).dy,
          p(8.5, 13.8).dx,
          p(8.5, 13.8).dy,
        )
        ..close();

      final facialFeatures = Path()
        ..addOval(Rect.fromCircle(center: leftEyeCenter, radius: eyeRadius * 1.1))
        ..addOval(Rect.fromCircle(center: rightEyeCenter, radius: eyeRadius * 1.1))
        ..addPath(smileCutout, Offset.zero);

      final filledUser = Path.combine(PathOperation.difference, facePath, facialFeatures);

      final fillPaint = Paint()
        ..color = color
        ..style = PaintingStyle.fill;

      canvas.drawPath(filledUser, fillPaint);
    }
  }

  @override
  bool shouldRepaint(covariant UserIconPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isSelected != isSelected;
}
