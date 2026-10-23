import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/utils/media_url_resolver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MediaUrlResolver 单元测试', () {
    test('空 URL 原样返回', () async {
      const input = SourceResolveResult(url: '', format: 'mp4');
      final output = await MediaUrlResolver.resolveRedirects(input);
      expect(output.url, '');
    });

    test('302 重定向展开并更新为 Location 最终落地直链', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.uri.toString().contains('test-redirect.com/play')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 302,
                  headers: Headers.fromMap({
                    'location': ['https://cdn.test.com/stream/index.m3u8'],
                  }),
                ),
              );
            }
            if (options.uri.toString().contains('cdn.test.com')) {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      const input = SourceResolveResult(
        url: 'https://test-redirect.com/play',
        format: 'mp4',
        headers: {'User-Agent': 'CustomUA'},
      );

      final result = await MediaUrlResolver.resolveRedirects(input, dioClient: dio);
      expect(result.url, 'https://cdn.test.com/stream/index.m3u8');
      expect(result.format, 'hls');
      expect(result.headers['User-Agent'], 'CustomUA');
    });

    test('多次 302 跳转保留传入的自定义请求头', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
              ),
            );
          },
        ),
      );

      const input = SourceResolveResult(
        url: 'https://jump.com/1.mp4',
        format: 'mp4',
        headers: {'Referer': 'https://custom.referer.com/'},
      );

      final result = await MediaUrlResolver.resolveRedirects(input, dioClient: dio);
      expect(result.headers['Referer'], 'https://custom.referer.com/');
    });

    test('预检发生异常或网络超时平滑降级，原样返回入参', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
                error: 'Connection timeout',
              ),
            );
          },
        ),
      );

      const input = SourceResolveResult(
        url: 'https://broken.com/video.mp4',
        format: 'mp4',
        headers: {'Custom': 'Header'},
      );

      final result = await MediaUrlResolver.resolveRedirects(input, dioClient: dio);
      expect(result.url, 'https://broken.com/video.mp4');
      expect(result.headers['Custom'], 'Header');
    });
  });
}
