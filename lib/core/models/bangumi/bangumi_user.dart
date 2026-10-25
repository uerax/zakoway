import '../../utils/html_utils.dart';

class BangumiUser {
  final int id;
  final String username;
  final String nickname;
  final String? sign;
  final Map<String, String> avatar;

  const BangumiUser({
    required this.id,
    required this.username,
    required this.nickname,
    this.sign,
    this.avatar = const {},
  });

  String get avatarUrl =>
      avatar['large'] ?? avatar['medium'] ?? avatar['small'] ?? '';

  factory BangumiUser.fromJson(Map<String, dynamic> json) {
    Map<String, String> avatarMap = {};
    if (json['avatar'] is Map) {
      final a = json['avatar'] as Map;
      a.forEach((k, v) {
        if (v != null) avatarMap[k.toString()] = v.toString();
      });
    } else if (json['avatar'] is String && (json['avatar'] as String).isNotEmpty) {
      avatarMap['large'] = json['avatar'] as String;
    }

    return BangumiUser(
      id: (json['id'] is num) ? (json['id'] as num).toInt() : int.tryParse('${json['id']}') ?? 0,
      username: json['username']?.toString() ?? '',
      nickname: decodeHtmlEntities(json['nickname']?.toString() ?? ''),
      sign: json['sign'] != null ? decodeHtmlEntities(json['sign'].toString()) : null,
      avatar: avatarMap,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'nickname': nickname,
        'sign': sign,
        'avatar': avatar,
      };
}
