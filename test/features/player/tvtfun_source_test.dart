import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/source/sources/tvtfun_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('测试 TvTFunSource 搜索、分集聚类与直链解析 (Nuxt 3 架构)', () async {
    final source = TvTFunSource();

    // 1. 验证搜索
    final hits = await source.search('鬼灭之刃');
    expect(hits, isNotEmpty);
    expect(hits.first.name, contains('鬼灭'));
    expect(hits.first.url, contains('/anime/'));

    // 2. 验证章节与线路聚类
    final target = hits.firstWhere((h) => h.name.contains('柱训练篇'), orElse: () => hits.first);
    final roads = await source.chapters(target.url);
    expect(roads, isNotEmpty);
    // 线路 1 为高优 AGE/BytePlus CDN 节点
    expect(roads.first.name, anyOf(contains('线路1'), contains('线路A'), contains('AGE'), contains('线路')));
    expect(roads.first.episodes, isNotEmpty);

    final firstEp = roads.first.episodes.first;
    expect(firstEp.name, isNotEmpty);
    expect(firstEp.url, contains('/watch/'));

    // 3. 验证直链解析
    final resolved = await source.resolve(firstEp.url);
    expect(resolved.url, startsWith('http'));
    expect(resolved.format, anyOf('mp4', 'hls'));
    expect(resolved.headers['Referer'], contains('tvtfun.net'));
  });
}
