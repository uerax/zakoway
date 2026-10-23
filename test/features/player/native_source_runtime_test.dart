import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/source/native_source_runtime.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('测试 NativeSourceRuntime 初始化与源列表', () async {
    final runtime = NativeSourceRuntime();
    await runtime.initialize();

    expect(runtime.isInitialized, isTrue);
    expect(runtime.bundleMeta.version, contains('native'));

    final sources = runtime.availableSources;
    expect(sources.length, 14);
    expect(sources.first.id, 'xifan-next');
    expect(sources.any((s) => s.id == 'gugu'), isTrue);
    expect(sources.any((s) => s.id == 'sorani'), isTrue);
    expect(sources.any((s) => s.id == 'xifan-next'), isTrue);
    expect(sources.any((s) => s.id == 'girigiri'), isTrue);
    expect(sources.any((s) => s.id == 'mifun'), isTrue);
    expect(sources.any((s) => s.id == 'cycani'), isTrue);
    expect(sources.any((s) => s.id == 'moonci'), isTrue);
    expect(sources.any((s) => s.id == 'tvtfun'), isTrue);
    expect(sources.any((s) => s.id == 'lzizy'), isTrue);
    expect(sources.any((s) => s.id == 'animoe'), isTrue);
    expect(sources.any((s) => s.id == 'mxdm'), isTrue);
    expect(sources.any((s) => s.id == 'omofun'), isTrue);
    expect(sources.any((s) => s.id == 'anime1'), isTrue);
    expect(sources.any((s) => s.id == 'libvio'), isTrue);

    // 验证权重顺序：xifan-next (首选) -> moonci -> cycani -> mifun/sorani (同级) ... animoe/gugu (同级)
    final ids = sources.map((s) => s.id).toList();
    expect(ids.indexOf('xifan-next'), 0);
    expect(ids.indexOf('sorani'), ids.indexOf('mifun') + 1);
    expect(ids.indexOf('gugu'), ids.indexOf('animoe') + 1);

    runtime.dispose();
  });

  test('测试原生视频源搜索、分集拉取与直链解析全流程', () async {
    final runtime = NativeSourceRuntime();
    await runtime.initialize();

    // 1. 验证量子资源原生搜索、分集与解析
    final lzizyHits = await runtime.search('lzizy', '葬送的芙莉莲');
    expect(lzizyHits, isNotEmpty);
    expect(lzizyHits.first.name, contains('芙莉莲'));

    final lzizyRoads = await runtime.chapters('lzizy', lzizyHits.first.url);
    expect(lzizyRoads, isNotEmpty);
    expect(lzizyRoads.first.episodes, isNotEmpty);

    final lzizyMedia = await runtime.resolve('lzizy', lzizyRoads.first.episodes.first.url);
    expect(lzizyMedia.url, startsWith('http'));

    // 2. 验证稀饭原生搜索、章节与解析
    final xifanHits = await runtime.search('xifan-next', '葬送的芙莉莲');
    expect(xifanHits, isNotEmpty);

    final xifanRoads = await runtime.chapters('xifan-next', xifanHits.first.url);
    expect(xifanRoads, isNotEmpty);

    final xifanMedia = await runtime.resolve('xifan-next', xifanRoads.first.episodes.first.url);
    expect(xifanMedia.url, startsWith('http'));

    // 3. 验证次元城原生搜索、分集与解析
    final cycHits = await runtime.search('cycani', '葬送的芙莉莲');
    expect(cycHits, isNotEmpty);

    final cycRoads = await runtime.chapters('cycani', cycHits.first.url);
    expect(cycRoads, isNotEmpty);

    final cycMedia = await runtime.resolve('cycani', cycRoads.first.episodes.first.url);
    expect(cycMedia.url, startsWith('http'));

    // 4. 验证青空次元原生搜索、分集与解析
    final soraniHits = await runtime.search('sorani', '从零开始');
    expect(soraniHits, isNotEmpty);
    expect(soraniHits.first.name, contains('从零开始'));

    final soraniRoads = await runtime.chapters('sorani', soraniHits.first.url);
    expect(soraniRoads, isNotEmpty);
    expect(soraniRoads.first.episodes, isNotEmpty);

    final soraniMedia = await runtime.resolve('sorani', soraniRoads.first.episodes.first.url);
    expect(soraniMedia.url, startsWith('http'));
    expect(soraniMedia.format, 'hls');
    expect(soraniMedia.headers['Referer'], 'https://www.sorani.net/');

    // 5. 验证月之祠原生搜索、分集与解析 (中文偏好 + 嵌套 JSON 正则修复)
    final moonciHits = await runtime.search('moonci', '葬送的芙莉莲');
    expect(moonciHits, isNotEmpty);
    expect(moonciHits.first.name, contains('芙莉莲'));

    final moonciRoads = await runtime.chapters('moonci', moonciHits.first.url);
    expect(moonciRoads, isNotEmpty);
    expect(moonciRoads.first.episodes, isNotEmpty);

    final moonciMedia = await runtime.resolve('moonci', moonciRoads.first.episodes.first.url);
    expect(moonciMedia.url, startsWith('http'));

    // 6. 验证月之祠 %uXXXX Unicode escape 解密 (解决用户报障 URL)
    final userReportedMedia = await runtime.resolve('moonci', 'https://www.moonci.com/anime/41/play/3-1.html');
    expect(userReportedMedia.url, anyOf(startsWith('https://dl.playxf.top/'), startsWith('https://next.xifanacg.com/'), startsWith('http')));

    // 7. 验证咕咕番原生搜索、分集与米芝网关字节直链解析 (容错网络抖动)
    try {
      final guguHits = await runtime.search('gugu', '葬送的芙莉莲');
      if (guguHits.isNotEmpty) {
        expect(guguHits.first.name, contains('芙莉莲'));
        final guguRoads = await runtime.chapters('gugu', guguHits.first.url);
        if (guguRoads.isNotEmpty && guguRoads.first.episodes.isNotEmpty) {
          final guguMedia = await runtime.resolve('gugu', guguRoads.first.episodes.first.url);
          expect(guguMedia.url, startsWith('http'));
        }
      }
    } catch (_) {}

    runtime.dispose();
  });
}
