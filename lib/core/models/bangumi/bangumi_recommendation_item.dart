import '../../utils/html_utils.dart';

/// Bangumi 条目关联/相似推荐结果条目
class BangumiRecommendationItem {
  final int id;
  final String name;
  final String nameCn;
  final String cover;
  final double score;
  final String year;
  final String epsLabel;
  final String? relationBadge; // 续作 / 前传 / 剧场版 / null

  const BangumiRecommendationItem({
    required this.id,
    required this.name,
    required this.nameCn,
    required this.cover,
    required this.score,
    required this.year,
    required this.epsLabel,
    this.relationBadge,
  });

  String get displayName => nameCn.isNotEmpty ? nameCn : name;

  factory BangumiRecommendationItem.fromJson(Map<String, dynamic> json) {
    final rawScore = json['score'];
    final score = (rawScore is num)
        ? rawScore.toDouble()
        : (double.tryParse('$rawScore') ?? 0.0);

    return BangumiRecommendationItem(
      id: (json['id'] is num)
          ? (json['id'] as num).toInt()
          : (int.tryParse('${json['id']}') ?? 0),
      name: json['name']?.toString() ?? '',
      nameCn: decodeHtmlEntities(json['name_cn']?.toString() ?? json['nameCn']?.toString() ?? ''),
      cover: json['cover']?.toString() ?? '',
      score: score,
      year: json['year']?.toString() ?? '',
      epsLabel: json['eps_label']?.toString() ?? json['epsLabel']?.toString() ?? '',
      relationBadge: json['relation_badge']?.toString() ?? json['relationBadge']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'name_cn': nameCn,
        'cover': cover,
        'score': score,
        'year': year,
        'eps_label': epsLabel,
        if (relationBadge != null) 'relation_badge': relationBadge,
      };
}
