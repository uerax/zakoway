import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// TvTFun (tvtfun.net) 专有视频源
/// 1:1 对齐 animaku (apps/server/src/lib/tvtfun.ts) 规范
class TvTFunSource extends VideoSource {
  TvTFunSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _baseUrl = 'https://www.tvtfun.net';

  @override
  String get id => 'tvtfun';

  @override
  String get name => 'TvTFun';

  @override
  String get version => '1.3.0';

  @override
  String get description => '1080P · 官方 BytePlus/Akamai 全球 CDN 极速主线';

  int _getSourcePriority(String name) {
    final n = name.trim();
    // 特殊处理说明：
    // 线路 A 指向字节跳动 BytePlus / Akamai CDN 全球直连节点，全球无地域限制且带宽高；
    // 线路 D 指向第三方切片源，对境外或代理 IP 存在严格的地域白名单封锁（返回 403 The region has been denied）；
    // 因此调整优先级：线路 A 设为最高优，规避播放器在非大陆特定网络下遭遇 403 阻断。
    if (RegExp(r'线路\s*A\b', caseSensitive: false).hasMatch(n) || n.contains('线路A')) return 100;
    if (RegExp(r'线路\s*B\b', caseSensitive: false).hasMatch(n) || n.contains('线路B')) return 80;
    if (RegExp(r'线路\s*C\b', caseSensitive: false).hasMatch(n) || n.contains('线路C')) return 70;
    if (RegExp(r'线路\s*D\b', caseSensitive: false).hasMatch(n) || n.contains('线路D')) return 60;
    return 50;
  }

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    try {
      final res = await _dio.get<dynamic>(
        '$_baseUrl/api/videos/search?q=${Uri.encodeComponent(q)}',
        options: Options(
          headers: {
            'User-Agent': _kDefaultUserAgent,
            'Accept': 'application/json, text/plain, */*',
            'Referer': '$_baseUrl/videos',
          },
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final resData = parseJsonMap(res.data);
      final videos = (resData?['data']?['videos'] as List?) ?? [];
      return videos
          .whereType<Map<String, dynamic>>()
          .map((v) => SourceSearchResult(
                name: v['name']?.toString().trim() ?? '番剧 #${v['id']}',
                url: '$_baseUrl/video/${v['id']}?slug=${Uri.encodeComponent(v['slug']?.toString() ?? v['id'].toString())}',
                cover: v['pic']?.toString() ?? v['picThumb']?.toString(),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async {
    final animeUri = Uri.tryParse(animeUrl);
    final match = RegExp(r'/video/([^/?#]+)').firstMatch(animeUrl);
    if (match == null) throw Exception('无法解析 TvTFun 视频 ID: $animeUrl');
    final videoId = match.group(1)!;

    final res = await _dio.get<dynamic>(
      '$_baseUrl/api/videos/$videoId',
      options: Options(
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Accept': 'application/json, text/plain, */*',
          'Referer': animeUrl,
        },
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final resData = parseJsonMap(res.data);
    final videoData = resData?['data'] as Map<String, dynamic>?;
    final playSources = (videoData?['playSources'] as List?) ?? [];
    if (playSources.isEmpty) return [];

    // 特殊处理说明：
    // TvTFun 网页前端 Next.js 路由规范为 /video/[slug]/play（其中 [slug] 为 Bangumi ID 等业务别名），
    // 若路由传入后端数据库内部 CUID（形如 cmp2wp...）会触发 Next.js 动态路由 404 错误。
    // 在此提取真实 slug 并透传给分集 URL 参数，以便 resolve 阶段顺畅加载鉴权播放页。
    final rawSlug = animeUri?.queryParameters['slug'] ?? videoData?['slug']?.toString() ?? videoId;
    final slug = rawSlug.trim().isNotEmpty ? rawSlug.trim() : videoId;

    // 保留原始 source 索引并置顶国内高优线路 A (BytePlus/Akamai 全球 CDN)
    final indexed = playSources.asMap().entries.map((e) => (src: e.value as Map<String, dynamic>, originalIdx: e.key)).toList();

    indexed.sort((a, b) {
      final pA = _getSourcePriority(a.src['name']?.toString() ?? '');
      final pB = _getSourcePriority(b.src['name']?.toString() ?? '');
      if (pA != pB) return pB - pA;
      return a.originalIdx - b.originalIdx;
    });

    final roads = <SourceChapterRoad>[];

    for (var i = 0; i < indexed.length; i++) {
      final item = indexed[i];
      final rawEps = (item.src['episodes'] as List?) ?? [];
      if (rawEps.isEmpty) continue;

      final sortedEps = rawEps.whereType<Map<String, dynamic>>().toList()
        ..sort((a, b) => ((a['sort'] as num?) ?? 0).compareTo((b['sort'] as num?) ?? 0));

      final roadName = (item.src['name']?.toString() ?? '线路 ${String.fromCharCode(65 + i)}').trim();

      final episodes = sortedEps.map((ep) {
        final epId = ep['id'];
        final epSort = ep['sort'] ?? 0;
        final epName = ep['name']?.toString().trim();
        return SourceEpisode(
          name: (epName != null && epName.isNotEmpty) ? epName : '第 ${epSort + 1} 话',
          url: '$_baseUrl/video/$videoId/play?episodeId=$epId&videoId=$videoId&slug=${Uri.encodeComponent(slug)}&source=${item.originalIdx}&epSort=$epSort',
        );
      }).toList();

      roads.add(SourceChapterRoad(name: roadName, episodes: episodes));
    }

    return roads;
  }

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    final uri = Uri.parse(episodeUrl);
    final episodeId = uri.queryParameters['episodeId'];
    final sourceIndex = uri.queryParameters['source'] ?? '0';
    final epSort = uri.queryParameters['epSort'] ?? '0';
    final videoIdMatch = RegExp(r'/video/([^/?#]+)').firstMatch(episodeUrl);

    // 特殊处理说明：
    // 优先采用 query 中的真实 slug（业务别名/Bangumi ID），若缺失再回退到路径提取，
    // 保证请求的前端播放页路由能正确命中 Next.js 页面并返回 200 与 tvt-pt 会话 cookie。
    final slug = uri.queryParameters['slug'] ?? videoIdMatch?.group(1) ?? '';

    if (episodeId == null || episodeId.isEmpty) {
      throw Exception('TvTFun 缺少 episodeId: $episodeUrl');
    }

    // 1. 请求播放页获取单次 tvt-pt 会话 cookie (对齐 animaku fetchFreshPlayCookie 规范)
    final playPageUrl = '$_baseUrl/video/$slug/play?source=$sourceIndex&episode=$epSort';
    final pageRes = await _dio.get<String>(
      playPageUrl,
      options: Options(
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        },
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    String cookieHeader = '';
    final rawCookies = pageRes.headers['set-cookie'] ?? pageRes.headers['Set-Cookie'] ?? [];
    for (final c in rawCookies) {
      final match = RegExp(r'tvt-pt=([^;]+)').firstMatch(c);
      if (match != null) {
        cookieHeader = 'tvt-pt=${match.group(1)}';
        break;
      }
    }

    // 2. 调接口解析真实地址 (带 X-Play-Ctx 令牌)
    final ctx = base64Encode(utf8.encode(jsonEncode({'f': 60, 'v': 1, 'w': 1920, 'hgt': 1080, 'p': 1})));
    final resolveRes = await _dio.get<dynamic>(
      '$_baseUrl/api/videos/resolve-play-url?episodeId=${Uri.encodeComponent(episodeId)}',
      options: Options(
        headers: {
          'User-Agent': _kDefaultUserAgent,
          if (cookieHeader.isNotEmpty) 'Cookie': cookieHeader,
          'X-Play-Ctx': ctx,
          'Referer': playPageUrl,
        },
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final resData = parseJsonMap(resolveRes.data);
    final playData = resData?['data'] as Map<String, dynamic>?;
    final directUrl = playData?['url']?.toString().trim() ?? '';
    if (directUrl.isEmpty || playData?['type'] == 'unavailable') {
      throw Exception('TvTFun 直链解析失败: ${resData?['error'] ?? '播放源不可用'}');
    }

    return SourceResolveResult(
      url: directUrl,
      headers: {
        'Referer': '$_baseUrl/',
        'User-Agent': _kDefaultUserAgent,
      },
      format: directUrl.contains('.m3u8') ? 'hls' : 'mp4',
    );
  }
}
