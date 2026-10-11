import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/auth/models/auth_credentials.dart';
import 'package:zakoway/core/auth/models/auth_provider_type.dart';
import 'package:zakoway/core/auth/models/auth_session.dart';
import 'package:zakoway/core/auth/models/auth_user.dart';
import 'package:zakoway/core/auth/services/i_auth_service.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/features/auth/widgets/auth_login_sheet.dart';

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
      id: 'bgm_123',
      nickname: '测试用户',
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

  testWidgets('AuthLoginSheet renders inputs, tabs and guide card',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AuthLoginSheet(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('连接账号'), findsOneWidget);
    expect(find.text('Bangumi 令牌'), findsOneWidget);
    expect(find.text('Zakoway 账号'), findsOneWidget);
    expect(find.text('如何获取 Bangumi Access Token？'), findsOneWidget);
    expect(find.text('立即验证并连接'), findsOneWidget);
  });

  testWidgets('AuthLoginSheet displays error on empty token submit',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AuthLoginSheet(),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('立即验证并连接'));
    await tester.pump();

    expect(find.text('请输入或粘贴 Bangumi Access Token'), findsOneWidget);
  });

  testWidgets(
      'AuthLoginSheet fits narrow 300px width without RenderFlex overflow',
      (tester) async {
    tester.view.physicalSize = const Size(300, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: AuthLoginSheet(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('一键复制 Token 获取网址'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
