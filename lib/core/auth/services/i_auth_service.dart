import '../models/auth_credentials.dart';
import '../models/auth_provider_type.dart';
import '../models/auth_session.dart';
import '../models/auth_user.dart';

/// 可插拔认证策略基类接口 (Auth Strategy Interface)：
/// 任何新的认证渠道（Bangumi、自建系统、OAuth 等）只需实现该接口，即可无缝接入全局认证系统。
abstract class IAuthService {
  /// 该服务对应的提供商枚举
  AuthProviderType get providerType;

  /// 验证凭据并生成会话
  Future<AuthSession> authenticate(AuthCredentials credentials);

  /// 根据 Token 拉取最新用户信息
  Future<AuthUser> fetchUserInfo(String token);

  /// 校验 Token 是否仍然有效
  Future<bool> validateToken(String token);

  /// 撤销/退出登录（根据平台特性实现，可选）
  Future<void> revokeToken(String token);
}
