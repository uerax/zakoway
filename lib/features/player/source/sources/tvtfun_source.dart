import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// TvTFun (tvtfun.net) 专有视频源
/// 适配 Nuxt 3 新架构 API (/api/client/anime 及 /api/site-auth/playback-resolve)
class TvTFunSource extends VideoSource {
  TvTFunSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _baseUrl = 'https://www.tvtfun.net';

  @override
  String get id => 'tvtfun';

  @override
  String get name => 'TvTFun';

  @override
  String get version => '2.0.0';

  @override
  String get description => '1080P · 官方 BytePlus/Akamai 全球 CDN 极速主线';

  @override
  bool get isDirect => true;

  int _getSourcePriority(String lineName, String srcName) {
    final combined = '$lineName $srcName'.toLowerCase();
    // 特殊处理说明：
    // 线路 1 / AGE 指向字节跳动 BytePlus / Akamai CDN 全球直连节点，全球无地域限制且带宽高；
    // 线路 2 / dytt 指向第三方切片备用源；
    // 因此赋予线路 1 / AGE 最高权重 100，优先调度最佳画质与速度。
    if (combined.contains('age') ||
        combined.contains('线路1') ||
        combined.contains('线路a') ||
        combined.contains('官方')) {
      return 100;
    }
    if (combined.contains('线路2') ||
        combined.contains('线路b') ||
        combined.contains('dytt')) {
      return 80;
    }
    if (combined.contains('线路3') || combined.contains('线路c')) return 70;
    if (combined.contains('线路4') || combined.contains('线路d')) return 60;
    return 50;
  }

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    try {
      final res = await _dio.get<dynamic>(
        '$_baseUrl/api/client/anime?keyword=${Uri.encodeComponent(q)}&page=1&pageSize=20',
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

      final resData = parseJsonMap(res.data);
      final items = (resData?['data']?['items'] as List?) ?? [];
      return items
          .whereType<Map<String, dynamic>>()
          .map((v) {
            final name = v['name']?.toString().trim() ??
                v['originalName']?.toString().trim() ??
                '番剧 #${v['id']}';
            final slug = v['slug']?.toString() ?? v['id']?.toString() ?? '';
            final cover = v['posterUrl']?.toString() ?? v['coverUrl']?.toString();
            return SourceSearchResult(
              name: name.isNotEmpty ? name : '番剧 #${v['id']}',
              url: '$_baseUrl/anime/$slug',
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
    final match = RegExp(r'/anime/([^/?#]+)').firstMatch(animeUrl) ??
        RegExp(r'/video/([^/?#]+)').firstMatch(animeUrl);
    if (match == null) throw Exception('无法解析 TvTFun 番剧标识: $animeUrl');
    final identifier = match.group(1)!;

    final res = await _dio.get<dynamic>(
      '$_baseUrl/api/client/anime/$identifier',
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
    final animeData = resData?['data'] as Map<String, dynamic>?;
    final seasons = (animeData?['seasons'] as List?) ?? [];
    if (seasons.isEmpty) return [];

    final slug = animeData?['slug']?.toString() ?? identifier;

    // 聚合所有分集（多季按序铺平）
    final allEpisodes = <Map<String, dynamic>>[];
    for (final season in seasons.whereType<Map<String, dynamic>>()) {
      final eps = (season['episodes'] as List?) ?? [];
      allEpisodes.addAll(eps.whereType<Map<String, dynamic>>());
    }
    if (allEpisodes.isEmpty) return [];

    // 按分集号升序排序
    allEpisodes.sort((a, b) {
      final numA = (a['number'] as num?) ?? 0;
      final numB = (b['number'] as num?) ?? 0;
      return numA.compareTo(numB);
    });

    // 特殊处理说明：
    // TvTFun Nuxt 3 接口在每个分集下挂载一组播放线路 sources（例如线路 1 为 AGE/BytePlus 全球高速 CDN，线路 2 为切片备用源）。
    // 将各分集按照 lineName/name 聚类归纳为 SourceChapterRoad，并保留原有的优先级加权排序。
    final lineMeta = <String, ({String name, String srcName, int priority, int order})>{};
    final lineEpisodes = <String, List<SourceEpisode>>{};

    for (final ep in allEpisodes) {
      final epId = ep['id']?.toString() ?? '';
      final epNum = (ep['number'] as num?)?.toInt() ?? 1;
      final rawTitle = ep['title']?.toString().trim() ?? '';
      final epName = rawTitle.isNotEmpty
          ? (RegExp(r'^\d+$').hasMatch(rawTitle) ? '第$rawTitle话' : rawTitle)
          : '第$epNum话';

      final sources = (ep['sources'] as List?) ?? [];
      for (var sIdx = 0; sIdx < sources.length; sIdx++) {
        final src = sources[sIdx];
        if (src is! Map<String, dynamic>) continue;

        final lineKey = src['playbackLineId']?.toString() ??
            src['lineName']?.toString() ??
            src['name']?.toString() ??
            'line_$sIdx';
        final lineName = (src['lineName']?.toString() ?? '线路 ${sIdx + 1}').trim();
        final srcName = (src['name']?.toString() ?? '').trim();
        final sourceId = src['id']?.toString() ?? '';
        final playback = (src['playback'] as Map<String, dynamic>?) ?? {};
        final requiresResolve = playback['requiresResolve'] != false;
        final directUrl = playback['url']?.toString().trim() ?? '';
        final mediaType = playback['mediaType']?.toString().trim() ?? 'mp4';

        if (!lineMeta.containsKey(lineKey)) {
          lineMeta[lineKey] = (
            name: lineName,
            srcName: srcName,
            priority: _getSourcePriority(lineName, srcName),
            order: (src['sortOrder'] as num?)?.toInt() ?? sIdx,
          );
          lineEpisodes[lineKey] = [];
        }

        final epUrl = '$_baseUrl/watch/$slug/$epNum?'
            'episodeId=${Uri.encodeComponent(epId)}&'
            'sourceId=${Uri.encodeComponent(sourceId)}&'
            'requiresResolve=$requiresResolve&'
            'mediaType=${Uri.encodeComponent(mediaType)}&'
            'url=${Uri.encodeComponent(directUrl)}';

        lineEpisodes[lineKey]!.add(SourceEpisode(
          name: epName,
          url: epUrl,
        ));
      }
    }

    final sortedLineKeys = lineMeta.keys.toList()
      ..sort((a, b) {
        final metaA = lineMeta[a]!;
        final metaB = lineMeta[b]!;
        if (metaA.priority != metaB.priority) {
          return metaB.priority.compareTo(metaA.priority);
        }
        return metaA.order.compareTo(metaB.order);
      });

    final roads = <SourceChapterRoad>[];
    for (final key in sortedLineKeys) {
      final eps = lineEpisodes[key];
      if (eps != null && eps.isNotEmpty) {
        roads.add(SourceChapterRoad(
          name: lineMeta[key]!.name,
          episodes: eps,
        ));
      }
    }

    return roads;
  }

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    final uri = Uri.parse(episodeUrl);
    final episodeId = uri.queryParameters['episodeId'];
    final sourceId = uri.queryParameters['sourceId'];
    final requiresResolve = uri.queryParameters['requiresResolve'] != 'false';
    final directUrl = uri.queryParameters['url'] ?? '';
    final mediaType = uri.queryParameters['mediaType'] ?? 'mp4';

    if (!requiresResolve && directUrl.isNotEmpty) {
      return SourceResolveResult(
        url: directUrl,
        headers: {
          'Referer': '$_baseUrl/',
          'User-Agent': _kDefaultUserAgent,
        },
        format: directUrl.contains('.m3u8') || mediaType == 'hls' ? 'hls' : 'mp4',
      );
    }

    if (episodeId == null || episodeId.isEmpty || sourceId == null || sourceId.isEmpty) {
      throw Exception('TvTFun 缺少必要解析参数: $episodeUrl');
    }

    final res = await _dio.post<dynamic>(
      '$_baseUrl/api/site-auth/playback-resolve',
      data: {
        'episodeId': episodeId,
        'sourceId': sourceId,
      },
      options: Options(
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Content-Type': 'application/json',
          'Accept': 'application/json, text/plain, */*',
          'Referer': episodeUrl,
        },
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final resData = parseJsonMap(res.data);
    final playData = resData?['data']?['playback'] as Map<String, dynamic>?;
    final playUrl = playData?['url']?.toString().trim() ?? '';
    final playMediaType = playData?['mediaType']?.toString().toLowerCase().trim() ?? '';

    if (playUrl.isEmpty) {
      throw Exception('TvTFun 直链解析失败: ${resData?['message'] ?? '播放源未返回可用地址'}');
    }

    final format = playMediaType == 'hls' || playUrl.contains('.m3u8') ? 'hls' : 'mp4';

    return SourceResolveResult(
      url: playUrl,
      headers: {
        'Referer': '$_baseUrl/',
        'User-Agent': _kDefaultUserAgent,
      },
      format: format,
    );
  }
}
