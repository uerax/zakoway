import 'auth_provider_type.dart';

/// 抽象登录凭据基类：
/// 各服务提供商扩展具体的凭据类型（如 Token、账号密码、OAuth Code 等）
abstract class AuthCredentials {
  final AuthProviderType providerType;

  const AuthCredentials(this.providerType);
}

/// Bangumi 访问令牌凭据
class BangumiTokenCredentials extends AuthCredentials {
  final String token;

  const BangumiTokenCredentials(this.token) : super(AuthProviderType.bangumi);
}

/// 预留：Zakoway 官方/自建账号系统密码凭据
class ZakowayPasswordCredentials extends AuthCredentials {
  final String account;
  final String password;

  const ZakowayPasswordCredentials({
    required this.account,
    required this.password,
  }) : super(AuthProviderType.zakoway);
}
