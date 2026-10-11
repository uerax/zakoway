import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/collection/models/anime_collection_item.dart';
import 'package:zakoway/core/collection/services/anime_collection_service.dart';
import 'package:zakoway/core/models/bangumi/bangumi_collection.dart';
import 'package:zakoway/core/models/bangumi/bangumi_item.dart';
import 'package:zakoway/core/services/app_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.init();
    AnimeCollectionService.instance.allItems.clear();
  });

  group('AnimeCollectionItem Model Tests', () {
    test('JSON serialization & deserialization roundtrip', () {
      final now = DateTime.now();
      final item = AnimeCollectionItem(
        subjectId: 1001,
        type: CollectType.watching,
        title: '葬送的芙莉莲',
        originalName: 'Sousou no Frieren',
        coverUrl: 'https://example.com/cover.jpg',
        score: 8.9,
        rank: 1,
        totalEpisodes: 28,
        tags: const ['奇幻', '冒险', '治愈'],
        updatedAt: now,
        myRating: 9,
        myComment: '作画顶级',
      );

      final json = item.toJson();
      final fromJson = AnimeCollectionItem.fromJson(json);

      expect(fromJson.subjectId, equals(1001));
      expect(fromJson.type, equals(CollectType.watching));
      expect(fromJson.title, equals('葬送的芙莉莲'));
      expect(fromJson.originalName, equals('Sousou no Frieren'));
      expect(fromJson.score, equals(8.9));
      expect(fromJson.tags, containsAll(['奇幻', '冒险', '治愈']));
      expect(fromJson.myRating, equals(9));
      expect(fromJson.myComment, equals('作画顶级'));
    });

    test('toBangumiItem maps fields correctly', () {
      final item = AnimeCollectionItem(
        subjectId: 2002,
        type: CollectType.planToWatch,
        title: '败犬女主太多了！',
        originalName: 'Makeine',
        coverUrl: 'https://example.com/makeine.jpg',
        score: 8.4,
        rank: 15,
        totalEpisodes: 12,
        tags: const ['青春', '恋爱', '校园'],
        updatedAt: DateTime.now(),
      );

      final bangumi = item.toBangumiItem();
      expect(bangumi.id, equals(2002));
      expect(bangumi.nameCn, equals('败犬女主太多了！'));
      expect(bangumi.name, equals('Makeine'));
      expect(bangumi.coverUrl, equals('https://example.com/makeine.jpg'));
      expect(bangumi.ratingScore, equals(8.4));
      expect(bangumi.eps, equals(12));
      expect(bangumi.tags.map((t) => t.name), contains('青春'));
    });
  });

  group('AnimeCollectionService Tests', () {
    test('CRUD and type filtering', () async {
      final service = AnimeCollectionService.instance;

      const mockBangumi = BangumiItem(
        id: 3003,
        type: 2,
        name: 'Dungeon Meshi',
        nameCn: '迷宫饭',
        summary: '美食与冒险',
        airDate: '2024-01-04',
        airWeekday: 4,
        rank: 8,
        images: {'large': 'https://example.com/dungeon.jpg'},
        tags: [BangumiTag(name: '奇幻'), BangumiTag(name: '美食')],
        alias: [],
        ratingScore: 8.5,
        votes: 1000,
        eps: 24,
        totalEpisodes: 24,
      );

      // 1. 添加为「在看」
      await service.updateStatusFromBangumiItem(
        bangumiItem: mockBangumi,
        type: CollectType.watching,
      );

      expect(service.getCollectionType(3003), equals(CollectType.watching));
      expect(service.totalCount, equals(1));
      expect(service.getItemsByType(CollectType.watching).length, equals(1));
      expect(service.getItemsByType(CollectType.planToWatch), isEmpty);

      // 2. 统计数量
      final stats = service.getCountStats();
      expect(stats[CollectType.watching], equals(1));
      expect(stats[CollectType.planToWatch], equals(0));

      // 3. 修改为「看过」
      await service.updateStatusFromBangumiItem(
        bangumiItem: mockBangumi,
        type: CollectType.watched,
      );

      expect(service.getCollectionType(3003), equals(CollectType.watched));
      expect(service.getItemsByType(CollectType.watching), isEmpty);
      expect(service.getItemsByType(CollectType.watched).length, equals(1));

      // 4. 移除（或设为 none）
      await service.removeItem(3003);
      expect(service.getCollectionType(3003), equals(CollectType.none));
      expect(service.totalCount, equals(0));
    });

    test('Remote merge conflict resolution: newer updatedAt wins', () async {
      final service = AnimeCollectionService.instance;

      final localItem = AnimeCollectionItem(
        subjectId: 5005,
        type: CollectType.planToWatch,
        title: '孤独摇滚！',
        updatedAt: DateTime(2026, 1, 1),
      );
      await service.setItem(localItem);

      // 远端拉取的数据时间较新 (2026-06-01)，状态为「看过」
      final newerRemote = AnimeCollectionItem(
        subjectId: 5005,
        type: CollectType.watched,
        title: '孤独摇滚！',
        updatedAt: DateTime(2026, 6, 1),
      );

      final merged = await service.mergeRemoteItems([newerRemote]);
      expect(merged, equals(1));
      expect(service.getCollectionType(5005), equals(CollectType.watched));

      // 远端拉取的数据时间较旧 (2025-01-01)，不应覆盖本地较新的「看过」
      final olderRemote = AnimeCollectionItem(
        subjectId: 5005,
        type: CollectType.planToWatch,
        title: '孤独摇滚！',
        updatedAt: DateTime(2025, 1, 1),
      );

      final mergedOlder = await service.mergeRemoteItems([olderRemote]);
      expect(mergedOlder, equals(0));
      expect(service.getCollectionType(5005), equals(CollectType.watched));
    });
  });
}
