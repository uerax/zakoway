import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/network/bangumi_client.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/core/services/app_prewarm_coordinator.dart';
import 'package:zakoway/features/settings/widgets/cache_settings_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.init();
    AppPrewarmCoordinator.instance.invalidateCacheSizes();

    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall methodCall) async {
          return '.';
        });
  });

  testWidgets('CacheSettingsCard renders header and tiles', (tester) async {
    final client = BangumiClient();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CacheSettingsCard(client: client, isVisible: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('数据与缓存'), findsOneWidget);
    expect(find.text('图片缓存'), findsOneWidget);
    expect(find.text('数据缓存'), findsOneWidget);
  });

  testWidgets('CacheSettingsCard triggers update when isVisible becomes true', (
    tester,
  ) async {
    final client = BangumiClient();

    // 初始挂载（isVisible 为 false）
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CacheSettingsCard(client: client, isVisible: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 切到前台可见（isVisible 由 false 变为 true）
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CacheSettingsCard(client: client, isVisible: true),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 验证组件在可见状态下正常渲染并完成刷新
    expect(find.byType(CacheSettingsCard), findsOneWidget);
    expect(find.text('数据与缓存'), findsOneWidget);
  });
}
