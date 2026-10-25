import 'dart:async';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/models/history/watch_history_item.dart';
import '../../../core/services/watch_history_service.dart';
import '../../../core/services/watched_episodes_service.dart';
import '../../../core/utils/anime_tag_filter.dart';
import '../core/proxy/media_preload_coordinator.dart';
import '../source/utils/playable_slot_engine.dart';

/// 播放进度与观看历史独立追踪器
///
/// 核心规范与设计职责 (严格对齐 animaku usePlaybackStats & usePlaybackResume 工业级规范)：
/// 1. 15 秒有效播放门槛 (Anti-Bounce Gate)：
///    仅自然有效递增播放累计满 15 秒才首次落盘并标记已看，杜绝点进视频 1~2 秒即退时产生大量 0 秒垃圾记录；
/// 2. 85% 实时完播与 ended 完播双重保底：
///    当视频接近末尾（时长 > 30s 且进度 >= 85%）或触发自然 ended 时，自动标记已看；
/// 3. 初始续播防卡死保护：
///    若历史记录进度已处于视频终点附近（>= 95% 或 距离末尾不足 15s），判定为已看毕，强制从头开播；若不足 15s 亦从 0 开始；
/// 4. 下一集首片无缝预拉取 (Next-Episode Seamless Handover)：
///    播放达到 75% 时后台异步提前解析并下载下一集前 2 个分片，保障自动连播 0ms 衔接；
/// 5. 10 秒节流持久化：满 15 秒后，每 10 秒周期性节流同步最新进度至 WatchHistoryService。
class WatchProgressTracker {
  double playSecAccumulated = 0.0;
  bool isValidPlayReported = false;
  double lastPlayTick = 0.0;
  int lastSaveTimeMs = 0;
  bool hasNextEpisodePreloaded = false;

  /// 重置当前集的统计状态
  void reset() {
    playSecAccumulated = 0.0;
    isValidPlayReported = false;
    lastPlayTick = 0.0;
    lastSaveTimeMs = 0;
    hasNextEpisodePreloaded = false;
  }

  /// 计算断点续播时间点并加入片尾与极短播放防卡死保护
  Duration? resolveInitialResumePosition({
    required int bangumiId,
    required int canonicalEp,
    Duration? initialPosition,
    int? currentEpisodeParam,
  }) {
    Duration? target;
    if (initialPosition != null && canonicalEp == currentEpisodeParam) {
      target = initialPosition;
    } else if (bangumiId > 0) {
      final historyId = WatchHistoryItem.buildId(bangumiId, canonicalEp);
      final match = WatchHistoryService.instance.items
          .where((e) => e.id == historyId)
          .firstOrNull;
      if (match != null && match.position > 0) {
        final d = match.duration;
        final p = match.position;
        if ((d > 30 && (p >= d - 15 || p / d >= 0.95)) || p < 15) {
          return null;
        }
        target = Duration(milliseconds: (p * 1000).round());
      }
    }

    if (target != null && target.inSeconds < 15) {
      return null;
    }
    return target;
  }

  /// 保存当前进度至本地观看历史
  void saveCurrentProgress({
    required int bangumiId,
    required int canonicalEp,
    required String title,
    required String coverUrl,
    required int roadIndex,
    required String sourceId,
    required String pageUrl,
    required double position,
    required double duration,
    BangumiItem? bangumiItem,
    BangumiItem? fullBangumiItem,
  }) {
    if (bangumiId <= 0 || position <= 0 || !position.isFinite) return;

    final effectiveTitle = (bangumiItem?.nameCn.isNotEmpty ?? false)
        ? bangumiItem!.nameCn
        : (bangumiItem?.name ?? title);

    final rawTags = (fullBangumiItem?.tags.isNotEmpty ?? false)
        ? fullBangumiItem!.tags
        : (bangumiItem?.tags ?? const <BangumiTag>[]);
    final extractedGenres = rawTags
        .map((t) => t.name.trim())
        .where((t) => AnimeTagFilter.isAllowedGenre(t))
        .toSet()
        .toList();

    final existingGenres = WatchHistoryService.instance.items
        .where((e) => e.bangumiId == bangumiId && e.genres.isNotEmpty)
        .firstOrNull
        ?.genres;
    final finalGenres = extractedGenres.isNotEmpty
        ? extractedGenres
        : (existingGenres ?? const <String>[]);

    final item = WatchHistoryItem(
      id: WatchHistoryItem.buildId(bangumiId, canonicalEp),
      bangumiId: bangumiId,
      title: effectiveTitle,
      cover: coverUrl,
      episode: canonicalEp,
      road: roadIndex,
      pluginName: sourceId,
      pageUrl: pageUrl,
      position: position,
      duration: duration > 0 ? duration : 1440.0,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
      genres: finalGenres,
    );

    WatchHistoryService.instance.recordProgress(item).ignore();
  }

  /// 页面退出或销毁时的安全落盘
  void saveProgressOnExit({
    required int bangumiId,
    required int canonicalEp,
    required String title,
    required String coverUrl,
    required int roadIndex,
    required String sourceId,
    required String pageUrl,
    required double position,
    required double duration,
    BangumiItem? bangumiItem,
    BangumiItem? fullBangumiItem,
  }) {
    if (bangumiId <= 0) return;
    if (position > 0 && (isValidPlayReported || (duration > 30 && position / duration >= 0.85))) {
      saveCurrentProgress(
        bangumiId: bangumiId,
        canonicalEp: canonicalEp,
        title: title,
        coverUrl: coverUrl,
        roadIndex: roadIndex,
        sourceId: sourceId,
        pageUrl: pageUrl,
        position: position,
        duration: duration,
        bangumiItem: bangumiItem,
        fullBangumiItem: fullBangumiItem,
      );
    }
  }

  /// 250ms 节流的时间线更新钩子
  void onTimelineTick({
    required double positionSeconds,
    required double durationSeconds,
    required bool isPlaying,
    required int bangumiId,
    required int canonicalEp,
    required String title,
    required String coverUrl,
    required int roadIndex,
    required String sourceId,
    required String pageUrl,
    required List<PlayableSlot> slots,
    BangumiItem? bangumiItem,
    BangumiItem? fullBangumiItem,
  }) {
    final t = positionSeconds;
    final d = durationSeconds;
    if (t < 0 || !t.isFinite) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // 1. 15s 自然有效播放累计门槛
    if (!isValidPlayReported && bangumiId > 0 && isPlaying) {
      final lastTick = lastPlayTick > 0 ? lastPlayTick : t;
      final tickDelta = t - lastTick;
      if (tickDelta > 0 && tickDelta <= 2.5) {
        playSecAccumulated += tickDelta;
        if (playSecAccumulated >= 15.0) {
          isValidPlayReported = true;
          WatchedEpisodesService.instance.markWatched(bangumiId, canonicalEp);
          lastSaveTimeMs = now;
          saveCurrentProgress(
            bangumiId: bangumiId,
            canonicalEp: canonicalEp,
            title: title,
            coverUrl: coverUrl,
            roadIndex: roadIndex,
            sourceId: sourceId,
            pageUrl: pageUrl,
            position: t,
            duration: d,
            bangumiItem: bangumiItem,
            fullBangumiItem: fullBangumiItem,
          );
        }
      }
    }
    lastPlayTick = t;

    // 2. 85% 完播兜底标记已看
    if (bangumiId > 0 && d > 30 && t / d >= 0.85) {
      WatchedEpisodesService.instance.markWatched(bangumiId, canonicalEp);
    }

    // 3. 75% 连播预载下一集首片
    if (!hasNextEpisodePreloaded && d > 30 && (t / d >= 0.75)) {
      hasNextEpisodePreloaded = true;
      if (slots.isNotEmpty) {
        final currentIdx = slots.indexWhere((s) => s.canonicalEp == canonicalEp);
        if (currentIdx != -1 && currentIdx + 1 < slots.length) {
          final nextSlot = slots[currentIdx + 1];
          MediaPreloadCoordinator.instance.preloadMediaFirstChunk(
            sourceId: sourceId,
            episodeUrl: nextSlot.pageUrl,
          ).ignore();
        }
      }
    }

    // 4. 周期性（每 10s）进度落盘
    if (isValidPlayReported && now - lastSaveTimeMs >= 10000) {
      lastSaveTimeMs = now;
      saveCurrentProgress(
        bangumiId: bangumiId,
        canonicalEp: canonicalEp,
        title: title,
        coverUrl: coverUrl,
        roadIndex: roadIndex,
        sourceId: sourceId,
        pageUrl: pageUrl,
        position: t,
        duration: d,
        bangumiItem: bangumiItem,
        fullBangumiItem: fullBangumiItem,
      );
    }
  }

  /// 视频完播处理（ended 事件）
  void onPlaybackEnded({
    required int bangumiId,
    required int canonicalEp,
    required String title,
    required String coverUrl,
    required int roadIndex,
    required String sourceId,
    required String pageUrl,
    required double durationSeconds,
    BangumiItem? bangumiItem,
    BangumiItem? fullBangumiItem,
  }) {
    if (bangumiId > 0) {
      WatchedEpisodesService.instance.markWatched(bangumiId, canonicalEp);
    }
    if (durationSeconds > 0) {
      saveCurrentProgress(
        bangumiId: bangumiId,
        canonicalEp: canonicalEp,
        title: title,
        coverUrl: coverUrl,
        roadIndex: roadIndex,
        sourceId: sourceId,
        pageUrl: pageUrl,
        position: durationSeconds,
        duration: durationSeconds,
        bangumiItem: bangumiItem,
        fullBangumiItem: fullBangumiItem,
      );
    }
  }
}
