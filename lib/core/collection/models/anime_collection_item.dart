import '../../models/bangumi/bangumi_collection.dart';
import '../../models/bangumi/bangumi_item.dart';

/// 本地追番实体模型：
/// 统一承载本地持久化、远端同步以及数据分析所需的番剧画像属性。
class AnimeCollectionItem {
  final int subjectId;
  final CollectType type;
  final String title;
  final String? originalName;
  final String coverUrl;
  final double score;
  final int rank;
  final int totalEpisodes;
  final List<String> tags;
  final DateTime updatedAt;
  final int? myRating;
  final String? myComment;

  const AnimeCollectionItem({
    required this.subjectId,
    required this.type,
    required this.title,
    this.originalName,
    this.coverUrl = '',
    this.score = 0.0,
    this.rank = 0,
    this.totalEpisodes = 0,
    this.tags = const [],
    required this.updatedAt,
    this.myRating,
    this.myComment,
  });

  /// 从 BangumiItem 快捷构造追番条目
  factory AnimeCollectionItem.fromBangumiItem({
    required BangumiItem item,
    required CollectType type,
    int? myRating,
    String? myComment,
    DateTime? updatedAt,
  }) {
    return AnimeCollectionItem(
      subjectId: item.id,
      type: type,
      title: item.preferredName,
      originalName: item.name != item.preferredName ? item.name : null,
      coverUrl: item.coverUrl,
      score: item.ratingScore,
      rank: item.rank,
      totalEpisodes: item.eps > 0 ? item.eps : 0,
      tags: item.tags.map((t) => t.name).toList(),
      updatedAt: updatedAt ?? DateTime.now(),
      myRating: myRating,
      myComment: myComment,
    );
  }

  AnimeCollectionItem copyWith({
    int? subjectId,
    CollectType? type,
    String? title,
    String? originalName,
    String? coverUrl,
    double? score,
    int? rank,
    int? totalEpisodes,
    List<String>? tags,
    DateTime? updatedAt,
    int? myRating,
    String? myComment,
  }) {
    return AnimeCollectionItem(
      subjectId: subjectId ?? this.subjectId,
      type: type ?? this.type,
      title: title ?? this.title,
      originalName: originalName ?? this.originalName,
      coverUrl: coverUrl ?? this.coverUrl,
      score: score ?? this.score,
      rank: rank ?? this.rank,
      totalEpisodes: totalEpisodes ?? this.totalEpisodes,
      tags: tags ?? this.tags,
      updatedAt: updatedAt ?? this.updatedAt,
      myRating: myRating ?? this.myRating,
      myComment: myComment ?? this.myComment,
    );
  }

  /// 转换为 BangumiItem 用于兼容播放器跳转及卡片渲染
  BangumiItem toBangumiItem() {
    return BangumiItem(
      id: subjectId,
      type: 2, // 2 = 动画
      name: originalName ?? title,
      nameCn: title,
      summary: '',
      airDate: '',
      airWeekday: 0,
      rank: rank,
      images: coverUrl.isNotEmpty
          ? {
              'large': coverUrl,
              'common': coverUrl,
              'medium': coverUrl,
              'small': coverUrl,
            }
          : const {},
      tags: tags.map((t) => BangumiTag(name: t)).toList(),
      alias: const [],
      ratingScore: score,
      votes: 0,
      eps: totalEpisodes,
      totalEpisodes: totalEpisodes,
    );
  }

  factory AnimeCollectionItem.fromJson(Map<String, dynamic> json) {
    final typeVal = json['type'];
    final collectType = typeVal is int
        ? CollectType.fromBangumiType(typeVal)
        : CollectType.values.firstWhere(
            (e) => e.name == json['type_name'] || e.label == json['type_name'],
            orElse: () => CollectType.none,
          );

    final rawTags = json['tags'];
    List<String> tagsList = [];
    if (rawTags is List) {
      tagsList = rawTags.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
    }

    return AnimeCollectionItem(
      subjectId: json['subject_id'] is num
          ? (json['subject_id'] as num).toInt()
          : int.tryParse('${json['subject_id']}') ?? 0,
      type: collectType,
      title: json['title']?.toString() ?? '未知番剧',
      originalName: json['original_name']?.toString(),
      coverUrl: json['cover_url']?.toString() ?? '',
      score: json['score'] is num
          ? (json['score'] as num).toDouble()
          : double.tryParse('${json['score']}') ?? 0.0,
      rank: json['rank'] is num
          ? (json['rank'] as num).toInt()
          : int.tryParse('${json['rank']}') ?? 0,
      totalEpisodes: json['total_episodes'] is num
          ? (json['total_episodes'] as num).toInt()
          : int.tryParse('${json['total_episodes']}') ?? 0,
      tags: tagsList,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      myRating: json['my_rating'] is num
          ? (json['my_rating'] as num).toInt()
          : int.tryParse('${json['my_rating']}'),
      myComment: json['my_comment']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'subject_id': subjectId,
        'type': type.toBangumiType(),
        'type_name': type.name,
        'title': title,
        'original_name': originalName,
        'cover_url': coverUrl,
        'score': score,
        'rank': rank,
        'total_episodes': totalEpisodes,
        'tags': tags,
        'updated_at': updatedAt.toIso8601String(),
        'my_rating': myRating,
        'my_comment': myComment,
      };
}
