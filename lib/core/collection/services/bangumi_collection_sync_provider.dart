import '../../auth/models/auth_provider_type.dart';
import '../../models/bangumi/bangumi_collection.dart';
import '../../network/bangumi_client.dart';
import '../models/anime_collection_item.dart';
import 'i_collection_sync_provider.dart';

/// Bangumi 官方 API 追番收藏同步实现
class BangumiCollectionSyncProvider implements ICollectionSyncProvider {
  final BangumiClient _client;

  BangumiCollectionSyncProvider({BangumiClient? client})
      : _client = client ?? BangumiClient();

  @override
  AuthProviderType get providerType => AuthProviderType.bangumi;

  @override
  Future<bool> pushCollection(AnimeCollectionItem item, String token) async {
    return await _client.setCollection(
      item.subjectId,
      item.type,
      token,
      rate: item.myRating,
      comment: item.myComment,
    );
  }

  @override
  Future<bool> deleteCollection(int subjectId, String token) async {
    return await _client.setCollection(
      subjectId,
      CollectType.none,
      token,
    );
  }

  @override
  Future<AnimeCollectionItem?> fetchCollection(
      int subjectId, String token) async {
    final entry = await _client.getCollection(subjectId, token);
    if (entry == null) return null;
    try {
      final subject = await _client.getSubject(subjectId);
      return AnimeCollectionItem.fromBangumiItem(
        item: subject,
        type: entry.type,
        myRating: entry.rate,
        myComment: entry.comment,
        updatedAt: entry.updatedAt != null
            ? DateTime.tryParse(entry.updatedAt!)
            : null,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<AnimeCollectionItem>> fetchAllRemoteCollections({
    required String token,
    required String username,
    CollectType? type,
  }) async {
    final results = <AnimeCollectionItem>[];
    var offset = 0;
    const limit = 30;

    // 分页拉取，最多批量同步前 120 条，保障网络性能与响应速度
    while (offset < 120) {
      final rawList = await _client.getUserCollections(
        username,
        token: token,
        type: type,
        limit: limit,
        offset: offset,
      );

      if (rawList.isEmpty) break;

      for (final raw in rawList) {
        final subjectMap = raw['subject'];
        final subjectId = raw['subject_id'] is num
            ? (raw['subject_id'] as num).toInt()
            : int.tryParse('${raw['subject_id']}') ?? 0;

        if (subjectId <= 0) continue;

        final collectType = CollectType.fromBangumiType(
          raw['type'] is int ? raw['type'] : int.tryParse('${raw['type']}'),
        );

        String title = '';
        String? originalName;
        String coverUrl = '';
        double score = 0.0;
        int rank = 0;
        int totalEps = 0;
        final List<String> tags = [];

        if (subjectMap is Map<String, dynamic>) {
          final nameCn = subjectMap['name_cn']?.toString() ?? '';
          final name = subjectMap['name']?.toString() ?? '';
          title = nameCn.isNotEmpty ? nameCn : name;
          originalName = (name.isNotEmpty && name != title) ? name : null;
          final images = subjectMap['images'];
          if (images is Map) {
            coverUrl = images['large']?.toString() ??
                images['common']?.toString() ??
                images['medium']?.toString() ??
                '';
          }
          score = (subjectMap['score'] is num)
              ? (subjectMap['score'] as num).toDouble()
              : double.tryParse('${subjectMap['score']}') ?? 0.0;
          rank = (subjectMap['rank'] is num)
              ? (subjectMap['rank'] as num).toInt()
              : int.tryParse('${subjectMap['rank']}') ?? 0;
          totalEps = (subjectMap['eps'] is num)
              ? (subjectMap['eps'] as num).toInt()
              : int.tryParse('${subjectMap['eps']}') ?? 0;

          final rawTags = subjectMap['tags'];
          if (rawTags is List) {
            for (final t in rawTags) {
              if (t is Map && t['name'] != null) {
                tags.add(t['name'].toString().trim());
              } else if (t is String) {
                tags.add(t.trim());
              }
            }
          }
        }

        results.add(
          AnimeCollectionItem(
            subjectId: subjectId,
            type: collectType,
            title: title.isNotEmpty ? title : '番剧 #$subjectId',
            originalName: originalName,
            coverUrl: coverUrl,
            score: score,
            rank: rank,
            totalEpisodes: totalEps,
            tags: tags,
            updatedAt: raw['updated_at'] != null
                ? DateTime.tryParse(raw['updated_at'].toString()) ??
                    DateTime.now()
                : DateTime.now(),
            myRating: raw['rate'] is num ? (raw['rate'] as num).toInt() : null,
            myComment: raw['comment']?.toString(),
          ),
        );
      }

      if (rawList.length < limit) break;
      offset += limit;
    }

    return results;
  }
}
