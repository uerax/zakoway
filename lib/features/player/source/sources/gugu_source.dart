import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// 咕咕番 (gugu.fan) 专有视频源
/// 站点重构为 Next.js 15 App Router 架构，播放需携带 Session 认证换取腾讯云 COS 等国内高速直链
class GuguSource extends VideoSource {
  GuguSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _baseUrl = 'https://gugu.fan';
  static const String _defaultAccount = 'zakoway';
  static const String _defaultPassword = 'zakoway@pw';

  // 内存中缓存会话 Cookie，避免每次请求重复登录
  String? _sessionCookie;

  @override
  String get id => 'gugu';

  @override
  int get weight => 59;

  @override
  String get name => '咕咕番';

  @override
  String get version => '2.1.0';

  @override
  String get description => '1080P · 国内极速直链/多线路 (需账号鉴权)';

  @override
  bool get isDirect => false;

  Map<String, String> _headers([String? referer]) {
    final h = <String, String>{
      'User-Agent': _kDefaultUserAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    };
    if (referer != null) h['Referer'] = referer;
    return h;
  }

  /// 维护咕咕番用户会话。由于 Next.js 开启了 CSRF 校验，必须携带严格匹配的 Origin
  Future<String> _ensureSession({bool forceRefresh = false}) async {
    if (!forceRefresh && _sessionCookie != null && _sessionCookie!.isNotEmpty) {
      return _sessionCookie!;
    }

    final res = await _dio.post<dynamic>(
      '$_baseUrl/api/session/login',
      data: {
        'account': _defaultAccount,
        'password': _defaultPassword,
        'remember': true,
      },
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Origin': _baseUrl,
          'Referer': '$_baseUrl/login',
          'User-Agent': _kDefaultUserAgent,
        },
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final setCookieHeaders = res.headers['set-cookie'] ?? [];
    final cookies = <String>[];
    for (final sc in setCookieHeaders) {
      final firstPart = sc.split(';').first.trim();
      if (firstPart.startsWith('ggf_viewer_session=') || firstPart.startsWith('ggf_viewer_remember=')) {
        cookies.add(firstPart);
      }
    }

    if (cookies.isEmpty) {
      throw Exception('咕咕番登录未返回有效 session cookie');
    }

    _sessionCookie = cookies.join('; ');
    return _sessionCookie!;
  }

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return const [];

    try {
      final res = await _dio.get<String>(
        '$_baseUrl/search?q=${Uri.encodeComponent(q)}',
        options: Options(
          headers: _headers('$_baseUrl/'),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final html = res.data ?? '';
      final cardRegex = RegExp(
        r'<article[^>]*class=["\x27][^"\x27]*search-result-card[^"\x27]*["\x27][\s\S]*?<\/article>',
        caseSensitive: false,
      );

      final results = <SourceSearchResult>[];
      for (final match in cardRegex.allMatches(html)) {
        final cardHtml = match.group(0)!;

        // 提取动漫详情路径 /anime/{id}
        final linkMatch = RegExp(r'href=["\x27](\/anime\/\d+)["\x27]').firstMatch(cardHtml);
        if (linkMatch == null) continue;
        final path = linkMatch.group(1)!;

        // 提取标题
        final titleMatch = RegExp(r'<h2[^>]*>(.*?)<\/h2>').firstMatch(cardHtml);
        final name = titleMatch != null
            ? titleMatch.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim()
            : '';
        if (name.isEmpty) continue;

        // 提取封面（若无则置空，交由上层匹配 Bangumi 高清封面）
        final coverMatch = RegExp(r'<img[^>]+src=["\x27]([^"\x27]+)["\x27]').firstMatch(cardHtml);
        var cover = coverMatch?.group(1);
        if (cover != null && cover.startsWith('/')) {
          cover = '$_baseUrl$cover';
        }

        results.add(
          SourceSearchResult(
            name: name,
            url: '$_baseUrl$path',
            cover: cover,
          ),
        );
      }

      return results;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async {
    final res = await _dio.get<String>(
      animeUrl,
      options: Options(
        headers: _headers('$_baseUrl/'),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final html = res.data ?? '';

    final epRegex = RegExp(
      r'<article[^>]*class=["\x27][^"\x27]*detail-episode[^"\x27]*["\x27][\s\S]*?<\/article>',
      caseSensitive: false,
    );

    final episodes = <SourceEpisode>[];
    for (final match in epRegex.allMatches(html)) {
      final epHtml = match.group(0)!;
      final linkMatch = RegExp(r'href=["\x27](\/watch\/[^"\x27]+)["\x27]').firstMatch(epHtml);
      if (linkMatch == null) continue;

      final href = linkMatch.group(1)!;

      // 提取集数序号（如 "第 1 话" 或 "01"），去除 Next.js 注释 <!-- -->
      var epNumber = '';
      final spanMatch = RegExp(
        r'<span[^>]*class=["\x27][^"\x27]*text-primary[^"\x27]*["\x27][^>]*>([\s\S]*?)<\/span>',
        caseSensitive: false,
      ).firstMatch(epHtml);
      if (spanMatch != null) {
        epNumber = spanMatch
            .group(1)!
            .replaceAll(RegExp(r'<!--[\s\S]*?-->'), '')
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
      }

      // 提取副标题（如 "雄小鬼也有洞呢…／会长要让梅同学娶回家"）
      var subTitle = '';
      final h3Match = RegExp(r'<h3[^>]*>(.*?)<\/h3>').firstMatch(epHtml);
      if (h3Match != null) {
        subTitle = h3Match.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      }

      // 组装集数名称：确保始终包含集数序号（如 "第 1 话"），以便播放器集数匹配器能够精准对齐
      String name;
      if (epNumber.isNotEmpty && subTitle.isNotEmpty) {
        name = '$epNumber $subTitle';
      } else if (epNumber.isNotEmpty) {
        name = epNumber;
      } else if (subTitle.isNotEmpty) {
        name = subTitle;
      } else {
        name = '第 ${episodes.length + 1} 集';
      }

      episodes.add(
        SourceEpisode(
          name: name,
          url: href.startsWith('http') ? href : '$_baseUrl$href',
        ),
      );
    }

    // 备用兜底：若页面未按 article 组织，直接扫描所有的 /watch/ 链接
    if (episodes.isEmpty) {
      final fallbackMatches = RegExp(r'href=["\x27](\/watch\/[^"\x27]+\?episode=\d+)["\x27]').allMatches(html);
      final seen = <String>{};
      var idx = 1;
      for (final fm in fallbackMatches) {
        final href = fm.group(1)!;
        if (seen.add(href)) {
          episodes.add(
            SourceEpisode(
              name: '第 $idx 集',
              url: href.startsWith('http') ? href : '$_baseUrl$href',
            ),
          );
          idx++;
        }
      }
    }

    if (episodes.isEmpty) {
      return const [];
    }

    // 特殊处理说明：
    // 咕咕番源站的各集可用线路并不统一（例如第1集有国内1/海外1，第2集有国内2/海外1，第4集仅海外1）。
    // 若查遍所有集数会产生数十次网络请求导致页面极慢并触发源站封号；
    // 因此在章节层直接交付标准双线路（国内1线 / 海外1线），0 额外网络开销，
    // 并在 resolve 解析层针对每集实际拥有的源进行智能同类对齐与平滑兜底，确保全集 100% 顺畅播放且不断播。
    return [
      SourceChapterRoad(
        name: '国内1线',
        episodes: episodes.map((e) {
          final sep = e.url.contains('?') ? '&' : '?';
          return SourceEpisode(
            name: e.name,
            url: '${e.url}${sep}preferred_source=domestic',
          );
        }).toList(),
      ),
      SourceChapterRoad(
        name: '海外1线',
        episodes: episodes.map((e) {
          final sep = e.url.contains('?') ? '&' : '?';
          return SourceEpisode(
            name: e.name,
            url: '${e.url}${sep}preferred_source=overseas',
          );
        }).toList(),
      ),
    ];
  }

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    final uri = Uri.parse(episodeUrl);
    final segments = uri.pathSegments;
    final watchIdx = segments.indexOf('watch');
    String animeId = '';
    if (watchIdx != -1 && segments.length > watchIdx + 1) {
      animeId = segments[watchIdx + 1];
    }
    final episodeId = uri.queryParameters['episode'] ?? '';
    final preferredSource = uri.queryParameters['preferred_source'] ?? 'domestic';

    if (animeId.isEmpty || episodeId.isEmpty) {
      throw Exception('未能从咕咕番播放链接中解析出 animeId 与 episodeId: $episodeUrl');
    }

    Future<SourceResolveResult> requestPlayback(String cookie) async {
      // 1. 请求服务端获取该集支持的全部 sources 列表及默认直链
      final apiRes = await _dio.get<dynamic>(
        '$_baseUrl/api/playback?anime=$animeId&episode=$episodeId',
        options: Options(
          headers: {
            'User-Agent': _kDefaultUserAgent,
            'Origin': _baseUrl,
            'Referer': episodeUrl,
            'Cookie': cookie,
          },
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      var data = parseJsonMap(apiRes.data);
      var currentSourceId = data?['sourceId'];
      final rawSources = (data?['sources'] as List?) ?? [];
      final sources = rawSources.whereType<Map<String, dynamic>>().toList();

      // 2. 线路智能对齐与平滑兜底：
      // 保证用户选国内线时只要有国内 CDN (vod_1080 / zy1080_01) 就坚决不走境外慢速源；
      // 遇到该集无对应线路时（如第4集无国内线，或某集无海外线），自动使用当前集唯一可用源，杜绝断流或报错。
      if (sources.length > 1) {
        int? targetSourceId;

        if (preferredSource == 'domestic') {
          // 国内通道优先：先查 vod_1080 (国内1线)，无则查 zy1080_01 (国内2线)
          final hit = sources.firstWhere(
            (s) => s['name'] == 'vod_1080',
            orElse: () => sources.firstWhere(
              (s) => s['name'] == 'zy1080_01',
              orElse: () => <String, dynamic>{},
            ),
          );
          if (hit.isNotEmpty) {
            targetSourceId = hit['id'] is int ? hit['id'] as int : int.tryParse(hit['id']?.toString() ?? '');
          }
        } else {
          // 海外备用通道优先：优先查 zy1080_02 (海外1线)
          final hit = sources.firstWhere(
            (s) => s['name'] == 'zy1080_02',
            orElse: () => <String, dynamic>{},
          );
          if (hit.isNotEmpty) {
            targetSourceId = hit['id'] is int ? hit['id'] as int : int.tryParse(hit['id']?.toString() ?? '');
          }
        }

        // 若命中更符合偏好的源且不同于当前下发源，携带 &source 重新签发直链
        if (targetSourceId != null && targetSourceId != currentSourceId) {
          final targetRes = await _dio.get<dynamic>(
            '$_baseUrl/api/playback?anime=$animeId&episode=$episodeId&source=$targetSourceId',
            options: Options(
              headers: {
                'User-Agent': _kDefaultUserAgent,
                'Origin': _baseUrl,
                'Referer': episodeUrl,
                'Cookie': cookie,
              },
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          );
          final targetData = parseJsonMap(targetRes.data);
          if (targetData != null && targetData['url'] != null) {
            data = targetData;
          }
        }
      }

      final directUrl = (data?['url']?.toString() ?? '').trim();
      if (directUrl.isEmpty || !directUrl.startsWith('http')) {
        throw Exception('咕咕番直链获取失败: ${data?['error'] ?? '未返回有效播放地址'}');
      }

      final format = data?['format']?.toString().toLowerCase() == 'mp4' ? 'mp4' : 'hls';

      return SourceResolveResult(
        url: directUrl,
        headers: {
          'User-Agent': _kDefaultUserAgent,
        },
        format: format,
      );
    }

    var cookie = await _ensureSession();
    try {
      return await requestPlayback(cookie);
    } on DioException catch (e) {
      // 若出现 401 Unauthorized 说明服务端会话已过期，强制重新登录刷新会话并重试一次
      if (e.response?.statusCode == 401) {
        cookie = await _ensureSession(forceRefresh: true);
        return await requestPlayback(cookie);
      }
      rethrow;
    }
  }
}
