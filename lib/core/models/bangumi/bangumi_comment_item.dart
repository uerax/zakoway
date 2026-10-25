import '../../utils/html_utils.dart';
import 'bangumi_user.dart';

/// Bangumi 吐槽与讨论领域模型 (1:1 对齐 animaku 规范)
class BangumiCommentItem {
  final dynamic id;
  final BangumiUser author;
  final String content;
  final int? rate; // 1~10 分，未评分为 null
  final int? collectionType; // 1:想看, 2:看过, 3:在看, 4:搁置, 5:抛弃
  final String updatedAt;
  final DateTime? createdAt;

  const BangumiCommentItem({
    required this.id,
    required this.author,
    required this.content,
    this.rate,
    this.collectionType,
    required this.updatedAt,
    this.createdAt,
  });

  /// 对应 5 星制分值 (0.5 ~ 5.0)
  double? get starScore => (rate != null && rate! > 0) ? rate! / 2.0 : null;

  /// 观看状态中文标签
  String? get collectionTypeLabel {
    return switch (collectionType) {
      1 => '想看',
      2 => '看过',
      3 => '在看',
      4 => '搁置',
      5 => '抛弃',
      _ => null,
    };
  }

  /// 相对时间显示格式化
  String get relativeTimeLabel {
    if (createdAt == null) return updatedAt;
    final now = DateTime.now();
    final diff = now.difference(createdAt!);

    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    if (diff.inDays < 365) return '${diff.inDays ~/ 30} 个月前';
    return '${createdAt!.year}-${createdAt!.month.toString().padLeft(2, '0')}-${createdAt!.day.toString().padLeft(2, '0')}';
  }

  factory BangumiCommentItem.fromJson(Map<String, dynamic> json, [int fallbackIndex = 0]) {
    final userJson = (json['user'] ?? json['author']) as Map<String, dynamic>? ?? {};
    final user = BangumiUser.fromJson(userJson);

    final rawRate = json['rate'];
    final rateNum = (rawRate is num)
        ? rawRate.toInt()
        : (int.tryParse('$rawRate') ?? 0);
    final rate = (rateNum >= 1 && rateNum <= 10) ? rateNum : null;

    final rawType = json['type'] ?? json['collectionType'];
    final colType = (rawType is num)
        ? rawType.toInt()
        : (int.tryParse('$rawType'));

    final rawComment = json['comment'] ?? json['content'] ?? '';
    final content = decodeHtmlEntities(rawComment.toString()).trim();

    DateTime? parsedDate;
    final rawUpdated = json['updated_at'] ?? json['updatedAt'] ?? json['createdAt'];
    String updatedStr = '';
    if (rawUpdated is num) {
      parsedDate = DateTime.fromMillisecondsSinceEpoch(rawUpdated.toInt() * 1000);
      updatedStr = parsedDate.toIso8601String();
    } else if (rawUpdated != null) {
      updatedStr = rawUpdated.toString();
      parsedDate = DateTime.tryParse(updatedStr);
    }

    final id = json['id'] ?? '${user.id > 0 ? user.id : user.username}-$fallbackIndex';

    return BangumiCommentItem(
      id: id,
      author: user,
      content: content,
      rate: rate,
      collectionType: colType,
      updatedAt: updatedStr,
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user': author.toJson(),
        'comment': content,
        if (rate != null) 'rate': rate,
        if (collectionType != null) 'type': collectionType,
        'updated_at': updatedAt,
      };
}
