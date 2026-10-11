import '../../network/bangumi_client.dart';
import '../models/auth_credentials.dart';
import '../models/auth_provider_type.dart';
import '../models/auth_session.dart';
import '../models/auth_user.dart';
import 'i_auth_service.dart';

/// Bangumi 访问令牌认证服务实现：
/// 通过 BangumiClient /v0/me 端点验证令牌并获取用户信息
class BangumiAuthService implements IAuthService {
  final BangumiClient _client;

  BangumiAuthService({BangumiClient? client})
      : _client = client ?? BangumiClient();

  @override
  AuthProviderType get providerType => AuthProviderType.bangumi;

  @override
  Future<AuthSession> authenticate(AuthCredentials credentials) async {
    if (credentials is! BangumiTokenCredentials) {
      throw const BangumiApiException('无效的 Bangumi 登录凭据');
    }

    final rawToken = credentials.token.trim();
    if (rawToken.isEmpty) {
      throw const BangumiApiException('访问令牌不能为空');
    }

    // 验证 Token 有效性：尝试拉取用户信息
    await _client.getCurrentUser(rawToken);

    return AuthSession(
      token: rawToken,
      providerType: AuthProviderType.bangumi,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<AuthUser> fetchUserInfo(String token) async {
    final cleanToken = token.trim();
    final bangumiUser = await _client.getCurrentUser(cleanToken);
    return AuthUser.fromBangumi(bangumiUser);
  }

  @override
  Future<bool> validateToken(String token) async {
    try {
      final cleanToken = token.trim();
      if (cleanToken.isEmpty) return false;
      await _client.getCurrentUser(cleanToken);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> revokeToken(String token) async {
    // Bangumi 个人访问令牌 (PAT) 为用户端受控凭据，无需向服务端发起注销请求
  }
}
