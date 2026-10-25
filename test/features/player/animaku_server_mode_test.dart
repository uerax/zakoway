import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/features/player/source/engines/animaku_server_engine.dart';
import 'package:zakoway/features/player/source/engines/local_source_engine.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/native_source_runtime.dart';
import 'package:zakoway/features/player/source/server/adapters/animaku_source_adapter.dart';
import 'package:zakoway/features/player/source/server/adapters/xifan_next_animaku_adapter.dart';
import 'package:zakoway/features/player/source/server/animaku_server_client.dart';
import 'package:zakoway/features/player/widgets/episode_picker_section.dart';
import 'package:zakoway/features/player/widgets/video_source_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Animaku 服务端模式单元与部件测试', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppPreferences.init();
    });

    test('默认配置与持久化测试', () async {
      // 默认状态应为关闭，默认地址应为 bakasine.eu.org
      expect(AppPreferences.isServerModeEnabled(), isFalse);
      expect(AppPreferences.getServerModeApiUrl(), equals('https://bakasine.eu.org'));

      // 修改状态并检查通知
      var notified = false;
      void listener() => notified = true;
      AppPreferences.serverModeNotifier.addListener(listener);

      await AppPreferences.setServerModeEnabled(true);
      expect(AppPreferences.isServerModeEnabled(), isTrue);
      expect(notified, isTrue);

      // 修改自定义地址
      await AppPreferences.setServerModeApiUrl('https://custom.animaku.test/');
      expect(AppPreferences.getServerModeApiUrl(), equals('https://custom.animaku.test'));

      // 恢复默认
      await AppPreferences.setServerModeApiUrl('https://bakasine.eu.org');
      expect(AppPreferences.getServerModeApiUrl(), equals('https://bakasine.eu.org'));

      AppPreferences.serverModeNotifier.removeListener(listener);
    });

    test('AnimakuServerClient 纯动态源匹配与别名归一化', () async {
      final client = AnimakuServerClient.instance;

      expect(client.normalizeSourceId('xifan_next'), equals('xifan-next'));
      expect(client.normalizeSourceId('CYCANI'), equals('cycani'));

      // 设置从服务端动态获取并持久化的源清单
      await AppPreferences.setServerModeCachedSources(['xifan-next', 'cycani', 'sorani', 'anime1']);
      client.clearCache();

      // 验证动态源均能正确匹配
      expect(client.isSourceSupported('xifan-next'), isTrue);
      expect(client.isSourceSupported('xifannext'), isTrue); // 别名匹配
      expect(client.isSourceSupported('cycani'), isTrue);
      expect(client.isSourceSupported('sorani'), isTrue);
      expect(client.isSourceSupported('anime1'), isTrue);
      expect(client.isSourceSupported('unknown_source_xyz'), isFalse);
    });

    testWidgets('VideoSourceView UI：源名称应用颜色且开启服务端模式时展示[服务端]徽章', (tester) async {
      // 预先缓存包含 cycani 的动态支持源
      await AppPreferences.setServerModeCachedSources(['cycani']);
      AnimakuServerClient.instance.clearCache();

      final testSources = [
        const VideoSourceItem(
          id: 'cycani',
          name: '次元城动画',
          description: '多线路原画',
          isDirect: true,
        ),
        const VideoSourceItem(
          id: 'mifun',
          name: 'Mifun',
          description: '本地直连源（服务端未收录）',
          isDirect: true,
        ),
      ];

      // 1. 关闭服务端模式：不应该出现“直连”或“代理”标签，也不出现“服务端”标签
      await AppPreferences.setServerModeEnabled(false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoSourceView(
              selectedSourceId: 'cycani',
              sources: testSources,
              onSourceSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 确认旧标签已彻底移除
      expect(find.text('直连'), findsNothing);
      expect(find.text('代理'), findsNothing);
      expect(find.text('服务端'), findsNothing);

      // 检查源名称正常展示
      expect(find.text('次元城动画'), findsOneWidget);
      expect(find.text('Mifun'), findsOneWidget);

      // 2. 开启服务端模式：仅动态匹配到的 cycani 展示 1 个“服务端”标签；mifun 自动保持本地直连
      await AppPreferences.setServerModeEnabled(true);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VideoSourceView(
              selectedSourceId: 'cycani',
              sources: testSources,
              onSourceSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 应该仅为被接管的 cycani 展示 1 个“服务端”胶囊标签
      expect(find.text('服务端'), findsOneWidget);
    });

    testWidgets('EpisodePickerSection 空态友好提示与换源回调测试', (tester) async {
      var switched = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpisodePickerSection(
              episodeCount: 0,
              slots: const [],
              sourceName: '稀饭Next',
              errorMessage: '网络连接超时 (504)',
              onSelectEpisode: (_) {},
              onSwitchSource: () => switched = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证不展示假集数
      expect(find.text('源未解析到分集'), findsOneWidget);
      expect(find.text('第 01 话'), findsNothing);

      // 验证友好错误提示卡片
      expect(find.text('「稀饭Next」暂无可播放分集'), findsOneWidget);
      expect(find.text('网络连接超时 (504)'), findsOneWidget);

      // 点击切换视频源
      await tester.tap(find.text('切换视频源'));
      await tester.pumpAndSettle();
      expect(switched, isTrue);
    });

    testWidgets('EpisodePickerSection 展示【开启服务端模式】并响应点击', (tester) async {
      var enabled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpisodePickerSection(
              episodeCount: 0,
              slots: const [],
              sourceName: 'AGE动漫',
              errorMessage: '当前源为服务端专属扩展源，无法在本地直连模式下解析分集与直链。',
              onSelectEpisode: (_) {},
              onEnableServerMode: () => enabled = true,
              onSwitchSource: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('开启服务端模式'), findsOneWidget);
      expect(find.text('切换视频源'), findsOneWidget);

      await tester.tap(find.text('开启服务端模式'));
      await tester.pumpAndSettle();
      expect(enabled, isTrue);
    });

    test('NativeSourceRuntime 服务端动态源扩展与收缩卸载测试', () async {
      final runtime = NativeSourceRuntime();

      // 默认未开启服务端模式：只有本地源
      expect(runtime.isLocalSource('xifan-next'), isTrue);
      expect(runtime.isLocalSource('agedm'), isFalse);
      expect(runtime.availableSources.any((s) => s.id == 'agedm'), isFalse);

      // 开启服务端模式，并探测到新源 agedm
      await AppPreferences.setServerModeEnabled(true);
      AnimakuServerClient.instance.supportedSourcesNotifier.value = {'xifan-next', 'cycani', 'agedm'};

      // 验证动态挂载：agedm 出现在可用源列表中，且不是本地源
      expect(runtime.availableSources.any((s) => s.id == 'agedm'), isTrue);
      expect(runtime.isLocalSource('agedm'), isFalse);

      // 关闭服务端模式
      await AppPreferences.setServerModeEnabled(false);

      // 验证动态收缩：agedm 被自动卸载清理，列表还原为纯净本地源
      expect(runtime.availableSources.any((s) => s.id == 'agedm'), isFalse);

      runtime.dispose();
    });

    test('AnimakuAdapterRegistry 默认回退与专属注册机制', () async {
      AnimakuAdapterRegistry.resetForTesting();

      // 1. 未注册的源默认返回 DefaultAnimakuSourceAdapter，具备原始透传能力
      final defaultAdapter = AnimakuAdapterRegistry.get('any_random_source');
      expect(defaultAdapter, isA<DefaultAnimakuSourceAdapter>());
      expect(AnimakuAdapterRegistry.hasCustomAdapter('any_random_source'), isFalse);

      final dummySearchResult = [const SourceSearchResult(name: '测试番剧', url: '/play/1')];
      expect(defaultAdapter.transformSearch(dummySearchResult, keyword: '测试'), equals(dummySearchResult));

      final dummyRoads = [
        const SourceChapterRoad(
          name: '主线',
          episodes: [SourceEpisode(name: '第1集', url: '/ep/1')],
        ),
      ];
      expect(defaultAdapter.transformChapters(dummyRoads, animeUrl: '/play/1'), equals(dummyRoads));

      final dummyResolve = const SourceResolveResult(url: 'https://cdn.com/1.m3u8', format: 'hls');
      expect(await defaultAdapter.transformResolve(dummyResolve, episodeUrl: '/ep/1'), equals(dummyResolve));

      // 2. 注册自定义专属适配器
      final customAdapter = _TestCustomSourceAdapter();
      AnimakuAdapterRegistry.register(customAdapter);

      expect(AnimakuAdapterRegistry.hasCustomAdapter('test_source'), isTrue);
      final retrieved = AnimakuAdapterRegistry.get('test_source');
      expect(retrieved, equals(customAdapter));

      // 3. 测试专属适配器的 transform 与 fallback
      final transformedSearch = retrieved.transformSearch(dummySearchResult, keyword: '测试');
      expect(transformedSearch.first.name, equals('[专属清洗] 测试番剧'));

      final transformedResolve = await retrieved.transformResolve(dummyResolve, episodeUrl: '/ep/1');
      expect(transformedResolve.headers['Referer'], equals('https://custom-referer.com'));
      expect(transformedResolve.format, equals('mp4'));

      AnimakuAdapterRegistry.resetForTesting();
    });

    test('AnimakuServerClient 适配器 Fallback 拦截与源级兜底测试', () async {
      AnimakuAdapterRegistry.resetForTesting();

      // 创建一个模拟失败返回 500 的 Dio
      final errorDio = Dio();
      errorDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                error: '服务端 500 内部故障',
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      final client = AnimakuServerClient(dio: errorDio);

      // 1. 默认源（DefaultAnimakuSourceAdapter）：无 fallback，应直接 rethrow 抛出异常
      expect(
        () => client.search('default_source', '测试'),
        throwsA(isA<DioException>()),
      );
      expect(
        () => client.chapters('default_source', '/play/1'),
        throwsA(isA<DioException>()),
      );
      expect(
        () => client.resolve('default_source', '/ep/1'),
        throwsA(isA<DioException>()),
      );

      // 2. 注册带有源专属 Fallback 的适配器
      final fallbackAdapter = _TestFallbackSourceAdapter();
      AnimakuAdapterRegistry.register(fallbackAdapter);

      // 3. 验证当服务端报错时，成功由源专属适配器拦截并返回兜底数据
      final fallbackSearch = await client.search('fallback_source', '测试');
      expect(fallbackSearch.length, equals(1));
      expect(fallbackSearch.first.name, equals('兜底搜索结果'));

      final fallbackChapters = await client.chapters('fallback_source', '/play/1');
      expect(fallbackChapters.length, equals(1));
      expect(fallbackChapters.first.name, equals('兜底备选线路'));

      final fallbackResolve = await client.resolve('fallback_source', '/ep/1');
      expect(fallbackResolve.url, equals('https://fallback-cdn.com/fallback.mp4'));

      AnimakuAdapterRegistry.resetForTesting();
    });

    test('去除自动降级测试：服务端异常且无 fallback 时抛出异常，不再自动回退本地直连', () async {
      AnimakuAdapterRegistry.resetForTesting();

      final errorDio = Dio();
      errorDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                error: '服务端模拟超时',
                type: DioExceptionType.connectionTimeout,
              ),
            );
          },
        ),
      );

      // 注入带有错误模拟的 Dio 到服务端 Client
      final client = AnimakuServerClient(dio: errorDio);
      await AppPreferences.setServerModeEnabled(true);
      await AppPreferences.setServerModeCachedSources(['xifan-next']);
      client.clearCache();

      // 创建 NativeSourceRuntime
      final runtime = NativeSourceRuntime();

      // 开启服务端模式下，xifan-next 走服务端代理，但由于服务端超时且无专属 fallback，
      // 必须直接抛出异常，绝不静默降级到本地 Dart 爬虫
      expect(
        () => runtime.search('xifan-next', '葬送的芙莉莲', bypassCache: true),
        throwsA(isA<DioException>()),
      );

      expect(
        () => runtime.chapters('xifan-next', 'https://next.xifanacg.com/play/1', bypassCache: true),
        throwsA(isA<DioException>()),
      );

      expect(
        () => runtime.resolve('xifan-next', 'https://next.xifanacg.com/watch/1', bypassCache: true),
        throwsA(isA<DioException>()),
      );

      runtime.dispose();
      await AppPreferences.setServerModeEnabled(false);
      AnimakuAdapterRegistry.resetForTesting();
    });

    test('XifanNextAnimakuAdapter 照搬本地原版对沃派网盘与普通直链的优化处理', () async {
      final mockDio = Dio();
      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            // 模拟沃派直链 302 重定向
            if (options.uri.toString().contains('apn.moedot.net')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 302,
                  headers: Headers.fromMap({
                    'location': ['https://bjdownload.pan.wo.cn:30443/openapi/download?fid=test_file_123'],
                  }),
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final adapter = XifanNextAnimakuAdapter(dio: mockDio);

      // 1. 普通非沃派直链：注入 https://next.xifanacg.com/ Referer，校验 format
      const normalResult = SourceResolveResult(
        url: 'https://play.xfvod.pro:8088/Z/01.mp4',
        format: 'hls', // 服务端给出的错误格式
      );
      final normalOptimized = await adapter.transformResolve(normalResult, episodeUrl: '/play/1');
      expect(normalOptimized.url, equals('https://play.xfvod.pro:8088/Z/01.mp4'));
      expect(normalOptimized.format, equals('mp4')); // 纠偏为 mp4
      expect(normalOptimized.headers['Referer'], equals('https://next.xifanacg.com/'));
      expect(normalOptimized.headers['User-Agent'], isNotEmpty);

      // 2. 沃派网盘直链：注入 https://pan.wo.cn/ Referer，且通过 HEAD 预检展开 302 重定向直链
      const woResult = SourceResolveResult(
        url: 'https://apn.moedot.net/d/wo/01.mp4',
        format: 'hls',
      );
      final woOptimized = await adapter.transformResolve(woResult, episodeUrl: '/play/2');
      expect(woOptimized.format, equals('mp4'));
      expect(woOptimized.headers['Referer'], equals('https://pan.wo.cn/'));
      // 成功解析出 302 展开后的最终下载地址 (可能由于本地 DNS 解析包含 IPv4 替换或保持域名)
      expect(
        woOptimized.url.contains('pan.wo.cn') ||
            woOptimized.url.contains('openapi/download'),
        isTrue,
      );
      expect(woOptimized.headers['User-Agent'], isNotEmpty);

      // 3. m3u8 流媒体链接：保持 hls 格式
      const m3u8Result = SourceResolveResult(
        url: 'https://dl.playxf.top/新番/01.m3u8',
        format: 'mp4', // 错误标为 mp4
      );
      final m3u8Optimized = await adapter.transformResolve(m3u8Result, episodeUrl: '/play/3');
      expect(m3u8Optimized.format, equals('hls'));
      expect(m3u8Optimized.headers['Referer'], equals('https://next.xifanacg.com/'));
    });

    test('AnimakuAdapterRegistry 默认内置稀饭适配器', () {
      AnimakuAdapterRegistry.resetForTesting(reinitializeDefaults: true);
      final adapter = AnimakuAdapterRegistry.get('xifan-next');
      expect(adapter, isA<XifanNextAnimakuAdapter>());
      expect(AnimakuAdapterRegistry.hasCustomAdapter('xifan-next'), isTrue);
      // 兼容别名
      expect(AnimakuAdapterRegistry.get('xifan'), isA<XifanNextAnimakuAdapter>());
    });

    test('LocalSourceEngine 与 AnimakuServerEngine 双引擎完全解耦与独立运作', () async {
      // 1. 测试 LocalSourceEngine: 自包含管理 15 个本地源，完全不依赖服务端状态
      final localEngine = LocalSourceEngine();
      expect(localEngine.availableSources.length, equals(15));
      expect(localEngine.isLocalSource('xifan-next'), isTrue);
      expect(localEngine.isLocalSource('cycani'), isTrue);
      expect(localEngine.isLocalSource('non_existent_source'), isFalse);
      expect(localEngine.getSource('cycani'), isNotNull);

      // 2. 测试 AnimakuServerEngine: 独立管理服务端状态与动态源，不耦合本地爬虫实现
      await AppPreferences.setServerModeEnabled(false);
      var sourcesChangedCalled = false;
      final serverEngine = AnimakuServerEngine(
        onSourcesChanged: () => sourcesChangedCalled = true,
        isLocalSourceChecker: localEngine.isLocalSource,
      );

      // 服务端模式关闭时，动态源列表为空且不支持任何源
      expect(serverEngine.isSourceSupported('xifan-next'), isFalse);
      expect(serverEngine.dynamicSources, isEmpty);

      // 模拟服务端开启与发现新扩展源
      await AppPreferences.setServerModeEnabled(true);
      await AppPreferences.setServerModeCachedSources(['xifan-next', 'agedm']);
      AnimakuServerClient.instance.clearCache();
      AnimakuServerClient.instance.supportedSourcesNotifier.value = {'xifan-next', 'agedm'};
      serverEngine.onServerModeChanged();

      expect(serverEngine.isSourceSupported('xifan-next'), isTrue);
      expect(serverEngine.dynamicSources.any((s) => s.id == 'agedm'), isTrue);
      // xifan-next 为本地已知源，不会重复生成动态扩展源
      expect(serverEngine.dynamicSources.any((s) => s.id == 'xifan-next'), isFalse);
      expect(sourcesChangedCalled, isTrue);

      serverEngine.dispose();
      await AppPreferences.setServerModeEnabled(false);
    });
  });
}

/// 测试用自定义清洗适配器
class _TestCustomSourceAdapter extends AnimakuSourceAdapter {
  @override
  String get sourceId => 'test_source';

  @override
  List<SourceSearchResult> transformSearch(List<SourceSearchResult> results, {required String keyword}) {
    return results.map((r) => SourceSearchResult(name: '[专属清洗] ${r.name}', url: r.url)).toList();
  }

  @override
  Future<SourceResolveResult> transformResolve(SourceResolveResult result, {required String episodeUrl}) async {
    return SourceResolveResult(
      url: result.url,
      format: 'mp4',
      headers: {'Referer': 'https://custom-referer.com'},
    );
  }
}

/// 测试用带源专属 Fallback 的适配器
class _TestFallbackSourceAdapter extends AnimakuSourceAdapter {
  @override
  String get sourceId => 'fallback_source';

  @override
  Future<List<SourceSearchResult>?> onSearchFallback(Object error, {required String keyword}) async {
    return const [SourceSearchResult(name: '兜底搜索结果', url: '/fallback/search')];
  }

  @override
  Future<List<SourceChapterRoad>?> onChaptersFallback(Object error, {required String animeUrl}) async {
    return const [
      SourceChapterRoad(
        name: '兜底备选线路',
        episodes: [SourceEpisode(name: '兜底第1集', url: '/fallback/ep/1')],
      ),
    ];
  }

  @override
  Future<SourceResolveResult?> onResolveFallback(Object error, {required String episodeUrl}) async {
    return const SourceResolveResult(
      url: 'https://fallback-cdn.com/fallback.mp4',
      format: 'mp4',
    );
  }
}
