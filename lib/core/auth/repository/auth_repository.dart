import 'dart:convert';
import 'dart:developer' as developer;
import '../../network/bangumi_api_exception.dart';
import '../../services/app_preferences.dart';
import '../models/auth_credentials.dart';
import '../models/auth_provider_type.dart';
import '../models/auth_session.dart';
import '../models/auth_user.dart';
import '../services/i_auth_service.dart';

/// 统一认证仓储门面 (Auth Repository)：
/// 负责管理多认证源策略、用户会话状态转换、持久化恢复及登出回退。
class AuthRepository {
  final Map<AuthProviderType, IAuthService> _services = {};

  AuthUser _currentUser;
  AuthSession? _currentSession;

  AuthUser get currentUser => _currentUser;
  AuthSession? get currentSession => _currentSession;
  bool get isLoggedIn => !_currentUser.isGuest && _currentSession != null;
  String? get activeToken => _currentSession?.token;

  AuthRepository({List<IAuthService> initialServices = const []})
      : _currentUser = AuthUser.guest(
          guestCode: AppPreferences.getGuestMachineCode(),
        ) {
    for (final s in initialServices) {
      registerService(s);
    }
    _restoreFromStorage();
  }

  /// 动态注册认证提供商策略（便于无痛接入自建用户系统）
  void registerService(IAuthService service) {
    _services[service.providerType] = service;
  }

  /// 从本地持久化缓存还原登录态
  void _restoreFromStorage() {
    try {
      final token = AppPreferences.getAuthToken();
      final userJsonStr = AppPreferences.getAuthUserJson();
      final sessionJsonStr = AppPreferences.getAuthSessionJson();

      if (token != null && token.isNotEmpty && userJsonStr != null) {
        final userMap = jsonDecode(userJsonStr) as Map<String, dynamic>;
        _currentUser = AuthUser.fromJson(userMap);

        if (sessionJsonStr != null) {
          final sessionMap =
              jsonDecode(sessionJsonStr) as Map<String, dynamic>;
          _currentSession = AuthSession.fromJson(sessionMap);
        } else {
          _currentSession = AuthSession(
            token: token,
            providerType: _currentUser.provider,
            createdAt: _currentUser.loginAt,
          );
        }
      }
    } catch (e) {
      developer.log('恢复登录态异常: $e', name: 'AuthRepository');
      _fallbackToGuest();
    }
  }

  /// 执行登录
  Future<AuthUser> login(AuthCredentials credentials) async {
    final service = _services[credentials.providerType];
    if (service == null) {
      throw BangumiApiException(
        '暂不支持 ${credentials.providerType.label} 登录方式',
      );
    }

    // 1. 鉴权并获得 Session
    final session = await service.authenticate(credentials);

    // 2. 获取用户最新详情
    final user = await service.fetchUserInfo(session.token);

    // 3. 落盘持久化
    _currentUser = user;
    _currentSession = session;

    await AppPreferences.saveAuthData(
      token: session.token,
      userJson: jsonEncode(user.toJson()),
      sessionJson: jsonEncode(session.toJson()),
    );

    return _currentUser;
  }

  /// 重新拉取当前用户信息
  Future<AuthUser> refreshUserInfo() async {
    final session = _currentSession;
    if (session == null || _currentUser.isGuest) {
      return _currentUser;
    }

    final service = _services[session.providerType];
    if (service == null) {
      return _currentUser;
    }

    final updatedUser = await service.fetchUserInfo(session.token);
    _currentUser = updatedUser;

    await AppPreferences.saveAuthData(
      token: session.token,
      userJson: jsonEncode(updatedUser.toJson()),
      sessionJson: jsonEncode(session.toJson()),
    );

    return _currentUser;
  }

  /// 退出登录，安全回退到游客态
  Future<void> logout() async {
    final session = _currentSession;
    if (session != null) {
      final service = _services[session.providerType];
      try {
        await service?.revokeToken(session.token);
      } catch (_) {}
    }

    _fallbackToGuest();
    await AppPreferences.clearAuthData();
  }

  void _fallbackToGuest() {
    _currentSession = null;
    _currentUser = AuthUser.guest(
      guestCode: AppPreferences.getGuestMachineCode(),
    );
  }
}
