import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// OmoFun / 211dm (cn.211dm.com) 专有视频源
/// 1:1 对齐 animaku (apps/server/src/lib/omofun.ts) 规范
class OmofunSource extends VideoSource {
  OmofunSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _baseUrl = 'https://cn.211dm.com';

  @override
  String get id => 'omofun';

  @override
  String get name => 'OmoFun';

  @override
  String get version => '1.3.0';

  @override
  String get description => '1080P · 备用解析线路 (原名优先)';

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

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

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
      final itemRegex = RegExp(r'''<a[^>]*href=["'](/anime/\d+\.html)["'][^>]*title=["']([^"']+)["']''', caseSensitive: false);
      final items = <SourceSearchResult>[];
      final seen = <String>{};

      for (final m in itemRegex.allMatches(html)) {
        final path = m.group(1)!;
        final name = m.group(2)!.trim();
        final detailUrl = '$_baseUrl$path';
        if (name.isNotEmpty && seen.add(detailUrl)) {
          items.add(SourceSearchResult(name: name, url: detailUrl));
        }
      }

      return items;
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
    final roads = <SourceChapterRoad>[];
    final boxRegex = RegExp(r'''<ul[^>]*class=["'][^"']*play-list-content[^"']*["'][^>]*>([\s\S]*?)</ul>''', caseSensitive: false);
    final boxMatches = boxRegex.allMatches(html);
    var roadIdx = 0;

    for (final bm in boxMatches) {
      final boxHtml = bm.group(1)!;
      final epRegex = RegExp(r'''<a[^>]*href=["'](/play/[^"']+)["'][^>]*>(.*?)</a>''', caseSensitive: false);
      final episodes = <SourceEpisode>[];

      for (final em in epRegex.allMatches(boxHtml)) {
        final href = em.group(1)!;
        final name = em.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (href.isNotEmpty && name.isNotEmpty) {
          episodes.add(SourceEpisode(
            name: name,
            url: href.startsWith('http') ? href : '$_baseUrl$href',
          ));
        }
      }

      if (episodes.isNotEmpty) {
        roads.add(SourceChapterRoad(name: '线路 ${roadIdx + 1}', episodes: episodes));
        roadIdx++;
      }
    }

    return roads;
  }

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    final res = await _dio.get<String>(
      episodeUrl,
      options: Options(
        headers: _headers('$_baseUrl/'),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final html = res.data ?? '';
    final match = RegExp(r'var\s+player_aaaa\s*=\s*(\{[\s\S]*?\})\s*<').firstMatch(html) ??
        RegExp(r'player_aaaa\s*=\s*(\{[\s\S]*?\})').firstMatch(html);

    if (match == null) {
      throw Exception('未在 OmoFun 播放页找到 player_aaaa 配置');
    }

    final player = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    var directUrl = (player['url']?.toString() ?? '').trim();
    final encrypt = player['encrypt'] ?? 0;

    if (encrypt == 1) {
      try {
        directUrl = Uri.decodeQueryComponent(directUrl);
      } catch (_) {}
    } else if (encrypt == 2) {
      try {
        final bytes = base64Decode(directUrl);
        final decoded = utf8.decode(bytes, allowMalformed: true);
        try {
          directUrl = Uri.decodeQueryComponent(decoded);
        } catch (_) {
          directUrl = decoded;
        }
      } catch (_) {}
    }

    if (!directUrl.startsWith('http')) {
      throw Exception('OmoFun 直链解析失败: $directUrl');
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
