import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/history/watch_history_item.dart';
import 'app_preferences.dart';

/// 播放历史与继续观看响应式单一数据源服务（对齐 animaku apps/web/src/stores/history.ts 与 Flutter ChangeNotifier 模式）：
/// 1. 响应式单一可信源：继承 ChangeNotifier，任何对历史的增删改均自动通过 notifyListeners() 广播至全应用所有监听页面；
/// 2. 独立于网络请求：本地播放历史与慢速网络 API 完全解耦，首页与历史页通过 ListenableBuilder 毫秒级动态同步；
/// 3. 分层聚合架构：底层精确记录到分集（同番同集去重，多集共存），保证各集断点续播不丢失；同时提供 latestByAnime 聚合属性供首页使用，杜绝首页刷屏；
/// 4. 容量与持久化管理：上限 200 条，落盘持久化至 AppPreferences；
/// 5. 本地无历史记录时保持空列表，不注入任何测试假数据。
class WatchHistoryService extends ChangeNotifier {
  static final WatchHistoryService instance = WatchHistoryService._();
  WatchHistoryService._();

  static const int maxItems = 200;

  List<WatchHistoryItem> _items = [];
  bool _isInitialized = false;

  /// 内存中当前的播放历史列表（只读不可变快照）
  List<WatchHistoryItem> get items => List.unmodifiable(_items);

  /// 供首页追番货架等场景消费：按番剧去重聚合，每部番剧只保留最新播放的一条记录
  List<WatchHistoryItem> get latestByAnime {
    final seen = <int>{};
    final result = <WatchHistoryItem>[];
    for (final item in _items) {
      if (seen.add(item.bangumiId)) {
        result.add(item);
      }
    }
    return result;
  }

  /// 供个性化推荐系统消费：按番剧聚合用户实际看过的有效题材词频画像
  Map<String, int> get userGenreFrequencies {
    final freq = <String, int>{};
    for (final item in latestByAnime) {
      for (final genre in item.genres) {
        final clean = genre.trim();
        if (clean.isNotEmpty) {
          freq[clean] = (freq[clean] ?? 0) + 1;
        }
      }
    }
    return freq;
  }

  /// 预置的 3 部测试数据（供单元测试场景按需引用）
  @visibleForTesting
  static List<WatchHistoryItem> get initialMockSeeds {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayTime1 = now.millisecondsSinceEpoch;
    final todayTime2 = (todayStart.add(const Duration(minutes: 1)).isBefore(now)
            ? todayStart.add(const Duration(minutes: 1))
            : now)
        .millisecondsSinceEpoch;
    final yesterdayTime = todayStart.subtract(const Duration(hours: 2)).millisecondsSinceEpoch;

    return [
      WatchHistoryItem(
        id: WatchHistoryItem.buildId(400650, 14),
        bangumiId: 400650,
        title: '葬送的芙莉莲',
        cover: 'https://lain.bgm.tv/pic/cover/l/d8/d5/400650_6Zz66.jpg',
        episode: 14,
        road: 1,
        pluginName: 'cycani',
        pageUrl: 'https://cycani.org/watch/400650/14',
        position: 1035.0, // 17:15
        duration: 1440.0, // 24:00
        updatedAt: todayTime1,
      ),
      WatchHistoryItem(
        id: WatchHistoryItem.buildId(395377, 8),
        bangumiId: 395377,
        title: '迷宫饭',
        cover: 'https://lain.bgm.tv/pic/cover/l/7f/29/395377_1m11O.jpg',
        episode: 8,
        road: 0,
        pluginName: 'anime1',
        pageUrl: 'https://anime1.me/watch/395377/8',
        position: 650.0, // 10:50
        duration: 1440.0, // 24:00
        updatedAt: todayTime2,
      ),
      WatchHistoryItem(
        id: WatchHistoryItem.buildId(410657, 4),
        bangumiId: 410657,
        title: '间谍过家家 第二季',
        cover: 'https://lain.bgm.tv/pic/cover/l/71/61/410657_vG6m4.jpg',
        episode: 4,
        road: 1,
        pluginName: 'omofun',
        pageUrl: 'https://omofun.tv/watch/410657/4',
        position: 1265.0, // 21:05
        duration: 1440.0, // 24:00
        updatedAt: yesterdayTime,
      ),
    ];
  }

  /// 获取播放历史列表（首次调用自动加载持久化缓存，为空时初始化为空列表）
  Future<List<WatchHistoryItem>> getHistory({bool forceReload = false}) async {
    if (_isInitialized && !forceReload) {
      return _items;
    }

    final rawJson = AppPreferences.getWatchHistoryJson();
    if (rawJson != null && rawJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawJson);
        if (decoded is List) {
          final loaded = decoded
              .whereType<Map<String, dynamic>>()
              .map((j) => WatchHistoryItem.fromJson(j))
              .toList();
          if (loaded.isNotEmpty) {
            _items = loaded;
            _isInitialized = true;
            notifyListeners();
            return _items;
          }
        }
      } catch (_) {}
    }

    // 本地缓存为空时，保持为空列表（不注入种子假数据）
    _items = [];
    _isInitialized = true;
    notifyListeners();
    return _items;
  }

  /// 内部持久化辅助方法
  Future<void> _persist() async {
    final jsonList = _items.take(maxItems).map((e) => e.toJson()).toList();
    await AppPreferences.saveWatchHistoryJson(jsonEncode(jsonList));
  }

  /// 全量保存历史记录（更新内存、落盘并广播）
  Future<void> saveHistory(List<WatchHistoryItem> newItems) async {
    _items = List.of(newItems.take(maxItems));
    _isInitialized = true;
    await _persist();
    notifyListeners();
  }

  /// 更新或插入单条播放进度（最新置顶；对齐 animaku 规范，按同番剧+同集数去重）
  /// 特殊处理说明：
  /// 底层持久化必须精确到每集（bangumiId + episode），严禁按番剧直接整部覆盖。
  /// 若按番剧粗暴覆盖，用户回头重温前序剧集时，当前正在追的最新剧集断点进度将被永久抹除；
  /// 多集记录共存保证各集续播精准，展示层的防刷屏则通过 latestByAnime 在首页单独聚合解决。
  Future<void> recordProgress(WatchHistoryItem entry) async {
    if (!_isInitialized) await getHistory();

    final updatedList = <WatchHistoryItem>[entry];

    // 同一番剧的同一集数只保留一条最新进度（不区分视频源，保存最后看的记录）；不同集数并存
    for (final item in _items) {
      final isSameBangumiAndEp =
          item.bangumiId == entry.bangumiId && item.episode == entry.episode;
      if (item.id != entry.id && !isSameBangumiAndEp) {
        updatedList.add(item);
      }
    }

    _items = updatedList.take(maxItems).toList();
    await _persist();
    notifyListeners();
  }

  /// 移除指定番剧的全部历史记录
  Future<void> removeByBangumi(int bangumiId) async {
    if (!_isInitialized) await getHistory();

    _items.removeWhere((item) => item.bangumiId == bangumiId);
    await _persist();
    notifyListeners();
  }

  /// 移除指定 ID 的记录
  Future<void> remove(String id) async {
    if (!_isInitialized) await getHistory();

    _items.removeWhere((item) => item.id == id);
    await _persist();
    notifyListeners();
  }

  /// 批量删除记录
  Future<void> removeMany(Set<String> ids) async {
    if (!_isInitialized) await getHistory();

    _items.removeWhere((item) => ids.contains(item.id));
    await _persist();
    notifyListeners();
  }

  /// 清空播放历史
  Future<void> clear() async {
    _items.clear();
    _isInitialized = true;
    await AppPreferences.clearWatchHistory();
    notifyListeners();
  }

  /// 重置初始化状态（主要用于单元测试隔离）
  @visibleForTesting
  void resetForTest() {
    _items = [];
    _isInitialized = false;
  }
}
