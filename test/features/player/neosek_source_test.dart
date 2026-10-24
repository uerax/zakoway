import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/source/native_source_runtime.dart';
import 'package:zakoway/features/player/source/sources/neosek_source.dart';
import 'package:zakoway/features/player/widgets/video_source_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('测试 NeosekSource 属性、直连组与 NativeSourceRuntime 注册', () {
    final source = NeosekSource();
    expect(source.id, 'neosekai');
    expect(source.name, 'neosek');
    expect(source.isDirect, isTrue);
    expect(source.description, contains('香港 CDN'));

    final runtime = NativeSourceRuntime();
    expect(runtime.isLocalSource('neosekai'), isTrue);

    final defaultItems = getDefaultSourceItems();
    final neosekItem = defaultItems.firstWhere((i) => i.id == 'neosekai');
    expect(neosekItem.name, 'neosek');
    expect(neosekItem.isDirect, isTrue);
  });

  test('测试 NeosekSource 搜索、分集与直链解析 (优先 original 原画)', () async {
    final source = NeosekSource();

    // 1. 验证搜索 (芙莉莲)
    final hits = await source.search('芙莉莲');
    expect(hits, isNotEmpty);
    expect(hits.first.name, contains('芙莉莲'));
    expect(hits.first.url, contains('neosek.ai/anime/'));

    // 2. 验证章节列表
    final roads = await source.chapters(hits.first.url);
    expect(roads, isNotEmpty);
    expect(roads.first.name, 'Neosek');
    expect(roads.first.episodes, isNotEmpty);

    final firstEp = roads.first.episodes.first;
    expect(firstEp.name, isNotEmpty);
    expect(firstEp.url, contains('/anime/'));

    // 3. 验证直链解析
    final resolved = await source.resolve(firstEp.url);
    expect(resolved.url, startsWith('https://'));
    expect(resolved.url, anyOf(contains('.m3u8'), contains('.mkv'), contains('.mp4')));
    expect(resolved.format, anyOf('hls', 'mp4'));
    expect(resolved.headers['Referer'], contains('neosek.ai'));

    // 4. 针对用户真实报错单集 (FX战士久留美 1272/1903) 回归测试
    final resolvedKurumi = await source.resolve('https://neosek.ai/anime/1272/1903');
    expect(resolvedKurumi.url, startsWith('https://'));
    expect(resolvedKurumi.url, anyOf(contains('.m3u8'), contains('.mkv'), contains('.mp4')));
    expect(resolvedKurumi.format, anyOf('hls', 'mp4'));
  });
}
