import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/core/models/bangumi/bangumi_calendar.dart';
import 'package:zakoway/core/models/bangumi/bangumi_item.dart';
import 'package:zakoway/core/models/home/recommend_item.dart';
import 'package:zakoway/core/network/bangumi_client.dart';
import 'package:zakoway/core/services/watch_history_service.dart';
import 'package:zakoway/features/home/pages/home_page.dart';
import 'package:zakoway/features/home/widgets/continue_watching_shelf.dart';
import 'package:zakoway/features/home/widgets/daily_spotlight_card.dart';
import 'package:zakoway/features/home/widgets/home_desktop_hero.dart';
import 'package:zakoway/features/home/widgets/today_anime_shelf.dart';

BangumiItem _createMockItem(int id, String name, double score) {
  return BangumiItem(
    id: id,
    type: 2,
    name: name,
    nameCn: '$name 中文',
    summary: '简介 $name',
    airDate: '2026-04-01',
    airWeekday: 1,
    rank: 1,
    images: {
      'large': 'https://lain.bgm.tv/pic/cover/l/mock_$id.jpg',
    },
    tags: const [],
    alias: const [],
    ratingScore: score,
    votes: 500,
    eps: 12,
    totalEpisodes: 12,
  );
}

void main() {
  group('RecommendItem model & rule engine tests', () {
    test('generateRecommendations creates sorted recommendations with explainability', () {
      final items = [
        _createMockItem(1, 'Item One', 7.5),
        _createMockItem(2, 'Item Two', 9.2),
        _createMockItem(3, 'Item Three', 8.4),
      ];

      final recs = RecommendItem.generateRecommendations(items);
      expect(recs.length, equals(3));
      // 高分优先
      expect(recs.first.item.id, equals(2));
      expect(recs.first.item.ratingScore, equals(9.2));
      expect(recs.first.matchRate, inInclusiveRange(85, 99));
      expect(recs.first.reason, isNotEmpty);
      expect(recs.first.tag, isNotEmpty);
    });

    test('generateRecommendations handles empty source gracefully', () {
      final recs = RecommendItem.generateRecommendations([]);
      expect(recs, isEmpty);
    });
  });

  group('ContinueWatchingShelf widget tests', () {
    testWidgets('Empty records renders SizedBox.shrink with 0 dimensions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ContinueWatchingShelf(records: []),
          ),
        ),
      );

      expect(find.text('继续追番'), findsNothing);
      expect(find.byType(ContinueWatchingShelf), findsOneWidget);
    });

    testWidgets('Non-empty records renders cards with progress information', (tester) async {
      final mockRecord = WatchProgressItem(
        item: _createMockItem(10, 'Frieren', 9.4),
        episodeNumber: 8,
        progress: 0.72,
        positionText: '18:23 / 24:00',
        lastWatchTime: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContinueWatchingShelf(
              records: [mockRecord],
            ),
          ),
        ),
      );

      expect(find.text('继续追番'), findsOneWidget);
      expect(find.text('Frieren 中文'), findsOneWidget);
      expect(find.textContaining('第 8 话'), findsOneWidget);
      expect(find.textContaining('72%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('Extremely narrow width (279.5dp) does not throw RenderFlex overflow', (tester) async {
      final records = [
        WatchProgressItem(
          item: _createMockItem(10, 'Frieren', 9.4),
          episodeNumber: 8,
          progress: 0.72,
          positionText: '18:23 / 24:00',
          lastWatchTime: DateTime.now(),
        ),
        WatchProgressItem(
          item: _createMockItem(11, 'DunMeshi', 9.0),
          episodeNumber: 5,
          progress: 0.50,
          positionText: '12:00 / 24:00',
          lastWatchTime: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 279.5, // 模拟引发 8.5px 溢出的极窄边界宽度
                child: ContinueWatchingShelf(records: records),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('继续追番'), findsOneWidget);
      expect(find.text('Frieren 中文'), findsOneWidget);
      expect(find.text('DunMeshi 中文'), findsOneWidget);
    });

    testWidgets('Ultra narrow width (180dp) for ContinueWatchingShelf adapts to 1 column without overflow', (tester) async {
      final records = [
        WatchProgressItem(
          item: _createMockItem(10, 'Frieren', 9.4),
          episodeNumber: 8,
          progress: 0.72,
          positionText: '18:23 / 24:00',
          lastWatchTime: DateTime.now(),
        ),
        WatchProgressItem(
          item: _createMockItem(11, 'DunMeshi', 9.0),
          episodeNumber: 5,
          progress: 0.50,
          positionText: '12:00 / 24:00',
          lastWatchTime: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180.0, // 极限窄窗宽度
                child: ContinueWatchingShelf(
                  records: records,
                  onViewAllHistory: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('继续追番'), findsOneWidget);
      expect(find.text('Frieren 中文'), findsOneWidget);
      // 超窄视口下自适应单卡片展示，第二部自动收拢
      expect(find.text('DunMeshi 中文'), findsNothing);
    });

    testWidgets('Wide screen (1440dp) caps card width to 280dp and does not stretch infinitely', (tester) async {
      final records = [
        WatchProgressItem(
          item: _createMockItem(10, 'Frieren', 9.4),
          episodeNumber: 8,
          progress: 0.72,
          positionText: '18:23 / 24:00',
          lastWatchTime: DateTime.now(),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1440.0,
              child: ContinueWatchingShelf(records: records),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // 获取卡片容器尺寸
      final cardFinder = find.ancestor(
        of: find.text('Frieren 中文'),
        matching: find.byType(SizedBox),
      ).first;
      final size = tester.getSize(cardFinder);
      expect(size.width, lessThanOrEqualTo(280.0));
      expect(size.height, equals(68.0));
    });
  });

  group('DailySpotlightCard widget tests', () {
    testWidgets('Renders recommendation details and supports switching', (tester) async {
      final recs = [
        RecommendItem(
          item: _createMockItem(101, 'Cowboy Bebop', 9.1),
          reason: '渡边信一郎硬核太空浪漫神作',
          tag: '口碑神作',
          matchRate: 98,
        ),
        RecommendItem(
          item: _createMockItem(102, 'Dungeon Meshi', 8.8),
          reason: '极高水准奇幻生态冒险剧',
          tag: '当季精选',
          matchRate: 95,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DailySpotlightCard(recommendations: recs),
          ),
        ),
      );

      // 第一部展示
      expect(find.text('每日推荐'), findsOneWidget);
      expect(find.text('98% 契合'), findsOneWidget);
      expect(find.text('口碑神作'), findsOneWidget);
      expect(find.text('Cowboy Bebop 中文'), findsOneWidget);
      expect(find.textContaining('渡边信一郎硬核太空浪漫神作'), findsOneWidget);

      // 点击“换一部”
      await tester.tap(find.text('换一部'));
      await tester.pumpAndSettle();

      // 切换至第二部
      expect(find.text('95% 契合'), findsOneWidget);
      expect(find.text('当季精选'), findsOneWidget);
      expect(find.text('Dungeon Meshi 中文'), findsOneWidget);
      expect(find.textContaining('极高水准奇幻生态冒险剧'), findsOneWidget);
    });

    testWidgets('Narrow width with long tag does not throw RenderFlex overflow', (tester) async {
      final recs = [
        RecommendItem(
          item: _createMockItem(103, 'Steins;Gate', 9.2),
          reason: '极高水准科幻悬疑神作',
          tag: '#硬核烧脑',
          matchRate: 98,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 301.0, // 对应右侧 143.0px 极限可用宽度的窄屏
                child: DailySpotlightCard(recommendations: recs),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('98% 契合'), findsOneWidget);
      expect(find.text('#硬核烧脑'), findsOneWidget);
    });

    testWidgets('Ultra narrow width (180dp) for DailySpotlightCard does not throw RenderFlex overflow', (tester) async {
      final recs = [
        RecommendItem(
          item: _createMockItem(103, 'Steins;Gate', 9.2),
          reason: '极高水准科幻悬疑神作',
          tag: '#硬核烧脑',
          matchRate: 98,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180.0, // 极限窄窗宽度
                child: DailySpotlightCard(recommendations: recs),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('每日推荐'), findsOneWidget);
      expect(find.text('换一部'), findsNothing); // 单部时无换一部
    });

    testWidgets('Multiple recommendations in ultra narrow width (180dp) displays 换一部 without overflow', (tester) async {
      final recs = [
        RecommendItem(
          item: _createMockItem(103, 'Steins;Gate', 9.2),
          reason: '极高水准科幻悬疑神作',
          tag: '#硬核烧脑',
          matchRate: 98,
        ),
        RecommendItem(
          item: _createMockItem(104, 'Clannad', 9.0),
          reason: 'KEY 社人生哲理神作',
          tag: '#治愈催泪',
          matchRate: 95,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 180.0,
                child: DailySpotlightCard(recommendations: recs),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('每日推荐'), findsOneWidget);
      expect(find.text('换一部'), findsOneWidget);
      // isNarrow (<280) 下“算法精选”自动收起，优先保全操作按钮且不溢出
      expect(find.text('算法精选'), findsNothing);
    });

    testWidgets('Normal width (400dp) aligns 换一部 to the far right', (tester) async {
      final recs = [
        RecommendItem(
          item: _createMockItem(101, 'Cowboy Bebop', 9.1),
          reason: '太空牛仔',
          tag: '口碑神作',
          matchRate: 98,
        ),
        RecommendItem(
          item: _createMockItem(102, 'Dungeon Meshi', 8.8),
          reason: '迷宫饭',
          tag: '当季精选',
          matchRate: 95,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400.0,
                child: DailySpotlightCard(recommendations: recs),
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('算法精选'), findsOneWidget);
      expect(find.text('换一部'), findsOneWidget);

      // 验证“换一部”按钮右边缘与父容器（400 - 16 = 384）最右侧贴齐，不再悬浮在中间
      final buttonFinder = find.ancestor(
        of: find.text('换一部'),
        matching: find.byType(Material),
      ).first;
      final buttonRect = tester.getRect(buttonFinder);
      // 父容器从 Center 出来在 (0, 0) 开始，宽度 400，padding left=16, right=16，内容可用右边界为 400 - 16 = 384
      // 允许 1px 浮点排版误差
      final cardRect = tester.getRect(find.byType(DailySpotlightCard));
      expect(buttonRect.right, closeTo(cardRect.right - 16.0, 1.0));
    });
  });

  group('TodayAnimeShelf single-character week strip tests', () {
    testWidgets('Renders all 7 single characters without overflow on compact 360dp screen', (tester) async {
      // 设置为极窄 360dp 手机屏幕
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockCalendarDays = List.generate(7, (i) {
        final dayId = i + 1;
        return BangumiCalendarDay(
          weekday: BangumiWeekday(id: dayId, en: '', cn: '周$dayId', ja: ''),
          items: [_createMockItem(200 + dayId, 'Anime $dayId', 8.0)],
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: TodayAnimeShelf(
                calendarDays: mockCalendarDays,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证 7 个单字均在屏幕中正常呈现
      for (final char in ['一', '二', '三', '四', '五', '六', '日']) {
        expect(find.text(char), findsOneWidget);
      }

      // 验证点击“五”能正常响应并触发选中
      await tester.tap(find.text('五'));
      await tester.pumpAndSettle();
      expect(find.textContaining('周五'), findsOneWidget);
    });
  });

  group('HomeDesktopHero desktop week strip tests', () {
    testWidgets('Renders segmented week strip and switches days on desktop width', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final mockCalendarDays = List.generate(7, (i) {
        final dayId = i + 1;
        return BangumiCalendarDay(
          weekday: BangumiWeekday(id: dayId, en: '', cn: '周$dayId', ja: ''),
          items: [_createMockItem(300 + dayId, 'Desktop Anime $dayId', 8.5)],
        );
      });

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomeDesktopHero(
              calendarDays: mockCalendarDays,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final char in ['一', '二', '三', '四', '五', '六', '日']) {
        expect(find.text(char), findsOneWidget);
      }

      // 点击“六”能正常响应并切换标题显示
      await tester.tap(find.text('六'));
      await tester.pumpAndSettle();
      expect(find.textContaining('周六'), findsOneWidget);
    });
  });

  group('HomePage responsive ContinueWatchingShelf placement tests', () {
    testWidgets('Mobile (<840dp): ContinueWatchingShelf is above TodayAnimeShelf', (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await WatchHistoryService.instance.saveHistory(WatchHistoryService.initialMockSeeds);

      final dio = Dio();
      dio.httpClientAdapter = _MockPlacementClientAdapter();
      final client = BangumiClient(dio: dio);

      await tester.pumpWidget(MaterialApp(home: HomePage(client: client)));
      await tester.pumpAndSettle();

      final continueWatchingY = tester.getTopLeft(find.byType(ContinueWatchingShelf)).dy;
      final todayShelfY = tester.getTopLeft(find.byType(TodayAnimeShelf)).dy;
      expect(continueWatchingY, lessThan(todayShelfY));
    });

    testWidgets('Desktop (>=840dp): ContinueWatchingShelf is below HomeDesktopHero', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await WatchHistoryService.instance.saveHistory(WatchHistoryService.initialMockSeeds);

      final dio = Dio();
      dio.httpClientAdapter = _MockPlacementClientAdapter();
      final client = BangumiClient(dio: dio);

      await tester.pumpWidget(MaterialApp(home: HomePage(client: client)));
      await tester.pumpAndSettle();

      final heroY = tester.getTopLeft(find.byType(HomeDesktopHero)).dy;
      final continueWatchingY = tester.getTopLeft(find.byType(ContinueWatchingShelf)).dy;
      expect(heroY, lessThan(continueWatchingY));
    });
  });
}

class _MockPlacementClientAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final now = DateTime.now();
    final todayWeekday = now.weekday;

    if (options.path.contains('calendar')) {
      final days = List.generate(7, (i) {
        final dayIndex = i + 1;
        return {
          'weekday': {'id': dayIndex, 'en': 'Day $dayIndex', 'cn': '星期$dayIndex', 'ja': ''},
          'items': dayIndex == todayWeekday
              ? [
                  {
                    'id': 1001,
                    'type': 2,
                    'name': 'Today Mock',
                    'name_cn': '今日番剧',
                    'summary': '简介',
                    'air_date': '2026-04-01',
                    'air_weekday': dayIndex,
                    'rank': 1,
                    'rating': {'score': 9.0, 'total': 100},
                    'collection': {'doing': 100, 'collect': 200},
                    'eps': 12,
                    'eps_count': 12,
                    'images': {'large': '', 'common': ''},
                  }
                ]
              : [],
        };
      });
      return ResponseBody.fromString(
        jsonEncode(days),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }

    return ResponseBody.fromString(
      jsonEncode({
        'data': [
          {
            'id': 2001,
            'type': 2,
            'name': 'TV Mock',
            'name_cn': '热门 TV',
            'summary': '简介',
            'air_date': '2026-04-01',
            'air_weekday': 1,
            'rank': 1,
            'rating': {'score': 8.5, 'total': 100},
            'collection': {'doing': 100, 'collect': 200},
            'eps': 12,
            'eps_count': 12,
            'images': {'large': '', 'common': ''},
          }
        ]
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
