/// 滚动弹幕轨道碰撞与防追尾状态管理器
/// 结合入场安全间隙与出场反超预测双重校验
class DanmakuScrollTrack {
  double _lastStartMs = -double.infinity;
  double _tailFreeMs = -double.infinity;
  double _lastEndMs = -double.infinity;
  double _lastSpeed = double.infinity;

  /// 前一条弹幕尾部腾出入场间隙的时刻 (ms)
  double get tailFreeMs => _tailFreeMs;

  /// 最后一次登记的入场时刻 (ms)
  double get lastStartMs => _lastStartMs;

  /// 前一条弹幕完全离开屏幕左边缘的时刻 (ms)
  double get lastEndMs => _lastEndMs;

  /// 前一条弹幕的飞行速度
  double get lastSpeed => _lastSpeed;

  /// 重置轨道状态
  void reset() {
    _lastStartMs = -double.infinity;
    _tailFreeMs = -double.infinity;
    _lastEndMs = -double.infinity;
    _lastSpeed = double.infinity;
  }

  /// 判定当前轨道在 [nowMs] 时刻是否能够接纳速度为 [speed] 的新弹幕入场
  /// [viewWidth] 屏幕/视口物理宽度
  /// [safetyGapPx] 前后两条弹幕之间的安全物理间隙（像素）
  bool canAccept(double nowMs, double speed, double viewWidth, {double safetyGapPx = 28.0}) {
    // 1. 入场安全间隙校验：前一条弹幕的尾部尚未完全进入视口右边缘并拉开间距前，严禁入场
    if (nowMs < _tailFreeMs) {
      return false;
    }

    // 2. 速度校验：新弹幕速度慢于或等于上一条，由于已满足入场间隙，后续绝对不会追尾
    if (speed <= _lastSpeed) {
      return true;
    }

    // 3. 终点反超预判校验：新弹幕速度比前一条快，计算新弹幕到达左边缘的时刻，
    //    必须在上一条弹幕离开左边缘时刻之后，否则会在中途发生超车穿模碰撞。
    //    特殊处理说明：此处必须减去 safetyGapPx，以确保新弹幕头部在到达终点前提前拉开安全间距，
    //    若误写为加号会导致判定时间偏大，误放行本会追尾的弹幕。
    final newArriveEndMs = nowMs + (viewWidth - safetyGapPx) / speed;
    return newArriveEndMs >= _lastEndMs;
  }

  /// 登记新弹幕进入该轨道
  void register({
    required double startMs,
    required double width,
    required double speed,
    required double viewWidth,
    double safetyGapPx = 28.0,
  }) {
    if (startMs < _lastStartMs) return;
    _lastStartMs = startMs;
    _lastSpeed = speed;
    _tailFreeMs = startMs + (width + safetyGapPx) / speed;
    _lastEndMs = startMs + (viewWidth + width) / speed;
  }

  /// 当最后登记的弹幕合流宽度或速度发生变化时，重新更新该轨道的尾部腾空与到达终点时刻
  bool updateTailIfLast({
    required double oldStartMs,
    required double newStartMs,
    required double newWidth,
    required double newSpeed,
    required double viewWidth,
    double safetyGapPx = 28.0,
  }) {
    if ((_lastStartMs - oldStartMs).abs() > 1e-3) {
      return false;
    }
    _lastStartMs = newStartMs;
    _lastSpeed = newSpeed;
    _tailFreeMs = newStartMs + (newWidth + safetyGapPx) / newSpeed;
    _lastEndMs = newStartMs + (viewWidth + newWidth) / newSpeed;
    return true;
  }
}
