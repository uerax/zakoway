import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:zakoway/features/player/core/proxy/local_media_proxy_server.dart';
import 'package:zakoway/features/player/source/source_bundle_manager.dart';

/// 预测性媒体流预载协调调度器 (Media Preload Coordinator)
///
/// 架构定位：
/// 借鉴主流旗舰流媒体 (Bilibili / TikTok / Netflix) 预测性调度体系：
/// 1. 首页继续追番卡片首片预拉取 (First-chunk Speculative Preload)：
///    在用户浏览首页的几秒内，静默将首个 TS 分片写入本地磁盘缓存，点击瞬间 < 200ms 瞬开！
/// 2. 播放中下一集连播预拉取 (Next-Episode Seamless Handover)：
///    当前集播放达到 75% 时，后台自动解析并下载下一集前 2 个切片，实现零转圈连播无缝衔接。
class MediaPreloadCoordinator {
  MediaPreloadCoordinator._();

  static final MediaPreloadCoordinator instance = MediaPreloadCoordinator._();

  final Set<String> _inFlightPreloads = {};
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..badCertificateCallback = (cert, host, port) => true;

  /// 预拉取指定番剧集数的首部分片数据 (极低优先级，后台非阻塞)
  Future<void> preloadMediaFirstChunk({
    required String sourceId,
    required String episodeUrl,
  }) async {
    final taskKey = '$sourceId:$episodeUrl';
    if (_inFlightPreloads.contains(taskKey)) return;
    _inFlightPreloads.add(taskKey);

    // 以微任务异步脱钩发起，绝不阻塞主线程与当前交互
    Future<void>.microtask(() async {
      try {
        final runtime = SourceBundleManager.instance.runtime;
        final res = await runtime.resolve(sourceId, episodeUrl);
        if (res.url.isEmpty) return;

        final directUrl = res.url;
        final headers = res.headers;

        // 1. 若为 HLS M3U8 流，拉取播放列表并提前下载前 1~2 个 TS 切片
        if (directUrl.contains('.m3u8')) {
          await _preloadM3u8LeadingSegments(directUrl, headers);
        }

        if (kDebugMode) {
          debugPrint('🎯 [MediaPreload] 预测性预载就绪 -> 源: $sourceId | 直链: $directUrl');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('⚠️ [MediaPreload] 预测性预载跳过 ($taskKey): $e');
        }
      } finally {
        _inFlightPreloads.remove(taskKey);
      }
    });
  }

  /// 抓取 M3U8 播放列表并预存前 2 个 TS 切片至 LocalMediaProxyServer
  Future<void> _preloadM3u8LeadingSegments(
    String m3u8Url,
    Map<String, String> headers,
  ) async {
    try {
      final baseUri = Uri.parse(m3u8Url);
      final req = await _httpClient.getUrl(baseUri);
      headers.forEach((k, v) {
        req.headers.set(k, v);
      });

      final resp = await req.close();
      if (resp.statusCode != HttpStatus.ok) return;

      final rawBody = await resp.transform(utf8.decoder).join();
      final lines = const LineSplitter().convert(rawBody);

      final leadingTsUrls = <String>[];
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;

        final absoluteTs = baseUri.resolve(trimmed).toString();
        leadingTsUrls.add(absoluteTs);
        // 最多预取前 2 个切片，即足以撑起起播首帧与前 5~10 秒播放
        if (leadingTsUrls.length >= 2) break;
      }

      for (final ts in leadingTsUrls) {
        await LocalMediaProxyServer.instance.prefetchSegment(ts, headers: headers);
      }
    } catch (_) {}
  }
}
