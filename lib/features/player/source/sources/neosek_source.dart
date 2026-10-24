import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// neosek.ai (neosek) 专有视频源
/// 适配器 ID: neosekai, 权重: 60, 归属于直连组
///
/// 注意 / 特殊限制说明：
/// 该站部署了地区封锁策略，明确禁用了日本地区 IP (Ban Japan IP)，
/// 请求与部署时请确保出站节点非日本 IP，否则将导致网络握手被阻断或接口返回异常。
class NeosekSource extends VideoSource {
  NeosekSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _baseUrl = 'https://neosek.ai';

  @override
  String get id => 'neosekai';

  @override
  String get name => 'neosek';

  @override
  String get version => '1.0.0';

  @override
  String get description => '1080P · 香港 CDN fMP4 HLS 直连 (权重 60)';

  @override
  bool get isDirect => true;

  /// 搜索番剧
  ///
  /// neosek.ai 搜索分类参数说明 (Search Category Parameter):
  /// - 全部: GET https://neosek.ai/api/v1/search?q={keyword}
  ///   (不传递 content_type，同时检索动画、漫画、同人志、图集等全站资源)
  /// - 漫画: GET https://neosek.ai/api/v1/search?q={keyword}&content_type=manga
  ///   (仅检索漫画、同人志、图集资源)
  /// - 动画: GET https://neosek.ai/api/v1/search?q={keyword}&content_type=anime
  ///   (本次接入所使用的参数：严格过滤非动画资源，仅检索动画番剧 TV/剧场版/OAD)
  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    try {
      final res = await _dio.get<dynamic>(
        '$_baseUrl/api/v1/search?q=${Uri.encodeComponent(q)}&content_type=anime',
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
      if (resData?['code'] != 0) return [];

      final items = (resData?['data']?['items'] as List?) ?? [];
      final results = <SourceSearchResult>[];
      final seenIds = <int>{};

      for (final item in items.whereType<Map<String, dynamic>>()) {
        final id = (item['id'] as num?)?.toInt();
        if (id == null || seenIds.contains(id)) continue;
        final title = item['title']?.toString().trim() ?? '';
        if (title.isEmpty) continue;

        seenIds.add(id);

        // 封面解析：优先 styles 中的 thumb，降级第一个 style
        String? coverUrl;
        final coverStyles = (item['cover']?['styles'] as List?) ?? [];
        for (final style in coverStyles.whereType<Map<String, dynamic>>()) {
          final fileUrl = style['file']?['url']?.toString();
          if (fileUrl != null && fileUrl.isNotEmpty) {
            coverUrl = fileUrl;
            if (style['name'] == 'thumb') break;
          }
        }

        results.add(SourceSearchResult(
          name: title,
          url: '$_baseUrl/anime/$id',
          cover: coverUrl,
        ));
      }

      return results;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async {
    final match = RegExp(r'/anime/(\d+)').firstMatch(animeUrl) ??
        RegExp(r'(\d+)$').firstMatch(animeUrl);
    if (match == null) throw Exception('无法从链接提取 neosek 番剧 ID: $animeUrl');
    final workId = match.group(1)!;

    final res = await _dio.get<dynamic>(
      '$_baseUrl/api/v1/works/$workId/units',
      options: Options(
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Accept': 'application/json, text/plain, */*',
          'Referer': '$_baseUrl/anime/$workId',
        },
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final resData = parseJsonMap(res.data);
    if (resData?['code'] != 0) {
      throw Exception('Neosek units 数据获取失败: ${resData?['message']}');
    }

    final rawUnits = (resData?['data']?['items'] as List?) ?? [];
    if (rawUnits.isEmpty) return [];

    final episodes = <SourceEpisode>[];
    for (final u in rawUnits.whereType<Map<String, dynamic>>()) {
      final unitId = u['id']?.toString() ?? '';
      if (unitId.isEmpty) continue;
      final sort = (u['sort'] as num?)?.toInt() ?? 0;
      final rawTitle = u['title']?.toString().trim() ?? '';
      final title = rawTitle.isNotEmpty ? rawTitle : '第 ${sort + 1} 话';

      episodes.add(SourceEpisode(
        name: title,
        url: '$_baseUrl/anime/$workId/$unitId',
      ));
    }

    if (episodes.isEmpty) return [];

    return [
      SourceChapterRoad(
        name: 'Neosek',
        episodes: episodes,
      ),
    ];
  }

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    final match = RegExp(r'/anime/\d+/(\d+)').firstMatch(episodeUrl) ??
        RegExp(r'(\d+)$').firstMatch(episodeUrl);
    if (match == null) throw Exception('无法从链接提取 neosek 选集 ID: $episodeUrl');
    final unitId = match.group(1)!;

    final res = await _dio.get<dynamic>(
      '$_baseUrl/api/v1/units/$unitId/items',
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
    if (resData?['code'] != 0) {
      throw Exception('Neosek items 获取失败: ${resData?['message']}');
    }

    final items = (resData?['data']?['items'] as List?) ?? [];
    String? playUrl;
    String format = 'hls';

    // 特殊处理说明：
    // 该站 HLS Master Playlist (fMP4) 包含 1400+ 秒独立长 VTT 字幕分片，
    // 在底层 libmpv/FFmpeg 解析交错时间戳时会触发 Packet corrupt 导致视频帧丢失黑屏。
    // 优先采用原站提供的 original 完整原画直链 (source.mkv / source.mp4)，
    // 零转码损失、原生支持 Range 寻道且播放秒开；无 original 时再回退 hls。
    for (final item in items.whereType<Map<String, dynamic>>()) {
      final video = item['video'] as Map<String, dynamic>?;
      if (video == null) continue;

      final originalUrl = video['original']?['url']?.toString().trim();
      if (originalUrl != null && originalUrl.isNotEmpty) {
        playUrl = originalUrl;
        format = originalUrl.contains('.m3u8') ? 'hls' : 'mp4';
        break;
      }

      final hlsUrl = video['hls']?['url']?.toString().trim();
      if (hlsUrl != null && hlsUrl.isNotEmpty) {
        playUrl = hlsUrl;
        format = 'hls';
        break;
      }
    }

    if (playUrl == null || playUrl.isEmpty) {
      throw Exception('未从 Neosek 找到可用播放流');
    }

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
