import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/models/bangumi/bangumi_item.dart';
import 'package:zakoway/core/models/bangumi/bangumi_search_result.dart';
import 'package:zakoway/core/network/bangumi_search_query_builder.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/features/search/controllers/search_controller.dart';
import 'package:zakoway/features/search/controllers/search_history_notifier.dart';
import 'package:zakoway/features/search/controllers/search_state.dart';
import 'package:zakoway/features/search/models/search_types.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BangumiSearchQueryBuilder tests', () {
    test('supports multi-type filtering', () {
      final payload = BangumiSearchQueryBuilder.buildPayload(
        keyword: 'EVA',
        types: [2, 6],
      );

      expect(payload, isNotNull);
      final filter = payload!['filter'] as Map<String, dynamic>;
      expect(filter['type'], equals([2, 6]));
      expect(payload['keyword'], equals('EVA'));
    });

    test('supports unconstrained type when type and types are null', () {
      final payload = BangumiSearchQueryBuilder.buildPayload(
        keyword: '高达',
        type: null,
        types: null,
      );

      expect(payload, isNotNull);
      final filter = payload!['filter'] as Map<String, dynamic>;
      expect(filter.containsKey('type'), isFalse);
      expect(payload['keyword'], equals('高达'));
    });

    test('defaults to type 2 for single type compatibility', () {
      final payload = BangumiSearchQueryBuilder.buildPayload(
        keyword: '葬送的芙莉莲',
      );

      expect(payload, isNotNull);
      final filter = payload!['filter'] as Map<String, dynamic>;
      expect(filter['type'], equals([2]));
    });
  });

  group('SearchHistoryNotifier tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppPreferences.init();
    });

    test('addSearch prepends, deduplicates and limits to 15 items', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(searchHistoryProvider.notifier);

      await notifier.addSearch('海贼王');
      await notifier.addSearch('火影忍者');
      await notifier.addSearch('海贼王'); // 重复词置顶

      var history = container.read(searchHistoryProvider);
      expect(history, equals(['海贼王', '火影忍者']));

      // 连续添加超过 15 条
      for (int i = 0; i < 20; i++) {
        await notifier.addSearch('Anime $i');
      }

      history = container.read(searchHistoryProvider);
      expect(history.length, equals(15));
      expect(history.first, equals('Anime 19'));

      // 验证本地持久化
      expect(AppPreferences.getSearchHistory().length, equals(15));
      expect(AppPreferences.getSearchHistory().first, equals('Anime 19'));
    });

    test('removeSearch removes targeted keyword', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(searchHistoryProvider.notifier);
      await notifier.addSearch('词条A');
      await notifier.addSearch('词条B');

      await notifier.removeSearch('词条A');
      expect(container.read(searchHistoryProvider), equals(['词条B']));
      expect(AppPreferences.getSearchHistory(), equals(['词条B']));
    });

    test('clearAll clears all history', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(searchHistoryProvider.notifier);
      await notifier.addSearch('词条1');
      await notifier.addSearch('词条2');

      await notifier.clearAll();
      expect(container.read(searchHistoryProvider), isEmpty);
      expect(AppPreferences.getSearchHistory(), isEmpty);
    });
  });

  group('SearchState filtering and sorting tests', () {
    final itemAnime1 = BangumiItem.fromJson({
      'id': 1,
      'name': 'Anime 1',
      'name_cn': '动漫一',
      'type': 2,
      'date': '2023-10-01',
    });
    final itemAnime2 = BangumiItem.fromJson({
      'id': 2,
      'name': 'Anime 2',
      'name_cn': '动漫二',
      'type': 2,
      'date': '2024-04-01',
    });
    final itemNonAnime = BangumiItem.fromJson({
      'id': 3,
      'name': 'Drama 1',
      'name_cn': '真人特摄',
      'type': 6,
      'date': '2024-01-01',
    });
    final itemUndated = BangumiItem.fromJson({
      'id': 4,
      'name': 'Undated Item',
      'name_cn': '无日期条目',
      'type': 2,
      'date': '',
    });

    test('correctly splits anime and non-anime items and counts', () {
      final state = SearchState(
        allItems: [itemAnime1, itemAnime2, itemNonAnime, itemUndated],
      );

      expect(state.allCount, equals(4));
      expect(state.animeCount, equals(3));
      expect(state.nonAnimeCount, equals(1));
      expect(state.animeItems.map((e) => e.id), equals([1, 2, 4]));
      expect(state.nonAnimeItems.map((e) => e.id), equals([3]));
    });

    test('sorts by latest air date with empty airDate placed last', () {
      final state = SearchState(
        allItems: [itemAnime1, itemAnime2, itemUndated],
        filter: SearchFilterType.anime,
        sort: SearchSortType.dateDesc,
      );

      final sorted = state.filteredAndSortedItems;
      expect(sorted.map((e) => e.id), equals([2, 1, 4]));
    });

    test('sorts by earliest air date with empty airDate placed last', () {
      final state = SearchState(
        allItems: [itemAnime1, itemAnime2, itemUndated],
        filter: SearchFilterType.anime,
        sort: SearchSortType.dateAsc,
      );

      final sorted = state.filteredAndSortedItems;
      expect(sorted.map((e) => e.id), equals([1, 2, 4]));
    });

    test('BangumiSearchResult roundtrips JSON serialization for disk cache', () {
      final original = BangumiSearchResult(
        items: [itemAnime1, itemAnime2, itemNonAnime],
        total: 100,
        limit: 30,
        offset: 0,
      );

      final json = original.toJson();
      final restored = BangumiSearchResult.fromJson(json);

      expect(restored.total, equals(100));
      expect(restored.limit, equals(30));
      expect(restored.offset, equals(0));
      expect(restored.items.length, equals(3));
      expect(restored.items[0].id, equals(1));
      expect(restored.items[0].preferredName, equals('动漫一'));
      expect(restored.items[1].name, equals('Anime 2'));
      expect(restored.items[2].type, equals(6));
    });

    test('searchControllerProvider retains state without auto-disposing when listeners detach', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // 订阅并触发一次状态变更
      final sub = container.listen(searchControllerProvider, (_, next) {});
      container.read(searchControllerProvider.notifier).setFilter(SearchFilterType.nonAnime);
      expect(container.read(searchControllerProvider).filter, equals(SearchFilterType.nonAnime));

      // 取消订阅（模拟 SearchPage 页面关闭/退出）
      sub.close();

      // 验证状态依然持久保留在内存中，未被 autoDispose 重置
      expect(container.read(searchControllerProvider).filter, equals(SearchFilterType.nonAnime));
    });
  });
}
