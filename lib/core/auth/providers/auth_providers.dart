import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../network/bangumi_api_exception.dart';
import '../../providers/bangumi_providers.dart';
import '../models/auth_credentials.dart';
import '../models/auth_session.dart';
import '../models/auth_user.dart';
import '../repository/auth_repository.dart';
import '../services/bangumi_auth_service.dart';

/// 全局 AuthRepository 单例 Provider
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final bangumiClient = ref.watch(bangumiClientProvider);
  return AuthRepository(
    initialServices: [
      BangumiAuthService(client: bangumiClient),
    ],
  );
});

/// 认证状态包装模型
class AuthState {
  final AuthUser user;
  final AuthSession? session;
  final bool isLoading;
  final String? error;

  const AuthState({
    required this.user,
    this.session,
    this.isLoading = false,
    this.error,
  });

  bool get isLoggedIn => !user.isGuest && session != null;
  String? get token => session?.token;

  AuthState copyWith({
    AuthUser? user,
    AuthSession? session,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearSession = false,
  }) {
    return AuthState(
      user: user ?? this.user,
      session: clearSession ? null : (session ?? this.session),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 全局认证控制器 (Riverpod Notifier)
class AuthController extends Notifier<AuthState> {
  late final AuthRepository _repository;

  @override
  AuthState build() {
    _repository = ref.watch(authRepositoryProvider);
    return AuthState(
      user: _repository.currentUser,
      session: _repository.currentSession,
    );
  }

  /// 使用指定凭据进行登录
  Future<bool> login(AuthCredentials credentials) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _repository.login(credentials);
      state = state.copyWith(
        user: user,
        session: _repository.currentSession,
        isLoading: false,
      );
      return true;
    } on BangumiApiException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.message,
      );
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: '登录失败: $e',
      );
      return false;
    }
  }

  /// 刷新当前用户信息
  Future<void> refreshUserInfo() async {
    if (!state.isLoggedIn) return;
    try {
      final updatedUser = await _repository.refreshUserInfo();
      state = state.copyWith(user: updatedUser);
    } catch (_) {}
  }

  /// 退出登录并恢复游客态
  Future<void> logout() async {
    state = state.copyWith(isLoading: true);
    await _repository.logout();
    state = AuthState(
      user: _repository.currentUser,
      session: null,
      isLoading: false,
    );
  }
}

/// 全局认证控制器 Provider
final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);

/// 当前登录用户 Provider 快捷读
final currentUserProvider = Provider<AuthUser>((ref) {
  return ref.watch(authControllerProvider).user;
});

/// 当前是否处于登录态 Provider
final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(authControllerProvider).isLoggedIn;
});

/// 当前活跃访问令牌 Provider（用于网络请求 Authorization 注入）
final currentAuthTokenProvider = Provider<String?>((ref) {
  return ref.watch(authControllerProvider).token;
});
