import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/auth/models/auth_credentials.dart';
import 'package:zakoway/core/auth/models/auth_provider_type.dart';
import 'package:zakoway/core/auth/models/auth_user.dart';
import 'package:zakoway/core/auth/repository/auth_repository.dart';
import 'package:zakoway/core/auth/services/i_auth_service.dart';
import 'package:zakoway/core/auth/models/auth_session.dart';
import 'package:zakoway/core/models/bangumi/bangumi_user.dart';
import 'package:zakoway/core/services/app_preferences.dart';

class MockBangumiAuthService implements IAuthService {
  @override
  AuthProviderType get providerType => AuthProviderType.bangumi;

  @override
  Future<AuthSession> authenticate(AuthCredentials credentials) async {
    final token = (credentials as BangumiTokenCredentials).token;
    return AuthSession(
      token: token,
      providerType: AuthProviderType.bangumi,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<AuthUser> fetchUserInfo(String token) async {
    return AuthUser(
      id: 'bgm_123456',
      nickname: '测试阿宅',
      username: 'otaku_test',
      avatarUrl: 'https://example.com/avatar.jpg',
      sign: '爱生活，爱动漫',
      provider: AuthProviderType.bangumi,
      loginAt: DateTime.now(),
    );
  }

  @override
  Future<bool> validateToken(String token) async => true;

  @override
  Future<void> revokeToken(String token) async {}
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.init();
  });

  group('Auth Model Tests', () {
    test('AuthUser guest initialization', () {
      final guest = AuthUser.guest(guestCode: 'A1B2C3');
      expect(guest.isGuest, isTrue);
      expect(guest.provider, equals(AuthProviderType.guest));
      expect(guest.nickname, equals('杂鱼A1B2C3'));
      expect(guest.id, equals('guest_A1B2C3'));
    });

    test('AuthUser fromBangumi mapping', () {
      const bgmUser = BangumiUser(
        id: 654321,
        username: 'bgm_coder',
        nickname: '代码狂魔',
        sign: '正在写代码',
        avatar: {'large': 'https://bgm.tv/large.jpg'},
      );

      final user = AuthUser.fromBangumi(bgmUser);
      expect(user.isGuest, isFalse);
      expect(user.provider, equals(AuthProviderType.bangumi));
      expect(user.id, equals('bgm_654321'));
      expect(user.nickname, equals('代码狂魔'));
      expect(user.username, equals('bgm_coder'));
      expect(user.avatarUrl, equals('https://bgm.tv/large.jpg'));
    });
  });

  group('AuthRepository Tests', () {
    test('Initial state is guest', () {
      final repo = AuthRepository();
      expect(repo.isLoggedIn, isFalse);
      expect(repo.currentUser.isGuest, isTrue);
      expect(repo.activeToken, isNull);
    });

    test('Login with token persists session and updates user', () async {
      final repo = AuthRepository(
        initialServices: [MockBangumiAuthService()],
      );

      final user = await repo.login(
        const BangumiTokenCredentials('mock_token_secret'),
      );

      expect(repo.isLoggedIn, isTrue);
      expect(user.isGuest, isFalse);
      expect(user.nickname, equals('测试阿宅'));
      expect(repo.activeToken, equals('mock_token_secret'));

      // 验证本地持久化
      expect(AppPreferences.getAuthToken(), equals('mock_token_secret'));

      // 重新构造 Repository 验证从本地缓存恢复
      final restoredRepo = AuthRepository(
        initialServices: [MockBangumiAuthService()],
      );
      expect(restoredRepo.isLoggedIn, isTrue);
      expect(restoredRepo.currentUser.nickname, equals('测试阿宅'));
      expect(restoredRepo.activeToken, equals('mock_token_secret'));

      // 验证登出
      await restoredRepo.logout();
      expect(restoredRepo.isLoggedIn, isFalse);
      expect(restoredRepo.currentUser.isGuest, isTrue);
      expect(AppPreferences.getAuthToken(), isNull);
    });
  });
}
