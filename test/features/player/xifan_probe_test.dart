import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/native_source_runtime.dart';
import 'package:zakoway/features/player/source/sources/xifan_next_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('测试 xifan-next 3403 选集与三线路独立解析', () async {
    final source = XifanNextSource();

    final roads = await source.chapters('https://next.xifanacg.com/anime/3403');
    expect(roads.length, 3);
    expect(roads[0].name, contains('稀饭新番主线-1'));
    expect(roads[1].name, contains('稀饭新番主线-2'));
    expect(roads[2].name, contains('稀饭备用-1'));

    // 1. 测试未指定线路（默认走国内沃云主线，遵循源站 no-referrer 规范）
    final res0 = await source.resolve('https://next.xifanacg.com/anime/3403/play/121397');
    expect(res0.url, anyOf(contains('pan.wo.cn'), contains('moedot.net')));
    expect(res0.format, 'mp4');
    expect(res0.headers['Referer'], isNull);

    // 2. 测试严格指定线路 0 (稀饭新番主线-1 -> 国内沃云，遵循 no-referrer)
    final resRoad0 = await source.resolve(roads[0].episodes.first.url);
    expect(resRoad0.url, anyOf(contains('pan.wo.cn'), contains('moedot.net')));
    expect(resRoad0.format, 'mp4');
    expect(resRoad0.headers['Referer'], isNull);

    // 3. 测试严格指定线路 1 (稀饭新番主线-2 -> 海外源)
    final resRoad1 = await source.resolve(roads[1].episodes.first.url);
    expect(resRoad1.url, contains('play.xfvod.pro:8088'));
    expect(resRoad1.format, 'mp4');
    expect(resRoad1.headers['Referer'], 'https://next.xifanacg.com/');

    // 4. 测试严格指定线路 2 (稀饭备用-1 -> 国内 HLS)
    final resRoad2 = await source.resolve(roads[2].episodes.first.url);
    expect(resRoad2.url, contains('dl.playxf.top'));
    expect(resRoad2.format, 'hls');
    expect(resRoad2.headers['Referer'], 'https://next.xifanacg.com/');

    // 5. 验证分集内存缓存与运行时防抖缓存生效
    final swCacheChapters = Stopwatch()..start();
    final cachedRoads = await source.chapters('https://next.xifanacg.com/anime/3403');
    swCacheChapters.stop();
    expect(cachedRoads.length, 3);
    expect(swCacheChapters.elapsedMilliseconds, lessThan(20));

    final runtime = NativeSourceRuntime();
    runtime.registerSource(source);
    await runtime.resolve(source.id, 'https://next.xifanacg.com/anime/3403/play/121397');
    final swCacheResolve = Stopwatch()..start();
    final cachedRes = await runtime.resolve(source.id, 'https://next.xifanacg.com/anime/3403/play/121397');
    swCacheResolve.stop();
    expect(cachedRes.url, anyOf(contains('pan.wo.cn'), contains('moedot.net')));
    expect(swCacheResolve.elapsedMilliseconds, lessThan(20));
    runtime.dispose();

    // 6. 验证持久化磁盘缓存 JSON 格式可逆转换
    final rawJsonList = roads.map((r) => r.toJson()).toList();
    expect(rawJsonList, isNotEmpty);
    final restoredRoads = rawJsonList.map(SourceChapterRoad.fromJson).toList();
    expect(restoredRoads.length, roads.length);
    expect(restoredRoads[0].name, roads[0].name);
    expect(restoredRoads[0].episodes.length, roads[0].episodes.length);
    expect(restoredRoads[0].episodes.first.url, roads[0].episodes.first.url);
  });
}
