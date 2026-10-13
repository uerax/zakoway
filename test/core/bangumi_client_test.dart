import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/core/constants/app_constants.dart';
import 'package:zakoway/core/models/bangumi/bangumi_collection.dart';
import 'package:zakoway/core/network/bangumi_client.dart';

class MockAdapter implements HttpClientAdapter {
  final Map<String, dynamic> Function(RequestOptions options) handler;

  MockAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final result = handler(options);
    final statusCode = result['statusCode'] as int? ?? 200;
    final data = result['data'];
    final jsonStr = jsonEncode(data);

    return ResponseBody.fromString(
      jsonStr,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('BangumiClient tests with MockAdapter', () {
    late Dio dio;
    late BangumiClient client;

    test('defaultUserAgent matches Bangumi API developer guidelines', () {
      expect(BangumiClient.defaultUserAgent, contains('uerax/zakoway/${AppConstants.appVersion}'));
      expect(BangumiClient.defaultUserAgent, contains('https://github.com/uerax/zakoway'));
      expect(
        BangumiClient.buildUserAgent(version: '2.0.0', platform: 'Android'),
        'uerax/zakoway/2.0.0 (Android) (https://github.com/uerax/zakoway)',
      );
    });

    test('getCalendar parses mock response', () async {
      dio = Dio(BaseOptions(baseUrl: 'https://api.bgm.tv'));
      dio.httpClientAdapter = MockAdapter((options) {
        expect(options.path, '/calendar');
        return {
          'statusCode': 200,
          'data': [
            {
              'weekday': {'id': 1, 'en': 'Mon', 'cn': '星期一', 'ja': '月曜日'},
              'items': [
                {'id': 101, 'name': 'Anime Mon', 'type': 2}
              ]
            }
          ]
        };
      });
      client = BangumiClient(dio: dio);

      final calendar = await client.getCalendar();
      expect(calendar.length, 1);
      expect(calendar.first.weekday.cn, '星期一');
      expect(calendar.first.items.first.name, 'Anime Mon');
    });

    test('getSubject returns parsed BangumiItem', () async {
      dio = Dio(BaseOptions(baseUrl: 'https://api.bgm.tv'));
      dio.httpClientAdapter = MockAdapter((options) {
        expect(options.path, '/v0/subjects/1234');
        return {
          'statusCode': 200,
          'data': {
            'id': 1234,
            'type': 2,
            'name': 'Original Name',
            'name_cn': '中文名',
            'eps': 12,
          }
        };
      });
      client = BangumiClient(dio: dio);

      final subject = await client.getSubject(1234);
      expect(subject.id, 1234);
      expect(subject.nameCn, '中文名');
      expect(subject.eps, 12);
    });

    test('getEpisodes returns list of episodes', () async {
      dio = Dio(BaseOptions(baseUrl: 'https://api.bgm.tv'));
      dio.httpClientAdapter = MockAdapter((options) {
        expect(options.path, '/v0/episodes');
        expect(options.queryParameters['subject_id'], 1234);
        return {
          'statusCode': 200,
          'data': {
            'total': 1,
            'limit': 100,
            'offset': 0,
            'data': [
              {
                'id': 999,
                'sort': 1,
                'name_cn': '第一集',
                'duration': '00:24:00',
              }
            ]
          }
        };
      });
      client = BangumiClient(dio: dio);

      final eps = await client.getEpisodes(1234);
      expect(eps.length, 1);
      expect(eps.first.id, 999);
      expect(eps.first.displayTitle, '第一集');
      expect(eps.first.durationSeconds, 1440);
    });

    test('setCollection sends correct authorization and payload', () async {
      dio = Dio(BaseOptions(baseUrl: 'https://api.bgm.tv'));
      dio.httpClientAdapter = MockAdapter((options) {
        expect(options.path, '/v0/users/-/collections/1234');
        expect(options.headers['Authorization'], 'Bearer mock_token');
        final data = options.data as Map<String, dynamic>;
        expect(data['type'], 3); // watching -> 3
        return {'statusCode': 200, 'data': {}};
      });
      client = BangumiClient(dio: dio);

      final success = await client.setCollection(
        1234,
        CollectType.watching,
        'mock_token',
      );
      expect(success, true);
    });

    test('searchWithTotal sends filter/sort payload and returns total & items', () async {
      dio = Dio(BaseOptions(baseUrl: 'https://api.bgm.tv'));
      dio.httpClientAdapter = MockAdapter((options) {
        expect(options.path, '/v0/search/subjects');
        expect(options.queryParameters['limit'], 24);
        expect(options.queryParameters['offset'], 0);
        final payload = options.data as Map<String, dynamic>;
        expect(payload['sort'], 'heat');
        final filter = payload['filter'] as Map<String, dynamic>;
        expect(filter['type'], [2]);
        expect(filter['tag'], ['热血']);
        expect(filter['air_date'], ['>=2024-04-01', '<2024-07-01']);
        return {
          'statusCode': 200,
          'data': {
            'total': 42,
            'limit': 24,
            'offset': 0,
            'data': [
              {
                'id': 1001,
                'name': 'Hot Anime',
                'name_cn': '热血动画',
                'air_date': '2024-04-05',
              }
            ]
          }
        };
      });
      client = BangumiClient(dio: dio);

      final res = await client.searchWithTotal(
        '',
        tags: ['热血'],
        airDate: ['>=2024-04-01', '<2024-07-01'],
        sort: 'heat',
        limit: 24,
        offset: 0,
      );

      expect(res.total, 42);
      expect(res.hasMore, true);
      expect(res.items.length, 1);
      expect(res.items.first.id, 1001);
      expect(res.items.first.nameCn, '热血动画');
    });

    test('searchWithTotal smartly branches rank filter for historical vs current season', () async {
      final requestedFilters = <Map<String, dynamic>>[];
      dio = Dio(BaseOptions(baseUrl: 'https://api.bgm.tv'));
      dio.httpClientAdapter = MockAdapter((options) {
        final payload = options.data as Map<String, dynamic>;
        requestedFilters.add(Map<String, dynamic>.from(payload['filter'] as Map<String, dynamic>));
        return {
          'statusCode': 200,
          'data': {'total': 10, 'limit': 24, 'offset': 0, 'data': []}
        };
      });
      client = BangumiClient(dio: dio);

      // 1. 历史年份 (如 2020) 按 score 排序：统一注入 rank > 0 与 rating_count >= 50 过滤
      await client.searchWithTotal('', year: 2020, sort: 'score');
      expect(requestedFilters.first.containsKey('rank'), true);
      expect(requestedFilters.first['rank'], ['>0', '<=99999']);
      expect(requestedFilters.first['rating_count'], ['>=50']);

      // 2. 当前当季新番按 score 排序：同样统一注入 rank > 0 与 rating_count >= 50 过滤，保障榜单质量
      await client.searchWithTotal(
        '',
        year: DateTime.now().year,
        airDate: ['>=${DateTime.now().year}-10-01', '<${DateTime.now().year + 1}-01-01'],
        sort: 'score',
      );
      expect(requestedFilters.last.containsKey('rank'), true);
      expect(requestedFilters.last['rank'], ['>0', '<=99999']);
      expect(requestedFilters.last['rating_count'], ['>=50']);
    });

    test('searchWithTotal caches query response and avoids redundant network requests', () async {
      int requestCount = 0;
      dio = Dio(BaseOptions(baseUrl: 'https://api.bgm.tv'));
      dio.httpClientAdapter = MockAdapter((options) {
        requestCount++;
        return {
          'statusCode': 200,
          'data': {
            'total': 1,
            'limit': 20,
            'offset': 0,
            'data': [
              {
                'id': 2001,
                'type': 2,
                'name': 'Cached Anime',
                'name_cn': '缓存动画',
              }
            ]
          }
        };
      });
      client = BangumiClient(dio: dio);

      // 首次请求：应触发网络调用
      final first = await client.searchWithTotal('', tags: ['科幻'], sort: 'heat');
      expect(requestCount, 1);
      expect(first.items.first.nameCn, '缓存动画');

      // 同一参数再次请求：应直接命中内存缓存，requestCount 依然为 1
      final second = await client.searchWithTotal('', tags: ['科幻'], sort: 'heat');
      expect(requestCount, 1);
      expect(second.items.first.nameCn, '缓存动画');

      // 同步探测 peekSearchCache：无需异步等待即可瞬间拿到缓存
      final peeked = client.peekSearchCache('', tags: ['科幻'], sort: 'heat');
      expect(peeked, isNotNull);
      expect(peeked!.items.first.id, 2001);

      // forceRefresh = true 时强刷穿透缓存：requestCount 增加到 2
      final forced = await client.searchWithTotal('', tags: ['科幻'], sort: 'heat', forceRefresh: true);
      expect(requestCount, 2);
      expect(forced.items.first.id, 2001);
    });

    test('getCalendar single-flight deduplicates concurrent requests', () async {
      int requestCount = 0;
      dio = Dio(BaseOptions(baseUrl: 'https://api.bgm.tv'));
      dio.httpClientAdapter = MockAdapter((options) {
        requestCount++;
        return {
          'statusCode': 200,
          'data': [
            {
              'weekday': {'id': 1, 'en': 'Mon', 'cn': '星期一', 'ja': '月曜日'},
              'items': [
                {'id': 101, 'name': 'Anime Mon', 'type': 2}
              ]
            }
          ]
        };
      });
      client = BangumiClient(dio: dio);

      // 并发触发 3 次请求
      final results = await Future.wait([
        client.getCalendar(forceRefresh: true),
        client.getCalendar(forceRefresh: true),
        client.getCalendar(forceRefresh: true),
      ]);

      // Single-Flight 机制确保仅发生 1 次网络 I/O
      expect(requestCount, 1);
      expect(results.length, 3);
      expect(results[0].first.items.first.id, 101);
      expect(results[1].first.items.first.id, 101);
      expect(results[2].first.items.first.id, 101);
    });

    test('getTrending single-flight deduplicates concurrent requests', () async {
      int requestCount = 0;
      dio = Dio(BaseOptions(baseUrl: 'https://api.bgm.tv'));
      dio.httpClientAdapter = MockAdapter((options) {
        requestCount++;
        return {
          'statusCode': 200,
          'data': {
            'data': [
              {
                'id': 3001,
                'type': 2,
                'name': 'Trending 1',
                'name_cn': '热门 1',
              }
            ]
          }
        };
      });
      client = BangumiClient(dio: dio);

      final results = await Future.wait([
        client.getTrending(limit: 18, forceRefresh: true),
        client.getTrending(limit: 18, forceRefresh: true),
        client.getTrending(limit: 18, forceRefresh: true),
      ]);

      expect(requestCount, 1);
      expect(results.length, 3);
      expect(results[0].first.id, 3001);
    });

    test('getHotMovies and getHotOva reuse search cache seamlessly', () async {
      int requestCount = 0;
      dio = Dio(BaseOptions(baseUrl: 'https://api.bgm.tv'));
      dio.httpClientAdapter = MockAdapter((options) {
        requestCount++;
        return {
          'statusCode': 200,
          'data': {
            'total': 1,
            'limit': 18,
            'offset': 0,
            'data': [
              {
                'id': 4001,
                'type': 2,
                'name': 'Movie Anime',
                'name_cn': '剧场版动画',
              }
            ]
          }
        };
      });
      client = BangumiClient(dio: dio);

      // 1. 首页请求热门剧场版
      final movies = await client.getHotMovies(limit: 18);
      expect(requestCount, 1);
      expect(movies.first.nameCn, '剧场版动画');

      // 2. 分类页面以相同筛选查询剧场版，应 0ms 命中同一份 search 缓存，不发网络请求
      final categoryPeek = client.peekSearchCache('', tags: ['剧场版'], sort: 'heat', limit: 18, offset: 0);
      expect(categoryPeek, isNotNull);
      expect(categoryPeek!.items.first.id, 4001);

      final categoryResult = await client.searchWithTotal('', tags: ['剧场版'], sort: 'heat', limit: 18, offset: 0);
      expect(requestCount, 1);
      expect(categoryResult.items.first.id, 4001);
    });

    test('getCollection and getUserCollections support memory cache, single-flight, and setCollection invalidation', () async {
      int getCollectionCount = 0;
      int getUserCollectionsCount = 0;
      int setCollectionCount = 0;

      dio = Dio(BaseOptions(baseUrl: 'https://api.bgm.tv'));
      dio.httpClientAdapter = MockAdapter((options) {
        final path = options.path;
        if (options.method == 'GET' && path.contains('/v0/users/-/collections/100')) {
          getCollectionCount++;
          return {
            'statusCode': 200,
            'data': {
              'subject_id': 100,
              'type': 3, // watching
              'rate': 8,
            }
          };
        } else if (options.method == 'GET' && path.contains('/v0/users/testuser/collections')) {
          getUserCollectionsCount++;
          return {
            'statusCode': 200,
            'data': {
              'total': 1,
              'data': [
                {
                  'subject_id': 100,
                  'type': 3,
                }
              ]
            }
          };
        } else if (options.method == 'POST' && path.contains('/v0/users/-/collections/')) {
          setCollectionCount++;
          return {
            'statusCode': 200,
            'data': {'success': true}
          };
        }
        return {'statusCode': 404, 'data': {}};
      });
      client = BangumiClient(dio: dio);

      // 1. getCollection 首次请求走网络
      final col1 = await client.getCollection(100, 'mock_token');
      expect(getCollectionCount, 1);
      expect(col1?.type, CollectType.watching);

      // 2. getCollection 二次请求命中缓存，零网络请求
      final col2 = await client.getCollection(100, 'mock_token');
      expect(getCollectionCount, 1);
      expect(col2?.type, CollectType.watching);

      // 3. getUserCollections 首次请求走网络
      final list1 = await client.getUserCollections('testuser', token: 'mock_token');
      expect(getUserCollectionsCount, 1);
      expect(list1.length, 1);

      // 4. getUserCollections 二次请求命中缓存
      final list2 = await client.getUserCollections('testuser', token: 'mock_token');
      expect(getUserCollectionsCount, 1);
      expect(list2.length, 1);

      // 5. setCollection 触发后，单项缓存与列表缓存自动失效
      final updated = await client.setCollection(100, CollectType.watched, 'mock_token');
      expect(updated, isTrue);
      expect(setCollectionCount, 1);

      // 6. 再次请求时重新打网络，拿到最新数据
      await client.getCollection(100, 'mock_token');
      expect(getCollectionCount, 2);

      await client.getUserCollections('testuser', token: 'mock_token');
      expect(getUserCollectionsCount, 2);
    });
  });
}
