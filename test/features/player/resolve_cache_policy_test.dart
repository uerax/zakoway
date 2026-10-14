import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/native_source_runtime.dart';
import 'package:zakoway/features/player/source/sources/video_source.dart';
import 'package:zakoway/features/player/source/sources/xifan_next_source.dart';

class _MockDynamicResolveSource extends VideoSource {
  @override
  String get id => 'mock-dynamic';
  @override
  String get name => 'Mock Dynamic';
  @override
  String get version => '1.0.0';
  @override
  String get description => 'Mock Dynamic Source';

  int resolveCallCount = 0;

  @override
  Future<List<SourceSearchResult>> search(String keyword) async => [];

  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async => [];

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    resolveCallCount++;
    return SourceResolveResult(
      url: 'https://cdn.example.com/stream_$resolveCallCount.mp4',
      format: 'mp4',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('播放链接 1 分钟短时防抖缓存与各个源无私有缓存测试', () {
    test('1 分钟内连续请求命中 L1 内存防抖缓存，避免重复请求上游', () async {
      final runtime = NativeSourceRuntime();
      final mock = _MockDynamicResolveSource();
      runtime.registerSource(mock);

      const epUrl = 'https://example.com/anime/1/play/1';

      // 1. 首次解析
      final res1 = await runtime.resolve('mock-dynamic', epUrl);
      expect(res1.url, 'https://cdn.example.com/stream_1.mp4');
      expect(mock.resolveCallCount, 1);

      // 2. 紧接着二次解析（1分钟内），命中 L1 防抖缓存，不再调用底层 resolve
      final res2 = await runtime.resolve('mock-dynamic', epUrl);
      expect(res2.url, 'https://cdn.example.com/stream_1.mp4');
      expect(mock.resolveCallCount, 1); // 未重复请求上游
    });

    test('bypassCache: true 可绕过 1 分钟防抖缓存重新请求新鲜链接', () async {
      final runtime = NativeSourceRuntime();
      final mock = _MockDynamicResolveSource();
      runtime.registerSource(mock);

      const epUrl = 'https://example.com/anime/1/play/2';

      // 1. 首次解析
      final res1 = await runtime.resolve('mock-dynamic', epUrl);
      expect(res1.url, 'https://cdn.example.com/stream_1.mp4');
      expect(mock.resolveCallCount, 1);

      // 2. bypassCache 再次解析，重新向上游请求新鲜链接
      final res2 = await runtime.resolve('mock-dynamic', epUrl, bypassCache: true);
      expect(res2.url, 'https://cdn.example.com/stream_2.mp4');
      expect(mock.resolveCallCount, 2);
    });

    test('各个源自身不维护私有播放链接缓存，直接调用源的 resolve 每次均返回新鲜链接', () async {
      final mock = _MockDynamicResolveSource();
      const epUrl = 'https://example.com/anime/1/play/3';

      final r1 = await mock.resolve(epUrl);
      final r2 = await mock.resolve(epUrl);

      expect(r1.url, 'https://cdn.example.com/stream_1.mp4');
      expect(r2.url, 'https://cdn.example.com/stream_2.mp4');
      expect(mock.resolveCallCount, 2);
    });
  });

  group('稀饭Next源站真实线路解析测试', () {
    test('源站仅有 2 条线路时严格返回 2 条真实线路，绝不硬编码伪造 3 线路', () async {
      // 构造包含 2 条真实线路的 Next.js SSR 页面
      const mockHtml = '''
<!DOCTYPE html><html><body>
<script>self.__next_f.push([1,"1:{\\"sources\\":[{\\"id\\":1,\\"code\\":\\"AL\\",\\"name\\":\\"稀饭新番主线-2\\",\\"episodes\\":[{\\"id\\":206574,\\"episode_number\\":1},{\\"id\\":206575,\\"episode_number\\":2}]},{\\"id\\":2,\\"code\\":\\"CS\\",\\"name\\":\\"稀饭备用-1\\",\\"episodes\\":[{\\"id\\":206574,\\"episode_number\\":1},{\\"id\\":206575,\\"episode_number\\":2}]}]}"])</script>
</body></html>
''';

      final mockDio = Dio();
      mockDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.resolve(
              Response(
                requestOptions: options,
                data: mockHtml,
                statusCode: 200,
              ),
            );
          },
        ),
      );

      final source = XifanNextSource(dio: mockDio);
      final roads = await source.chapters('https://next.xifanacg.com/anime/3457');

      // 验证严格为 2 条真实线路，绝无伪造的“稀饭新番主线-1 (xfxf1)”
      expect(roads.length, 2);
      expect(roads[0].name, '稀饭新番主线-2');
      expect(roads[0].episodes.first.url, contains('source_id=1&source=AL'));
      expect(roads[1].name, '稀饭备用-1');
      expect(roads[1].episodes.first.url, contains('source_id=2&source=CS'));
      expect(roads.any((r) => r.name.contains('主线-1') || r.episodes.any((e) => e.url.contains('xfxf1'))), isFalse);
    });
  });
}

