import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/models/history/watch_history_item.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/core/services/watch_history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.init();
    WatchHistoryService.instance.resetForTest();
  });

  group('WatchHistoryItem & WatchHistoryService tests', () {
    test('WatchHistoryItem serialization and helper getters', () {
      final item = WatchHistoryItem(
        id: '400650::ep14',
        bangumiId: 400650,
        title: '葬送的芙莉莲',
        cover: 'https://lain.bgm.tv/pic/cover/l/d8/d5/400650_6Zz66.jpg',
        episode: 14,
        road: 1,
        pluginName: 'cycani',
        pageUrl: 'https://cycani.org/watch/400650/14',
        position: 1035.0, // 17:15
        duration: 1440.0, // 24:00
        updatedAt: 1712000000000,
        genres: const ['奇幻', '冒险', '治愈'],
      );

      expect(item.progress, closeTo(0.718, 0.01));
      expect(item.positionText, equals('17:15 / 24:00'));
      expect(item.pluginName, equals('cycani'));
      expect(item.road, equals(1));
      expect(item.genres, equals(['奇幻', '冒险', '治愈']));

      final json = item.toJson();
      final parsed = WatchHistoryItem.fromJson(json);

      expect(parsed.id, equals(item.id));
      expect(parsed.bangumiId, equals(400650));
      expect(parsed.title, equals('葬送的芙莉莲'));
      expect(parsed.episode, equals(14));
      expect(parsed.pluginName, equals('cycani'));
      expect(parsed.road, equals(1));
      expect(parsed.position, equals(1035.0));
      expect(parsed.duration, equals(1440.0));
      expect(parsed.genres, equals(['奇幻', '冒险', '治愈']));
    });

    test('getHistory returns empty list on empty cache without injecting mock seeds', () async {
      final history = await WatchHistoryService.instance.getHistory();

      expect(history, isEmpty);
      // 验证未持久化任何种子假数据
      final persistedJson = AppPreferences.getWatchHistoryJson();
      expect(persistedJson, isNull);
    });

    test('recordProgress accurately preserves different episodes and dedupes same episode, latestByAnime aggregates correctly', () async {
      await WatchHistoryService.instance.saveHistory(WatchHistoryService.initialMockSeeds); // 显式置入 3 条测试数据 (芙莉莲 ep14, 迷宫饭 ep8, 间谍过家家 ep4)

      var notified = false;
      void listener() {
        notified = true;
      }
      WatchHistoryService.instance.addListener(listener);

      // 1. 播放芙莉莲第 15 话 (新集数)：此时芙莉莲 ep14 与 ep15 应同时保存在底层历史中，共 4 条
      final ep15Progress = WatchHistoryItem(
        id: WatchHistoryItem.buildId(400650, 15),
        bangumiId: 400650,
        title: '葬送的芙莉莲',
        episode: 15,
        pluginName: 'cycani',
        road: 1,
        position: 1200.0, // 20:00
        duration: 1440.0,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await WatchHistoryService.instance.recordProgress(ep15Progress);
      final updated = await WatchHistoryService.instance.getHistory();

      expect(notified, isTrue);
      // 底层历史总数变为 4 (芙莉莲 ep15 与 ep14 并存，多集进度不丢失)
      expect(updated.length, equals(4));
      // 最新记录排在第一位，且集数为 15
      expect(updated.first.bangumiId, equals(400650));
      expect(updated.first.episode, equals(15));
      expect(updated.first.position, equals(1200.0));

      // 验证首页聚合属性 latestByAnime：每部番剧仅保留最新一条 (共 3 部番剧)
      final latest = WatchHistoryService.instance.latestByAnime;
      expect(latest.length, equals(3));
      expect(latest.first.bangumiId, equals(400650));
      expect(latest.first.episode, equals(15)); // 取到最新的第 15 话

      // 2. 重新播放同一番剧的同一集 (芙莉莲 ep15 进度更新到 22:00)
      final ep15Updated = WatchHistoryItem(
        id: WatchHistoryItem.buildId(400650, 15),
        bangumiId: 400650,
        title: '葬送的芙莉莲',
        episode: 15,
        pluginName: 'cycani',
        road: 1,
        position: 1320.0, // 22:00
        duration: 1440.0,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await WatchHistoryService.instance.recordProgress(ep15Updated);
      final reUpdated = await WatchHistoryService.instance.getHistory();
      // 同集数覆盖更新，总数依然为 4
      expect(reUpdated.length, equals(4));
      expect(reUpdated.first.position, equals(1320.0));

      // 3. 测试按番剧全量删除
      await WatchHistoryService.instance.removeByBangumi(400650);
      final afterRemoveBangumi = await WatchHistoryService.instance.getHistory();
      // 芙莉莲全部集数被清除，剩余 2 部番剧
      expect(afterRemoveBangumi.length, equals(2));
      expect(afterRemoveBangumi.any((i) => i.bangumiId == 400650), isFalse);

      WatchHistoryService.instance.removeListener(listener);
    });

    test('groupWatchHistory and computeHistoryStats algorithms work correctly', () {
      final now = DateTime(2026, 10, 4, 15, 30);
      final items = [
        WatchHistoryItem(
          id: '1::ep1',
          bangumiId: 1,
          title: '今天番剧',
          episode: 1,
          pluginName: 'cycani',
          position: 1400.0,
          duration: 1440.0, // 已看完
          updatedAt: DateTime(2026, 10, 4, 14, 0).millisecondsSinceEpoch,
        ),
        WatchHistoryItem(
          id: '2::ep2',
          bangumiId: 2,
          title: '昨天番剧',
          episode: 2,
          pluginName: 'anime1',
          position: 720.0,
          duration: 1440.0,
          updatedAt: DateTime(2026, 10, 3, 20, 0).millisecondsSinceEpoch,
        ),
        WatchHistoryItem(
          id: '3::ep3',
          bangumiId: 3,
          title: '近7天番剧',
          episode: 3,
          pluginName: 'omofun',
          position: 300.0,
          duration: 1440.0,
          updatedAt: DateTime(2026, 10, 1, 10, 0).millisecondsSinceEpoch,
        ),
      ];

      final groups = groupWatchHistory(items, now);
      expect(groups.length, equals(3));
      expect(groups[0].label, equals('今天'));
      expect(groups[0].items.first.title, equals('今天番剧'));
      expect(groups[1].label, equals('昨天'));
      expect(groups[2].label, equals('近 7 天'));

      final stats = computeHistoryStats(items, now);
      expect(stats.totalCount, equals(3));
      expect(stats.todayCount, equals(1));
      expect(stats.finishedCount, equals(1));
      expect(stats.totalWatchHours, closeTo(0.67, 0.05));
    });

    test('userGenreFrequencies aggregates distinct genres by anime', () async {
      final service = WatchHistoryService.instance;
      // 记录同一番剧的不同集数与不同番剧
      await service.recordProgress(
        const WatchHistoryItem(
          id: '100::ep1',
          bangumiId: 100,
          title: '番剧A 第1集',
          episode: 1,
          pluginName: 'cycani',
          position: 100,
          duration: 1440,
          updatedAt: 1000,
          genres: ['奇幻', '冒险'],
        ),
      );
      await service.recordProgress(
        const WatchHistoryItem(
          id: '100::ep2',
          bangumiId: 100,
          title: '番剧A 第2集',
          episode: 2,
          pluginName: 'cycani',
          position: 100,
          duration: 1440,
          updatedAt: 2000,
          genres: ['奇幻', '冒险'],
        ),
      );
      await service.recordProgress(
        const WatchHistoryItem(
          id: '200::ep1',
          bangumiId: 200,
          title: '番剧B',
          episode: 1,
          pluginName: 'cycani',
          position: 100,
          duration: 1440,
          updatedAt: 3000,
          genres: ['奇幻', '日常'],
        ),
      );

      final freqs = service.userGenreFrequencies;
      // 番剧A (按番去重算 1 次) + 番剧B (算 1 次) -> 奇幻: 2, 冒险: 1, 日常: 1
      expect(freqs['奇幻'], equals(2));
      expect(freqs['冒险'], equals(1));
      expect(freqs['日常'], equals(1));
    });

    test('remove and clear methods work as expected and notify listeners', () async {
      await WatchHistoryService.instance.saveHistory(WatchHistoryService.initialMockSeeds);
      final history = await WatchHistoryService.instance.getHistory();
      expect(history.length, equals(3));

      var removeNotified = false;
      WatchHistoryService.instance.addListener(() => removeNotified = true);

      await WatchHistoryService.instance.remove(history.first.id);
      final afterRemove = await WatchHistoryService.instance.getHistory();
      expect(afterRemove.length, equals(2));
      expect(removeNotified, isTrue);

      var clearNotified = false;
      WatchHistoryService.instance.addListener(() => clearNotified = true);

      await WatchHistoryService.instance.clear();
      expect(AppPreferences.getWatchHistoryJson(), isNull);
      expect(WatchHistoryService.instance.items, isEmpty);
      expect(clearNotified, isTrue);

      // 验证清空后再次 forceReload，依然保持为空列表，不会复活种子数据
      final reloadHistory = await WatchHistoryService.instance.getHistory(forceReload: true);
      expect(reloadHistory, isEmpty);
    });
  });
}
