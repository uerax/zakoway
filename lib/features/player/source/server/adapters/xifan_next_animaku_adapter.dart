import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'animaku_source_adapter.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// 稀饭Next (xifan-next) Animaku 服务端模式专属适配器
///
/// 特殊处理说明：
/// 1. 稀饭官方源站具有严格的 Referer 防盗链校验：
///    - 沃派网盘线路（含 pan.wo.cn、moedot.net、apn.moedot.net）必须携带 'https://pan.wo.cn/'；
///    - 官方普通直链必须携带 'https://next.xifanacg.com/'；
/// 2. 沃派网盘直链经过 302 跳转至 pan.wo.cn 节点时，国内部分 IPv6/宽带环境在 30443 端口存在 TLS 握手立即断开异常（-0x4e / EOF），
///    此处直接照搬本地原生适配器的优化逻辑：通过轻量 HEAD 预检展开 302 落地直链，并解析锁定纯净 IPv4 地址绑定 Host，
///    从根源上消除播放内核起播时的握手黑洞与多次重试延迟；
/// 3. 严格遵循原则：本适配器仅对最终播放直链做清洗与优化，绝不干涉搜索与选集流程。
class XifanNextAnimakuAdapter extends AnimakuSourceAdapter {
  XifanNextAnimakuAdapter({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  String get sourceId => 'xifan-next';

  void _log(String message) {
    debugPrint('[XifanAnimakuAdapter] $message');
  }

  @override
  Future<SourceResolveResult> transformResolve(
    SourceResolveResult result, {
    required String episodeUrl,
  }) async {
    final playUrl = result.url.trim();
    if (playUrl.isEmpty) return result;

    final isWoPan = playUrl.contains('pan.wo.cn') ||
        playUrl.contains('moedot.net') ||
        playUrl.contains('apn.moedot.net');

    // 沃派网盘直链遵循官方规范携带 'https://pan.wo.cn/'，非沃派普通直链规范携带官方前端来源 'https://next.xifanacg.com/'
    final referer = isWoPan ? 'https://pan.wo.cn/' : 'https://next.xifanacg.com/';
    final format = playUrl.contains('.m3u8') ? 'hls' : 'mp4';

    // 针对沃派网盘 302 节点进行轻量展开与纯净 IPv4 锁定
    final optimized = await _optimizeMediaUrl(playUrl, referer);

    _log('直链清洗完成: url=${optimized.url}, 格式: $format, Referer: ${optimized.headers['Referer'] ?? "none"}');

    // 合并原有 headers，以优化后的 UA、Referer 及 Host 为最高优先级
    final mergedHeaders = Map<String, String>.from(result.headers)
      ..addAll(optimized.headers);

    return SourceResolveResult(
      url: optimized.url,
      headers: mergedHeaders,
      format: format,
    );
  }

  /// 沃派网盘 (pan.wo.cn / moedot.net) 302 预检展开与纯净 IPv4 锁定（直接对齐本地原生处理逻辑）
  Future<({String url, Map<String, String> headers})> _optimizeMediaUrl(
    String rawUrl,
    String referer,
  ) async {
    final isWoPan = rawUrl.contains('pan.wo.cn') ||
        rawUrl.contains('moedot.net') ||
        rawUrl.contains('apn.moedot.net');

    if (!isWoPan || rawUrl.contains('.m3u8')) {
      return (
        url: rawUrl,
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Referer': referer,
        },
      );
    }

    try {
      // 1. 通过轻量 HEAD 预检提前跟随 302 探测最终真实直链，耗时仅几十毫秒
      final headRes = await _dio.get<void>(
        rawUrl,
        options: Options(
          method: 'HEAD',
          followRedirects: false,
          validateStatus: (s) => s != null && (s == 301 || s == 302 || s < 400),
          headers: {
            'User-Agent': _kDefaultUserAgent,
            'Referer': referer,
          },
          sendTimeout: const Duration(seconds: 2),
          receiveTimeout: const Duration(seconds: 2),
        ),
      );

      var finalUrl = rawUrl;
      final location = headRes.headers.value('location');
      if (location != null && location.isNotEmpty) {
        finalUrl = location.startsWith('http')
            ? location
            : Uri.parse(rawUrl).resolve(location).toString();
        _log('HEAD 预检解析出 302 真实下载直链: $finalUrl');
      }

      final uri = Uri.parse(finalUrl);
      final host = uri.host;

      // 2. 针对存在节点握手黑洞的 pan.wo.cn 节点，主动解析并绑定纯净 IPv4 地址
      if (host.contains('pan.wo.cn')) {
        final ipv4s = await InternetAddress.lookup(
          host,
          type: InternetAddressType.IPv4,
        ).timeout(const Duration(milliseconds: 1500), onTimeout: () => []);

        if (ipv4s.isNotEmpty) {
          // 采用轮询分散策略避免单点瞬时故障
          final targetIp = ipv4s[DateTime.now().second % ipv4s.length].address;
          final hostHeader = uri.hasPort ? '$host:${uri.port}' : host;
          final optimizedUri = uri.replace(host: targetIp);
          _log('成功将沃云域名 $host 锁定为 IPv4 节点 $targetIp: $optimizedUri');

          return (
            url: optimizedUri.toString(),
            headers: {
              'User-Agent': _kDefaultUserAgent,
              'Referer': referer,
              'Host': hostHeader,
            },
          );
        }
      }

      return (
        url: finalUrl,
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Referer': referer,
        },
      );
    } catch (e) {
      _log('直链预检优化异常，平滑降级使用原地址: $e');
      return (
        url: rawUrl,
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Referer': referer,
        },
      );
    }
  }
}
