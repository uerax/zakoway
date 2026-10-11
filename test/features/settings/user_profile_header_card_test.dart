import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/auth/models/auth_user.dart';
import 'package:zakoway/core/auth/providers/auth_providers.dart';
import 'package:zakoway/core/models/bangumi/bangumi_user.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/features/settings/widgets/user_action_control_bar.dart';
import 'package:zakoway/features/settings/widgets/user_profile_header_card.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.init();
  });

  testWidgets('UserProfileHeaderCard renders guest state when not logged in',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: UserProfileHeaderCard(),
          ),
        ),
      ),
    );
    await tester.pump();

    // 默认展示游客机器码及引导文案
    expect(find.textContaining('杂鱼'), findsOneWidget);
    expect(find.text('点击登录'), findsOneWidget);
  });

  testWidgets('UserProfileHeaderCard renders Bangumi user state when logged in',
      (tester) async {
    final bgmUser = AuthUser.fromBangumi(
      const BangumiUser(
        id: 998877,
        username: 'zakoni_fan',
        nickname: '追番达人',
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserProvider.overrideWithValue(bgmUser),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: UserProfileHeaderCard(),
          ),
        ),
      ),
    );
    await tester.pump();

    // 展示 Bangumi 用户昵称、UID 及平台徽章
    expect(find.text('追番达人'), findsOneWidget);
    expect(find.text('BGM'), findsOneWidget);
    expect(find.text('已连接'), findsOneWidget);
    expect(find.textContaining('UID: 998877'), findsOneWidget);
  });

  testWidgets('UserActionControlBar renders 4 action tiles', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: UserActionControlBar(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('观看历史'), findsOneWidget);
    expect(find.text('我的追番'), findsOneWidget);
    expect(find.text('数据分析'), findsOneWidget);
    expect(find.text('离线缓存'), findsOneWidget);
  });
}
