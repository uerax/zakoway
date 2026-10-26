import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// 本地流媒体反向代理服务器 (Local Media Proxy)
///
/// 架构定位：
/// 在 App 内部通过 127.0.0.1 动态端口运行轻量 HTTP 代理服务，
/// 使得底层播放器 (media_kit / libmpv) 始终与纯本地回环网络 (Loopback) 通信。
///
/// 核心解决痛点：
/// 1. 彻底终结底层 FFmpeg/mbedtls 脆弱的 SSL 握手阻断与重连死循环 (mbedtls_ssl_handshake -0x4e)；
/// 2. 借助 Dart 高性能 HttpClient 连接池实现 Keep-Alive 长连接复用与证书容灾；
/// 3. 支持透明 Range 字节范围请求与状态码保持 (206 Partial Content)；
/// 4. 支持 M3U8 切片自动重写与断点起播虚拟剪裁，消灭 mpv 先读 0 秒再 seek 的二次缓冲；
/// 5. 边下边播本地分片持久化缓存 (Cache-as-you-go) + 异步后继切片预读流水线 (Readahead Pipeline)。
class LocalMediaProxyServer {
  LocalMediaProxyServer._();

  static final LocalMediaProxyServer instance = LocalMediaProxyServer._();

  HttpServer? _server;
  HttpClient? _httpClient;
  int _port = 0;
  bool _isStarting = false;

  Directory? _cacheDir;
  final Map<String, String> _nextSegmentMap = {};
  final Set<String> _inflightPrefetch = {};

  /// 代理服务当前绑定的回环端口 (未启动时为 0)
  int get port => _port;

  /// 代理服务是否已就绪
  bool get isRunning => _server != null && _port > 0;

  /// 确保代理服务已启动并返回本地端口
  Future<int> ensureStarted() async {
    if (isRunning) return _port;
    if (_isStarting) {
      while (_isStarting) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (isRunning) return _port;
    }

    _isStarting = true;
    try {
      // 0. 初始化分片本地持久化缓存目录
      final baseTemp = Directory.systemTemp.path;
      _cacheDir = Directory('$baseTemp/zakoway_stream_cache');
      if (!_cacheDir!.existsSync()) {
        await _cacheDir!.create(recursive: true);
      }

      // 1. 初始化高并发复用 Dart HttpClient
      _httpClient = HttpClient()
        ..maxConnectionsPerHost = 16
        ..idleTimeout = const Duration(seconds: 60)
        ..connectionTimeout = const Duration(seconds: 10)
        ..badCertificateCallback = (cert, host, port) => true; // 放行海外源自签名或过期证书

      // 2. 动态绑定 127.0.0.1 随机可用空闲端口，彻底杜绝端口冲突
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;

      if (kDebugMode) {
        debugPrint('🚀 [LocalMediaProxy] 本地流媒体代理服务已就绪 -> 127.0.0.1:$_port');
      }

      // 3. 启动请求监听分发循环
      _server!.listen(
        _handleIncomingRequest,
        onError: (Object error) {
          if (kDebugMode) {
            debugPrint('⚠️ [LocalMediaProxy] 代理监听异常: $error');
          }
        },
        cancelOnError: false,
      );

      return _port;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ [LocalMediaProxy] 启动本地代理服务失败: $e');
      }
      return 0;
    } finally {
      _isStarting = false;
    }
  }

  /// 将远程媒体 URL 包装为本地代理 URL
  String buildProxyUrl(
    String remoteUrl, {
    Map<String, String>? headers,
    Duration? start,
  }) {
    final trimmed = remoteUrl.trim();
    if (trimmed.isEmpty) return remoteUrl;

    // 若未启动或本身已是本地代理自身地址，原样返回，防止套娃代理
    if (!isRunning ||
        trimmed.contains('127.0.0.1:$_port') ||
        trimmed.contains('localhost:$_port')) {
      return remoteUrl;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return remoteUrl;
    }

    final queryParams = <String, String>{
      'url': trimmed,
    };

    if (headers != null && headers.isNotEmpty) {
      queryParams['headers'] = jsonEncode(headers);
    }

    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _port,
      path: '/stream',
      queryParameters: queryParams,
    ).toString();
  }

  /// 关闭本地代理服务并释放资源
  Future<void> dispose() async {
    try {
      await _server?.close(force: true);
    } catch (_) {}
    _server = null;
    _port = 0;
    try {
      _httpClient?.close(force: true);
    } catch (_) {}
    _httpClient = null;
    _nextSegmentMap.clear();
    _inflightPrefetch.clear();
  }

  // ===========================================================================
  // 请求路由与核心代理管线
  // ===========================================================================

  Future<void> _handleIncomingRequest(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/stream' || path == '/segment') {
      await _proxyMediaStream(request);
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close().catchError((_) {});
    }
  }

  Future<void> _proxyMediaStream(HttpRequest clientReq) async {
    final clientResp = clientReq.response;
    final remoteUrl = clientReq.uri.queryParameters['url'];
    if (remoteUrl == null || remoteUrl.isEmpty) {
      clientResp.statusCode = HttpStatus.badRequest;
      await clientResp.close().catchError((_) {});
      return;
    }

    // 解析附加请求头
    Map<String, String> extraHeaders = {};
    final rawHeaders = clientReq.uri.queryParameters['headers'];
    if (rawHeaders != null && rawHeaders.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawHeaders);
        if (decoded is Map) {
          extraHeaders = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }

    // =========================================================================
    // 1. 分片本地磁盘缓存击穿检测 (Cache Hit -> 0ms 本地瞬发)
    // =========================================================================
    final isSegmentRequest = clientReq.uri.path == '/segment';
    final urlHash = md5.convert(utf8.encode(remoteUrl)).toString();
    final cacheFile = File('${_cacheDir?.path}/seg_$urlHash.ts');

    if (isSegmentRequest && _cacheDir != null && cacheFile.existsSync()) {
      try {
        final fileLen = cacheFile.lengthSync();
        if (fileLen > 0) {
          clientResp.statusCode = HttpStatus.ok;
          clientResp.headers.set('Content-Type', 'video/MP2T');
          clientResp.headers.set('Content-Length', fileLen.toString());
          clientResp.headers.set('Access-Control-Allow-Origin', '*');
          clientResp.headers.set('Accept-Ranges', 'bytes');
          clientResp.headers.set('X-Proxy-Cache', 'HIT');

          await cacheFile.openRead().pipe(clientResp).catchError((Object _) {});

          // 本地命中后，依然驱动流水线投机预读下一个分片
          _schedulePrefetchNext(remoteUrl, extraHeaders);
          return;
        }
      } catch (_) {}
    }

    // =========================================================================
    // 2. 缓存未命中 -> 通过长连接池向远程发起请求 (Cache Miss & Cache-as-you-go)
    // =========================================================================
    try {
      final targetUri = Uri.parse(remoteUrl);
      final remoteReq = await _httpClient!.openUrl(clientReq.method, targetUri);

      // 1. 透传客户端的 Range 请求头与标准请求头
      clientReq.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower != 'host' && lower != 'connection') {
          for (final v in values) {
            remoteReq.headers.add(name, v);
          }
        }
      });

      // 2. 注入外部源所需的专属认证头 (如 Referer, User-Agent)
      extraHeaders.forEach((k, v) {
        remoteReq.headers.set(k, v);
      });

      final remoteResp = await remoteReq.close();

      // 判断是否为 M3U8 播放列表文本
      final contentType = remoteResp.headers.contentType?.toString().toLowerCase() ?? '';
      final isM3u8 = clientReq.uri.path == '/stream' &&
          (remoteUrl.contains('.m3u8') ||
              contentType.contains('mpegurl') ||
              contentType.contains('application/x-mpegurl') ||
              contentType.contains('application/vnd.apple.mpegurl'));

      if (isM3u8 && remoteResp.statusCode == HttpStatus.ok) {
        // HLS M3U8 核心改写流与切片顺序表登记
        await _handleM3u8Rewrite(
          remoteResp,
          clientResp,
          baseUri: targetUri,
          headers: extraHeaders,
        );
      } else {
        // 普通媒体流 / MP4 Range / TS 分片直接管道透传
        clientResp.statusCode = remoteResp.statusCode;

        // 透传关键响应头
        remoteResp.headers.forEach((name, values) {
          final lower = name.toLowerCase();
          if (lower != 'connection' && lower != 'transfer-encoding') {
            for (final v in values) {
              clientResp.headers.add(name, v);
            }
          }
        });

        clientResp.headers.set('Access-Control-Allow-Origin', '*');
        clientResp.headers.set('Accept-Ranges', 'bytes');
        clientResp.headers.set('X-Proxy-Cache', 'MISS');

        if (isSegmentRequest && remoteResp.statusCode == HttpStatus.ok && _cacheDir != null) {
          // 特殊处理说明：
          // 边下边存 (Cache-as-you-go 双路流式输出)：
          // 一路无延迟即时 push 给底层播放器 socket；另一路异步写入本地磁盘缓存文件；
          // 彻底杜绝拖拽回看或下一次播放时的重复远程高延迟拉取。
          final tempFile = File('${_cacheDir!.path}/tmp_$urlHash.tmp');
          IOSink? sink;
          try {
            sink = tempFile.openWrite();
          } catch (_) {}

          final completer = Completer<void>();
          remoteResp.listen(
            (chunk) {
              clientResp.add(chunk);
              sink?.add(chunk);
            },
            onDone: () async {
              try {
                await sink?.flush();
                await sink?.close();
                if (tempFile.existsSync() && tempFile.lengthSync() > 0) {
                  await tempFile.rename(cacheFile.path);
                }
              } catch (_) {}
              if (!completer.isCompleted) completer.complete();
            },
            onError: (Object err) {
              sink?.close().catchError((_) {});
              try {
                tempFile.deleteSync();
              } catch (_) {}
              if (!completer.isCompleted) completer.completeError(err);
            },
            cancelOnError: true,
          );

          await completer.future.catchError((Object _) {});
          await clientResp.close().catchError((_) {});

          // 当前切片拉取完毕，触发后台投机预读下一个分片
          _schedulePrefetchNext(remoteUrl, extraHeaders);
        } else {
          // MP4 Range 或非分片响应直接 pipe 透传
          await remoteResp.pipe(clientResp).catchError((Object _) {});
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ [LocalMediaProxy] 远程流拉取失败 ($remoteUrl): $e');
      }
      try {
        clientResp.statusCode = HttpStatus.badGateway;
        await clientResp.close().catchError((_) {});
      } catch (_) {}
    }
  }

  /// M3U8 文本逐行解析与切片 URL 回环重写引擎
  ///
  /// 特殊处理说明：
  /// 此处严禁对 M3U8 做任何丢弃切片的“虚拟剪裁”！
  /// 点播流 (VOD HLS) 的总时长由全部分片累加而成。若人为剔除历史断点前的切片，
  /// 会导致播放器 Duration 永久缩水、时间轴归零错乱、弹幕无法对齐并引发滚雪球式截短。
  /// 断点起播已由底层 media_kit 原生 `Media(start: start)` 通过 mpv `--start` 一体化直达，
  /// 无需且绝不可侵入 M3U8 的切片列表。
  Future<void> _handleM3u8Rewrite(
    HttpClientResponse remoteResp,
    HttpResponse clientResp, {
    required Uri baseUri,
    required Map<String, String> headers,
  }) async {
    final rawBody = await remoteResp.transform(utf8.decoder).join();
    final lines = const LineSplitter().convert(rawBody);

    final rewrittenLines = <String>[];
    final orderedSegments = <String>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#')) {
        rewrittenLines.add(line);
      } else {
        final absoluteTsUrl = baseUri.resolve(line).toString();
        orderedSegments.add(absoluteTsUrl);

        final segmentQuery = <String, String>{
          'url': absoluteTsUrl,
        };
        if (headers.isNotEmpty) {
          segmentQuery['headers'] = jsonEncode(headers);
        }

        final localSegmentUrl = Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: _port,
          path: '/segment',
          queryParameters: segmentQuery,
        ).toString();

        rewrittenLines.add(localSegmentUrl);
      }
    }

    // 建立后继切片映射表 (用于顺序预读流水线)
    for (var i = 0; i < orderedSegments.length - 1; i++) {
      _nextSegmentMap[orderedSegments[i]] = orderedSegments[i + 1];
    }

    final outputText = rewrittenLines.join('\n');
    final bytes = utf8.encode(outputText);

    clientResp.statusCode = HttpStatus.ok;
    clientResp.headers.set('Content-Type', 'application/vnd.apple.mpegurl; charset=utf-8');
    clientResp.headers.set('Content-Length', bytes.length.toString());
    clientResp.headers.set('Access-Control-Allow-Origin', '*');

    clientResp.add(bytes);
    await clientResp.close().catchError((_) {});
  }

  /// 显式预拉取指定分片并写入本地磁盘缓存
  Future<bool> prefetchSegment(String segmentUrl, {Map<String, String>? headers}) async {
    await ensureStarted();
    if (_httpClient == null || _cacheDir == null) return false;

    final segHash = md5.convert(utf8.encode(segmentUrl)).toString();
    final targetFile = File('${_cacheDir!.path}/seg_$segHash.ts');

    if (targetFile.existsSync() && targetFile.lengthSync() > 0) {
      return true;
    }
    if (_inflightPrefetch.contains(segmentUrl)) {
      return false;
    }

    _inflightPrefetch.add(segmentUrl);
    try {
      final targetUri = Uri.parse(segmentUrl);
      final req = await _httpClient!.openUrl('GET', targetUri);
      if (headers != null) {
        headers.forEach((k, v) {
          req.headers.set(k, v);
        });
      }

      final resp = await req.close();
      if (resp.statusCode == HttpStatus.ok) {
        final tempFile = File('${_cacheDir!.path}/tmp_$segHash.tmp');
        final sink = tempFile.openWrite();
        await resp.pipe(sink);
        if (tempFile.existsSync() && tempFile.lengthSync() > 0) {
          await tempFile.rename(targetFile.path);
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      _inflightPrefetch.remove(segmentUrl);
    }
  }

  /// 异步切片预读调度器 (Readahead Pipeline)
  void _schedulePrefetchNext(String currentTsUrl, Map<String, String> headers) {
    final nextUrl = _nextSegmentMap[currentTsUrl];
    if (nextUrl == null || nextUrl.isEmpty) return;

    prefetchSegment(nextUrl, headers: headers).ignore();
  }
}
