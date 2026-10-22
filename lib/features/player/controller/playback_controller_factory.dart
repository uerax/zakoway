import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/core/backend/player_backend.dart';

/// 播放器控制器统一工厂创建方法
///
/// 默认构造并返回全新重写架构的 [ZakowayPlaybackController] (组合 PlaybackFsm + MediaKitPlayerBackend)。
ZakowayPlaybackController createPlaybackController({
  PlayerBackend? backend,
}) {
  return ZakowayPlaybackController(backend: backend);
}
