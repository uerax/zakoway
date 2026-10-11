import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/core/models/history/watch_history_item.dart';
import 'package:zakoway/core/services/watch_history_service.dart';
import 'package:zakoway/features/settings/pages/data_analysis_page.dart';
import 'package:zakoway/features/settings/services/anime_analytics_service.dart';
import 'package:zakoway/features/settings/widgets/user_action_control_bar.dart';

void main() {
  group('AnimeAnalyticsService tests', () {
    test('Empty history returns graceful empty report', () {
      final report = AnimeAnalyticsService.analyze([]);
      expect(report.isEmpty, isTrue);
      expect(report.totalAnimeCount, equals(0));
      expect(report.personaTitle, equals('初入次元的萌新'));
      expect(report.diversityScore, equals(0));
    });

    test('Computes accurate top genres, hours and persona for fantasy lovers', () {
      final history = [
        const WatchHistoryItem(
          id: '1::ep1',
          bangumiId: 1,
          title: '葬送的芙莉莲',
          episode: 1,
          pluginName: 'cycani',
          position: 1200,
          duration: 1440,
          updatedAt: 1712000000000,
          genres: ['奇幻', '冒险', '治愈'],
        ),
        const WatchHistoryItem(
          id: '1::ep2',
          bangumiId: 1,
          title: '葬送的芙莉莲',
          episode: 2,
          pluginName: 'cycani',
          position: 1200,
          duration: 1440,
          updatedAt: 1712000000000,
          genres: ['奇幻', '冒险', '治愈'],
        ),
        const WatchHistoryItem(
          id: '2::ep1',
          bangumiId: 2,
          title: '迷宫饭',
          episode: 1,
          pluginName: 'anime1',
          position: 1200,
          duration: 1440,
          updatedAt: 1712000000000,
          genres: ['奇幻', '美食'],
        ),
      ];

      final report = AnimeAnalyticsService.analyze(history);
      expect(report.isEmpty, isFalse);
      expect(report.totalAnimeCount, equals(2)); // 去重后 2 部番剧
      expect(report.totalEpisodesCount, equals(3)); // 3 集
      expect(report.totalWatchHours, closeTo(1.0, 0.05)); // 3600 秒 = 1.0 小时

      // 题材频次：奇幻 (2部), 冒险 (1部), 治愈 (1部), 美食 (1部)
      expect(report.topGenres.first.genre, equals('奇幻'));
      expect(report.topGenres.first.count, equals(2));

      // 判定称号为异世界冒险者
      expect(report.personaTitle, contains('异界特级冒险者'));
      expect(report.genreAnimeSamples['奇幻'], contains('葬送的芙莉莲'));
      expect(report.genreAnimeSamples['奇幻'], contains('迷宫饭'));
    });

    test('Computes accurate persona for pure romance lovers', () {
      final history = [
        const WatchHistoryItem(
          id: '10::ep1',
          bangumiId: 10,
          title: '辉夜大小姐',
          episode: 1,
          pluginName: 'cycani',
          position: 1440,
          duration: 1440,
          updatedAt: 1712000000000,
          genres: ['恋爱', '搞笑', '校园'],
        ),
      ];

      final report = AnimeAnalyticsService.analyze(history);
      expect(report.personaTitle, contains('纯爱战神'));
    });

    test('Computes accurate persona for healing daily lovers', () {
      final history = [
        const WatchHistoryItem(
          id: '20::ep1',
          bangumiId: 20,
          title: '悠哉日常大王',
          episode: 1,
          pluginName: 'cycani',
          position: 1440,
          duration: 1440,
          updatedAt: 1712000000000,
          genres: ['日常', '治愈'],
        ),
      ];

      final report = AnimeAnalyticsService.analyze(history);
      expect(report.personaTitle, contains('治愈系养老仙人'));
    });
  });

  group('UserActionControlBar & DataAnalysisPage UI tests', () {
    testWidgets('UserActionControlBar displays Data Analysis in 3rd slot and Offline Cache in 4th slot', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: UserActionControlBar(),
          ),
        ),
      );

      // 验证 4 个按钮的存在
      expect(find.text('观看历史'), findsOneWidget);
      expect(find.text('我的追番'), findsOneWidget);
      expect(find.text('数据分析'), findsOneWidget);
      expect(find.text('离线缓存'), findsOneWidget);

      // 验证交流吹水已经被替换
      expect(find.text('交流吹水'), findsNothing);

      // 验证顺序：数据分析在离线缓存左侧
      final analyticsPos = tester.getCenter(find.text('数据分析'));
      final downloadPos = tester.getCenter(find.text('离线缓存'));
      expect(analyticsPos.dx, lessThan(downloadPos.dx));
    });

    testWidgets('DataAnalysisPage renders empty state when no history', (tester) async {
      WatchHistoryService.instance.resetForTest();

      await tester.pumpWidget(
        const MaterialApp(
          home: DataAnalysisPage(),
        ),
      );

      expect(find.text('追番数据分析'), findsOneWidget);
      expect(find.text('尚无播放数据'), findsOneWidget);
    });

    testWidgets('DataAnalysisPage renders Tag Cloud where higher frequency genre has larger font size', (tester) async {
      WatchHistoryService.instance.resetForTest();
      // 写入番剧：奇幻(2部), 冒险(1部)
      await WatchHistoryService.instance.recordProgress(
        const WatchHistoryItem(
          id: '1::ep1',
          bangumiId: 1,
          title: '番剧1',
          episode: 1,
          pluginName: 'cycani',
          position: 100,
          duration: 1440,
          updatedAt: 1000,
          genres: ['奇幻', '冒险'],
        ),
      );
      await WatchHistoryService.instance.recordProgress(
        const WatchHistoryItem(
          id: '2::ep1',
          bangumiId: 2,
          title: '番剧2',
          episode: 1,
          pluginName: 'cycani',
          position: 100,
          duration: 1440,
          updatedAt: 2000,
          genres: ['奇幻'],
        ),
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: DataAnalysisPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('属性标签词云'), findsOneWidget);
      expect(find.text('#奇幻'), findsOneWidget);
      expect(find.text('#冒险'), findsOneWidget);

      final fantasyText = tester.widget<Text>(find.text('#奇幻'));
      final adventureText = tester.widget<Text>(find.text('#冒险'));

      // 验证频次更高的“奇幻”字号严格大于频次较少的“冒险”
      expect(fantasyText.style?.fontSize, greaterThan(adventureText.style?.fontSize ?? 0));
    });
  });
}
