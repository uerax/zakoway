import '../../auth/models/auth_provider_type.dart';
import '../../models/bangumi/bangumi_collection.dart';
import '../models/anime_collection_item.dart';

/// 可插拔追番数据同步策略接口：
/// 隔离不同服务商（当前 Bangumi、未来自建账号系统、或其他第三方同步服务）的追番收藏同步协议。
abstract class ICollectionSyncProvider {
  /// 该同步服务对应的认证提供商类型
  AuthProviderType get providerType;

  /// 将本地收藏变更推送到远端服务器
  Future<bool> pushCollection(AnimeCollectionItem item, String token);

  /// 取消追番收藏（或重置状态）
  Future<bool> deleteCollection(int subjectId, String token);

  /// 获取单个番剧在远端的最新收藏状态
  Future<AnimeCollectionItem?> fetchCollection(int subjectId, String token);

  /// 全量拉取远端用户的全部收藏（用于登录后首次对齐或手动下拉刷新）
  Future<List<AnimeCollectionItem>> fetchAllRemoteCollections({
    required String token,
    required String username,
    CollectType? type,
  });
}
