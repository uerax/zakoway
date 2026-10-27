import 'package:dio/dio.dart';
import 'package:zakoway/core/services/app_preferences.dart';
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

  /// 维护咕咕番用户会话。
  /// 优先使用内存与磁盘持久化 Cookie（有效期 30 天），彻底消灭每次起播 900ms 的登录延迟；
  /// 会话失效时清理本地持久化并强制重新登录刷新。
  Future<String> _ensureSession({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      if (_sessionCookie != null && _sessionCookie!.isNotEmpty) {
        return _sessionCookie!;
      }
      final diskCookie = AppPreferences.getGuguSessionCookie();
      if (diskCookie != null && diskCookie.isNotEmpty) {
        _sessionCookie = diskCookie;
        return _sessionCookie!;
      }
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
    await AppPreferences.setGuguSessionCookie(_sessionCookie);
    return _sessionCookie!;
  }

  /// 清理失效的 Cookie（内存与本地持久化双清）
  Future<void> _clearSession() async {
    _sessionCookie = null;
    await AppPreferences.setGuguSessionCookie(null);
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
    // 咕咕番源站线路划分为【国内线路】与【海外线路】两大标准通道：
    // 1. 国内线路：默认排在首位，内部按国内2线 (zy1080_01) > 国内1线 (vod_1080) > 海外1线 (zy1080_02) 顺位锁定；
    // 2. 海外线路：内部按海外1线 (zy1080_02) > 国内2线 (zy1080_01) > 国内1线 (vod_1080) 顺位锁定。
    // 目标源一旦按顺位锁定即刻直连，不做任何后台换源容灾，若源站挂了就如实报错。
    return [
      SourceChapterRoad(
        name: '国内线路',
        episodes: episodes.map((e) {
          final sep = e.url.contains('?') ? '&' : '?';
          return SourceEpisode(
            name: e.name,
            url: '${e.url}${sep}preferred_source=domestic',
          );
        }).toList(),
      ),
      SourceChapterRoad(
        name: '海外线路',
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
    final preferredSource = uri.queryParameters['preferred_source'] ??
        uri.queryParameters['line'] ??
        'domestic';

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
      final initialErr = data?['error']?.toString();
      if (initialErr != null && (initialErr.contains('登录') || initialErr.contains('会话'))) {
        throw DioException(
          requestOptions: RequestOptions(path: '$_baseUrl/api/playback'),
          response: Response(
            requestOptions: RequestOptions(path: '$_baseUrl/api/playback'),
            statusCode: 401,
            data: data,
          ),
        );
      }

      final currentSourceId = data?['sourceId']?.toString();
      final rawSources = (data?['sources'] as List?) ?? [];
      final sources = rawSources.whereType<Map<String, dynamic>>().toList();

      // 2. 线路顺位锁定（按用户规范：国内按 2线 -> 1线 -> 海外 顺位；海外按 海外 -> 2线 -> 1线 顺位）
      // 匹配出第一个存在的源即刻锁定目标源，不做任何后台换源容灾，挂了就如实报错
      final bool isOverseas = preferredSource == 'overseas' || preferredSource == 'overseas1';
      final order = isOverseas
          ? const ['zy1080_02', 'zy1080_01', 'vod_1080']
          : const ['zy1080_01', 'vod_1080', 'zy1080_02'];

      Map<String, dynamic> matchedSource = const {};
      for (final name in order) {
        matchedSource = sources.firstWhere(
          (s) => s['name'] == name,
          orElse: () => const <String, dynamic>{},
        );
        if (matchedSource.isNotEmpty) break;
      }

      if (matchedSource.isEmpty) {
        throw Exception('咕咕番该集源站未提供任何可用线路');
      }

      // 特殊处理说明：
      // 线路 ID 严格归一化为字符串比对，消除源站 JSON 数据中 int 与 String 混用引发的假性不一致二次请求
      final targetSourceId = matchedSource['id']?.toString();

      // 若锁定的目标源不同于默认下发的源，携带 &source 重新签发直链；
      // 若源站报错（如 503）如实抛出，不做任何后台换源容灾，挂了就明确显示挂了
      if (targetSourceId != null &&
          targetSourceId.isNotEmpty &&
          targetSourceId != currentSourceId) {
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

      final directUrl = (data?['url']?.toString() ?? '').trim();
      final err = data?['error']?.toString();
      if (err != null && (err.contains('登录') || err.contains('会话'))) {
        throw DioException(
          requestOptions: RequestOptions(path: '$_baseUrl/api/playback'),
          response: Response(
            requestOptions: RequestOptions(path: '$_baseUrl/api/playback'),
            statusCode: 401,
            data: data,
          ),
        );
      }

      if (directUrl.isEmpty || !directUrl.startsWith('http')) {
        throw Exception('咕咕番直链获取失败: ${err ?? '未返回有效播放地址'}');
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

    bool isSessionExpired(Object err) {
      if (err is DioException) {
        final code = err.response?.statusCode;
        if (code == 401 || code == 403) return true;

        final resData = err.response?.data;
        final errMsg = resData is Map
            ? (resData['error']?.toString() ?? '')
            : (resData?.toString() ?? '');
        if (errMsg.contains('登录') || errMsg.contains('会话')) return true;
      }
      final msg = err.toString();
      if (msg.contains('登录') || msg.contains('会话')) return true;

      return false;
    }

    var cookie = await _ensureSession();
    try {
      return await requestPlayback(cookie);
    } catch (e) {
      // 多维度判断会话是否失效 (实测源站涵盖 401/403 状态码以及包含“登录”或“会话”文案的报错)
      // 一旦判定失效，立即双清本地持久化与内存 Cookie，强制重新登录刷新会话并安全重试一次
      if (isSessionExpired(e)) {
        await _clearSession();
        cookie = await _ensureSession(forceRefresh: true);
        return await requestPlayback(cookie);
      }
      rethrow;
    }
  }
}
