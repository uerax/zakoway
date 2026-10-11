import 'dart:convert';
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';
import '../../models/bangumi/bangumi_collection.dart';
import '../../models/bangumi/bangumi_item.dart';
import '../../services/app_preferences.dart';
import '../models/anime_collection_item.dart';

/// 本地追番数据核心服务：
/// 负责追番状态的内存缓存、落盘持久化、按分类查询与多端合并。
class AnimeCollectionService extends ChangeNotifier {
  static final AnimeCollectionService instance =
      AnimeCollectionService._internal();

  AnimeCollectionService._internal() {
    _restoreFromStorage();
  }

  final Map<int, AnimeCollectionItem> _items = {};

  List<AnimeCollectionItem> get allItems => _items.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  int get totalCount => _items.length;

  void _restoreFromStorage() {
    try {
      final jsonStr = AppPreferences.getAnimeCollectionsJson();
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr);
        if (decoded is List) {
          for (final raw in decoded) {
            if (raw is Map<String, dynamic>) {
              final item = AnimeCollectionItem.fromJson(raw);
              if (item.subjectId > 0 && item.type != CollectType.none) {
                _items[item.subjectId] = item;
              }
            }
          }
        }
      }
    } catch (e) {
      developer.log('恢复追番持久化数据异常: $e', name: 'AnimeCollectionService');
    }
  }

  Future<void> _persistToStorage() async {
    try {
      final list = _items.values.map((e) => e.toJson()).toList();
      await AppPreferences.saveAnimeCollectionsJson(jsonEncode(list));
    } catch (e) {
      developer.log('追番数据持久化落盘异常: $e', name: 'AnimeCollectionService');
    }
  }

  /// 获取指定条目的追番状态
  CollectType getCollectionType(int subjectId) {
    return _items[subjectId]?.type ?? CollectType.none;
  }

  /// 获取指定条目的追番实体
  AnimeCollectionItem? getItem(int subjectId) {
    return _items[subjectId];
  }

  /// 获取指定分类的所有番剧列表（按更新时间降序）
  List<AnimeCollectionItem> getItemsByType(CollectType type) {
    return _items.values
        .where((e) => e.type == type)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  /// 获取各状态分类的番剧数量统计
  Map<CollectType, int> getCountStats() {
    final stats = <CollectType, int>{
      CollectType.watching: 0,
      CollectType.planToWatch: 0,
      CollectType.watched: 0,
      CollectType.onHold: 0,
      CollectType.abandoned: 0,
    };
    for (final item in _items.values) {
      if (stats.containsKey(item.type)) {
        stats[item.type] = (stats[item.type] ?? 0) + 1;
      }
    }
    return stats;
  }

  /// 设置或更新追番条目
  Future<void> setItem(AnimeCollectionItem item) async {
    if (item.type == CollectType.none) {
      await removeItem(item.subjectId);
      return;
    }

    _items[item.subjectId] = item;
    await _persistToStorage();
    notifyListeners();
  }

  /// 从 BangumiItem 更新追番状态
  Future<AnimeCollectionItem> updateStatusFromBangumiItem({
    required BangumiItem bangumiItem,
    required CollectType type,
    int? myRating,
    String? myComment,
  }) async {
    if (type == CollectType.none) {
      await removeItem(bangumiItem.id);
      return AnimeCollectionItem.fromBangumiItem(
        item: bangumiItem,
        type: CollectType.none,
      );
    }

    final existing = _items[bangumiItem.id];
    final updated = AnimeCollectionItem(
      subjectId: bangumiItem.id,
      type: type,
      title: bangumiItem.preferredName,
      originalName: bangumiItem.name != bangumiItem.preferredName
          ? bangumiItem.name
          : null,
      coverUrl: bangumiItem.coverUrl.isNotEmpty
          ? bangumiItem.coverUrl
          : (existing?.coverUrl ?? ''),
      score: bangumiItem.ratingScore > 0
          ? bangumiItem.ratingScore
          : (existing?.score ?? 0.0),
      rank: bangumiItem.rank > 0 ? bangumiItem.rank : (existing?.rank ?? 0),
      totalEpisodes: bangumiItem.eps > 0
          ? bangumiItem.eps
          : (existing?.totalEpisodes ?? 0),
      tags: bangumiItem.tags.isNotEmpty
          ? bangumiItem.tags.map((t) => t.name).toList()
          : (existing?.tags ?? const []),
      updatedAt: DateTime.now(),
      myRating: myRating ?? existing?.myRating,
      myComment: myComment ?? existing?.myComment,
    );

    _items[bangumiItem.id] = updated;
    await _persistToStorage();
    notifyListeners();
    return updated;
  }

  /// 移除追番记录
  Future<void> removeItem(int subjectId) async {
    if (_items.containsKey(subjectId)) {
      _items.remove(subjectId);
      await _persistToStorage();
      notifyListeners();
    }
  }

  /// 合并远端拉取的数据（冲突解决机制：以较新的 updatedAt 为准）
  Future<int> mergeRemoteItems(List<AnimeCollectionItem> remoteItems) async {
    var changedCount = 0;
    for (final remote in remoteItems) {
      if (remote.subjectId <= 0 || remote.type == CollectType.none) continue;
      final local = _items[remote.subjectId];
      if (local == null) {
        _items[remote.subjectId] = remote;
        changedCount++;
      } else if (remote.updatedAt.isAfter(local.updatedAt)) {
        // 远端更新时间较新，合并更新
        _items[remote.subjectId] = remote.copyWith(
          // 保留本地更清晰的中文标题/封面如果远端缺失
          title: local.title.isNotEmpty ? local.title : remote.title,
          coverUrl: local.coverUrl.isNotEmpty ? local.coverUrl : remote.coverUrl,
          tags: local.tags.isNotEmpty ? local.tags : remote.tags,
        );
        changedCount++;
      }
    }

    if (changedCount > 0) {
      await _persistToStorage();
      notifyListeners();
    }
    return changedCount;
  }
}
