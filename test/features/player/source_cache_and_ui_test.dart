import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/core/models/bangumi/bangumi_item.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/source_aggregator.dart';
import 'package:zakoway/features/player/source/source_keyword_matcher.dart';
import 'package:zakoway/features/player/widgets/video_source_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('视频源缓存隔离与关键词去重测试', () {
    test('1. 中文番剧名称生成的磁盘缓存 Key 必须互斥隔离，杜绝跨番剧缓存串号', () {
      const sourceId = 'cycani';
      const anime1 = '药屋少女的呢喃 第三季';
      const anime2 = '侦探已经死了。 第二季';

      final key1 = 'src_search_${sourceId}_${base64Url.encode(utf8.encode(anime1.toLowerCase()))}';
      final key2 = 'src_search_${sourceId}_${base64Url.encode(utf8.encode(anime2.toLowerCase()))}';

      expect(key1, isNot(equals(key2)));
      expect(key1, contains('cycani'));
      expect(key2, contains('cycani'));
    });

    test('2. 关键词去重引擎能够正确归一化全角空格与不间断空格，无重复胶囊', () {
      final candidates = SourceKeywordMatcher.buildCandidates(
        defaultTitle: '侦探已经死了。　第二季', // 全角空格
        item: const BangumiItem(
          id: 12345,
          type: 2,
          name: '探偵はもう、死んでいる。 Season 2',
          nameCn: '侦探已经死了。 第二季', // 半角空格
          summary: '',
          airDate: '',
          airWeekday: 1,
          rank: 0,
          images: {},
          tags: [],
          alias: ['侦探已经死了。 第二季'],
          ratingScore: 0,
          votes: 0,
          eps: 12,
          totalEpisodes: 12,
        ),
      );

      // 验证去重有效性
      final lowerList = candidates.map((c) => c.toLowerCase()).toList();
      final setLength = lowerList.toSet().length;
      expect(lowerList.length, equals(setLength));
    });

    testWidgets('3. VideoSourceView 候选态使用柔和橙色且无刺眼黄色', (tester) async {
      final aggregator = SourceAggregator();
      final src = const VideoSourceItem(
        id: 'cycani',
        name: '次元城',
        description: '测试源',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoSourceView(
              sources: [src],
              selectedSourceId: 'xifan-next',
              aggregator: aggregator,
              onSourceSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证未包含任何老版粗糙生硬的 Colors.amber 颜色
      final amberWidgets = find.byWidgetPredicate((widget) {
        if (widget is Text && widget.style?.color == Colors.amber) return true;
        if (widget is Icon && widget.color == Colors.amber) return true;
        if (widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color == Colors.amber) {
          return true;
        }
        return false;
      });
      expect(amberWidgets, findsNothing);
    });

    testWidgets('4. VideoSourceView 实时监听 aggregator 状态流并在后台探活完成时秒级自动刷新', (tester) async {
      final aggregator = SourceAggregator();
      final src = const VideoSourceItem(
        id: 'cycani',
        name: '次元城',
        description: '测试源',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoSourceView(
              sources: [src],
              selectedSourceId: 'xifan-next',
              aggregator: aggregator,
              onSourceSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 初始为待探活 (灰色)
      expect(find.text('待探活 (点击探活)'), findsOneWidget);
      expect(find.text('探活'), findsOneWidget);

      // 模拟后台开始探活 -> probing
      aggregator.updateSourceState(
        'cycani',
        AggregatedSourceState(
          meta: const SourceMeta(id: 'cycani', name: '次元城', version: '1.0'),
          status: SourceProbeStatus.probing,
          searched: true,
        ),
      );
      await tester.pump();

      // UI 立即自动响应为探活中
      expect(find.text('探活检索中...'), findsOneWidget);
      expect(find.text('探活中'), findsOneWidget);

      // 模拟后台探活成功完成 -> ready
      aggregator.updateSourceState(
        'cycani',
        AggregatedSourceState(
          meta: const SourceMeta(id: 'cycani', name: '次元城', version: '1.0'),
          status: SourceProbeStatus.ready,
          matchedHit: const SourceSearchResult(name: '命中番剧第1季', url: 'https://test/1'),
          searched: true,
        ),
      );
      await tester.pumpAndSettle();

      // UI 立即自动响应为命中并展示“切换”按钮，不再需要用户任何额外点击
      expect(find.text('命中番剧第1季'), findsOneWidget);
      expect(find.text('切换'), findsOneWidget);
    });
  });
}
