import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';

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

  final _embeddedSubtitlesController =
      StreamController<({String masterUrl, List<SourceSubtitleTrack> tracks})>.broadcast();

  /// 监听从 HLS Master 播放列表中提取出的内置字幕轨广播流
  Stream<({String masterUrl, List<SourceSubtitleTrack> tracks})>
      get onEmbeddedSubtitlesExtracted => _embeddedSubtitlesController.stream;

  final Map<String, List<SourceSubtitleTrack>> _embeddedSubtitlesMap = {};

  /// 同步读取指定 Master M3U8 已提取的内置字幕轨
  List<SourceSubtitleTrack> getEmbeddedSubtitles(String masterUrl) {
    return _embeddedSubtitlesMap[masterUrl] ?? const [];
  }

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
    _embeddedSubtitlesMap.clear();
  }

  // ===========================================================================
  // 请求路由与核心代理管线
  // ===========================================================================

  Future<void> _handleIncomingRequest(HttpRequest request) async {
    final path = request.uri.path;
    if (path.startsWith('/stream') || path.startsWith('/segment')) {
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
    final isSegmentRequest = clientReq.uri.path.startsWith('/segment');
    final urlHash = md5.convert(utf8.encode(remoteUrl)).toString();
    final cacheFile = File('${_cacheDir?.path}/seg_$urlHash.ts');

    if (isSegmentRequest && _cacheDir != null && cacheFile.existsSync()) {
      try {
        final fileLen = cacheFile.lengthSync();
        if (fileLen > 0) {
          final rangeHeader = clientReq.headers.value('range');
          if (rangeHeader != null && rangeHeader.startsWith('bytes=0-')) {
            clientResp.statusCode = HttpStatus.partialContent;
            clientResp.headers.set('Content-Range', 'bytes 0-${fileLen - 1}/$fileLen');
          } else {
            clientResp.statusCode = HttpStatus.ok;
          }

          clientResp.headers.set('Content-Type', _resolveSegmentContentType(remoteUrl));
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

      // 特殊处理说明：
      // 对于 M3U8 播放列表文本，严禁向远程转发客户端的 Range 请求头：
      // 1. FFmpeg/mpv 在可寻道模式下默认会附带 Range: bytes=0- 探测服务器 Range 支持能力；
      // 2. 若将 Range 头透传给支持断点续传的 CDN，CDN 会响应 206 Partial Content 甚至文本截断分段；
      // 3. 剥离 Range 请求头后，远程必定返回包含完整标签的 200 OK 文本，确保 M3U8 改写引擎完整解析。
      final isM3u8Url = clientReq.uri.path.startsWith('/stream') &&
          (remoteUrl.toLowerCase().contains('.m3u8') ||
              clientReq.headers.value('accept')?.toLowerCase().contains('mpegurl') == true);

      // 1. 透传客户端的请求头（M3U8 播放列表请求剥离 Range 头）
      clientReq.headers.forEach((name, values) {
        final lower = name.toLowerCase();
        if (lower != 'host' && lower != 'connection') {
          if (isM3u8Url && lower == 'range') return;
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
      final isM3u8 = clientReq.uri.path.startsWith('/stream') &&
          (remoteUrl.toLowerCase().contains('.m3u8') ||
              contentType.contains('mpegurl') ||
              contentType.contains('application/x-mpegurl') ||
              contentType.contains('application/vnd.apple.mpegurl'));

      if (isM3u8 &&
          (remoteResp.statusCode == HttpStatus.ok ||
              remoteResp.statusCode == HttpStatus.partialContent)) {
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
          late StreamSubscription<List<int>> sub;
          sub = remoteResp.listen(
            (chunk) {
              try {
                clientResp.add(chunk);
              } catch (_) {
                // 特殊处理说明：
                // 客户端（播放器 mpv）在播放中途 Seek 会主动切断中止前序切片的 TCP 连接；
                // 此时向 clientResp 写入会抛出已断开异常。必须立即 cancel 远程流监听、
                // 关闭临时 sink、清理未下完的临时文件碎片，并唤醒 completer 正常退出，
                // 彻底杜绝请求协程挂死、文件句柄泄漏与 HttpClient 远程长连接被占满。
                sub.cancel().catchError((_) {});
                sink?.close().catchError((_) {});
                try {
                  tempFile.deleteSync();
                } catch (_) {}
                if (!completer.isCompleted) completer.complete();
                return;
              }
              try {
                sink?.add(chunk);
              } catch (_) {}
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

  static final RegExp _hlsUriAttributeRegex = RegExp(r'URI="([^"]+)"');

  /// 根据分片扩展名解析对应的 Content-Type，确保 fMP4/MP4/TS/KEY 格式准确
  String _resolveSegmentContentType(String url, {String? defaultType}) {
    final lower = url.toLowerCase();
    if (lower.contains('audio') || lower.contains('.m4a') || lower.contains('.aac') || lower.contains('.mp3')) {
      return 'audio/mp4';
    }
    if (lower.contains('.mp4') || lower.contains('.m4s') || lower.contains('init_')) {
      return 'video/mp4';
    }
    if (lower.contains('.key')) {
      return 'application/octet-stream';
    }
    if (lower.contains('.vtt')) {
      return 'text/vtt';
    }
    if (lower.contains('.ass')) {
      return 'text/x-ssa';
    }
    return defaultType ?? 'video/MP2T';
  }

  /// 构建本地代理回环 URL（严格区分 /stream 播放列表递归与 /segment 实体分片）
  String _buildLocalProxyUrl({
    required String targetUrl,
    required bool isStream,
    required Map<String, String> headers,
  }) {
    final query = <String, String>{
      'url': targetUrl,
    };
    if (headers.isNotEmpty) {
      query['headers'] = jsonEncode(headers);
    }

    // 特殊处理说明：
    // FFmpeg HLS demuxer (hls.c) 在执行 seek 寻道时会对播放列表中所有切片 URL 执行严格的
    // allowed_segment_extensions 扩展名白名单校验。
    // 若代理 URL 为纯 /segment?url=...&headers=...，URL 末尾为 %7D 或参数，
    // FFmpeg 判定扩展名非法并抛出 "is not in allowed_segment_extensions"，
    // 导致 "could not seek to position" 并直接以 EOF 失败退出（表现为播放进度瞬间跳至 24:00 尽头）。
    // 将真实文件名及合法扩展名附加到 path（如 /segment/seg-00000.m4s 或 /stream/index.m3u8），
    // 使 FFmpeg 准确识别扩展名，瞬时解复用出画。
    final targetUri = Uri.tryParse(targetUrl);
    final rawFileName = targetUri != null && targetUri.pathSegments.isNotEmpty
        ? targetUri.pathSegments.last
        : '';
    final safeFileName = Uri.encodeComponent(rawFileName);

    final basePath = isStream ? '/stream' : '/segment';
    final effectivePath = safeFileName.isNotEmpty ? '$basePath/$safeFileName' : basePath;

    return Uri(
      scheme: 'http',
      host: '127.0.0.1',
      port: _port,
      path: effectivePath,
      queryParameters: query,
    ).toString();
  }

  /// M3U8 文本逐行解析与切片 URL 回环重写引擎
  ///
  /// 特殊处理说明：
  /// 1. 严禁对 M3U8 做任何丢弃切片的“虚拟剪裁”，点播流总时长由全部分片累加而成；
  /// 2. HLS 高阶协议标签严密改写 (RFC 8216 / RFC 8216bis)：
  ///    - #EXT-X-MAP:URI="..." (fMP4 初始化分片头)：重写为 /segment 代理地址，避免相对路径请求 127.0.0.1 导致 404；
  ///    - #EXT-X-MEDIA:TYPE=AUDIO/SUBTITLES (外挂/独立音轨与字幕轨)：若为 .m3u8 重写为 /stream 代理地址，保证多音轨与字幕完整加载；
  ///    - #EXT-X-KEY:URI="..." (AES 加密密钥)：重写为 /segment 代理地址，自动附带 Referer 凭证，消除 403 无法解密问题；
  /// 3. Master Playlist 多码率索引子播放列表：
  ///    - 非 # 开头的行如果为 .m3u8 或上一行为 #EXT-X-STREAM-INF，重写为 /stream 路由，进行二级递归改写，
  ///      绝不能粗暴当作 /segment 二进制 TS 切片，从根本上杜绝解复用器格式冲突崩溃。
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
    final extractedSubtitles = <SourceSubtitleTrack>[];

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#EXT-X-MAP')) {
        // fMP4 初始化分片头：#EXT-X-MAP:URI="init_0.mp4"
        final match = _hlsUriAttributeRegex.firstMatch(line);
        if (match != null) {
          final rawUri = match.group(1)!;
          final absoluteUrl = baseUri.resolve(rawUri).toString();
          final localUrl = _buildLocalProxyUrl(
            targetUrl: absoluteUrl,
            isStream: false,
            headers: headers,
          );
          rewrittenLines.add(line.replaceFirst(rawUri, localUrl));
          continue;
        }
      } else if (line.startsWith('#EXT-X-MEDIA')) {
        final match = _hlsUriAttributeRegex.firstMatch(line);
        if (line.contains('TYPE=SUBTITLES')) {
          // 特殊处理说明：
          // HLS Master 清单字幕解耦与外挂化提取：
          // 1. 部分源站（如 hentai.wiki / Hanime）在 Master M3U8 中内嵌整集时长（如 1420 秒）的单个 WebVTT 切片；
          // 2. FFmpeg HLS demuxer 在并行解复用 6 秒音视频切片与 1420 秒字幕切片时，多路流交错队列发生时间戳冲突，
          //    导致 libmpv 误判视频帧严重落后时钟并全部 drop 丢弃，表现为持续黑屏且仅有声音；
          // 3. 此处将其从 M3U8 清单彻底剔除，并提取其标题与 URI 结构化转存为内置字幕轨，交由上层外挂字幕线程独立加载，
          //    既彻底根除了 HLS 解复用黑屏丢帧死锁，又保全了字幕内容。
          if (match != null) {
            final rawUri = match.group(1)!;
            final absoluteUrl = baseUri.resolve(rawUri).toString();
            final nameMatch = RegExp(r'NAME="([^"]+)"').firstMatch(line);
            final name = nameMatch?.group(1) ?? '内置字幕';

            // 特殊处理说明：
            // 若提取出的字幕 URI 包含 .m3u8 播放列表，绝不能直接交由底层 mpv sub-add：
            // 必须预解析出其内部真正的 .vtt 纯文本切片直链，以静态文本文件方式提供外挂渲染；
            // 纯文本字幕加载后一次性常驻内存按时间戳二分匹配，彻底消除解复用器在主视频 Seek 时的流式寻道死锁。
            String? targetVttUrl = absoluteUrl;
            if (absoluteUrl.toLowerCase().contains('.m3u8')) {
              targetVttUrl = await _resolveVttUrlFromSubM3u8(absoluteUrl, headers);
            }

            if (targetVttUrl != null && targetVttUrl.isNotEmpty) {
              final localSubUrl = _buildLocalProxyUrl(
                targetUrl: targetVttUrl,
                isStream: false,
                headers: headers,
              );

              extractedSubtitles.add(SourceSubtitleTrack(
                id: 'embedded_${extractedSubtitles.length}',
                label: name,
                url: localSubUrl,
                format: 'vtt',
              ));
            }
          }
          // 关键：不加入 rewrittenLines，彻底从 HLS 协议层剥离
          continue;
        }

        // 分离音轨：#EXT-X-MEDIA:TYPE=AUDIO,...,URI="v1/audio-0/index.m3u8"
        if (match != null) {
          final rawUri = match.group(1)!;
          final absoluteUrl = baseUri.resolve(rawUri).toString();
          final isSubStream = absoluteUrl.toLowerCase().contains('.m3u8');
          final localUrl = _buildLocalProxyUrl(
            targetUrl: absoluteUrl,
            isStream: isSubStream,
            headers: headers,
          );
          rewrittenLines.add(line.replaceFirst(rawUri, localUrl));
          continue;
        }
      } else if (line.startsWith('#EXT-X-KEY')) {
        // AES-128 加密密钥：#EXT-X-KEY:METHOD=AES-128,URI="ts.key"
        final match = _hlsUriAttributeRegex.firstMatch(line);
        if (match != null) {
          final rawUri = match.group(1)!;
          final absoluteUrl = baseUri.resolve(rawUri).toString();
          final localUrl = _buildLocalProxyUrl(
            targetUrl: absoluteUrl,
            isStream: false,
            headers: headers,
          );
          rewrittenLines.add(line.replaceFirst(rawUri, localUrl));
          continue;
        }
      } else if (line.startsWith('#EXT-X-STREAM-INF')) {
        // 特殊处理说明：
        // 移除 #EXT-X-STREAM-INF 中的 SUBTITLES 属性关联，避免播放器尝试绑定已剥离的字幕组
        final sanitized = line.replaceAll(RegExp(r',?SUBTITLES="[^"]*"'), '');
        rewrittenLines.add(sanitized);
        continue;
      }

      if (line.startsWith('#')) {
        rewrittenLines.add(line);
      } else {
        final absoluteUrl = baseUri.resolve(line).toString();
        // 区分该 URI 究竟是子播放列表 (Variant Playlist) 还是具体音视频媒体切片
        final isSubPlaylist = absoluteUrl.toLowerCase().contains('.m3u8') ||
            (i > 0 && lines[i - 1].trim().startsWith('#EXT-X-STREAM-INF'));

        if (isSubPlaylist) {
          // 子播放列表路由到 /stream，允许播放器递归请求并由代理二次改写
          final localStreamUrl = _buildLocalProxyUrl(
            targetUrl: absoluteUrl,
            isStream: true,
            headers: headers,
          );
          rewrittenLines.add(localStreamUrl);
        } else {
          // 真实视频/音频切片登记入后继预读表并路由到 /segment 享受缓存加速
          orderedSegments.add(absoluteUrl);
          final localSegmentUrl = _buildLocalProxyUrl(
            targetUrl: absoluteUrl,
            isStream: false,
            headers: headers,
          );
          rewrittenLines.add(localSegmentUrl);
        }
      }
    }

    // 建立后继切片映射表 (用于顺序预读流水线)
    for (var i = 0; i < orderedSegments.length - 1; i++) {
      _nextSegmentMap[orderedSegments[i]] = orderedSegments[i + 1];
    }

    if (extractedSubtitles.isNotEmpty) {
      final masterKey = baseUri.toString();
      _embeddedSubtitlesMap[masterKey] = extractedSubtitles;
      if (!_embeddedSubtitlesController.isClosed) {
        _embeddedSubtitlesController.add((
          masterUrl: masterKey,
          tracks: extractedSubtitles,
        ));
      }
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

  /// 从字幕 M3U8 清单中解析提取真实的 WebVTT 纯文本切片绝对直链
  Future<String?> _resolveVttUrlFromSubM3u8(
    String subM3u8Url,
    Map<String, String> headers,
  ) async {
    try {
      final baseUri = Uri.parse(subM3u8Url);
      final req = await _httpClient!.getUrl(baseUri);
      headers.forEach((k, v) => req.headers.set(k, v));
      final resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) return null;
      final body = await resp.transform(utf8.decoder).join();
      final lines = const LineSplitter().convert(body);
      for (final l in lines) {
        final trimmed = l.trim();
        if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
          return baseUri.resolve(trimmed).toString();
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
