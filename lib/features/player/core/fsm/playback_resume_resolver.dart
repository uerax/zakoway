/// 历史断点续播位置纯计算工具函数
///
/// 遵循 docs/player-rewrite/06-acceptance-scenarios.md (TC-03)
library;

/// 计算历史续播位置（若接近片尾 >= 95% 或剩余不足 15s，或不足 15s，重置为 null 从头播）
Duration? resolveInitialResumePosition({
  required Duration rawPosition,
  required Duration totalDuration,
}) {
  if (rawPosition <= Duration.zero) {
    return null;
  }

  // 播放不足 15 秒，视为片头刚起步或偶发误触，从头播
  if (rawPosition.inSeconds < 15) {
    return null;
  }

  // 当视频总时长大于 30 秒时，校验末尾临界点
  if (totalDuration > const Duration(seconds: 30)) {
    final remaining = totalDuration - rawPosition;
    final ratio = rawPosition.inMilliseconds / totalDuration.inMilliseconds;

    // 距末尾不足 15 秒，或已播超过 95%（ED / 演职员表），重置从头播放，防止死循环切集
    if (remaining <= const Duration(seconds: 15) || ratio >= 0.95) {
      return null;
    }
  }

  return rawPosition;
}
