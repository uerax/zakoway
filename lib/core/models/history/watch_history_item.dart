import '../bangumi/bangumi_item.dart';

/// 播放时长格式化辅助函数（秒数转 mm:ss 或 hh:mm:ss）
String formatPlaybackTime(double seconds) {
  if (seconds <= 0 || !seconds.isFinite) return '0:00';
  final total = seconds.floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) {
    return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// 播放历史记录实体（对齐 animaku packages/shared/src/history.ts WatchHistoryEntry 结构）：
/// 1. 包含视频源 (pluginName)、线路 (road)、选集/详情/直链 URL (pageUrl / sourceUrl / playUrl)；
/// 2. 包含播放进度秒数 (position) 与总时长 (duration)；
/// 3. 自带 progress 与 positionText 计算属性，供首页与历史记录列表消费；
/// 4. 支持导出轻量 BangumiItem 供番剧详情 Sheet 无缝展示。
class WatchHistoryItem {
  final String id;
  final int bangumiId;
  final String title;
  final String? cover;
  final int episode;
  final int road;
  final String pluginName;
  final String pageUrl;
  final String? sourceUrl;
  final String? playUrl;
  final double position; // 当前播放进度（秒）
  final double duration; // 视频总时长（秒）
  final int updatedAt; // 毫秒时间戳
  final List<String> genres; // 题材标签列表（用于偏好画像分析）

  const WatchHistoryItem({
    required this.id,
    required this.bangumiId,
    required this.title,
    this.cover,
    required this.episode,
    this.road = 0,
    required this.pluginName,
    this.pageUrl = '',
    this.sourceUrl,
    this.playUrl,
    required this.position,
    required this.duration,
    required this.updatedAt,
    this.genres = const [],
  });

  /// 依据 bangumiId 与集数合成标准唯一标识（对齐 animaku: `${bangumiId}::ep${episode}`）
  static String buildId(int bangumiId, int episode) => '$bangumiId::ep$episode';

  /// 归一化播放进度百分比 (0.0 ~ 1.0)
  double get progress {
    if (duration <= 0) return 0.0;
    return (position / duration).clamp(0.0, 1.0);
  }

  /// 格式化播放时间字串（如 "17:15 / 24:00"）
  String get positionText {
    return '${formatPlaybackTime(position)} / ${formatPlaybackTime(duration)}';
  }

  /// 是否已看完整集（进度达到 90% 或剩余时长不足 60 秒）
  bool get isFinished {
    if (duration <= 0) return false;
    if (duration > 120 && duration - position <= 60) return true;
    return progress >= 0.9;
  }

  /// 精细相对时间标注（对齐 animaku：刚刚 / X分钟前 / HH:mm / 昨天 HH:mm / X天前 / MM-DD）
  String formatRelativeWatchTime([DateTime? now]) {
    final current = now ?? DateTime.now();
    final itemDate = DateTime.fromMillisecondsSinceEpoch(updatedAt);
    final diff = current.difference(itemDate);

    final todayStart = DateTime(current.year, current.month, current.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final last7DaysStart = todayStart.subtract(const Duration(days: 6));

    final hourStr = itemDate.hour.toString().padLeft(2, '0');
    final minStr = itemDate.minute.toString().padLeft(2, '0');
    final timeStr = '$hourStr:$minStr';

    if (!itemDate.isBefore(todayStart)) {
      if (diff.inSeconds < 60) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      return timeStr;
    }

    if (!itemDate.isBefore(yesterdayStart)) {
      return '昨天 $timeStr';
    }

    if (!itemDate.isBefore(last7DaysStart)) {
      final days = current.difference(itemDate).inDays + 1;
      return '$days天前';
    }

    final monthStr = itemDate.month.toString().padLeft(2, '0');
    final dayStr = itemDate.day.toString().padLeft(2, '0');
    if (itemDate.year == current.year) {
      return '$monthStr-$dayStr';
    }
    return '${itemDate.year}-$monthStr-$dayStr';
  }

  /// 兼容属性：对应集数
  int get episodeNumber => episode;

  /// 兼容属性：获取轻量 BangumiItem 实体
  BangumiItem get item => toBangumiItem();

  /// 转换为 DateTime 对象
  DateTime get lastWatchTime => DateTime.fromMillisecondsSinceEpoch(updatedAt);

  /// 转换为用于首页弹窗交互的 BangumiItem 实体
  BangumiItem toBangumiItem() {
    return BangumiItem(
      id: bangumiId,
      type: 2,
      name: title,
      nameCn: title,
      summary: '',
      airDate: '',
      airWeekday: 1,
      rank: 0,
      images: {
        'large': cover ?? '',
        'common': cover ?? '',
      },
      tags: const [],
      alias: const [],
      ratingScore: 0.0,
      votes: 0,
      eps: episode,
      totalEpisodes: 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bangumiId': bangumiId,
        'title': title,
        'cover': cover,
        'episode': episode,
        'road': road,
        'pluginName': pluginName,
        'pageUrl': pageUrl,
        'sourceUrl': sourceUrl,
        'playUrl': playUrl,
        'position': position,
        'duration': duration,
        'updatedAt': updatedAt,
        'genres': genres,
      };

  factory WatchHistoryItem.fromJson(Map<String, dynamic> json) {
    final bangumiId = (json['bangumiId'] as num?)?.toInt() ?? 0;
    final episode = (json['episode'] as num?)?.toInt() ?? 1;
    final id = json['id']?.toString() ?? buildId(bangumiId, episode);
    final rawGenres = json['genres'];
    final genres = rawGenres is List
        ? rawGenres.map((e) => e.toString()).toList()
        : const <String>[];

    return WatchHistoryItem(
      id: id,
      bangumiId: bangumiId,
      title: json['title']?.toString() ?? '',
      cover: json['cover']?.toString(),
      episode: episode,
      road: (json['road'] as num?)?.toInt() ?? 0,
      pluginName: json['pluginName']?.toString() ?? '默认源',
      pageUrl: json['pageUrl']?.toString() ?? '',
      sourceUrl: json['sourceUrl']?.toString(),
      playUrl: json['playUrl']?.toString(),
      position: (json['position'] as num?)?.toDouble() ?? 0.0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0.0,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
      genres: genres,
    );
  }
}

/// 历史时间轴四段式分组
class WatchHistoryTimeGroup {
  final String key;
  final String label;
  final List<WatchHistoryItem> items;

  const WatchHistoryTimeGroup({
    required this.key,
    required this.label,
    required this.items,
  });
}

/// 历史统计指标数据
class WatchHistoryStats {
  final int totalCount;
  final int todayCount;
  final int finishedCount;
  final double totalWatchHours;

  const WatchHistoryStats({
    required this.totalCount,
    required this.todayCount,
    required this.finishedCount,
    required this.totalWatchHours,
  });

  String get totalWatchHoursText {
    if (totalWatchHours <= 0) return '0 小时';
    if (totalWatchHours < 0.1) return '0.1 小时';
    return '${totalWatchHours.toStringAsFixed(1)} 小时';
  }
}

/// 业界主流四段式历史记录分组算法：
/// - 今天 (today): 今日 00:00:00 至今
/// - 昨天 (yesterday): 昨日 00:00:00 至 今日 00:00:00
/// - 近 7 天 (last7Days): 距今 7 天内（除今天与昨天）
/// - 更早以前 (earlier): 7 天以前
List<WatchHistoryTimeGroup> groupWatchHistory(
  List<WatchHistoryItem> entries, [
  DateTime? now,
]) {
  if (entries.isEmpty) return const [];

  final current = now ?? DateTime.now();
  final todayStart = DateTime(current.year, current.month, current.day).millisecondsSinceEpoch;
  final yesterdayStart = todayStart - 86400000;
  final last7DaysStart = todayStart - 6 * 86400000;

  final todayItems = <WatchHistoryItem>[];
  final yesterdayItems = <WatchHistoryItem>[];
  final last7DaysItems = <WatchHistoryItem>[];
  final earlierItems = <WatchHistoryItem>[];

  for (final item in entries) {
    final t = item.updatedAt;
    if (t >= todayStart) {
      todayItems.add(item);
    } else if (t >= yesterdayStart) {
      yesterdayItems.add(item);
    } else if (t >= last7DaysStart) {
      last7DaysItems.add(item);
    } else {
      earlierItems.add(item);
    }
  }

  final groups = <WatchHistoryTimeGroup>[];
  if (todayItems.isNotEmpty) {
    groups.add(WatchHistoryTimeGroup(key: 'today', label: '今天', items: todayItems));
  }
  if (yesterdayItems.isNotEmpty) {
    groups.add(WatchHistoryTimeGroup(key: 'yesterday', label: '昨天', items: yesterdayItems));
  }
  if (last7DaysItems.isNotEmpty) {
    groups.add(WatchHistoryTimeGroup(key: 'last7Days', label: '近 7 天', items: last7DaysItems));
  }
  if (earlierItems.isNotEmpty) {
    groups.add(WatchHistoryTimeGroup(key: 'earlier', label: '更早以前', items: earlierItems));
  }
  return groups;
}

/// 计算历史统计指标
WatchHistoryStats computeHistoryStats(
  List<WatchHistoryItem> entries, [
  DateTime? now,
]) {
  if (entries.isEmpty) {
    return const WatchHistoryStats(
      totalCount: 0,
      todayCount: 0,
      finishedCount: 0,
      totalWatchHours: 0.0,
    );
  }

  final current = now ?? DateTime.now();
  final todayStart = DateTime(current.year, current.month, current.day).millisecondsSinceEpoch;

  var todayCount = 0;
  var finishedCount = 0;
  var totalPositionSec = 0.0;

  for (final item in entries) {
    if (item.updatedAt >= todayStart) {
      todayCount++;
    }
    if (item.isFinished) {
      finishedCount++;
    }
    totalPositionSec += item.position;
  }

  final totalHours = totalPositionSec / 3600.0;

  return WatchHistoryStats(
    totalCount: entries.length,
    todayCount: todayCount,
    finishedCount: finishedCount,
    totalWatchHours: totalHours,
  );
}
