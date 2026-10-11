import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/core/models/bangumi/bangumi_item.dart';
import 'package:zakoway/core/network/bangumi_client.dart';
import 'package:zakoway/core/services/daily_recommend_service.dart';

class MockDailyClientAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> recordedPayloads = [];
  final List<RequestOptions> recordedOptions = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<dynamic>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    recordedOptions.add(options);
    if (options.data is Map<String, dynamic>) {
      recordedPayloads.add(options.data as Map<String, dynamic>);
    }

    final dataList = List.generate(15, (index) {
      final id = 1000 + index;
      return {
        'id': id,
        'type': 2,
        'name': 'Mock Item $id',
        'name_cn': '模拟动画 $id',
        'summary': '简介 $id',
        'air_date': '2024-01-01',
        'air_weekday': 1,
        'rank': index + 1,
        'rating': {'score': 8.0, 'total': 300},
        'collection': {'doing': 100, 'collect': 200},
        'eps': 12,
        'eps_count': 12,
        'images': {
          'large': 'https://lain.bgm.tv/pic/cover/l/mock_$id.jpg',
        },
      };
    });

    return ResponseBody.fromString(
      '{"total": 100, "data": ${dataList.map((e) => '{"id": ${e['id']}, "type": 2, "name": "${e['name']}", "name_cn": "${e['name_cn']}", "rating": {"score": 8.0, "total": 300}, "images": {"large": "https://lain.bgm.tv/cover.jpg"}}').toList()}}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('DailyRecommendService tests', () {
    test('computeSeed produces deterministic and diversified seeds', () {
      final seedDay1 = DailyRecommendService.computeSeed('dev_123', DateTime(2026, 10, 4));
      final seedDay1Again = DailyRecommendService.computeSeed('dev_123', DateTime(2026, 10, 4));
      final seedDay2 = DailyRecommendService.computeSeed('dev_123', DateTime(2026, 10, 5));
      final seedOtherDevice = DailyRecommendService.computeSeed('dev_456', DateTime(2026, 10, 4));

      // 当天同设备绝对幂等
      expect(seedDay1, equals(seedDay1Again));
      // 跨天种子不同
      expect(seedDay1, isNot(equals(seedDay2)));
      // 不同设备种子不同
      expect(seedDay1, isNot(equals(seedOtherDevice)));
    });

    test('Cold start fetches with tags: [日本]', () async {
      final dio = Dio();
      final adapter = MockDailyClientAdapter();
      dio.httpClientAdapter = adapter;
      final client = BangumiClient(dio: dio);

      final result = await DailyRecommendService.getDailyRecommendations(
        client: client,
        rawUserTagFreq: const {}, // 无数据冷启动
        customDate: DateTime(2026, 10, 4),
        customDeviceId: 'test_dev_cold',
        forceRefresh: true,
      );

      expect(result.length, inInclusiveRange(1, 5));
      expect(adapter.recordedPayloads, isNotEmpty);
      final firstFilter = adapter.recordedPayloads.first['filter'] as Map<String, dynamic>;
      // 验证必须包含“日本”标签
      expect(firstFilter['tag'], contains('日本'));
    });

    test('Personalized recommendation queries with Top 3 tags and 日本', () async {
      final dio = Dio();
      final adapter = MockDailyClientAdapter();
      dio.httpClientAdapter = adapter;
      final client = BangumiClient(dio: dio);

      final rawTags = {
        'TV': 100, // 噪音，应被过滤
        '恋爱': 66, // Top 1
        '悬疑': 22, // Top 2
        '打斗': 15, // Top 3
        '科幻': 8,  // 长尾
      };

      final result = await DailyRecommendService.getDailyRecommendations(
        client: client,
        rawUserTagFreq: rawTags,
        customDate: DateTime(2026, 10, 4),
        customDeviceId: 'test_dev_profile',
        forceRefresh: true,
      );

      expect(result, isNotEmpty);
      // 校验发出的检索请求中，均包含“日本”且包含了 Top 标签
      final queriedTagSets = adapter.recordedPayloads.map((p) {
        final filter = p['filter'] as Map<String, dynamic>;
        return (filter['tag'] as List).cast<String>();
      }).toList();

      for (final tags in queriedTagSets) {
        expect(tags, contains('日本'));
      }

      // 验证 Top 1 标签“恋爱”被正确查询
      final hasLoveTag = queriedTagSets.any((tags) => tags.contains('恋爱'));
      expect(hasLoveTag, isTrue);
    });

    test('Cold start samples across scattered mutual-exclusive genre slots with non-contiguous offsets', () async {
      final dio = Dio();
      final adapter = MockDailyClientAdapter();
      dio.httpClientAdapter = adapter;
      final client = BangumiClient(dio: dio);

      final result = await DailyRecommendService.getDailyRecommendations(
        client: client,
        rawUserTagFreq: const {},
        customDate: DateTime(2026, 10, 4),
        customDeviceId: 'test_dev_scattered',
        forceRefresh: true,
      );

      expect(result, isNotEmpty);
      // 验证发出的请求覆盖了 5 个槽位
      expect(adapter.recordedPayloads.length, equals(5));

      // 提取每个槽位专属的题材标签（排除固定的“日本”）
      final sampledGenres = adapter.recordedPayloads.map((p) {
        final filter = p['filter'] as Map<String, dynamic>;
        final tags = (filter['tag'] as List).cast<String>();
        return tags.firstWhere((t) => t != '日本', orElse: () => '');
      }).toList();

      // 验证 5 个槽位的题材完全互斥，绝无重复
      final uniqueGenres = sampledGenres.toSet();
      expect(uniqueGenres.length, equals(5));

      // 验证各槽位的翻页 offset 大跨度散落，绝对不连号
      final offsets = adapter.recordedOptions
          .map((opt) => opt.queryParameters['offset'] as int)
          .toList();
      for (var i = 0; i < offsets.length - 1; i++) {
        // 相邻槽位的 offset 差值不为 0 且绝对值不为 1 (不连号)
        expect((offsets[i] - offsets[i + 1]).abs(), isNot(equals(1)));
      }
    });

    test('Watched items are strictly deduped and filtered from recommendations', () async {
      final dio = Dio();
      final adapter = MockDailyClientAdapter();
      dio.httpClientAdapter = adapter;
      final client = BangumiClient(dio: dio);

      // 模拟已看过 1000, 1001, 1002
      final watchedIds = {1000, 1001, 1002};

      final result = await DailyRecommendService.getDailyRecommendations(
        client: client,
        rawUserTagFreq: const {},
        watchedSubjectIds: watchedIds,
        customDate: DateTime(2026, 10, 4),
        customDeviceId: 'test_dev_dedup',
        forceRefresh: true,
      );

      expect(result, isNotEmpty);
      // 验证推荐列表绝不包含已看番剧
      for (final rec in result) {
        expect(watchedIds.contains(rec.item.id), isFalse);
      }
    });

    test('resolveDisplayTag generates accurate anime slang tags', () {
      BangumiItem makeItem(List<String> tags) {
        return BangumiItem(
          id: 1,
          type: 2,
          name: 'Item',
          nameCn: '作品',
          summary: '',
          airDate: '',
          airWeekday: 1,
          rank: 1,
          images: const {},
          tags: tags.map((t) => BangumiTag(name: t)).toList(),
          alias: const [],
          ratingScore: 8.6,
          votes: 100,
          eps: 12,
          totalEpisodes: 12,
        );
      }

      // 恋爱 + 治愈 -> #纯爱治愈
      expect(
        DailyRecommendService.resolveDisplayTag('恋爱', makeItem(['治愈', '日本'])),
        equals('#纯爱治愈'),
      );
      // 恋爱 + 搞笑 -> #恋爱喜剧
      expect(
        DailyRecommendService.resolveDisplayTag('恋爱', makeItem(['搞笑', '日本'])),
        equals('#恋爱喜剧'),
      );
      // 打斗 + 热血 -> #战斗爽
      expect(
        DailyRecommendService.resolveDisplayTag('打斗', makeItem(['热血', '超能力'])),
        equals('#战斗爽'),
      );
      // 日常 + 美食 -> #下饭神作
      expect(
        DailyRecommendService.resolveDisplayTag('日常', makeItem(['美食'])),
        equals('#下饭神作'),
      );
      // 奇幻 + 异世界 -> #异界冒险
      expect(
        DailyRecommendService.resolveDisplayTag('奇幻', makeItem(['异世界'])),
        equals('#异界冒险'),
      );
      // 宫廷 + 悬疑 -> #宫廷权谋
      expect(
        DailyRecommendService.resolveDisplayTag('宫廷', makeItem(['悬疑'])),
        equals('#宫廷权谋'),
      );
    });

    test('buildRecommendReason formats accurate four-dimensional templates', () {
      final mockItem = BangumiItem(
        id: 1,
        type: 2,
        name: 'Item',
        nameCn: '作品',
        summary: '',
        airDate: '',
        airWeekday: 1,
        rank: 1,
        images: const {},
        tags: const [],
        alias: const [],
        ratingScore: 8.6,
        votes: 100,
        eps: 12,
        totalEpisodes: 12,
      );

      // 槽位 0 (Top 1 主力)
      expect(
        DailyRecommendService.buildRecommendReason(0, '恋爱', mockItem),
        equals('命中你偏好最高的【恋爱】题材，Bangumi 8.6分'),
      );
      // 槽位 1 (Top 2 次级主力)
      expect(
        DailyRecommendService.buildRecommendReason(1, '悬疑', mockItem),
        equals('兼顾你关注的【悬疑】风向，Bangumi 8.6分'),
      );
      // 槽位 3 (长尾探索)
      expect(
        DailyRecommendService.buildRecommendReason(3, '科幻', mockItem),
        equals('偶尔换换口味：捕捉到你兴趣库中的【科幻】基因，翻出的宝藏作品'),
      );
      // 冷启动
      expect(
        DailyRecommendService.buildRecommendReason(0, null, mockItem),
        equals('今日番剧推荐：Bangumi 8.6分'),
      );
    });
  });
}
