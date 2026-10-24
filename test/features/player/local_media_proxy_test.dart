import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/core/proxy/local_media_proxy_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalMediaProxyServer 单元测试', () {
    late HttpServer dummyRemoteServer;
    int remotePort = 0;

    setUpAll(() async {
      // 允许本地回环真实网络测试，解除 Flutter test 默认的 _MockHttpClient
      HttpOverrides.global = null;

      // 启动一个模拟远程服务器
      dummyRemoteServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      remotePort = dummyRemoteServer.port;

      dummyRemoteServer.listen((req) async {
        if (req.uri.path == '/video.m3u8') {
          req.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
          req.response.write(
            '#EXTM3U\n'
            '#EXT-X-VERSION:3\n'
            '#EXT-X-TARGETDURATION:10\n'
            '#EXTINF:10.0,\n'
            'seg1.ts\n'
            '#EXTINF:10.0,\n'
            'https://cdn.example.com/seg2.ts\n'
            '#EXT-X-ENDLIST\n',
          );
          await req.response.close();
        } else if (req.uri.path == '/video.mp4') {
          final range = req.headers.value('range');
          if (range != null && range.startsWith('bytes=0-')) {
            req.response.statusCode = HttpStatus.partialContent;
            req.response.headers.set('Content-Range', 'bytes 0-9/10');
            req.response.headers.set('Content-Length', '10');
            req.response.add(utf8.encode('0123456789'));
          } else {
            req.response.statusCode = HttpStatus.ok;
            req.response.headers.set('Content-Length', '10');
            req.response.add(utf8.encode('0123456789'));
          }
          await req.response.close();
        } else if (req.uri.path == '/seg1.ts') {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.set('Content-Type', 'video/MP2T');
          req.response.write('TS_SEGMENT_1_CONTENT');
          await req.response.close();
        } else {
          req.response.statusCode = HttpStatus.notFound;
          await req.response.close();
        }
      });
    });

    tearDownAll(() async {
      await dummyRemoteServer.close(force: true);
      await LocalMediaProxyServer.instance.dispose();
    });

    test('代理服务启动与端口动态分配', () async {
      final port = await LocalMediaProxyServer.instance.ensureStarted();
      expect(port, greaterThan(0));
      expect(LocalMediaProxyServer.instance.isRunning, isTrue);
    });

    test('buildProxyUrl 格式与参数编码正确性', () {
      final proxyUrl = LocalMediaProxyServer.instance.buildProxyUrl(
        'https://example.com/video.mp4',
        headers: {'Referer': 'https://example.com/'},
        start: const Duration(seconds: 15),
      );

      final uri = Uri.parse(proxyUrl);
      expect(uri.host, equals('127.0.0.1'));
      expect(uri.port, equals(LocalMediaProxyServer.instance.port));
      expect(uri.path, equals('/stream'));
      expect(uri.queryParameters['url'], equals('https://example.com/video.mp4'));
      expect(uri.queryParameters['start'], equals('15.000'));
      expect(uri.queryParameters['headers'], contains('Referer'));
    });

    test('MP4 Range 请求透传与 206 Partial Content 保持测试', () async {
      final remoteUrl = 'http://127.0.0.1:$remotePort/video.mp4';
      final proxyUrl = LocalMediaProxyServer.instance.buildProxyUrl(remoteUrl);

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(proxyUrl));
      req.headers.set('Range', 'bytes=0-9');
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();

      expect(resp.statusCode, equals(HttpStatus.partialContent));
      expect(resp.headers.value('content-range'), equals('bytes 0-9/10'));
      expect(body, equals('0123456789'));
      client.close();
    });

    test('M3U8 解析与切片 URL 自动重写为本地 /segment 测试', () async {
      final remoteUrl = 'http://127.0.0.1:$remotePort/video.m3u8';
      final proxyUrl = LocalMediaProxyServer.instance.buildProxyUrl(
        remoteUrl,
        headers: {'User-Agent': 'CustomUA'},
      );

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(proxyUrl));
      final resp = await req.close();

      expect(resp.statusCode, equals(HttpStatus.ok));
      final body = await resp.transform(utf8.decoder).join();

      // 验证切片被重写为 127.0.0.1 的 /segment
      expect(body, contains('http://127.0.0.1:${LocalMediaProxyServer.instance.port}/segment?url='));
      expect(body, contains('seg1.ts'));
      expect(body, contains('seg2.ts'));
      client.close();
    });

    test('TS 切片边下边存与二次请求 HIT 命中测试', () async {
      final remoteTsUrl = 'http://127.0.0.1:$remotePort/seg1.ts';
      final segmentProxyUri = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: LocalMediaProxyServer.instance.port,
        path: '/segment',
        queryParameters: {'url': remoteTsUrl},
      );

      final client = HttpClient();

      // 1. 首次请求：MISS 并异步落盘
      final req1 = await client.getUrl(segmentProxyUri);
      final resp1 = await req1.close();
      expect(resp1.statusCode, equals(HttpStatus.ok));
      expect(resp1.headers.value('x-proxy-cache'), equals('MISS'));
      final body1 = await resp1.transform(utf8.decoder).join();
      expect(body1, equals('TS_SEGMENT_1_CONTENT'));

      // 微等待确保文件落地完成
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // 2. 二次请求：HIT 本地瞬发
      final req2 = await client.getUrl(segmentProxyUri);
      final resp2 = await req2.close();
      expect(resp2.statusCode, equals(HttpStatus.ok));
      expect(resp2.headers.value('x-proxy-cache'), equals('HIT'));
      final body2 = await resp2.transform(utf8.decoder).join();
      expect(body2, equals('TS_SEGMENT_1_CONTENT'));

      client.close();
    });
  });
}
