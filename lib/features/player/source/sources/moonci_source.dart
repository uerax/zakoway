import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';
import 'xifan_next_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// 月之祠 (moonci.com) 专有视频源
/// 1:1 对齐 animaku (apps/server/src/lib/moonci.ts) 规范
class MoonciSource extends VideoSource {
  MoonciSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _baseUrl = 'https://www.moonci.com';

  @override
  String get id => 'moonci';

  @override
  String get name => '月之祠';

  @override
  String get version => '1.4.0';

  @override
  String get description => '1080P · 备用多线路直连 (双轨极速解析)';

  Map<String, String> _headers([String? referer]) {
    final h = <String, String>{
      'User-Agent': _kDefaultUserAgent,
      'Accept': 'application/json, text/html, application/xhtml+xml, */*',
    };
    if (referer != null) h['Referer'] = referer;
    return h;
  }

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    final items = <SourceSearchResult>[];
    final seenUrls = <String>{};

    // 1. Primary: suggest JSON API
    try {
      final res = await _dio.get<dynamic>(
        '$_baseUrl/index.php/ajax/suggest?mid=1&wd=${Uri.encodeComponent(q)}',
        options: Options(
          headers: _headers('$_baseUrl/'),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final data = parseJsonMap(res.data);
      final list = (data?['list'] as List?) ?? [];
      for (final it in list.whereType<Map<String, dynamic>>()) {
        final id = it['id']?.toString() ?? '';
        final name = it['name']?.toString().trim() ?? '';
        if (id.isEmpty || name.isEmpty) continue;
        final detailUrl = '$_baseUrl/anime/$id.html';
        if (seenUrls.add(detailUrl)) {
          items.add(SourceSearchResult(
            name: name,
            url: detailUrl,
            cover: it['pic']?.toString(),
          ));
        }
      }
    } catch (_) {}

    if (items.isNotEmpty) return items;

    // 2. Fallback: Web HTML Search
    try {
      final res = await _dio.get<String>(
        '$_baseUrl/search/-------------.html?wd=${Uri.encodeComponent(q)}',
        options: Options(
          headers: _headers('$_baseUrl/'),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final html = res.data ?? '';
      final itemRegex = RegExp(r'''href=["'](/anime/\d+\.html)["'][^>]*title=["']([^"']+)["']''', caseSensitive: false);
      for (final m in itemRegex.allMatches(html)) {
        final path = m.group(1)!;
        final title = m.group(2)!.trim();
        final detailUrl = '$_baseUrl$path';
        if (title.isNotEmpty && seenUrls.add(detailUrl)) {
          items.add(SourceSearchResult(name: title, url: detailUrl));
        }
      }
    } catch (_) {}

    return items;
  }

  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async {
    final match = RegExp(r'/anime/(\d+)').firstMatch(animeUrl);
    if (match == null) throw Exception('无法从链接提取 Moonci 番剧 ID: $animeUrl');
    final animeId = match.group(1)!;

    final detailUrl = '$_baseUrl/anime/$animeId.html';
    final res = await _dio.get<String>(
      detailUrl,
      options: Options(
        headers: _headers('$_baseUrl/'),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final html = res.data ?? '';

    // 1. 提取多线路 Tab 标签 (对齐 animaku 规范)
    final tabLabels = <String>[];
    final tabRegex = RegExp(
      r'''<span[^>]*class=["'][^"']*hl-from-[^"']*["'][^>]*>(.*?)</span>''',
      caseSensitive: false,
    );
    for (final tm in tabRegex.allMatches(html)) {
      final raw = tm.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (raw.isNotEmpty) tabLabels.add(raw);
    }

    // 2. 提取分集列表
    final listRegex = RegExp(r'''<ul[^>]*class=["'][^"']*hl-plays-list[^"']*["'][^>]*>([\s\S]*?)</ul>''', caseSensitive: false);
    final roads = <SourceChapterRoad>[];
    var roadIdx = 0;

    for (final lm in listRegex.allMatches(html)) {
      final listHtml = lm.group(1)!;
      final epRegex = RegExp(r'''<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>''', caseSensitive: false);
      final episodes = <SourceEpisode>[];

      for (final em in epRegex.allMatches(listHtml)) {
        final href = em.group(1)!;
        final name = em.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (href.isNotEmpty && !href.startsWith('javascript:') && name.isNotEmpty) {
          final absUrl = href.startsWith('http') ? href : '$_baseUrl$href';
          episodes.add(SourceEpisode(name: name, url: absUrl));
        }
      }

      if (episodes.isNotEmpty) {
        final roadName = roadIdx < tabLabels.length ? tabLabels[roadIdx] : '线路 ${roadIdx + 1}';
        roads.add(SourceChapterRoad(name: roadName, episodes: episodes));
        roadIdx++;
      }
    }

    return roads;
  }

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    final absUrl = episodeUrl.startsWith('http') ? episodeUrl : '$_baseUrl$episodeUrl';
    final res = await _dio.get<String>(
      absUrl,
      options: Options(
        headers: _headers('$_baseUrl/'),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final html = res.data ?? '';
    final match = RegExp(r'player_aaaa\s*=\s*(\{[\s\S]*?\})\s*</script>', caseSensitive: false).firstMatch(html) ??
        RegExp(r'player_aaaa\s*=\s*(\{[\s\S]*?\})\s*<', caseSensitive: false).firstMatch(html) ??
        RegExp(r'player_aaaa\s*=\s*(\{[\s\S]*?\})', caseSensitive: false).firstMatch(html);

    if (match == null) {
      throw Exception('未在月之祠播放页找到 player_aaaa 配置: $absUrl');
    }

    final player = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    var rawUrl = (player['url']?.toString() ?? '').trim();
    final encrypt = player['encrypt'] ?? 0;

    if (encrypt == 1) {
      rawUrl = jsUnescape(rawUrl);
    } else if (encrypt == 2) {
      try {
        final bytes = base64Decode(rawUrl);
        final decoded = utf8.decode(bytes, allowMalformed: true);
        rawUrl = jsUnescape(decoded);
      } catch (_) {
        rawUrl = jsUnescape(rawUrl);
      }
    } else if (encrypt == 3) {
      try {
        rawUrl = Uri.decodeComponent(rawUrl);
      } catch (_) {}
    }

    rawUrl = rawUrl.trim();
    if (rawUrl.startsWith('//')) {
      rawUrl = 'https:$rawUrl';
    }

    if (!rawUrl.startsWith('http')) {
      throw Exception('月之祠直链格式不正确: $rawUrl');
    }

    // 特殊处理说明：
    // 月之祠近期底层改版，站内视频流全部封装嵌入为稀饭动漫（next.xifanacg.com）播放页面链接。
    // 若识别到为该类嵌入页面，自动委托 XifanNextSource 进行二次解析，获取真正的 1080P 媒体流直链，
    // 实现 100% 自愈起播，彻底杜绝播放器将 HTML 网页误当成视频流导致解复用失败。
    if (rawUrl.contains('next.xifanacg.com') || rawUrl.contains('xifanacg')) {
      return XifanNextSource(dio: _dio).resolve(rawUrl);
    }

    // 原生媒体流直链兜底 (moedot / unicom 节点原生播放)
    return SourceResolveResult(
      url: rawUrl,
      headers: {
        'User-Agent': _kDefaultUserAgent,
      },
      format: rawUrl.contains('.m3u8') ? 'hls' : 'mp4',
    );
  }
}
