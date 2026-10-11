import '../../models/bangumi/bangumi_user.dart';
import 'auth_provider_type.dart';

/// 统一领域用户模型：
/// 抹平不同认证源（游客、Bangumi、自建系统）字段差异，向上层 UI 提供一致的用户实体。
class AuthUser {
  final String id;
  final String nickname;
  final String? username;
  final String? avatarUrl;
  final String? sign;
  final AuthProviderType provider;
  final DateTime loginAt;
  final Map<String, dynamic>? extraData;

  const AuthUser({
    required this.id,
    required this.nickname,
    this.username,
    this.avatarUrl,
    this.sign,
    required this.provider,
    required this.loginAt,
    this.extraData,
  });

  /// 是否为游客身份
  bool get isGuest => provider == AuthProviderType.guest;

  /// 构造游客身份实体
  factory AuthUser.guest({required String guestCode}) {
    return AuthUser(
      id: 'guest_$guestCode',
      nickname: '杂鱼$guestCode',
      provider: AuthProviderType.guest,
      loginAt: DateTime.now(),
    );
  }

  /// 从 Bangumi 官方用户实体转换
  factory AuthUser.fromBangumi(BangumiUser user) {
    return AuthUser(
      id: 'bgm_${user.id}',
      nickname: user.nickname.isNotEmpty ? user.nickname : user.username,
      username: user.username,
      avatarUrl: user.avatarUrl.isNotEmpty ? user.avatarUrl : null,
      sign: user.sign,
      provider: AuthProviderType.bangumi,
      loginAt: DateTime.now(),
      extraData: user.toJson(),
    );
  }

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id']?.toString() ?? '',
      nickname: json['nickname']?.toString() ?? '未知用户',
      username: json['username']?.toString(),
      avatarUrl: json['avatar_url']?.toString(),
      sign: json['sign']?.toString(),
      provider: AuthProviderType.fromId(json['provider']?.toString()),
      loginAt: json['login_at'] != null
          ? DateTime.tryParse(json['login_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      extraData: json['extra_data'] is Map
          ? Map<String, dynamic>.from(json['extra_data'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'nickname': nickname,
        'username': username,
        'avatar_url': avatarUrl,
        'sign': sign,
        'provider': provider.id,
        'login_at': loginAt.toIso8601String(),
        'extra_data': extraData,
      };
}
