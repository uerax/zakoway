import 'package:zakoway/features/player/danmaku/models/danmaku_item.dart';
import 'package:zakoway/features/player/danmaku/utils/danmaku_text_normalizer.dart';
import 'package:zakoway/features/player/danmaku/view/danmaku_text_layout.dart';

/// 屏幕上正在活动的弹幕运行时实体
class DanmakuEntry {
  DanmakuEntry({
    required this.item,
    required this.track,
    required this.startMs,
    required this.durationMs,
    required this.speed,
    required this.x,
    required this.y,
    required this.baseText,
    required this.layout,
    this.count = 1,
    String? normalizedKey,
  }) : normalizedKey = normalizedKey ?? DanmakuTextNormalizer.normalize(baseText);

  /// 原始弹幕数据
  final DanmakuItem item;

  /// 所占用的轨道索引
  int track;

  /// 弹幕开始显示的起始时钟时刻（毫秒）
  double startMs;

  /// 弹幕穿越屏幕的总持续时长（毫秒）
  double durationMs;

  /// 弹幕飞行物理速度（像素/毫秒，仅用于轨道防追尾碰撞管理，不再参与绘制）
  double speed;

  /// 渲染水平坐标
  double x;

  /// 渲染垂直坐标
  double y;

  /// 原始文本（用于 In-Flight 实时合流比对）
  final String baseText;

  /// 预先归一化的特征 Key（避免合流遍历时重复正则计算与临时字符串分配）
  final String normalizedKey;

  /// 动态合流计数（默认为 1，合流后变为 2, 3...）
  int count;

  /// 该弹幕是否已经在可视区域内完成过至少一次首帧光栅化绘制
  bool hasBeenPainted = false;

  /// 排版与绘制封装
  DanmakuTextLayout layout;

  /// 弹幕离开可视区域的理论截止时刻（毫秒）
  double get endMs => startMs + durationMs;

  /// 弹幕类型快捷访问
  DanmakuMode get mode => item.mode;

  void dispose() {
    layout.dispose();
  }
}
