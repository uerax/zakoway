import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// girigiri愛動漫 (ani.girigirilove.com) 专有视频源
/// 1:1 对齐 animaku (apps/server/src/lib/girigiri.ts) 规范
class GirigiriSource extends VideoSource {
  GirigiriSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _baseUrl = 'https://ani.girigirilove.com';

  @override
  String get id => 'girigiri';

  @override
  String get name => 'girigiri';

  @override
  String get version => '1.3.0';

  @override
  String get description => '1080P · Cloudflare CDN 原画直连 (老番优先)';

  @override
  bool get isDirect => false;

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    try {
      final res = await _dio.get<Map<String, dynamic>>(
        '$_baseUrl/index.php/ajax/suggest?mid=1&wd=${Uri.encodeComponent(q)}',
        options: Options(
          headers: {
            'User-Agent': _kDefaultUserAgent,
            'Accept': 'application/json, text/plain, */*',
            'Referer': '$_baseUrl/',
          },
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final list = (res.data?['list'] as List?) ?? [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => SourceSearchResult(
                name: item['name']?.toString().trim() ?? '',
                url: '$_baseUrl/GV${item['id']}/',
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
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Referer': '$_baseUrl/',
        },
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final html = res.data ?? '';
    final roads = <SourceChapterRoad>[];

    final boxRegex = RegExp(
      r'''<div[^>]*class=["'][^"']*(?:anthology-list-box|module-play-list)[^"']*["'][^>]*>([\s\S]*?)</div>''',
      caseSensitive: false,
    );

    final boxMatches = boxRegex.allMatches(html);
    var roadIdx = 0;

    for (final bm in boxMatches) {
      final boxHtml = bm.group(1)!;
      final epRegex = RegExp(r'''<a[^>]*href=["'](/playGV[^"']+)["'][^>]*>(.*?)</a>''', caseSensitive: false);
      final epMatches = epRegex.allMatches(boxHtml);
      final episodes = <SourceEpisode>[];

      for (final em in epMatches) {
        final href = em.group(1)!;
        final rawName = em.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        final name = RegExp(r'^\d+$').hasMatch(rawName) ? '第${rawName.padLeft(2, '0')}集' : rawName;
        episodes.add(SourceEpisode(
          name: name,
          url: '$_baseUrl$href',
        ));
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
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Referer': '$_baseUrl/',
        },
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final html = res.data ?? '';
    final match = RegExp(r'var\s+player_aaaa\s*=\s*(\{[\s\S]*?\})\s*<').firstMatch(html) ??
        RegExp(r'player_aaaa\s*=\s*(\{[\s\S]*?\})').firstMatch(html);

    if (match == null) {
      throw Exception('未在girigiri播放页找到 player_aaaa 配置');
    }

    final player = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    var rawUrl = player['url']?.toString().trim() ?? '';
    final encrypt = player['encrypt'] ?? 0;

    if (rawUrl.contains('*')) {
      rawUrl = rawUrl.split('*')[0].trim();
    }

    if (encrypt == 1) {
      try {
        rawUrl = Uri.decodeQueryComponent(rawUrl);
      } catch (_) {}
    } else if (encrypt == 2) {
      try {
        final decodedBytes = base64Decode(rawUrl);
        final decodedStr = utf8.decode(decodedBytes, allowMalformed: true);
        try {
          rawUrl = Uri.decodeQueryComponent(decodedStr);
        } catch (_) {
          rawUrl = decodedStr;
        }
      } catch (_) {}
    }

    rawUrl = rawUrl.replaceAll(r'\/', '/').trim();
    if (!rawUrl.startsWith('http')) {
      throw Exception('girigiri直链格式不正确: $rawUrl');
    }

    return SourceResolveResult(
      url: rawUrl,
      headers: {
        'Referer': '$_baseUrl/',
        'User-Agent': _kDefaultUserAgent,
      },
      format: rawUrl.contains('.m3u8') ? 'hls' : 'mp4',
    );
  }
}
