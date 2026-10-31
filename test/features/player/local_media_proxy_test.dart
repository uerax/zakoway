import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/core/proxy/local_media_proxy_server.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';

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
            'seg2.ts\n'
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
        } else if (req.uri.path == '/master.m3u8') {
          req.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
          req.response.write(
            '#EXTM3U\n'
            '#EXT-X-VERSION:7\n'
            '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="ja",URI="audio.m3u8"\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=5000000,AUDIO="aud"\n'
            'video-1080p.m3u8\n',
          );
          await req.response.close();
        } else if (req.uri.path == '/video-1080p.m3u8') {
          req.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
          req.response.write(
            '#EXTM3U\n'
            '#EXT-X-VERSION:7\n'
            '#EXT-X-MAP:URI="init.mp4"\n'
            '#EXTINF:6.0,\n'
            'seg1.m4s\n',
          );
          await req.response.close();
        } else if (req.uri.path == '/seg2.ts') {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.set('Content-Type', 'video/MP2T');
          req.response.write('TS_SEGMENT_2_CONTENT');
          await req.response.close();
        } else if (req.uri.path == '/range-master.m3u8') {
          // 若收到 Range 头返回 206，无 Range 则返回 200
          final range = req.headers.value('range');
          req.response.statusCode = range != null ? HttpStatus.partialContent : HttpStatus.ok;
          req.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
          req.response.write(
            '#EXTM3U\n'
            '#EXT-X-VERSION:7\n'
            '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="ja",URI="v1/audio-0/index.m3u8"\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=5000000,AUDIO="aud"\n'
            'v1/1080/index.m3u8\n',
          );
          await req.response.close();
        } else if (req.uri.path == '/forced-206.m3u8') {
          // 模拟某些极端 CDN 强制返回 206 Partial Content
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
          req.response.write(
            '#EXTM3U\n'
            '#EXT-X-VERSION:7\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=5000000\n'
            'v1/1080/index.m3u8\n',
          );
          await req.response.close();
        } else if (req.uri.path == '/master-with-subs.m3u8') {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
          req.response.add(utf8.encode(
            '#EXTM3U\n'
            '#EXT-X-VERSION:7\n'
            '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="ja",URI="audio.m3u8"\n'
            '#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="[Sakurato] 简体中文",LANGUAGE="zh",URI="subs/zh.m3u8"\n'
            '#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",NAME="[Sakurato] 繁体中文",LANGUAGE="zh",URI="subs/zh-tw.m3u8"\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=5000000,AUDIO="aud",SUBTITLES="subs"\n'
            'video-1080p.m3u8\n',
          ));
          await req.response.close();
        } else if (req.uri.path == '/subs/zh.m3u8') {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
          req.response.write(
            '#EXTM3U\n'
            '#EXT-X-VERSION:3\n'
            '#EXT-X-TARGETDURATION:1421\n'
            '#EXTINF:1420.0,\n'
            'zh.vtt\n'
            '#EXT-X-ENDLIST\n',
          );
          await req.response.close();
        } else if (req.uri.path == '/subs/zh-tw.m3u8') {
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
          req.response.write(
            '#EXTM3U\n'
            '#EXT-X-VERSION:3\n'
            '#EXT-X-TARGETDURATION:1421\n'
            '#EXTINF:1420.0,\n'
            'zh-tw.vtt\n'
            '#EXT-X-ENDLIST\n',
          );
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
      );

      final uri = Uri.parse(proxyUrl);
      expect(uri.host, equals('127.0.0.1'));
      expect(uri.port, equals(LocalMediaProxyServer.instance.port));
      expect(uri.path, equals('/stream'));
      expect(uri.queryParameters['url'], equals('https://example.com/video.mp4'));
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

      // 验证切片被重写为 127.0.0.1 的 /segment 并保留后缀名
      expect(body, contains('http://127.0.0.1:${LocalMediaProxyServer.instance.port}/segment/seg1.ts?url='));
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
        path: '/segment/seg1.ts',
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

    test('高阶 Master Playlist 多码率索引与 fMP4 #EXT-X-MAP 递归改写测试', () async {
      final remoteMasterUrl = 'http://127.0.0.1:$remotePort/master.m3u8';
      final proxyMasterUrl = LocalMediaProxyServer.instance.buildProxyUrl(remoteMasterUrl);

      final client = HttpClient();

      // 1. 请求 master.m3u8
      final req1 = await client.getUrl(Uri.parse(proxyMasterUrl));
      final resp1 = await req1.close();
      expect(resp1.statusCode, equals(HttpStatus.ok));
      final body1 = await resp1.transform(utf8.decoder).join();

      final port = LocalMediaProxyServer.instance.port;

      // 验证 #EXT-X-MEDIA 中的音频轨被正确改写为 /stream
      expect(body1, contains('#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="ja",URI="http://127.0.0.1:$port/stream/audio.m3u8?url='));
      expect(body1, contains('audio.m3u8'));

      // 验证子播放列表被正确改写为 /stream (而非 /segment)
      expect(body1, contains('http://127.0.0.1:$port/stream/video-1080p.m3u8?url='));
      expect(body1, contains('video-1080p.m3u8'));

      // 2. 模拟播放器递归请求子播放列表 video-1080p.m3u8
      final subProxyUrl = LocalMediaProxyServer.instance.buildProxyUrl(
        'http://127.0.0.1:$remotePort/video-1080p.m3u8',
      );
      final req2 = await client.getUrl(Uri.parse(subProxyUrl));
      final resp2 = await req2.close();
      expect(resp2.statusCode, equals(HttpStatus.ok));
      final body2 = await resp2.transform(utf8.decoder).join();

      // 验证 #EXT-X-MAP 中的 init.mp4 被正确改写为 /segment
      expect(body2, contains('#EXT-X-MAP:URI="http://127.0.0.1:$port/segment/init.mp4?url='));
      expect(body2, contains('init.mp4'));

      // 验证 fMP4 切片 seg1.m4s 被正确改写为 /segment
      expect(body2, contains('http://127.0.0.1:$port/segment/seg1.m4s?url='));
      expect(body2, contains('seg1.m4s'));

      client.close();
    });

    test('带 Range 请求头的 M3U8 播放列表剥离 Range 并成功改写测试', () async {
      final remoteUrl = 'http://127.0.0.1:$remotePort/range-master.m3u8';
      final proxyUrl = LocalMediaProxyServer.instance.buildProxyUrl(remoteUrl);

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(proxyUrl));
      // 模拟 mpv / FFmpeg 默认发送 Range: bytes=0-
      req.headers.set('Range', 'bytes=0-');
      final resp = await req.close();

      expect(resp.statusCode, equals(HttpStatus.ok));
      final body = await resp.transform(utf8.decoder).join();

      final port = LocalMediaProxyServer.instance.port;
      // 验证音频子播放列表与视频子播放列表均被正确重写为 /stream，未出现相对路径
      expect(body, contains('#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="ja",URI="http://127.0.0.1:$port/stream/index.m3u8?url='));
      expect(body, contains('http://127.0.0.1:$port/stream/index.m3u8?url='));
      expect(body, contains('v1%2F1080%2Findex.m3u8'));
      expect(body, isNot(contains('URI="v1/audio-0/index.m3u8"')));

      client.close();
    });

    test('强制返回 206 Partial Content 的 M3U8 依然能够被正常改写', () async {
      final remoteUrl = 'http://127.0.0.1:$remotePort/forced-206.m3u8';
      final proxyUrl = LocalMediaProxyServer.instance.buildProxyUrl(remoteUrl);

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(proxyUrl));
      final resp = await req.close();

      expect(resp.statusCode, equals(HttpStatus.ok));
      final body = await resp.transform(utf8.decoder).join();

      final port = LocalMediaProxyServer.instance.port;
      expect(body, contains('http://127.0.0.1:$port/stream/index.m3u8?url='));
      expect(body, contains('v1%2F1080%2Findex.m3u8'));

      client.close();
    });

    test('Master M3U8 字幕解耦与外挂结构化提取测试', () async {
      final remoteUrl = 'http://127.0.0.1:$remotePort/master-with-subs.m3u8';
      final proxyUrl = LocalMediaProxyServer.instance.buildProxyUrl(remoteUrl);

      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(proxyUrl));
      final resp = await req.close();

      expect(resp.statusCode, equals(HttpStatus.ok));
      final body = await resp.transform(utf8.decoder).join();

      // 验证 1：#EXT-X-MEDIA:TYPE=SUBTITLES 被彻底从 HLS 清单中剔除，防止 libmpv 交错丢帧黑屏
      expect(body, isNot(contains('TYPE=SUBTITLES')));
      expect(body, isNot(contains('subs/zh.m3u8')));
      expect(body, isNot(contains('subs/zh-tw.m3u8')));

      // 验证 2：#EXT-X-STREAM-INF 中的 SUBTITLES 属性被清洗
      expect(body, isNot(contains('SUBTITLES="subs"')));
      expect(body, contains('AUDIO="aud"'));

      // 验证 3：从 Master 清单提取的字幕已安全解析为纯文本分片直链
      final extracted = LocalMediaProxyServer.instance.getEmbeddedSubtitles(remoteUrl);
      expect(extracted.length, equals(2));
      expect(extracted[0].label, equals('[Sakurato] 简体中文'));
      expect(extracted[0].url, contains('/segment/zh.vtt?url='));
      expect(extracted[0].url, contains('zh.vtt'));
      expect(extracted[1].label, equals('[Sakurato] 繁体中文'));
      expect(extracted[1].url, contains('/segment/zh-tw.vtt?url='));
      expect(extracted[1].url, contains('zh-tw.vtt'));

      client.close();
    });

    test('ZakowayPlaybackController.selectBestSubtitle 优先级决选与抛弃测试', () {
      final extSimp = const SourceSubtitleTrack(id: '1', label: '外挂简体', url: 'http://a/1.ass');
      final extTrad = const SourceSubtitleTrack(id: '2', label: '外挂繁体', url: 'http://a/2.ass');
      final embSimp = const SourceSubtitleTrack(id: '3', label: '[Sakurato] 简体中文', url: 'http://a/3.vtt');
      final embTrad = const SourceSubtitleTrack(id: '4', label: '[Sakurato] 繁体中文', url: 'http://a/4.vtt');
      final engSub = const SourceSubtitleTrack(id: '5', label: 'English', url: 'http://a/5.ass');
      final jpnSub = const SourceSubtitleTrack(id: '6', label: '日本語', url: 'http://a/6.vtt');

      // 1. 外挂简体 优先级最高
      expect(
        ZakowayPlaybackController.selectBestSubtitle(
          externalSubtitles: [extTrad, extSimp],
          embeddedSubtitles: [embSimp, embTrad],
        )?.id,
        equals('1'),
      );

      // 2. 无外挂简体时，外挂繁体 优先于 内置简体
      expect(
        ZakowayPlaybackController.selectBestSubtitle(
          externalSubtitles: [extTrad],
          embeddedSubtitles: [embSimp, embTrad],
        )?.id,
        equals('2'),
      );

      // 3. 无外挂字幕时，内置简体 优先于 内置繁体
      expect(
        ZakowayPlaybackController.selectBestSubtitle(
          externalSubtitles: [engSub],
          embeddedSubtitles: [embTrad, embSimp],
        )?.id,
        equals('3'),
      );

      // 4. 仅有内置繁体时，选用内置繁体
      expect(
        ZakowayPlaybackController.selectBestSubtitle(
          externalSubtitles: const [],
          embeddedSubtitles: [embTrad],
        )?.id,
        equals('4'),
      );

      // 5. 其它非中文字幕完全忽略抛弃，返回 null
      expect(
        ZakowayPlaybackController.selectBestSubtitle(
          externalSubtitles: [engSub],
          embeddedSubtitles: [jpnSub],
        ),
        isNull,
      );
    });
  });
}
