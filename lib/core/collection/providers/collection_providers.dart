import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../auth/providers/auth_providers.dart';
import '../../models/bangumi/bangumi_collection.dart';
import '../../models/bangumi/bangumi_item.dart';
import '../../providers/bangumi_providers.dart';
import '../models/anime_collection_item.dart';
import '../services/anime_collection_service.dart';
import '../services/bangumi_collection_sync_provider.dart';
import '../services/i_collection_sync_provider.dart';

/// 本地追番服务 Provider
final animeCollectionServiceProvider = Provider<AnimeCollectionService>((ref) {
  return AnimeCollectionService.instance;
});

/// 追番同步 Provider（可插拔扩展点：当前挂载 Bangumi，未来可无缝切换自建系统）
final collectionSyncProvider = Provider<ICollectionSyncProvider>((ref) {
  final client = ref.watch(bangumiClientProvider);
  return BangumiCollectionSyncProvider(client: client);
});

/// 追番状态模型
class CollectionState {
  final List<AnimeCollectionItem> items;
  final bool isSyncing;
  final String? syncError;
  final DateTime? lastSyncTime;

  const CollectionState({
    required this.items,
    this.isSyncing = false,
    this.syncError,
    this.lastSyncTime,
  });

  CollectionState copyWith({
    List<AnimeCollectionItem>? items,
    bool? isSyncing,
    String? syncError,
    DateTime? lastSyncTime,
    bool clearError = false,
  }) {
    return CollectionState(
      items: items ?? this.items,
      isSyncing: isSyncing ?? this.isSyncing,
      syncError: clearError ? null : (syncError ?? this.syncError),
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

/// 追番全局控制器 Notifier
class CollectionNotifier extends Notifier<CollectionState> {
  late final AnimeCollectionService _service;
  late final ICollectionSyncProvider _syncProvider;

  @override
  CollectionState build() {
    _service = ref.watch(animeCollectionServiceProvider);
    _syncProvider = ref.watch(collectionSyncProvider);

    void onServiceChanged() {
      state = state.copyWith(items: _service.allItems);
    }

    _service.addListener(onServiceChanged);
    ref.onDispose(() {
      _service.removeListener(onServiceChanged);
    });

    return CollectionState(items: _service.allItems);
  }

  /// 更新番剧追番状态（本地瞬间落盘 + 若登录则后台异步同步至远端）
  Future<void> updateStatus({
    required BangumiItem bangumiItem,
    required CollectType type,
    int? myRating,
    String? myComment,
  }) async {
    // 1. 本地数据库瞬间更新，保障 0ms 响应无感交互
    final updatedItem = await _service.updateStatusFromBangumiItem(
      bangumiItem: bangumiItem,
      type: type,
      myRating: myRating,
      myComment: myComment,
    );

    // 2. 检查登录态并触发静默异步同步
    final token = ref.read(currentAuthTokenProvider);
    if (token != null && token.isNotEmpty) {
      if (type == CollectType.none) {
        _syncProvider.deleteCollection(bangumiItem.id, token).catchError((_) => false);
      } else {
        _syncProvider.pushCollection(updatedItem, token).catchError((_) => false);
      }
    }
  }

  /// 取消追番
  Future<void> removeStatus(int subjectId) async {
    await _service.removeItem(subjectId);
    final token = ref.read(currentAuthTokenProvider);
    if (token != null && token.isNotEmpty) {
      _syncProvider.deleteCollection(subjectId, token).catchError((_) => false);
    }
  }

  /// 全量/增量从远端服务器同步对齐追番列表
  Future<int> syncWithRemote({CollectType? type}) async {
    final token = ref.read(currentAuthTokenProvider);
    final currentUser = ref.read(currentUserProvider);

    if (token == null || token.isEmpty || currentUser.isGuest) {
      return 0;
    }

    state = state.copyWith(isSyncing: true, clearError: true);
    try {
      final username = currentUser.username ?? currentUser.id.replaceFirst('bgm_', '');
      final remoteItems = await _syncProvider.fetchAllRemoteCollections(
        token: token,
        username: username,
        type: type,
      );

      final mergedCount = await _service.mergeRemoteItems(remoteItems);
      state = state.copyWith(
        items: _service.allItems,
        isSyncing: false,
        lastSyncTime: DateTime.now(),
      );
      return mergedCount;
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        syncError: '同步失败: $e',
      );
      return 0;
    }
  }
}

/// 全局追番控制器 Provider
final collectionControllerProvider =
    NotifierProvider<CollectionNotifier, CollectionState>(
  CollectionNotifier.new,
);

/// 获取全部追番条目 Provider
final allCollectionsProvider = Provider<List<AnimeCollectionItem>>((ref) {
  return ref.watch(collectionControllerProvider).items;
});

/// 获取指定状态分类下的追番条目 Provider
final collectionsByTypeProvider =
    Provider.family<List<AnimeCollectionItem>, CollectType>((ref, type) {
  final all = ref.watch(allCollectionsProvider);
  return all.where((e) => e.type == type).toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
});

/// 获取特定番剧当前的追番状态 Provider
final collectionTypeForSubjectProvider =
    Provider.family<CollectType, int>((ref, subjectId) {
  final all = ref.watch(allCollectionsProvider);
  for (final item in all) {
    if (item.subjectId == subjectId) return item.type;
  }
  return CollectType.none;
});

/// 获取各状态分类的数量统计 Provider
final collectionCountStatsProvider = Provider<Map<CollectType, int>>((ref) {
  final all = ref.watch(allCollectionsProvider);
  final stats = <CollectType, int>{
    CollectType.watching: 0,
    CollectType.planToWatch: 0,
    CollectType.watched: 0,
    CollectType.onHold: 0,
    CollectType.abandoned: 0,
  };
  for (final item in all) {
    if (stats.containsKey(item.type)) {
      stats[item.type] = (stats[item.type] ?? 0) + 1;
    }
  }
  return stats;
});
