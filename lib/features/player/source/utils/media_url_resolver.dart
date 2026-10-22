import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// 全局通用的媒体直链 302 重定向展开与请求头规范化解析器
class MediaUrlResolver {
  MediaUrlResolver._();

  static final Dio _internalDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(milliseconds: 1500),
      receiveTimeout: const Duration(milliseconds: 1500),
      sendTimeout: const Duration(milliseconds: 1500),
    ),
  );

  /// 展开 301/302/303/307/308 重定向，并对齐 Referer 与 Host 头
  ///
  /// 特殊处理说明：
  /// 1. 嗅探或原生解析捕获的直链很多是跳转跳板（如 apn.moedot.net），播放内核直接起播容易因跨域丢 Referer 或握手超时失败；
  /// 2. 本方法通过轻量 HEAD 预检（通常 <100ms）提前跟随重定向，提取最终落地真实媒体 URL；
  /// 3. 若未发生重定向或请求异常（如服务端禁用 HEAD 或超时），零风险平滑降级，原样返回入参；
  /// 4. 针对沃派网盘 (pan.wo.cn) 节点，自动对齐 'https://pan.wo.cn/' Referer，并在 Windows/Android 环境下解析绑定纯净 IPv4 绕开握手黑洞。
  static Future<SourceResolveResult> resolveRedirects(
    SourceResolveResult result, {
    Duration timeout = const Duration(milliseconds: 1500),
    Dio? dioClient,
  }) async {
    final rawUrl = result.url.trim();
    if (rawUrl.isEmpty) return result;

    final client = dioClient ?? _internalDio;
    var currentUrl = rawUrl;
    final headers = Map<String, String>.from(result.headers);
    final ua = headers['User-Agent'] ?? headers['user-agent'] ?? _kDefaultUserAgent;
    headers['User-Agent'] = ua;

    try {
      var hops = 0;
      const maxHops = 5;

      while (hops < maxHops) {
        hops++;
        final currentReferer = headers['Referer'] ?? headers['referer'] ?? '';

        Response<void>? headRes;
        try {
          headRes = await client.get<void>(
            currentUrl,
            options: Options(
              method: 'HEAD',
              followRedirects: false,
              validateStatus: (s) =>
                  s != null &&
                  (s == 301 ||
                      s == 302 ||
                      s == 303 ||
                      s == 307 ||
                      s == 308 ||
                      s < 400),
              headers: {
                'User-Agent': ua,
                if (currentReferer.isNotEmpty) 'Referer': currentReferer,
              },
            ),
          ).timeout(timeout);
        } catch (e) {
          // 当前单次预检失败（如目标节点不支持 HEAD、海外连接超时或 TLS 阻断），终止后续递归，保留当前可用地址
          debugPrint('[MediaUrlResolver] 预检请求中断/超时 ($currentUrl): $e');
          break;
        }

        final status = headRes.statusCode ?? 200;
        final isRedirect = status == 301 ||
            status == 302 ||
            status == 303 ||
            status == 307 ||
            status == 308;

        if (!isRedirect) {
          // 不再发生重定向，已到达最终媒体直链
          break;
        }

        final location = headRes.headers.value('location');
        if (location == null || location.trim().isEmpty) {
          break;
        }

        final nextUrl = location.startsWith('http')
            ? location.trim()
            : Uri.parse(currentUrl).resolve(location.trim()).toString();

        debugPrint('[MediaUrlResolver] 探测到 302 重定向: $currentUrl -> $nextUrl');
        currentUrl = nextUrl;

        // 特殊处理说明：沃派网盘必须携带官方规范 Referer，且跳转后即为最终下载端口，无需二次探测
        if (currentUrl.contains('pan.wo.cn') ||
            currentUrl.contains('moedot.net') ||
            currentUrl.contains('apn.moedot.net')) {
          headers['Referer'] = 'https://pan.wo.cn/';
          break;
        }
      }

      // 针对沃派网盘在 Windows/Android 环境下的 IPv4 绑定优化 (规避 30443 端口 TLS EOF 握手黑洞)
      final uri = Uri.tryParse(currentUrl);
      if (uri != null &&
          uri.host.contains('pan.wo.cn') &&
          !kIsWeb &&
          (Platform.isWindows || Platform.isAndroid)) {
        try {
          final ipv4s = await InternetAddress.lookup(
            uri.host,
            type: InternetAddressType.IPv4,
          ).timeout(const Duration(milliseconds: 1500), onTimeout: () => []);

          if (ipv4s.isNotEmpty) {
            final targetIp = ipv4s[DateTime.now().second % ipv4s.length].address;
            final hostHeader = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
            final optimizedUri = uri.replace(host: targetIp);
            headers['Host'] = hostHeader;
            currentUrl = optimizedUri.toString();
            debugPrint('[MediaUrlResolver] 沃云节点绑定纯净 IPv4: $currentUrl');
          }
        } catch (_) {}
      }

      final lower = currentUrl.toLowerCase();
      final finalFormat = lower.contains('.m3u8')
          ? 'hls'
          : (lower.contains('.mp4') ? 'mp4' : result.format);

      return SourceResolveResult(
        url: currentUrl,
        format: finalFormat,
        headers: headers,
      );
    } catch (e) {
      debugPrint('[MediaUrlResolver] 预检异常，平滑回退: $e');
      return result;
    }
  }
}
