import 'auth_provider_type.dart';

/// 认证会话凭证：
/// 封装当前登录令牌、有效期限及服务元信息
class AuthSession {
  final String token;
  final AuthProviderType providerType;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final Map<String, dynamic>? meta;

  const AuthSession({
    required this.token,
    required this.providerType,
    required this.createdAt,
    this.expiresAt,
    this.meta,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      token: json['token']?.toString() ?? '',
      providerType: AuthProviderType.fromId(json['provider_type']?.toString()),
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      expiresAt: json['expires_at'] != null
          ? DateTime.tryParse(json['expires_at'].toString())
          : null,
      meta: json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'provider_type': providerType.id,
        'created_at': createdAt.toIso8601String(),
        'expires_at': expiresAt?.toIso8601String(),
        'meta': meta,
      };
}
