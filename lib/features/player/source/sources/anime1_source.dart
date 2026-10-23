import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// Anime1.me 专有视频源
/// 1:1 对齐 animaku (apps/server/src/lib/anime1.ts) 规范
class Anime1Source extends VideoSource {
  Anime1Source({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _site = 'https://anime1.me';
  static const String _api = 'https://v.anime1.me/api';

  @override
  String get id => 'anime1';

  @override
  String get name => 'Anime1';

  @override
  String get version => '1.3.0';

  @override
  String get description => 'MP4 · 动画全集带鉴权直连 (繁体原名优先)';

  @override
  bool get isDirect => true;

  Map<String, String> _headers([String? referer]) {
    final h = <String, String>{
      'User-Agent': _kDefaultUserAgent,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-TW,zh;q=0.9,en;q=0.8',
    };
    if (referer != null) h['Referer'] = referer;
    return h;
  }

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    try {
      final res = await _dio.get<String>(
        '$_site/?s=${Uri.encodeComponent(q)}',
        options: Options(
          headers: _headers('$_site/'),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final html = res.data ?? '';
      final seriesMap = <String, SourceSearchResult>{};
      final re = RegExp(r'''<h2[^>]*class="[^"]*entry-title[^"]*"[^>]*>\s*<a[^>]+href=["']([^"']+)["'][^>]*>([^<]+)</a>''', caseSensitive: false);
      final hits = <({String url, String title})>[];

      for (final m in re.allMatches(html)) {
        final epUrl = m.group(1)!;
        final title = m.group(2)!.trim();
        final uri = Uri.tryParse(epUrl);
        if (uri != null && RegExp(r'^/\d+/?$').hasMatch(uri.path)) {
          hits.add((url: epUrl, title: title));
        }
      }

      // 采样前 8 项解析分类页面 (对齐 animaku)
      await Future.wait(
        hits.take(8).map((hit) async {
          try {
            final pageRes = await _dio.get<String>(
              hit.url,
              options: Options(
                headers: _headers('$_site/'),
                sendTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 5),
              ),
            );
            final pHtml = pageRes.data ?? '';
            final catMatch = RegExp(r'''href=["']/?\?cat=(\d+)["']''', caseSensitive: false).firstMatch(pHtml);
            if (catMatch != null) {
              final catId = catMatch.group(1)!;
              final cleanTitle = hit.title.replaceAll(RegExp(r'\s*\[\d+\]\s*$'), '').trim();
              final seriesUrl = '$_site/?cat=$catId';
              if (!seriesMap.containsKey(seriesUrl)) {
                seriesMap[seriesUrl] = SourceSearchResult(name: cleanTitle, url: seriesUrl);
              }
            }
          } catch (_) {}
        }),
      );

      return seriesMap.values.toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async {
    var url = animeUrl.trim();
    if (RegExp(r'^\d+$').hasMatch(url)) {
      url = '$_site/?cat=$url';
    }

    final res = await _dio.get<String>(
      url,
      options: Options(
        headers: _headers('$_site/'),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final html = res.data ?? '';
    final episodes = <({int ep, String name, String url})>[];
    final re = RegExp(r'''<h2[^>]*class="[^"]*entry-title[^"]*"[^>]*>\s*<a[^>]+href=["']([^"']+)["'][^>]*>([^<]+)</a>''', caseSensitive: false);

    for (final m in re.allMatches(html)) {
      final epUrl = m.group(1)!;
      final epTitle = m.group(2)!.trim();
      final numMatch = RegExp(r'\[(\d+)\]').firstMatch(epTitle);
      final epNum = numMatch != null ? int.tryParse(numMatch.group(1)!) ?? 0 : 0;
      episodes.add((ep: epNum, name: epTitle, url: epUrl));
    }

    if (episodes.isEmpty) return [];

    episodes.sort((a, b) => a.ep.compareTo(b.ep));

    return [
      SourceChapterRoad(
        name: 'Anime1',
        episodes: episodes.map((e) => SourceEpisode(
              name: e.ep > 0 ? '第 ${e.ep} 话' : e.name,
              url: e.url,
            )).toList(),
      ),
    ];
  }

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    final res = await _dio.get<String>(
      episodeUrl,
      options: Options(
        headers: _headers('$_site/'),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final html = res.data ?? '';
    final apireqMatch = RegExp(r'''data-apireq=["']([^"']+)["']''', caseSensitive: false).firstMatch(html);
    if (apireqMatch == null) {
      throw Exception('Anime1 页面无 data-apireq（可能需登录或结构变更）');
    }
    final apireq = apireqMatch.group(1)!;

    // 特殊处理说明：
    // Anime1 页面中的 data-apireq 本身已经是 URL 编码格式（形如 %7B%22c...%7D），
    // 若在此处再次调用 Uri.encodeComponent 会导致字符被二次编码 (%257B)，触发服务端校验失败并报 403 Signature invalid。
    // 因此此处直接按原始编码串进行表单拼接 (data: 'd=$apireq')，杜绝二次转义。
    final apiRes = await _dio.post<dynamic>(
      _api,
      data: 'd=$apireq',
      options: Options(
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Origin': _site,
          'Referer': episodeUrl,
          'Accept': 'application/json, text/javascript, */*; q=0.01',
        },
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    final json = parseJsonMap(apiRes.data);
    if (json?['success'] == false) {
      throw Exception('Anime1 鉴权失败: ${json?['errors']}');
    }

    String mediaUrl = '';
    final s = json?['s'];
    if (s is List && s.isNotEmpty) {
      final first = s[0];
      mediaUrl = first is Map ? first['src']?.toString() ?? '' : first.toString();
    } else if (s is String) {
      mediaUrl = s;
    }

    if (mediaUrl.isEmpty) {
      throw Exception('Anime1 API 未返回有效播放地址');
    }

    if (mediaUrl.startsWith('//')) {
      mediaUrl = 'https:$mediaUrl';
    }

    // 提取会话 Cookie (对齐 animaku cookiesFromResponse 规范)
    final cookieList = <String>[];
    final rawCookies = apiRes.headers['set-cookie'] ?? apiRes.headers['Set-Cookie'] ?? [];
    for (final c in rawCookies) {
      final pair = c.split(';')[0].trim();
      if (pair.isNotEmpty) cookieList.add(pair);
    }

    return SourceResolveResult(
      url: mediaUrl,
      headers: {
        'User-Agent': _kDefaultUserAgent,
        'Referer': '$_site/',
        if (cookieList.isNotEmpty) 'Cookie': cookieList.join('; '),
      },
      format: 'mp4',
    );
  }
}
