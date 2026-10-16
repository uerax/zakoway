import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/features/player/source/server/animaku_server_client.dart';
import 'package:zakoway/features/player/widgets/episode_picker_section.dart';
import 'package:zakoway/features/player/widgets/video_source_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Animaku 服务端模式单元与部件测试', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppPreferences.init();
    });

    test('默认配置与持久化测试', () async {
      // 默认状态应为关闭，默认地址应为 bakasine.eu.org
      expect(AppPreferences.isServerModeEnabled(), isFalse);
      expect(AppPreferences.getServerModeApiUrl(), equals('https://bakasine.eu.org'));

      // 修改状态并检查通知
      var notified = false;
      void listener() => notified = true;
      AppPreferences.serverModeNotifier.addListener(listener);

      await AppPreferences.setServerModeEnabled(true);
      expect(AppPreferences.isServerModeEnabled(), isTrue);
      expect(notified, isTrue);

      // 修改自定义地址
      await AppPreferences.setServerModeApiUrl('https://custom.animaku.test/');
      expect(AppPreferences.getServerModeApiUrl(), equals('https://custom.animaku.test'));

      // 恢复默认
      await AppPreferences.setServerModeApiUrl('https://bakasine.eu.org');
      expect(AppPreferences.getServerModeApiUrl(), equals('https://bakasine.eu.org'));

      AppPreferences.serverModeNotifier.removeListener(listener);
    });

    test('AnimakuServerClient 源支持判定与别名归一化', () {
      final client = AnimakuServerClient.instance;

      expect(client.normalizeSourceId('xifan_next'), equals('xifan-next'));
      expect(client.normalizeSourceId('CYCANI'), equals('cycani'));

      // 初始固化源测试
      expect(client.isSourceSupported('xifan-next'), isTrue);
      expect(client.isSourceSupported('cycani'), isTrue);
      // anime1 属于全量代拉源，客户端主动排除以保护公共服务器带宽
      expect(client.isSourceSupported('anime1'), isFalse);
      expect(client.isSourceSupported('unknown_source_xyz'), isFalse);
    });

    testWidgets('VideoSourceView UI：源名称应用颜色且开启服务端模式时展示[服务端]徽章', (tester) async {
      final testSources = [
        const VideoSourceItem(
          id: 'cycani',
          name: '次元城动画',
          description: '多线路原画',
          isDirect: true,
        ),
        const VideoSourceItem(
          id: 'anime1',
          name: 'Anime1',
          description: '海外源（主动排除服务端代拉，保持本地）',
          isDirect: false,
        ),
      ];

      // 1. 关闭服务端模式：不应该出现“直连”或“代理”标签，也不出现“服务端”标签
      await AppPreferences.setServerModeEnabled(false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoSourceView(
              selectedSourceId: 'cycani',
              sources: testSources,
              onSourceSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 确认旧标签已彻底移除
      expect(find.text('直连'), findsNothing);
      expect(find.text('代理'), findsNothing);
      expect(find.text('服务端'), findsNothing);

      // 检查源名称正常展示
      expect(find.text('次元城动画'), findsOneWidget);
      expect(find.text('Anime1'), findsOneWidget);

      // 2. 开启服务端模式：仅 cycani 被服务端支持接管，展示 1 个“服务端”标签；anime1 保持本地直连
      await AppPreferences.setServerModeEnabled(true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoSourceView(
              selectedSourceId: 'cycani',
              sources: testSources,
              onSourceSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 应该仅为被接管的 cycani 展示 1 个“服务端”胶囊标签
      expect(find.text('服务端'), findsOneWidget);
    });

    testWidgets('EpisodePickerSection 空态友好提示与换源回调测试', (tester) async {
      var switched = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpisodePickerSection(
              episodeCount: 0,
              slots: const [],
              sourceName: '稀饭Next',
              errorMessage: '网络连接超时 (504)',
              onSelectEpisode: (_) {},
              onSwitchSource: () => switched = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证不展示假集数
      expect(find.text('源未解析到分集'), findsOneWidget);
      expect(find.text('第 01 话'), findsNothing);

      // 验证友好错误提示卡片
      expect(find.text('「稀饭Next」暂无可播放分集'), findsOneWidget);
      expect(find.text('网络连接超时 (504)'), findsOneWidget);

      // 点击切换视频源
      await tester.tap(find.text('切换视频源'));
      await tester.pumpAndSettle();
      expect(switched, isTrue);
    });
  });
}
