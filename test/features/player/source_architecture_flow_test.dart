import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/models/bangumi/bangumi_episode.dart';
import 'package:zakoway/core/models/bangumi/bangumi_item.dart';
import 'package:zakoway/features/player/source/auto_source_pick_coordinator.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/services/plugin_circuit_breaker.dart';
import 'package:zakoway/features/player/source/services/source_binding_service.dart';
import 'package:zakoway/features/player/source/source_aggregator.dart';
import 'package:zakoway/features/player/source/source_bundle_manager.dart';
import 'package:zakoway/features/player/source/source_keyword_matcher.dart';
import 'package:zakoway/features/player/source/sources/video_source.dart';
import 'package:zakoway/features/player/source/utils/chinese_s2t_converter.dart';
import 'package:zakoway/features/player/source/utils/playable_slot_engine.dart';

BangumiItem _createItem({
  required int id,
  required String name,
  required String nameCn,
  List<String> alias = const [],
}) {
  return BangumiItem(
    id: id,
    type: 2,
    name: name,
    nameCn: nameCn,
    summary: '简介',
    airDate: '2024-01-01',
    airWeekday: 1,
    rank: 1,
    images: const {},
    tags: const [],
    alias: alias,
    ratingScore: 8.5,
    votes: 1000,
    eps: 12,
    totalEpisodes: 12,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. 繁简转换测试 (ChineseS2TConverter)', () {
    test('将简体中文精确转换为繁体中文', () {
      expect(ChineseS2TConverter.convert('葬送的芙莉莲'), '葬送的芙莉蓮');
      expect(ChineseS2TConverter.convert('间谍过家家 第二季'), '間諜過家家 第二季');
      expect(ChineseS2TConverter.convert('进击的巨人 最终季'), '進擊的巨人 最終季');
      expect(ChineseS2TConverter.convert('命运石之门'), '命運石之門');
    });

    test('为繁体源生成关键词变体 (keywordVariantsZh)', () {
      final variants = ChineseS2TConverter.keywordVariantsZh('葬送的芙莉莲 第二季');
      expect(variants, contains('葬送的芙莉蓮 第二季'));
      expect(variants, contains('葬送的芙莉莲 第二季'));
      expect(variants, contains('葬送的芙莉蓮'));
    });
  });

  group('2. 关键词与打分引擎测试 (SourceKeywordMatcher)', () {
    final item = _createItem(
      id: 364450,
      name: 'チェンソー曼',
      nameCn: '电锯人',
      alias: ['Chainsaw Man', '电锯英雄'],
    );

    test('源语言偏好解析 (resolveDefaultKeyword)', () {
      // 日语原名优先源
      expect(
        SourceKeywordMatcher.resolveDefaultKeyword(
          defaultTitle: '电锯人',
          item: item,
          sourceId: 'xifan-next',
        ),
        'チェンソー曼',
      );

      // 中文标准源
      expect(
        SourceKeywordMatcher.resolveDefaultKeyword(
          defaultTitle: '电锯人',
          item: item,
          sourceId: 'cycani',
        ),
        '电锯人',
      );

      // 繁体源
      expect(
        SourceKeywordMatcher.resolveDefaultKeyword(
          defaultTitle: '电锯人',
          item: item,
          sourceId: 'anime1',
        ),
        '電鋸人',
      );

      // 中文紧凑源 (mifun)
      final multiSeasonItem = _createItem(
        id: 123,
        name: 'Grand Blue',
        nameCn: '碧蓝之海 第二季',
      );
      expect(
        SourceKeywordMatcher.resolveDefaultKeyword(
          defaultTitle: '碧蓝之海 第二季',
          item: multiSeasonItem,
          sourceId: 'mifun',
        ),
        '碧蓝之海第二季',
      );
    });

    test('多层级候选词生成与特殊符号/副标题剥离 (buildCandidates)', () {
      final candidates = SourceKeywordMatcher.buildCandidates(
        defaultTitle: 'Re：从零开始的异世界生活 第四季 夺还篇',
        item: _createItem(
          id: 456,
          name: 'Re:ゼロから始める異世界生活 4th season',
          nameCn: 'Re：从零开始的异世界生活 第四季 夺还篇',
          alias: ['从零开始的异世界生活 第4季'],
        ),
      );

      expect(candidates, contains('Re：从零开始的异世界生活 第四季 夺还篇'));
      expect(candidates, contains('Re：从零开始的异世界生活 第四季'));
      expect(candidates, contains('Re：从零开始的异世界生活'));
    });

    test('继续追番同名实体 (name == nameCn) buildCandidates 严禁触发 RangeError 越界崩溃', () {
      // 模拟继续追番卡片生成的实体 (WatchHistoryItem.toBangumiItem): name 与 nameCn 均为 title
      final historyItem = _createItem(
        id: 400650,
        name: '葬送的芙莉莲',
        nameCn: '葬送的芙莉莲',
      );

      final candidates = SourceKeywordMatcher.buildCandidates(
        defaultTitle: '葬送的芙莉莲',
        item: historyItem,
        sourceId: 'xifan-next', // 偏好 original 的源
      );

      expect(candidates, isNotEmpty);
      expect(candidates.first, '葬送的芙莉莲');
    });

    test('季数提取 (extractSeason) 覆盖中文数字、罗马数字与阿拉伯数字', () {
      expect(SourceKeywordMatcher.extractSeason('间谍过家家 第二季'), 2);
      expect(SourceKeywordMatcher.extractSeason('关于我转生成为史莱姆的那档事 第3期'), 3);
      expect(SourceKeywordMatcher.extractSeason('进击的巨人 Season 4'), 4);
      expect(SourceKeywordMatcher.extractSeason('王者天下 Ⅳ'), 4);
      expect(SourceKeywordMatcher.extractSeason('机动战士高达 Ⅱ'), 2);
      expect(SourceKeywordMatcher.extractSeason('电锯人'), isNull);
    });

    test('Season Guard 季数防线打分算法验证', () {
      // 1. 硬季数冲突 (S4 vs S2) -> 强制 0.15 分，杜绝自动误选
      final conflictScore = SourceKeywordMatcher.calculateSimilarity(
        'Re:从零开始的异世界生活 第四季',
        'Re:从零开始的异世界生活 第二季',
      );
      expect(conflictScore, 0.15);

      // 2. 修饰词不匹配 (S4 vs S1 裸主名) -> 钳制在 0.45 分以下 (低于 0.55 auto-pick 门槛)
      final mismatchScore = SourceKeywordMatcher.calculateSimilarity(
        'Re:从零开始的异世界生活 第四季',
        'Re:从零开始的异世界生活',
      );
      expect(mismatchScore, lessThanOrEqualTo(0.45));

      // 3. 完全相同或高度吻合
      final matchScore = SourceKeywordMatcher.calculateSimilarity(
        '葬送的芙莉莲',
        '葬送的芙莉莲 1080P',
      );
      expect(matchScore, greaterThanOrEqualTo(0.85));
    });

    test('搜索命中排序 (rankSearchHits)', () {
      final hits = [
        const SourceSearchResult(name: '间谍过家家 第一季', url: 'https://test/1'),
        const SourceSearchResult(name: '间谍过家家 第三季', url: 'https://test/3'),
        const SourceSearchResult(name: '间谍过家家 第二季', url: 'https://test/2'),
      ];

      final ranked = SourceKeywordMatcher.rankSearchHits(hits, ['间谍过家家 第二季']);
      expect(ranked.first.name, '间谍过家家 第二季');
    });
  });

  group('3. 持久化源绑定服务测试 (SourceBindingService)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('设置绑定、读取绑定与 LRU 淘汰机制', () async {
      final service = SourceBindingService.instance;
      await service.initialize();
      await service.clear();

      final success = await service.setBinding(
        bangumiId: 1001,
        sourceId: 'xifan-next',
        sourceUrl: 'https://xifan/detail/1001',
        title: '葬送的芙莉莲',
        similarity: 0.95,
      );
      expect(success, isTrue);

      final binding = service.getBinding(1001, 'xifan-next');
      expect(binding, isNotNull);
      expect(binding!.sourceUrl, 'https://xifan/detail/1001');
      expect(binding.title, '葬送的芙莉莲');

      await service.removeBinding(1001, 'xifan-next');
      expect(service.getBinding(1001, 'xifan-next'), isNull);
    });
  });

  group('4. 集数双层对齐引擎测试 (PlayableSlotEngine)', () {
    test('Layer 1 权威位置对齐：过滤 PV/预告 并 1:1 映射 Bangumi 正片 (抗《86》等剧名带数字干扰)', () {
      final sourceEps = [
        const SourceEpisode(name: 'PV1 预告篇', url: 'https://test/pv1'),
        const SourceEpisode(name: '86 -不存在的战区- 第1话 战区', url: 'https://test/ep1'),
        const SourceEpisode(name: '86 -不存在的战区- 第2话 觉醒', url: 'https://test/ep2'),
        const SourceEpisode(name: '特别篇 花絮', url: 'https://test/sp'),
        const SourceEpisode(name: '86 -不存在的战区- 第3话 羁绊', url: 'https://test/ep3'),
      ];

      final officialEps = [
        const BangumiEpisode(id: 1, type: 0, sort: 1, name: '戦線', nameCn: '战区', airdate: '2021-04-10'),
        const BangumiEpisode(id: 2, type: 0, sort: 2, name: '覚醒', nameCn: '觉醒', airdate: '2021-04-17'),
        const BangumiEpisode(id: 3, type: 0, sort: 3, name: '絆', nameCn: '羁绊', airdate: '2021-04-24'),
      ];

      final slots = PlayableSlotEngine.buildPlayableSlots(
        episodes: sourceEps,
        officialEpisodes: officialEps,
      );

      expect(slots.length, 3);
      expect(slots[0].canonicalEp, 1);
      expect(slots[0].displayTitle, '第 01 话 战区');
      expect(slots[0].sourceIndex, 1); // 自动跳过了 PV1 (index: 0)
      expect(slots[0].isLayer2, isFalse);

      expect(slots[1].canonicalEp, 2);
      expect(slots[1].sourceIndex, 2);

      expect(slots[2].canonicalEp, 3);
      expect(slots[2].sourceIndex, 4); // 自动跳过了特别篇 (index: 3)
    });

    test('Layer 2 保守模式：支持 0 集/序章 识别与保守回退', () {
      final sourceEps = [
        const SourceEpisode(name: '第00话 序章 PROLOGUE', url: 'https://test/ep0'),
        const SourceEpisode(name: '第01话 起始之日', url: 'https://test/ep1'),
        const SourceEpisode(name: '第02话 旅途', url: 'https://test/ep2'),
      ];

      final slots = PlayableSlotEngine.buildPlayableSlots(
        episodes: sourceEps,
        officialEpisodes: null, // 无官方数据
      );

      expect(slots.length, 3);
      expect(slots[0].canonicalEp, 0);
      expect(slots[0].displayTitle, '第 00 话');
      expect(slots[0].isLayer2, isTrue);

      expect(slots[1].canonicalEp, 1);
      expect(slots[1].displayTitle, '第 01 话');
    });
  });

  group('5. 单飞故障熔断器测试 (PluginCircuitBreaker)', () {
    test('软超时 2 次触发 90s 冷却，硬故障单次触发冷却', () {
      final breaker = PluginCircuitBreaker.instance;
      breaker.reset('test_source');

      expect(breaker.checkBeforeRequest('test_source').allowed, isTrue);

      // 第一次软超时 -> 不熔断
      breaker.recordFailure('test_source', '504 Gateway Timeout');
      expect(breaker.checkBeforeRequest('test_source').allowed, isTrue);

      // 第二次软超时 -> 触发 90s 熔断冷却
      breaker.recordFailure('test_source', 'Request timed out');
      final res = breaker.checkBeforeRequest('test_source');
      expect(res.allowed, isFalse);
      expect(res.reason, contains('熔断冷却中'));

      // 成功请求 -> 恢复正常
      breaker.recordSuccess('test_source');
      expect(breaker.checkBeforeRequest('test_source').allowed, isTrue);

      // 硬故障 -> 单次直接熔断
      breaker.recordFailure('test_source', 'SocketException: Connection refused');
      expect(breaker.checkBeforeRequest('test_source').allowed, isFalse);
      breaker.reset('test_source');
    });
  });

  group('6. 自适应宽限自动选源仲裁器测试 (AutoSourcePickCoordinator)', () {
    test('0ms 秒提决议：当最高优先级源就绪时直接 immediate 起播', () {
      final sources = {
        'xifan-next': AggregatedSourceState(
          meta: const SourceMeta(id: 'xifan-next', name: '稀饭Next', version: '1.0'),
          status: SourceProbeStatus.ready,
          matchedHit: const SourceSearchResult(name: '电锯人', url: 'url1'),
        ),
        'cycani': const AggregatedSourceState(
          meta: SourceMeta(id: 'cycani', name: '次元城', version: '1.0'),
          status: SourceProbeStatus.idle,
        ),
      };

      final decision = AutoSourcePickCoordinator.resolveDecision(
        sources: sources,
        inFlightSources: ['cycani'],
        sourceOrder: ['xifan-next', 'cycani'],
      );

      expect(decision.action, AutoPickAction.immediate);
      expect(decision.candidate?.meta.id, 'xifan-next');
    });

    test('方案 A 极速起播决议：当低优先级源先就绪时，直接 immediate 采纳起播', () {
      final sources = {
        'xifan-next': const AggregatedSourceState(
          meta: SourceMeta(id: 'xifan-next', name: '稀饭Next', version: '1.0'),
          status: SourceProbeStatus.probing,
        ),
        'cycani': AggregatedSourceState(
          meta: const SourceMeta(id: 'cycani', name: '次元城', version: '1.0'),
          status: SourceProbeStatus.ready,
          matchedHit: const SourceSearchResult(name: '电锯人', url: 'url2'),
        ),
      };

      final decision = AutoSourcePickCoordinator.resolveDecision(
        sources: sources,
        inFlightSources: ['xifan-next'], // 高优源在 flight
        sourceOrder: ['xifan-next', 'cycani'],
      );

      expect(decision.action, AutoPickAction.immediate);
      expect(decision.candidate?.meta.id, 'cycani');
    });

    test('自适应宽限决议：当开启 waitHigherPriority 时，低优先级源先就绪进入 waitGrace', () {
      final sources = {
        'xifan-next': const AggregatedSourceState(
          meta: SourceMeta(id: 'xifan-next', name: '稀饭Next', version: '1.0'),
          status: SourceProbeStatus.probing,
        ),
        'cycani': AggregatedSourceState(
          meta: const SourceMeta(id: 'cycani', name: '次元城', version: '1.0'),
          status: SourceProbeStatus.ready,
          matchedHit: const SourceSearchResult(name: '电锯人', url: 'url2'),
        ),
      };

      final decision = AutoSourcePickCoordinator.resolveDecision(
        sources: sources,
        inFlightSources: ['xifan-next'], // 高优源在 flight
        sourceOrder: ['xifan-next', 'cycani'],
        waitHigherPriority: true,
      );

      expect(decision.action, AutoPickAction.waitGrace);
      expect(decision.candidate?.meta.id, 'cycani');
      expect(decision.higherPriorityInFlight, contains('xifan-next'));
    });
  });

  group('7. 针对用户反馈的三大优化点测试', () {
    test('优化点 2: AggregatedSourceState 缓存有效分集 roads，确保假绿灯被杜绝', () {
      const meta = SourceMeta(id: 'test', name: '测试源', version: '1.0');
      const testHit = SourceSearchResult(name: '葬送的芙莉莲', url: 'https://test/1');
      final validRoads = [
        const SourceChapterRoad(
          name: '主线路',
          episodes: [
            SourceEpisode(name: '第 1 话', url: 'https://test/ep1'),
            SourceEpisode(name: '第 2 话', url: 'https://test/ep2'),
          ],
        )
      ];

      // 真正绿灯状态携带 validatedRoads
      final readyState = AggregatedSourceState(
        meta: meta,
        status: SourceProbeStatus.ready,
        matchedHit: testHit,
        roads: validRoads,
      );

      expect(readyState.status, SourceProbeStatus.ready);
      expect(readyState.roads, isNotEmpty);
      expect(readyState.roads.first.episodes.length, 2);
    });

    test('优化点 3: 选集卡片名换成对应映射到的 Bangumi 集数 (cardLabel)', () {
      final sourceEps = [
        const SourceEpisode(name: '预告PV', url: 'https://test/pv'),
        const SourceEpisode(name: '超清 01.mp4', url: 'https://test/ep1'),
        const SourceEpisode(name: '高清-02-国语', url: 'https://test/ep2'),
      ];

      final officialEps = [
        const BangumiEpisode(id: 1, type: 0, sort: 1, name: 'EP1', nameCn: '冒险开始', airdate: '2023-10-01'),
        const BangumiEpisode(id: 2, type: 0, sort: 2, name: 'EP2', nameCn: '旅途之中', airdate: '2023-10-08'),
      ];

      final slots = PlayableSlotEngine.buildPlayableSlots(
        episodes: sourceEps,
        officialEpisodes: officialEps,
      );

      expect(slots.length, 2);
      // 卡片名必须完全脱离源站杂乱名称 "超清 01.mp4"，严格显示映射到的 Bangumi 集数
      expect(slots[0].cardLabel, '第 01 话');
      expect(slots[0].canonicalEp, 1);

      expect(slots[1].cardLabel, '第 02 话');
      expect(slots[1].canonicalEp, 2);
    });
  });

  group('8. 探活超时熔断与并发死锁解除测试', () {
    test('模拟底层网络卡死挂起时，5秒准时触发熔断，状态置为 error 并释放并发槽位', () async {
      SourceBundleManager.instance.runtime.registerSource(_HangingMockSource());
      final aggregator = SourceAggregator();
      aggregator.syncAndProbe(
        bangumiId: 1001,
        defaultTitle: '测试番剧',
        isOpen: true,
      );

      aggregator.prioritizeSource('hanging-mock');
      expect(aggregator.activeJobsCount, greaterThan(0));
      expect(aggregator.states['hanging-mock']?.status, equals(SourceProbeStatus.probing));

      // 等待 5.3 秒超过 5s 探活超时阈值
      await Future.delayed(const Duration(milliseconds: 5300));

      expect(aggregator.states['hanging-mock']?.status, equals(SourceProbeStatus.error));
      expect(aggregator.states['hanging-mock']?.errorMsg, contains('超时'));

      aggregator.dispose();
    }, timeout: const Timeout(Duration(seconds: 12)));
  });
}

class _HangingMockSource extends VideoSource {
  @override
  String get id => 'hanging-mock';
  @override
  String get name => '卡死挂起源';
  @override
  String get version => '1.0';
  @override
  String get description => '测试超时挂起源';

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    // 模拟底层网络请求无限挂起，永不返回
    await Completer<void>().future;
    return [];
  }

  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async => [];

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async =>
      const SourceResolveResult(url: '');
}
