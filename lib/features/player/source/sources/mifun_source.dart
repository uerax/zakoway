import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// MiFun (ios.mifun.org) 专有视频源
/// 1:1 对齐 animaku (apps/server/src/lib/mifun.ts) 规范
class MifunSource extends VideoSource {
  MifunSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _baseUrl = 'https://ios.mifun.org';
  static const String _resolverBaseUrl = 'https://data.m3u8.in/player';

  @override
  String get id => 'mifun';

  @override
  String get name => 'MiFun';

  @override
  String get version => '1.3.0';

  @override
  String get description => '1080P · 字节/百度 CDN 高速切片 (零代理原画)';

  @override
  bool get isDirect => true;

  Map<String, String> _headers([String? referer]) {
    final h = <String, String>{
      'User-Agent': _kDefaultUserAgent,
      'Accept': 'application/json, text/html, */*',
    };
    if (referer != null) h['Referer'] = referer;
    return h;
  }

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

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
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => SourceSearchResult(
                name: item['name']?.toString().trim() ?? '',
                url: '$_baseUrl/voddetail/${item['id']}.html',
                cover: item['pic']?.toString(),
              ))
          .where((s) => s.name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
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

    // 1. 提取 Tab 标签
    final tabLabels = <String>[];
    final tabRegex = RegExp(r'''class=["'][^"']*(?:hl-plays-from|hl-tabs-btn)[^"']*["'][^>]*>(.*?)</div>''', caseSensitive: false);
    final aRegex = RegExp(r'''<a[^>]*>(.*?)</a>''', caseSensitive: false);
    final tabMatch = tabRegex.firstMatch(html);
    if (tabMatch != null) {
      for (final a in aRegex.allMatches(tabMatch.group(1)!)) {
        final label = a.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (label.isNotEmpty) tabLabels.add(label);
      }
    }

    // 2. 提取分集列表
    final roads = <SourceChapterRoad>[];
    final boxRegex = RegExp(r'''<ul[^>]*class=["'][^"']*hl-plays-list[^"']*["'][^>]*>([\s\S]*?)</ul>''', caseSensitive: false);
    final boxMatches = boxRegex.allMatches(html);
    var roadIdx = 0;

    for (final bm in boxMatches) {
      final boxHtml = bm.group(1)!;
      final epRegex = RegExp(r'''<a[^>]*href=["'](/vodplay/[^"']+)["'][^>]*>(.*?)</a>''', caseSensitive: false);
      final episodes = <SourceEpisode>[];

      for (final em in epRegex.allMatches(boxHtml)) {
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
    final match = RegExp(r'player_aaaa\s*=\s*(\{[\s\S]*?\})\s*<').firstMatch(html) ??
        RegExp(r'player_aaaa\s*=\s*(\{[\s\S]*?\})').firstMatch(html);

    if (match == null) {
      throw Exception('未在 MiFun 播放页找到 player_aaaa 配置');
    }

    final player = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    final playerUrl = (player['url']?.toString() ?? '').trim();

    if (playerUrl.isEmpty) {
      throw Exception('MiFun 播放器配置 url 为空');
    }

    // 若已经直接是媒体流直链，直接返回 (对齐 animaku 规范)
    if (playerUrl.startsWith('http') && (playerUrl.contains('.mp4') || playerUrl.contains('.m3u8'))) {
      return SourceResolveResult(
        url: playerUrl,
        headers: {'User-Agent': _kDefaultUserAgent},
        format: playerUrl.contains('.m3u8') ? 'hls' : 'mp4',
      );
    }

    // 2. 调用 data.m3u8.in 解析网关提取动态 Sign
    final parseUrl = '$_resolverBaseUrl/?url=${Uri.encodeComponent(playerUrl)}';
    final parseRes = await _dio.get<String>(
      parseUrl,
      options: Options(
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Referer': absUrl,
        },
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final parseHtml = parseRes.data ?? '';
    final signMatch = RegExp(r'''const\s+Sign\s*=\s*["']([^"']+)["']''', caseSensitive: false).firstMatch(parseHtml);
    if (signMatch == null || signMatch.group(1) == null) {
      throw Exception('未在 MiFun 解析网关提取到动态 Sign');
    }
    final sign = signMatch.group(1)!.trim();

    // 3. 请求 api.php 获取抖音/百度 CDN 直链
    final apiUrl = '$_resolverBaseUrl/api.php?url=${Uri.encodeComponent(playerUrl)}&sign=${Uri.encodeComponent(sign)}';
    final apiRes = await _dio.get<dynamic>(
      apiUrl,
      options: Options(
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': parseUrl,
        },
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final apiData = parseJsonMap(apiRes.data);
    final directUrl = apiData?['url']?.toString().trim() ?? '';
    if (directUrl.isEmpty || !directUrl.startsWith('http')) {
      throw Exception('MiFun 网关直链解析失败: ${apiRes.data}');
    }

    return SourceResolveResult(
      url: directUrl,
      headers: {
        'User-Agent': _kDefaultUserAgent,
      },
      format: directUrl.contains('.m3u8') ? 'hls' : 'mp4',
    );
  }
}
