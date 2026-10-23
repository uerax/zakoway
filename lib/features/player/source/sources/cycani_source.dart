import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// 次元城 (cycani.org) 专有视频源
/// 1:1 对齐 animaku (apps/server/src/lib/cycani.ts) 规范
class CycaniSource extends VideoSource {
  CycaniSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _baseUrl = 'https://www.cycani.org';
  static const String _username = 'animaku';
  static const String _password = 'sxii8BX2VgfRIL';

  String _cachedToken = '';
  int _tokenExpiresAt = 0;

  @override
  String get id => 'cycani';

  @override
  String get name => '次元城';

  @override
  String get version => '1.3.0';

  @override
  String get description => '1080P · 纯净 REST API 多线路 (Cloudflare CDN 原画)';

  @override
  bool get isDirect => false;

  Map<String, String> _baseHeaders([String? token]) {
    final t = token ?? _cachedToken;
    return {
      'User-Agent': _kDefaultUserAgent,
      'Accept': 'application/json, text/plain, */*',
      'X-App-Name': 'cyc_web',
      'X-App-Version': 'cycweb',
      if (t.isNotEmpty) 'Authorization': t.startsWith('Bearer ') ? t : 'Bearer $t',
    };
  }

  Future<String> _ensureValidToken({bool forceRefresh = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!forceRefresh && _cachedToken.isNotEmpty && _tokenExpiresAt > now + 30 * 60 * 1000) {
      return _cachedToken;
    }

    try {
      final res = await _dio.post<dynamic>(
        '$_baseUrl/api/auth/login',
        data: {'username': _username, 'password': _password},
        options: Options(
          headers: _baseHeaders(),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final resData = parseJsonMap(res.data);
      final data = resData?['data'] as Map<String, dynamic>?;
      final token = data?['token']?.toString().trim() ?? '';
      if (token.isNotEmpty) {
        _cachedToken = token.startsWith('Bearer ') ? token : 'Bearer $token';
        final expiresAtStr = data?['expires_at']?.toString();
        _tokenExpiresAt = expiresAtStr != null
            ? DateTime.tryParse(expiresAtStr)?.millisecondsSinceEpoch ?? (now + 6 * 24 * 3600 * 1000)
            : (now + 6 * 24 * 3600 * 1000);
        return _cachedToken;
      }
      throw Exception('次元城登录未返回有效 Token: ${resData?['msg']}');
    } catch (e) {
      throw Exception('次元城登录鉴权失败: $e');
    }
  }

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    try {
      final res = await _dio.get<dynamic>(
        '$_baseUrl/api/videos/search?q=${Uri.encodeComponent(q)}&page=1&page_size=24',
        options: Options(
          headers: _baseHeaders(),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final resData = parseJsonMap(res.data);
      final list = (resData?['data']?['list'] as List?) ?? [];
      return list
          .whereType<Map<String, dynamic>>()
          .map((item) => SourceSearchResult(
                name: item['title']?.toString().trim() ?? '番剧 #${item['video_id']}',
                url: '$_baseUrl/anime/${item['video_id']}',
                cover: item['cover_url']?.toString(),
              ))
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async {
    final match = RegExp(r'/(?:anime|videos)/(\d+)').firstMatch(animeUrl) ?? RegExp(r'(\d+)$').firstMatch(animeUrl);
    if (match == null) throw Exception('无法从链接提取次元城番剧 ID: $animeUrl');
    final videoId = match.group(1)!;

    final detailRes = await _dio.get<dynamic>(
      '$_baseUrl/api/videos/$videoId',
      options: Options(
        headers: _baseHeaders(),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final detailData = parseJsonMap(detailRes.data);
    final playFromList = (detailData?['data']?['play_from'] as List?) ??
        [
          {'code': 'cychub', 'title': 'CYC_Main'}
        ];

    final roads = <SourceChapterRoad>[];

    await Future.wait(
      playFromList.map((line) async {
        final code = line['code']?.toString() ?? 'cychub';
        final title = (line['title']?.toString() ?? '线路').trim();

        try {
          final sectionsRes = await _dio.get<dynamic>(
            '$_baseUrl/api/videos/$videoId/sections?player_code=${Uri.encodeComponent(code)}&page=1&page_size=100',
            options: Options(
              headers: _baseHeaders(),
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          );

          final secData = parseJsonMap(sectionsRes.data);
          final epList = (secData?['data']?['list'] as List?) ?? [];
          if (epList.isEmpty) return;

          // 特殊处理说明：次元城官方前端播放路由为纯顺序 /anime/:id/play/:epIndex，
          // 直接根据数组自然下标顺序 1..N 构造真实合法的播放链接，并在 query 附带真实 sid 供原生解析秒开
          final episodes = <SourceEpisode>[];
          for (var i = 0; i < epList.length; i++) {
            final ep = epList[i] as Map<String, dynamic>;
            final epNum = i + 1;
            final epTitle = ep['title']?.toString().trim();
            final name = (epTitle != null && epTitle.isNotEmpty) ? epTitle : '第$epNum集';
            episodes.add(SourceEpisode(
              name: name,
              url: '$_baseUrl/anime/$videoId/play/$epNum?sid=${ep['id']}',
            ));
          }

          roads.add(SourceChapterRoad(name: title, episodes: episodes));
        } catch (_) {}
      }),
    );

    return roads;
  }

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    final uri = Uri.tryParse(episodeUrl);
    String? sectionId = uri?.queryParameters['sid'] ?? uri?.queryParameters['section_id'];
    if (sectionId == null || sectionId.isEmpty) {
      final match = RegExp(r'/play/\d+/(\d+)').firstMatch(episodeUrl) ?? RegExp(r'(\d+)$').firstMatch(episodeUrl);
      if (match == null) throw Exception('无法提取次元城选集 ID: $episodeUrl');
      sectionId = match.group(1)!;
    }

    var token = await _ensureValidToken();

    var res = await _dio.get<dynamic>(
      '$_baseUrl/api/v2/sections/$sectionId/play-url',
      options: Options(
        headers: _baseHeaders(token),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        validateStatus: (_) => true,
      ),
    );

    var resData = parseJsonMap(res.data);

    // 401 自动续期自愈重试 (对齐 animaku)
    if (res.statusCode == 401 || resData?['code'] == 401) {
      token = await _ensureValidToken(forceRefresh: true);
      res = await _dio.get<dynamic>(
        '$_baseUrl/api/v2/sections/$sectionId/play-url',
        options: Options(
          headers: _baseHeaders(token),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (_) => true,
        ),
      );
      resData = parseJsonMap(res.data);
    }

    final playUrl = resData?['data']?['url']?.toString().trim() ?? '';
    if (playUrl.isEmpty) {
      throw Exception('次元城直链解析失败: ${resData?['msg'] ?? '未获取到直链'}');
    }

    return SourceResolveResult(
      url: playUrl,
      headers: {
        'Referer': '$_baseUrl/',
        'User-Agent': _kDefaultUserAgent,
      },
      format: playUrl.contains('.m3u8') ? 'hls' : 'mp4',
    );
  }
}
