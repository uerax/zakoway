import 'package:flutter/foundation.dart';
import 'package:zakoway/features/player/controller/passive_playback_observer.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/controller/rewritten_playback_controller.dart';
import 'package:zakoway/features/player/core/backend/player_backend.dart';

/// 全局特性开关：是否启用全面重写的播放器控制核心 (PlaybackFsm + MediaKitPlayerBackend)
/// 遵循 docs/player-rewrite/11-facade-plan.md：默认关闭 (false)，确保生产环境 100% 稳定
const bool kUseRewrittenPlayerCore = false;

/// 播放器控制器统一工厂创建方法
///
/// 当 [kUseRewrittenPlayerCore] 为 true 时，返回全新 [RewrittenPlaybackController]；
/// 默认 (false) 返回成熟稳定的 [ZakowayPlaybackController]，并在调试模式下挂载 [PassivePlaybackObserver] 进行无感被动审计。
ZakowayPlaybackController createPlaybackController({
  PlayerBackend? backend,
  bool? useRewrittenCore,
}) {
  final useRewritten = useRewrittenCore ?? kUseRewrittenPlayerCore;
  if (useRewritten) {
    return RewrittenPlaybackController(backend: backend);
  }
  final legacyController = ZakowayPlaybackController();
  if (kDebugMode) {
    PassivePlaybackObserver.attach(legacyController);
  }
  return legacyController;
}
