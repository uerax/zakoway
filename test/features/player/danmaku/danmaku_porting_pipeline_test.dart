import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';

void main() {
  group('DanmakuEpisodeMatcher 智能集数匹配测试', () {
    final sampleEpisodes = [
      const DanmakuEpisodeItem(episodeId: 101, episodeTitle: '00 PROLOGUE'),
      const DanmakuEpisodeItem(episodeId: 102, episodeTitle: '第01话 启动'),
      const DanmakuEpisodeItem(episodeId: 103, episodeTitle: 'EP02 进击'),
      const DanmakuEpisodeItem(episodeId: 104, episodeTitle: '3 终章'),
    ];

    test('解析标题中的数字 (支持 00 话、第01话、EP02 等)', () {
      expect(DanmakuEpisodeMatcher.parseEpisodeNumber('00 PROLOGUE'), equals(0));
      expect(DanmakuEpisodeMatcher.parseEpisodeNumber('第01话 启动'), equals(1));
      expect(DanmakuEpisodeMatcher.parseEpisodeNumber('EP02 进击'), equals(2));
      expect(DanmakuEpisodeMatcher.parseEpisodeNumber('第 12 集'), equals(12));
    });

    test('匹配 0 话与对应集数', () {
      final ep0 = DanmakuEpisodeMatcher.matchEpisode(sampleEpisodes, 0);
      expect(ep0?.episodeId, equals(101));

      final ep1 = DanmakuEpisodeMatcher.matchEpisode(sampleEpisodes, 1);
      expect(ep1?.episodeId, equals(102));

      final ep2 = DanmakuEpisodeMatcher.matchEpisode(sampleEpisodes, 2);
      expect(ep2?.episodeId, equals(103));
    });

    test('越界与非正规序号回退为合理条目', () {
      final fallback = DanmakuEpisodeMatcher.matchEpisode(sampleEpisodes, 99);
      expect(fallback?.episodeId, equals(101));
    });
  });

  group('BilibiliInputParser 语法与链接解析测试', () {
    test('解析标准 BV 视频与分P参数', () {
      final target = BilibiliInputParser.parse('https://www.bilibili.com/video/BV1TT4y1g77n?p=3');
      expect(target, isNotNull);
      expect(target?.type, equals(BilibiliTargetType.bv));
      expect(target?.bvid, equals('BV1TT4y1g77n'));
      expect(target?.page, equals(3));
    });

    test('解析番剧单集 ep 与季度 ss', () {
      final epTarget = BilibiliInputParser.parse('https://www.bilibili.com/bangumi/play/ep86012');
      expect(epTarget, isNotNull);
      expect(epTarget?.type, equals(BilibiliTargetType.ep));
      expect(epTarget?.epId, equals(86012));

      final ssTarget = BilibiliInputParser.parse('ss28277');
      expect(ssTarget, isNotNull);
      expect(ssTarget?.type, equals(BilibiliTargetType.ss));
      expect(ssTarget?.seasonId, equals(28277));
    });

    test('解析 b23.tv 短链与纯 BV', () {
      final b23 = BilibiliInputParser.parse('https://b23.tv/BV1xx?page=2');
      expect(b23, isNotNull);
      expect(b23?.type, equals(BilibiliTargetType.b23));
      expect(b23?.page, equals(2));
    });
  });

  group('BangumiBilibiliMappingService 跨站番剧关联测试', () {
    test('根据 Bangumi ID 查询预置跨站 B 站映射', () async {
      final service = BangumiBilibiliMappingService.instance;
      // 37258: 铁人28号 -> 1950
      final targetId1 = await service.getBilibiliTargetId(37258);
      expect(targetId1, equals('1950'));

      // 未知 ID 返回 null
      final unknown = await service.getBilibiliTargetId(999999999);
      expect(unknown, isNull);
    });
  });

  group('BilibiliXmlParser XML 弹幕解析测试', () {
    const sampleXml = '''
<?xml version="1.0" encoding="UTF-8"?>
<i>
  <chatserver>chat.bilibili.com</chatserver>
  <d p="12.5,1,25,16777215,1600000000,0,d41d8cd9,1">前方高能 &lt;预警&gt;</d>
  <d p="15.0,4,25,16711680,1600000001,0,hash123,2">底部弹幕字幕 &#x54c8;&#x54c8;</d>
  <d p="18.2,5,25,65280,1600000002,0,hash456,3">顶部高能提示</d>
</i>
''';

    test('正确解析 XML 标签、属性与实体字符', () {
      final comments = BilibiliXmlParser.parse(sampleXml);
      expect(comments.length, equals(3));

      // 滚动弹幕
      expect(comments[0].text, equals('前方高能 <预警>'));
      expect(comments[0].timeMs, equals(12500));
      expect(comments[0].mode, equals(DanmakuMode.scroll));
      expect(comments[0].senderHash, equals('d41d8cd9'));

      // 底部弹幕
      expect(comments[1].text, equals('底部弹幕字幕 哈哈'));
      expect(comments[1].timeMs, equals(15000));
      expect(comments[1].mode, equals(DanmakuMode.bottom));

      // 顶部弹幕
      expect(comments[2].text, equals('顶部高能提示'));
      expect(comments[2].timeMs, equals(18200));
      expect(comments[2].mode, equals(DanmakuMode.top));
    });

    test('正确解压与解析 B 站 Raw Deflate (RFC 1951) 压缩弹幕流', () {
      final rawDeflateBytes = ZLibEncoder(raw: true).convert(utf8.encode(sampleXml));
      final decompressedXml = utf8.decode(ZLibDecoder(raw: true).convert(rawDeflateBytes));
      final comments = BilibiliXmlParser.parse(decompressedXml);
      expect(comments.length, equals(3));
      expect(comments[0].text, equals('前方高能 <预警>'));
    });
  });

  group('DanmakuPoolsManager 多源池与增量交叉去重测试', () {
    test('多源增量去重 (指纹与 ±2.5s 滑动窗口匹配)', () {
      final base = [
        DanmakuItem(text: '前方高能', timeMs: 10000, senderHash: 'userA'),
        DanmakuItem(text: '名场面打卡', timeMs: 12000),
      ];

      final extra = [
        // 规则 1 命中: 相同 senderHash + 相同归一化内容
        DanmakuItem(text: '前方高能！', timeMs: 10000, senderHash: 'userA'),
        // 规则 2 命中: 内容相同且在 ±2500ms 窗口内 (12000 - 11000 = 1000ms <= 2500ms)
        DanmakuItem(text: '名场面打卡', timeMs: 11000),
        // 增量有效弹幕
        DanmakuItem(text: 'B站专属弹幕哈哈', timeMs: 15000),
      ];

      final result = DanmakuPoolsManager.deduplicateDanmakuIncremental(
        base,
        extra,
        windowSeconds: 2.5,
      );

      expect(result.duplicatesCount, equals(2));
      expect(result.incremental.length, equals(1));
      expect(result.incremental.first.text, equals('B站专属弹幕哈哈'));
    });

    test('多源池时移与聚合合并', () {
      final mgr = DanmakuPoolsManager();

      mgr.writePool(
        DanmakuPoolId.dandan,
        [DanmakuItem(text: '弹弹A', timeMs: 1000)],
        replace: true,
      );

      mgr.writePool(
        DanmakuPoolId.bilibiliAuto,
        [DanmakuItem(text: 'B站B', timeMs: 2000)],
        replace: true,
      );

      // 设置 B 站独立时移 +500ms
      mgr.setPoolOffset(DanmakuPoolId.bilibiliAuto, 500);

      // 设置全局时移 +1000ms
      mgr.globalTimeOffsetMs = 1000;

      final flattened = mgr.flattenEnabledPools();
      expect(flattened.length, equals(2));

      // 弹弹A: 1000 + 1000(global) = 2000ms
      expect(flattened[0].text, equals('弹弹A'));
      expect(flattened[0].timeMs, equals(2000));

      // B站B: 2000 + 500(pool) + 1000(global) = 3500ms
      expect(flattened[1].text, equals('B站B'));
      expect(flattened[1].timeMs, equals(3500));
    });

    test('二分判断时间窗去重准确性 (多同名时间段覆盖与边界值)', () {
      final base = [
        DanmakuItem(text: '233', timeMs: 1000),
        DanmakuItem(text: '233', timeMs: 10000),
        DanmakuItem(text: '233', timeMs: 20000),
      ];

      final extra = [
        // 距离 1000ms 仅 500ms -> 重复剔除
        DanmakuItem(text: '233', timeMs: 1500),
        // 距离 10000ms 刚好 2500ms (12500 - 10000 = 2500) -> 边界命中剔除
        DanmakuItem(text: '233', timeMs: 12500),
        // 距离 10000ms 为 2501ms，距离 20000ms 为 7499ms -> 处于两窗之间安全保留
        DanmakuItem(text: '233', timeMs: 12501),
        // 远超 20000ms -> 保留
        DanmakuItem(text: '233', timeMs: 30000),
      ];

      final res = DanmakuPoolsManager.deduplicateDanmakuIncremental(
        base,
        extra,
        windowSeconds: 2.5,
      );
      expect(res.duplicatesCount, equals(2));
      expect(res.incremental.length, equals(2));
      expect(res.incremental[0].timeMs, equals(12501));
      expect(res.incremental[1].timeMs, equals(30000));
    });

    test('flattenEnabledPoolsAsync 异步隔离执行正确性', () async {
      final mgr = DanmakuPoolsManager();
      mgr.writePool(
        DanmakuPoolId.dandan,
        [DanmakuItem(text: '弹幕1', timeMs: 1000)],
      );
      mgr.writePool(
        DanmakuPoolId.bilibiliAuto,
        [DanmakuItem(text: '弹幕2', timeMs: 1500)],
      );
      mgr.globalTimeOffsetMs = 200;

      final flattened = await mgr.flattenEnabledPoolsAsync();
      expect(flattened.length, equals(2));
      expect(flattened[0].timeMs, equals(1200));
      expect(flattened[1].timeMs, equals(1700));
    });

    test('DanmakuSessionCoordinator 时移调节 200ms 防抖测试', () async {
      final controller = DanmakuController();
      final coord = DanmakuSessionCoordinator(danmakuController: controller);

      coord.poolsManager.writePool(
        DanmakuPoolId.dandan,
        [DanmakuItem(text: '测试弹幕', timeMs: 1000)],
      );
      // 等待 writePool 初始异步加载完成
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(controller.items.length, equals(1));
      expect(controller.items[0].timeMs, equals(1000));

      var coordNotified = 0;
      coord.addListener(() => coordNotified++);

      // 连续 3 次调整时移 (模拟快速连点 stepper)
      coord.poolsManager.globalTimeOffsetMs = 500;
      expect(coordNotified, equals(1));
      expect(coord.poolsManager.globalTimeOffsetMs, equals(500));
      // 此时防抖中，控制器中的弹幕尚未更新
      expect(controller.items[0].timeMs, equals(1000));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      coord.poolsManager.globalTimeOffsetMs = 1000;
      expect(coordNotified, equals(2));
      expect(controller.items[0].timeMs, equals(1000));

      await Future<void>.delayed(const Duration(milliseconds: 50));
      coord.poolsManager.globalTimeOffsetMs = 1500;
      expect(coordNotified, equals(3));
      expect(controller.items[0].timeMs, equals(1000));

      // 前进 100ms（距最后一次调整仅 100ms，防抖未超时）
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(controller.items[0].timeMs, equals(1000));

      // 推进 250ms（超过 200ms 防抖时间并等待 compute 完成），防抖结束触发实际重建
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(controller.items[0].timeMs, equals(2500));

      coord.dispose();
      controller.dispose();
    });
  });

  group('DanmakuFilterEngine 滑动窗口精简测试', () {
    test('4.0s 窗口内重复弹幕聚合为 ×N 徽标', () {
      final comments = [
        DanmakuItem(text: '233333', timeMs: 1000),
        DanmakuItem(text: '2333', timeMs: 2000),
        DanmakuItem(text: '23333333！', timeMs: 3500),
        DanmakuItem(text: '完全不同的弹幕', timeMs: 1200),
      ];

      final simplified = DanmakuFilterEngine.simplify(comments);
      expect(simplified.length, equals(2));

      final merged233 = simplified.firstWhere((c) => c.text.contains('×3'));
      expect(merged233, isNotNull);
      expect(merged233.text, contains('×3'));
    });
  });
}
