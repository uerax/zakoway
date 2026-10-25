/// 播放器 UI 交互与动画时长常量配置
class PlayerUiConstants {
  const PlayerUiConstants._();

  /// 桌面端：播放中鼠标静止自动隐藏控制栏时长（默认 2 秒）
  static const Duration desktopControlsAutoHideDelay =
      Duration(milliseconds: 2000);

  /// 桌面端：鼠标静止自动隐藏光标与联动收起控制栏时长（默认 1.5 秒）
  static const Duration desktopCursorAutoHideDelay =
      Duration(milliseconds: 1500);

  /// 移动端：静止自动隐藏控制栏时长（默认 2.5 秒）
  static const Duration mobileControlsAutoHideDelay =
      Duration(milliseconds: 2500);

  /// 移动端/通用端：锁屏状态下唤出解锁按钮的自动隐藏时长（默认 2 秒）
  static const Duration lockButtonAutoHideDelay = Duration(seconds: 2);
}
