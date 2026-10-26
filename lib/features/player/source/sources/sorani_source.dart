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
  int get weight => 59;

  @override
  String get name => '青空次元';

  @override
  String get version => '1.0.0';

  @override
  String get description => '1080P · 官方原生 API 直出 (最高画质)';

  @override
  bool get isDirect => false;

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
            final malId = item['malId'];
            final title = item['title']?.toString().trim() ?? '';
            final cover = item['cover']?.toString() ?? item['coverThumb']?.toString();
            // 特殊处理说明：对齐青空次元官方前端规范，番剧详情链接采用 /anime/mal/:malId 路径，
            // 并在 query 携带原始 video id 供 chapters 请求 API 时精准定位
            final String animeUrl;
            if (malId != null && malId.toString().isNotEmpty) {
              animeUrl = '$_webBaseUrl/anime/mal/$malId?id=$id';
            } else {
              animeUrl = '$_webBaseUrl/anime/$id';
            }
            return SourceSearchResult(
              name: title,
              url: animeUrl,
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
    final uri = Uri.tryParse(trimmed);
    String? videoId = uri?.queryParameters['id'] ?? uri?.queryParameters['videoId'];

    if (videoId == null || videoId.isEmpty) {
      final match = RegExp(r'/anime/(?:mal/)?(\d+)', caseSensitive: false).firstMatch(trimmed) ??
          RegExp(r'/video/(\d+)', caseSensitive: false).firstMatch(trimmed) ??
          RegExp(r'(\d+)$').firstMatch(trimmed);

      if (match == null) {
        throw Exception('无法从链接提取青空次元番剧 ID: $animeUrl');
      }
      videoId = match.group(1)!;
    }

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
    final dataMap = detailData?['data'] as Map<String, dynamic>?;
    final rawEpisodes = (dataMap?['episodes'] as List?) ?? [];
    if (rawEpisodes.isEmpty) return [];

    final activeEpisodes = rawEpisodes
        .whereType<Map<String, dynamic>>()
        .where((ep) => ep['enable'] != false)
        .toList();

    if (activeEpisodes.isEmpty) return [];

    // 计算标准官方番剧详情基础路径 (如 /anime/mal/4756)
    final malId = dataMap?['malId'];
    final String animeBasePath;
    if (trimmed.contains('/anime/mal/')) {
      final malPathMatch = RegExp(r'(/anime/mal/\d+)').firstMatch(trimmed);
      animeBasePath = malPathMatch?.group(1) ?? '/anime/mal/$videoId';
    } else if (malId != null && malId.toString().isNotEmpty) {
      animeBasePath = '/anime/mal/$malId';
    } else {
      animeBasePath = '/anime/$videoId';
    }

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
      for (var i = 0; i < activeEpisodes.length; i++) {
        final ep = activeEpisodes[i];
        final epId = ep['episodeId'] ?? ep['id'];
        final rawOrder = ep['episodeOrder'];
        final int orderInt = (rawOrder is num)
            ? rawOrder.toInt()
            : (int.tryParse(rawOrder?.toString() ?? '') ?? (i + 1));
        final rawTitle = ep['title']?.toString().trim() ?? '';
        final epLabel = ep['episodeLabel']?.toString().trim() ?? '';
        final orderStr = orderInt.toString().padLeft(2, '0');
        final title = rawTitle.isNotEmpty
            ? rawTitle
            : (epLabel.isNotEmpty ? epLabel : '第$orderStr集');

        // 特殊处理说明：对齐青空次元官方 SvelteKit 前端真实播放路由 /anime/mal/:id/episode/:order (如 /episode/01)，
        // 确保无头 WebView 嗅探能进入真实官方页面启动播放器，并在 query 携带 epId 与 lineCode 供原生 Dart 极速秒开
        final epUrl =
            '$_webBaseUrl$animeBasePath/episode/$orderStr?epId=$epId&lineCode=${Uri.encodeComponent(lineCode)}';

        episodes.add(
          SourceEpisode(
            name: title,
            url: epUrl,
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
      episodeId = uri.queryParameters['epId'] ?? uri.queryParameters['episodeId'];
    } catch (_) {}

    // 容错 1：老版本老链接或备选兼容提取真实数据库 ID (如 /episode/66078 且数字大)
    if (episodeId == null || episodeId.isEmpty) {
      final match = RegExp(r'/episode/(\d+)', caseSensitive: false).firstMatch(trimmed) ??
          RegExp(r'/ep/(\d+)', caseSensitive: false).firstMatch(trimmed);
      if (match != null) {
        final candidate = match.group(1)!;
        if (int.tryParse(candidate) != null && int.parse(candidate) > 99) {
          episodeId = candidate;
        }
      }
    }

    // 容错 2：若为纯净官方播放路由 /anime/mal/:malId/episode/:order (无 query epId)，通过 API 反查真实 epId
    if (episodeId == null || episodeId.isEmpty) {
      final animeMatch = RegExp(r'/anime/(?:mal/)?(\d+)', caseSensitive: false).firstMatch(trimmed);
      final epOrderMatch = RegExp(r'/episode/(\d+)', caseSensitive: false).firstMatch(trimmed);
      if (animeMatch != null && epOrderMatch != null) {
        final vId = animeMatch.group(1)!;
        final targetOrder = int.tryParse(epOrderMatch.group(1)!);
        try {
          final detailRes = await _dio.get<dynamic>(
            '$_apiBaseUrl/api/video/$vId',
            options: Options(
              headers: _baseHeaders(),
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          );
          final detailData = parseJsonMap(detailRes.data);
          final rawEpisodes = (detailData?['data']?['episodes'] as List?) ?? [];
          for (var i = 0; i < rawEpisodes.length; i++) {
            final ep = rawEpisodes[i] as Map<String, dynamic>;
            final order = ep['episodeOrder'] ?? (i + 1);
            if (order == targetOrder) {
              episodeId = (ep['episodeId'] ?? ep['id'])?.toString();
              break;
            }
          }
          if (episodeId == null && rawEpisodes.isNotEmpty) {
            final idx = (targetOrder != null && targetOrder > 0 && targetOrder <= rawEpisodes.length)
                ? targetOrder - 1
                : 0;
            episodeId = (rawEpisodes[idx]['episodeId'] ?? rawEpisodes[idx]['id'])?.toString();
          }
        } catch (_) {}
      }
    }

    if (episodeId == null || episodeId.isEmpty) {
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
