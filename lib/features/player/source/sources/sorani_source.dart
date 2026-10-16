import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// 青空次元 (sorani.net / api.sorani.cc) 专有视频源
/// 1:1 对齐 animaku (apps/server/src/lib/sorani.ts) 规范
class SoraniSource extends VideoSource {
  SoraniSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _webBaseUrl = 'https://www.sorani.net';
  static const String _apiBaseUrl = 'https://api.sorani.cc/sorani-cms';

  @override
  String get id => 'sorani';

  @override
  String get name => '青空次元';

  @override
  String get version => '1.0.0';

  @override
  String get description => '1080P · 官方原生 API 直出 (最高画质)';

  @override
  bool get isDirect => true;

  Map<String, String> _baseHeaders([String? referer]) {
    return {
      'User-Agent': _kDefaultUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'Referer': referer ?? '$_webBaseUrl/',
      'Origin': _webBaseUrl,
    };
  }

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    try {
      final res = await _dio.get<dynamic>(
        '$_apiBaseUrl/api/video/search?keyword=${Uri.encodeComponent(q)}',
        options: Options(
          headers: _baseHeaders(),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final resData = parseJsonMap(res.data);
      final list = (resData?['data'] as List?) ?? [];

      return list
          .whereType<Map<String, dynamic>>()
          .map((item) {
            final id = item['id'];
            final title = item['title']?.toString().trim() ?? '';
            final cover = item['cover']?.toString() ?? item['coverThumb']?.toString();
            return SourceSearchResult(
              name: title,
              url: '$_webBaseUrl/anime/$id',
              cover: cover,
            );
          })
          .where((s) => s.name.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async {
    final trimmed = animeUrl.trim();
    final match = RegExp(r'/anime/(?:mal/)?(\d+)', caseSensitive: false).firstMatch(trimmed) ??
        RegExp(r'/video/(\d+)', caseSensitive: false).firstMatch(trimmed) ??
        RegExp(r'(\d+)$').firstMatch(trimmed);

    if (match == null) {
      throw Exception('无法从链接提取青空次元番剧 ID: $animeUrl');
    }
    final videoId = match.group(1)!;

    // 1. 获取番剧分集详情
    final detailRes = await _dio.get<dynamic>(
      '$_apiBaseUrl/api/video/$videoId',
      options: Options(
        headers: _baseHeaders(),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final detailData = parseJsonMap(detailRes.data);
    final rawEpisodes = (detailData?['data']?['episodes'] as List?) ?? [];
    if (rawEpisodes.isEmpty) return [];

    final activeEpisodes = rawEpisodes
        .whereType<Map<String, dynamic>>()
        .where((ep) => ep['enable'] != false)
        .toList();

    if (activeEpisodes.isEmpty) return [];

    // 2. 获取可用线路 (容错兜底)
    List<Map<String, dynamic>> lines = [];
    try {
      final linesRes = await _dio.get<dynamic>(
        '$_apiBaseUrl/api/video/$videoId/play-lines',
        options: Options(
          headers: _baseHeaders(),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final linesData = parseJsonMap(linesRes.data);
      lines = ((linesData?['data'] as List?) ?? [])
          .whereType<Map<String, dynamic>>()
          .where((l) => l['enable'] != false)
          .toList();
    } catch (_) {}

    if (lines.isEmpty) {
      lines = [
        {'lineId': 1, 'code': 'anime_jp_m3u8', 'name': '青空次元'}
      ];
    }

    final roads = <SourceChapterRoad>[];

    for (final line in lines) {
      final lineCode = line['code']?.toString() ?? 'anime_jp_m3u8';
      final lineName = (line['name']?.toString() ?? '青空次元').trim();

      final episodes = <SourceEpisode>[];
      for (final ep in activeEpisodes) {
        final epId = ep['episodeId'] ?? ep['id'];
        final epOrder = ep['episodeOrder'] ?? 1;
        final rawTitle = ep['title']?.toString().trim() ?? '';
        final epLabel = ep['episodeLabel']?.toString().trim() ?? '';
        final title = rawTitle.isNotEmpty
            ? rawTitle
            : (epLabel.isNotEmpty ? epLabel : '第${epOrder.toString().padLeft(2, '0')}集');

        episodes.add(
          SourceEpisode(
            name: title,
            url: '$_webBaseUrl/anime/$videoId/episode/$epId?lineCode=${Uri.encodeComponent(lineCode)}',
          ),
        );
      }

      roads.add(SourceChapterRoad(name: lineName, episodes: episodes));
    }

    return roads;
  }

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    final trimmed = episodeUrl.trim();
    String? lineCode;
    String? episodeId;

    try {
      final uri = Uri.parse(trimmed);
      lineCode = uri.queryParameters['lineCode'] ?? uri.queryParameters['line'];
      final pathMatch = RegExp(r'/episode/(\d+)', caseSensitive: false).firstMatch(uri.path) ??
          RegExp(r'/ep/(\d+)', caseSensitive: false).firstMatch(uri.path) ??
          RegExp(r'/play/(\d+)', caseSensitive: false).firstMatch(uri.path);
      if (pathMatch != null) {
        episodeId = pathMatch.group(1);
      }
    } catch (_) {}

    if (episodeId == null) {
      final fallbackMatch = RegExp(r'/episode/(\d+)', caseSensitive: false).firstMatch(trimmed) ??
          RegExp(r'(\d+)$').firstMatch(trimmed);
      if (fallbackMatch != null) {
        episodeId = fallbackMatch.group(1);
      }
    }

    if (episodeId == null) {
      throw Exception('无法从播放链接提取青空次元选集 ID: $episodeUrl');
    }

    var playApiUrl = '$_apiBaseUrl/api/video/episode/$episodeId/play';
    if (lineCode != null && lineCode.isNotEmpty) {
      playApiUrl += '?lineCode=${Uri.encodeComponent(lineCode)}';
    }

    final res = await _dio.get<dynamic>(
      playApiUrl,
      options: Options(
        headers: _baseHeaders(),
        sendTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    final resData = parseJsonMap(res.data);
    final data = resData?['data'] as Map<String, dynamic>?;
    final canPlay = data?['canPlay'] == true;
    final playUrl = data?['playUrl']?.toString().trim() ?? '';

    if (!canPlay || playUrl.isEmpty) {
      final msg = data?['message']?.toString() ?? resData?['message']?.toString() ?? '未获取到有效直链';
      throw Exception('青空次元直链解析失败: $msg');
    }

    return SourceResolveResult(
      url: playUrl,
      headers: {
        'Referer': '$_webBaseUrl/',
        'User-Agent': _kDefaultUserAgent,
      },
      format: playUrl.toLowerCase().contains('.mp4') ? 'mp4' : 'hls',
    );
  }
}
