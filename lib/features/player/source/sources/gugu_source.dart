import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// 咕咕番 (www.gugu3.com) 专有视频源
/// 依托 MacCMS + 米芝解析网关，提供字节跳动 TOS / ImageX 国内高速原画直链
class GuguSource extends VideoSource {
  GuguSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _baseUrl = 'https://www.gugu3.com';
  static const String _playerGateUrl = 'https://player.gugu3.com';

  @override
  String get id => 'gugu';

  @override
  int get weight => 59;

  @override
  String get name => '咕咕番';

  @override
  String get version => '1.0.0';

  @override
  String get description => '1080P · 字节 TOS 国内极速直链 (咕咕新线/A线)';

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
    if (q.isEmpty) return const [];

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
          .map((item) {
            final id = item['id']?.toString() ?? '';
            final name = item['name']?.toString().trim() ?? '';
            var pic = item['pic']?.toString() ?? '';
            if (pic.startsWith('/img.php?url=')) {
              pic = Uri.decodeComponent(pic.replaceFirst('/img.php?url=', ''));
            } else if (pic.startsWith('/')) {
              pic = '$_baseUrl$pic';
            }
            return SourceSearchResult(
              name: name,
              url: '$_baseUrl/index.php/vod/detail/id/$id.html',
              cover: pic.isNotEmpty ? pic : null,
            );
          })
          .where((s) => s.name.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
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

    // 1. 提取线路 Tab 名称 (如 "咕咕新线(国内高速)", "咕咕A线")
    final tabNames = <String>[];
    final tabMatch = RegExp(
      r'''class=["'][^"']*anthology-tab[^"']*["'][^>]*>([\s\S]*?)</div>''',
      caseSensitive: false,
    ).firstMatch(html);

    if (tabMatch != null) {
      final aRegex = RegExp(r'''<a[^>]*>(.*?)</a>''', caseSensitive: false);
      for (final am in aRegex.allMatches(tabMatch.group(1)!)) {
        final label = am
            .group(1)!
            .replaceAll(RegExp(r'<[^>]+>'), '')
            .replaceAll('&nbsp;', ' ')
            .replaceAll(RegExp(r'\s*\d+\s*$'), '')
            .trim();
        if (label.isNotEmpty && !label.contains('排序')) {
          tabNames.add(label);
        }
      }
    }

    // 2. 提取分集列表
    final ulMatches = RegExp(
      r'''<ul[^>]*class=["'][^"']*anthology-list-play[^"']*["'][^>]*>([\s\S]*?)</ul>''',
      caseSensitive: false,
    ).allMatches(html);

    final effectiveUlMatches = ulMatches.isNotEmpty
        ? ulMatches
        : RegExp(r'''<ul[^>]*>([\s\S]*?)</ul>''', caseSensitive: false)
            .allMatches(html)
            .where((u) => u.group(1)!.contains('/vod/play/'));

    final roads = <SourceChapterRoad>[];
    var roadIdx = 0;

    for (final um in effectiveUlMatches) {
      final ulHtml = um.group(1)!;
      final epRegex = RegExp(
        r'''<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>''',
        caseSensitive: false,
      );
      final episodes = <SourceEpisode>[];

      for (final em in epRegex.allMatches(ulHtml)) {
        final href = em.group(1)!;
        final name = em.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (href.isNotEmpty && name.isNotEmpty) {
          episodes.add(
            SourceEpisode(
              name: name,
              url: href.startsWith('http') ? href : '$_baseUrl$href',
            ),
          );
        }
      }

      if (episodes.isNotEmpty) {
        final roadName = roadIdx < tabNames.length ? tabNames[roadIdx] : '线路 ${roadIdx + 1}';
        roads.add(SourceChapterRoad(name: roadName, episodes: episodes));
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
    final playMatch = RegExp(r'''player_aaaa\s*=\s*(\{[\s\S]*?\})\s*</script>''')
            .firstMatch(html) ??
        RegExp(r'''player_aaaa\s*=\s*(\{[\s\S]*?\})''').firstMatch(html);

    if (playMatch == null) {
      throw Exception('未在咕咕番播放页提取到 player_aaaa 配置');
    }

    final player = parseJsonMap(playMatch.group(1)!);
    final rawUrl = (player?['url']?.toString() ?? '').trim();

    if (rawUrl.isEmpty) {
      throw Exception('咕咕番播放器配置 url 为空');
    }

    // 若已经直接是媒体直链，直接交付
    if (rawUrl.startsWith('http') && (rawUrl.contains('.mp4') || rawUrl.contains('.m3u8'))) {
      return SourceResolveResult(
        url: rawUrl,
        headers: {'User-Agent': _kDefaultUserAgent},
        format: rawUrl.contains('.m3u8') ? 'hls' : 'mp4',
      );
    }

    // 特殊处理说明：
    // 咕咕番视频采用米芝解析播放器网关 (player.gugu3.com)，
    // 1. 先向解析器页面发起轻量拉取，从内嵌 script 中提取动态签发的 time 与 vkey 鉴权令牌；
    // 2. 携带令牌向 /admin/mizhi_json.php 发起异步 POST 签名换取真实的字节跳动 TOS / ImageX 直链。
    final playerPageUrl = '$_playerGateUrl/?url=${Uri.encodeComponent(rawUrl)}';
    final playerPageRes = await _dio.get<String>(
      playerPageUrl,
      options: Options(
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Referer': episodeUrl,
        },
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final pHtml = playerPageRes.data ?? '';
    final timeMatch = RegExp(r'''"time"\s*:\s*["']?(\d+)["']?''').firstMatch(pHtml)?.group(1);
    final vkeyMatch = RegExp(r'''"vkey"\s*:\s*["']([0-9a-fA-F]+)["']''').firstMatch(pHtml)?.group(1);

    if (timeMatch == null || vkeyMatch == null) {
      throw Exception('未在咕咕番播放网关中提取到有效鉴权令牌 (time/vkey)');
    }

    final apiRes = await _dio.post<dynamic>(
      '$_playerGateUrl/admin/mizhi_json.php',
      data: 'url=${Uri.encodeComponent(rawUrl)}&time=$timeMatch&key=&vkey=$vkeyMatch',
      options: Options(
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'X-Requested-With': 'XMLHttpRequest',
          'Referer': playerPageUrl,
          'User-Agent': _kDefaultUserAgent,
        },
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final apiData = parseJsonMap(apiRes.data);
    final directUrl = (apiData?['url']?.toString() ?? '').trim();

    if (directUrl.isEmpty || !directUrl.startsWith('http')) {
      throw Exception('咕咕番直链签发失败: ${apiData?['msg'] ?? '未返回有效播放地址'}');
    }

    final format = directUrl.contains('.m3u8') ? 'hls' : 'mp4';

    return SourceResolveResult(
      url: directUrl,
      headers: {
        'User-Agent': _kDefaultUserAgent,
      },
      format: format,
    );
  }
}
