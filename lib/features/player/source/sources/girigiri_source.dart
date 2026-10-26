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
  // 特殊说明：girigiri 整体重构为 Vite/React SPA 后，主站所有页面路径均返回单页静态 HTML。
  // 数据接口全量迁移至后端的独立 API 域名 m3u8.girigirilove.com。
  static const String _apiBaseUrl = 'https://m3u8.girigirilove.com';

  @override
  String get id => 'girigiri';

  @override
  int get weight => 59;

  @override
  String get name => 'girigiri';

  @override
  String get version => '1.4.0';

  @override
  String get description => '1080P · Cloudflare CDN 原画直连 (老番优先)';

  @override
  bool get isDirect => true;

  /// 格式化 girigiri 的线路代号为用户友好的展示标签
  String _formatRoadName(String rawName, int index) {
    final trimmed = rawName.trim();
    final lower = trimmed.toLowerCase();
    if (lower == 'cht') return '繁体';
    if (lower == 'chs') return '简体';
    if (lower == 'db') return '杜比视界';
    if (lower == '1080p') return '1080P超清';
    if (lower == '4k') return '4K超清';
    return trimmed.isNotEmpty ? trimmed : '线路 ${index + 1}';
  }

  /// 从页面 URL、详情 URL 或旧版 URL 中解析出 vod_id
  String? _extractVodId(String source) {
    final trimmed = source.trim();
    if (RegExp(r'^\d+$').hasMatch(trimmed)) return trimmed;
    final match = RegExp(r'(?:detail/|play/|GV|vod_id=)(\d+)', caseSensitive: false).firstMatch(trimmed);
    return match?.group(1);
  }

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    // 1. 优先请求主线 REST API: Vod/get_list
    try {
      final res = await _dio.get(
        '$_apiBaseUrl/api.php/Vod/get_list?offset=0&limit=24&vod_name=${Uri.encodeComponent(q)}',
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

      final data = parseJsonMap(res.data);
      if (data != null && data['code'] == 1 && data['info'] is Map) {
        final rows = (data['info']['rows'] as List?) ?? [];
        final results = <SourceSearchResult>[];
        for (final row in rows.whereType<Map>()) {
          final vodId = row['vod_id']?.toString() ?? '';
          final vodName = row['vod_name']?.toString().trim() ?? '';
          if (vodId.isEmpty || vodName.isEmpty) continue;
          results.add(SourceSearchResult(
            name: vodName,
            url: '$_baseUrl/detail/$vodId',
            cover: row['vod_pic']?.toString(),
          ));
        }
        if (results.isNotEmpty) {
          return results;
        }
      }
    } catch (_) {
      // 失败后继续尝试 suggest 回退
    }

    // 2. 回退到 m3u8 域名的 suggest API
    try {
      final res = await _dio.get(
        '$_apiBaseUrl/index.php/ajax/suggest?mid=1&wd=${Uri.encodeComponent(q)}',
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

      final data = parseJsonMap(res.data);
      final list = (data?['list'] as List?) ?? [];
      return list
          .whereType<Map>()
          .map((item) {
            final id = item['id']?.toString() ?? '';
            final name = item['name']?.toString().trim() ?? '';
            return SourceSearchResult(
              name: name,
              url: '$_baseUrl/detail/$id',
              cover: item['pic']?.toString(),
            );
          })
          .where((s) => s.name.isNotEmpty && s.url.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async {
    final vodId = _extractVodId(animeUrl);
    if (vodId == null) {
      throw Exception('无法从输入来源解析 girigiri 番剧 ID: $animeUrl');
    }

    final res = await _dio.get(
      '$_apiBaseUrl/api.php/Vod/get_detail?vod_id=$vodId&user_id=',
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

    final data = parseJsonMap(res.data);
    if (data == null || data['code'] != 1 || data['info'] is! Map) {
      throw Exception('girigiri 番剧详情接口返回异常: ${data?['msg'] ?? '未获取到有效详情'}');
    }

    final info = Map<String, dynamic>.from(data['info'] as Map);
    final playFrom = info['vod_play_from']?.toString() ?? '';
    final playUrl = info['vod_play_url']?.toString() ?? '';

    final fromList = playFrom.split(r'$$$').map((s) => s.trim()).toList();
    final urlGroups = playUrl.split(r'$$$').map((s) => s.trim()).toList();

    final roads = <SourceChapterRoad>[];

    for (var i = 0; i < urlGroups.length; i++) {
      final group = urlGroups[i];
      if (group.isEmpty) continue;

      final rawFrom = i < fromList.length ? fromList[i] : '';
      final roadName = _formatRoadName(rawFrom, i);
      final episodes = <SourceEpisode>[];

      final epEntries = group.split('#');
      for (final ep in epEntries) {
        final trimmedEp = ep.trim();
        if (trimmedEp.isEmpty) continue;

        final dollarIdx = trimmedEp.indexOf(r'$');
        String epName = '';
        String epUrl = '';
        if (dollarIdx != -1) {
          epName = trimmedEp.substring(0, dollarIdx).trim();
          epUrl = trimmedEp.substring(dollarIdx + 1).trim();
        } else {
          epUrl = trimmedEp;
        }

        if (epUrl.isEmpty || !epUrl.startsWith('http')) continue;

        if (RegExp(r'^\d+$').hasMatch(epName)) {
          epName = '第${epName.padLeft(2, '0')}集';
        } else if (epName.isEmpty) {
          epName = '第${(episodes.length + 1).toString().padLeft(2, '0')}集';
        }

        episodes.add(SourceEpisode(
          name: epName,
          url: epUrl,
        ));
      }

      if (episodes.isNotEmpty) {
        roads.add(SourceChapterRoad(name: roadName, episodes: episodes));
      }
    }

    return roads;
  }

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    final playUrl = episodeUrl.trim();

    // 1. 若已经是媒体流直链，直接透传返回
    if (playUrl.contains('.m3u8') || playUrl.contains('.mp4')) {
      return SourceResolveResult(
        url: playUrl,
        headers: {
          'Referer': '$_baseUrl/',
          'User-Agent': _kDefaultUserAgent,
        },
        format: playUrl.contains('.m3u8') ? 'hls' : 'mp4',
      );
    }

    // 2. 页面 URL 回退处理（支持 /play/:id?sourceIndex=0&episodeIndex=0 或 /detail/:id）
    final vodId = _extractVodId(playUrl);
    if (vodId == null) {
      throw Exception('无法从播放页地址提取 girigiri ID: $playUrl');
    }

    final roadList = await chapters(vodId);
    if (roadList.isEmpty || roadList.first.episodes.isEmpty) {
      throw Exception('girigiri 解析播放源失败: 未获取到可用分集');
    }

    var sourceIdx = 0;
    var episodeIdx = 0;

    try {
      final uri = Uri.parse(playUrl);
      final sParam = uri.queryParameters['sourceIndex'];
      final eParam = uri.queryParameters['episodeIndex'];
      if (sParam != null) sourceIdx = int.tryParse(sParam) ?? 0;
      if (eParam != null) episodeIdx = int.tryParse(eParam) ?? 0;
    } catch (_) {}

    final targetRoad = (sourceIdx >= 0 && sourceIdx < roadList.length) ? roadList[sourceIdx] : roadList.first;
    if (targetRoad.episodes.isEmpty) {
      throw Exception('girigiri 未找到指定线路的分集直链');
    }

    final targetEp = (episodeIdx >= 0 && episodeIdx < targetRoad.episodes.length)
        ? targetRoad.episodes[episodeIdx]
        : targetRoad.episodes.first;

    final directUrl = targetEp.url.trim();
    if (!directUrl.startsWith('http')) {
      throw Exception('girigiri 解析到的直链格式异常: $directUrl');
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
