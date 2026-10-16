import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// 标题噪点正则（剔除解说、预告片、花絮等低质噪点，对齐 animaku JUNK_TITLE_REGEX）
final RegExp _kLzizyJunkRegex = RegExp(
  r'(?:\[|\()?(?:电影解说|电视剧解说|解说|预告片|预告|花絮)(?:\]|\))?',
  caseSensitive: false,
);

class LzizySource extends VideoSource {
  LzizySource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _apiBase = 'https://cj.lziapi.com/api.php/provide/vod';

  @override
  String get id => 'lzizy';

  @override
  String get name => '量子资源';

  @override
  String get version => '1.2.0';

  @override
  String get description => 'HLS · 全品类影视 0ms 纯直链切片';

  @override
  bool get isDirect => true;

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    try {
      final res = await _dio.get<dynamic>(
        '$_apiBase/?ac=detail&wd=${Uri.encodeComponent(q)}',
        options: Options(
          headers: {'User-Agent': _kDefaultUserAgent},
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final data = parseJsonMap(res.data);
      final list = (data?['list'] as List?) ?? [];
      return list
          .whereType<Map<String, dynamic>>()
          .where((item) {
            final name = (item['vod_name']?.toString() ?? '').trim();
            if (name.isEmpty) return false;
            final typeId = item['type_id'];
            if (typeId == 35 || typeId == 45) return false;
            if (_kLzizyJunkRegex.hasMatch(name)) return false;
            return true;
          })
          .map((item) => SourceSearchResult(
                name: item['vod_name']?.toString().trim() ?? '影视 #${item['vod_id']}',
                url: '$_apiBase/?ac=detail&ids=${item['vod_id']}',
                cover: item['vod_pic']?.toString(),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async {
    final idMatch = RegExp(r'ids=(\d+)').firstMatch(animeUrl) ?? RegExp(r'(\d+)$').firstMatch(animeUrl);
    if (idMatch == null) {
      throw Exception('无法提取量子资源 ID: $animeUrl');
    }
    final vodId = idMatch.group(1)!;

    final res = await _dio.get<dynamic>(
      '$_apiBase/?ac=detail&ids=$vodId',
      options: Options(
        headers: {'User-Agent': _kDefaultUserAgent},
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final resData = parseJsonMap(res.data);
    final item = (resData?['list'] as List?)?.firstOrNull as Map<String, dynamic>?;
    if (item == null) {
      throw Exception('量子资源未查询到剧集详情');
    }

    final sourceNames = (item['vod_play_from']?.toString() ?? '').split('\$\$\$');
    final rawGroups = (item['vod_play_url']?.toString() ?? '').split('\$\$\$');

    final rawRoads = <({String fromName, SourceChapterRoad road})>[];

    for (var sIdx = 0; sIdx < rawGroups.length; sIdx++) {
      final rawFrom = (sIdx < sourceNames.length ? sourceNames[sIdx] : '线路${sIdx + 1}').trim();
      final group = rawGroups[sIdx];
      final episodes = <SourceEpisode>[];

      for (final entry in group.split('#')) {
        final sep = entry.indexOf('\$');
        if (sep <= 0) continue;
        final title = entry.substring(0, sep).trim();
        final rawUrl = entry.substring(sep + 1).trim();
        if (rawUrl.startsWith('http')) {
          episodes.add(SourceEpisode(
            name: title.isNotEmpty ? title : '第${episodes.length + 1}集',
            url: rawUrl,
          ));
        }
      }

      if (episodes.isNotEmpty) {
        rawRoads.add((
          fromName: rawFrom,
          road: SourceChapterRoad(name: rawFrom, episodes: episodes),
        ));
      }
    }

    // 线路排序与精炼（对齐 animaku）：
    // 1. 优先提取 lzm3u8 线路，命名为「量子极速(直链)」
    // 2. 严格剔除 liangzi 网页分享线路（/share/... 属于 HTML 播放外壳，无法原生解码）
    final m3u8Roads = <SourceChapterRoad>[];
    final otherRoads = <SourceChapterRoad>[];

    for (final r in rawRoads) {
      final lowerFrom = r.fromName.toLowerCase();
      final isM3u8Line = lowerFrom.contains('lzm3u8') ||
          lowerFrom.contains('m3u8') ||
          r.road.episodes.any((e) => e.url.contains('.m3u8'));

      if (isM3u8Line) {
        m3u8Roads.add(SourceChapterRoad(
          name: lowerFrom.contains('lzm3u8') ? '量子极速(直链)' : r.fromName,
          episodes: r.road.episodes,
        ));
      } else if (!lowerFrom.contains('liangzi') && !r.road.episodes.any((e) => e.url.contains('/share/'))) {
        otherRoads.add(r.road);
      }
    }

    final finalRoads = [...m3u8Roads, ...otherRoads];
    return finalRoads.isNotEmpty ? finalRoads : rawRoads.map((r) => r.road).toList();
  }

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    final directUrl = episodeUrl.trim();
    return SourceResolveResult(
      url: directUrl,
      headers: {'User-Agent': _kDefaultUserAgent},
      format: directUrl.contains('.m3u8') ? 'hls' : 'mp4',
    );
  }
}
