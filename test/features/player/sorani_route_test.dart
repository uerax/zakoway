import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/source/sources/sorani_source.dart';

void main() {
  group('青空次元 (SoraniSource) 官方路由对齐规范测试', () {
    test('1. 验证 search 返回的标准番剧详情页路径与 query id', () async {
      final source = SoraniSource();
      final hits = await source.search('从零开始');
      expect(hits, isNotEmpty);
      final first = hits.first;
      // 验证番剧详情链接包含官方标准 /anime/mal/ 或 /anime/ 路径
      expect(first.url, matches(RegExp(r'https://www\.sorani\.net/anime/(?:mal/)?\d+')));
    });

    test('2. 验证 chapters 生成的选集播放链接严格对齐官方 /episode/01 规范', () async {
      final source = SoraniSource();
      final hits = await source.search('从零开始');
      expect(hits, isNotEmpty);

      final roads = await source.chapters(hits.first.url);
      expect(roads, isNotEmpty);
      expect(roads.first.episodes, isNotEmpty);

      final ep1 = roads.first.episodes.first;
      // 必须严格对齐官方前端 SvelteKit 播放页路由 /episode/01 格式
      expect(ep1.url, contains('/episode/01'));
      // 必须携带 epId 参数供原生解析极速直出
      expect(ep1.url, contains('epId='));

      // 验证第二集（若存在）为 /episode/02
      if (roads.first.episodes.length > 1) {
        final ep2 = roads.first.episodes[1];
        expect(ep2.url, contains('/episode/02'));
      }
    });

    test('3. 验证 resolve 能够从官方播放链接秒解视频流直链', () async {
      final source = SoraniSource();
      final hits = await source.search('从零开始');
      final roads = await source.chapters(hits.first.url);
      final epUrl = roads.first.episodes.first.url;

      final result = await source.resolve(epUrl);
      expect(result.url, startsWith('http'));
      expect(result.headers['Referer'], 'https://www.sorani.net/');
    });
  });
}
