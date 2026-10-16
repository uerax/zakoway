import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// MX动漫 (dcc3.com) 专有视频源
class MxdmSource extends VideoSource {
  MxdmSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _baseUrl = 'https://www.dcc3.com';

  @override
  String get id => 'mxdm';

  @override
  String get name => 'MX动漫';

  @override
  String get version => '1.3.0';

  @override
  String get description => 'HLS · 备用多线路模板解析';

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
        '$_baseUrl/search/?wd=${Uri.encodeComponent(q)}',
        options: Options(
          headers: _headers('$_baseUrl/'),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final html = res.data ?? '';
      // 特殊处理说明：
      // 源站改版后详情页链接从旧版 /comic/\d+\.html 全面迁移至 /detail/\d+/?，
      // 此处正则使用联合匹配以向下兼容新老版本页面结构。
      final itemRegex = RegExp(
        r'''<a[^>]*href=["'](/detail/\d+/?|/comic/\d+\.html)["'][^>]*title=["']([^"']+)["']''',
        caseSensitive: false,
      );
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

    // 特殊处理说明：
    // MX动漫改版后，页面通过 <div class="tabs"> 存放线路名，<div class="row"> 存放各线路的分集列表。
    // 为实现最大程度的容错与向下兼容，优先尝试解析现代 tabs/row 结构，未命中时回退到旧版 <ul> 匹配。
    final tabs = <String>[];
    final tabsRegex = RegExp(r'''<div class="tabs"[^>]*>([\s\S]*?)</div>''', caseSensitive: false);
    final tabsMatch = tabsRegex.firstMatch(html);
    if (tabsMatch != null) {
      final aRegex = RegExp(r'''<a[^>]*>(.*?)</a>''', caseSensitive: false);
      for (final am in aRegex.allMatches(tabsMatch.group(1)!)) {
        final label = am.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        if (label.isNotEmpty && !label.contains('排序')) tabs.add(label);
      }
    }

    final rowRegex = RegExp(r'''<div class="row"[^>]*>([\s\S]*?)</div>''', caseSensitive: false);
    final rowMatches = rowRegex.allMatches(html);

    if (rowMatches.isNotEmpty) {
      var rIdx = 0;
      for (final rm in rowMatches) {
        final rowHtml = rm.group(1)!;
        final epRegex = RegExp(r'''<a[^>]*href=["'](/play/[^"']+)["'][^>]*>(.*?)</a>''', caseSensitive: false);
        final episodes = <SourceEpisode>[];

        for (final em in epRegex.allMatches(rowHtml)) {
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
          final roadName = rIdx < tabs.length ? tabs[rIdx] : '线路 ${rIdx + 1}';
          roads.add(SourceChapterRoad(name: roadName, episodes: episodes));
          rIdx++;
        }
      }
    }

    // 回退旧版模板：若 tabs/row 未提取到，解析 ul.playlist 结构
    if (roads.isEmpty) {
      final boxRegex = RegExp(r'''<ul[^>]*class=["'][^"']*(?:movurl|playlist|anthology)[^"']*["'][^>]*>([\s\S]*?)</ul>''', caseSensitive: false);
      final boxMatches = boxRegex.allMatches(html);
      var roadIdx = 0;

      for (final bm in boxMatches) {
        final boxHtml = bm.group(1)!;
        final epRegex = RegExp(r'''<a[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>''', caseSensitive: false);
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
    }

    // 特殊处理说明：
    // MX动漫部分番剧的首条线路（如“高清”）指向已断开的失效 CDN (如 cdn.vvvip-plays33.cc 发生 TLS 握手断开)；
    // 而 ikun 与 量子 线路均为大型高可用主流切片 CDN，极速稳定。
    // 因此对线路进行稳定性优先级排序，将 ikun 与 量子 置于首位，规避默认选线踩坑。
    int getLinePriority(String name) {
      final n = name.trim().toLowerCase();
      if (n.contains('ikun')) return 100;
      if (n.contains('量子')) return 90;
      if (n.contains('非凡')) return 70;
      if (n.contains('高清')) return 40;
      return 60;
    }

    roads.sort((a, b) => getLinePriority(b.name).compareTo(getLinePriority(a.name)));

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

    // 特殊处理说明：
    // MX动漫已升级为 Artplayer 播放内核，播放直链直接内嵌在 var art = new Artplayer({ url: '...' }) 中，
    // 优先从 Artplayer 配置中捕获 m3u8 地址，若无再回退至经典 player_aaaa 模式。
    final artMatch = RegExp(r'''url:\s*['"](https?://[^'"]+\.m3u8[^'"]*)['"]''', caseSensitive: false).firstMatch(html);
    if (artMatch != null) {
      final directUrl = artMatch.group(1)!.trim();
      return SourceResolveResult(
        url: directUrl,
        headers: {
          'Referer': '$_baseUrl/',
          'User-Agent': _kDefaultUserAgent,
        },
        format: 'hls',
      );
    }

    final match = RegExp(r'var\s+player_aaaa\s*=\s*(\{[\s\S]*?\})\s*<').firstMatch(html) ??
        RegExp(r'player_aaaa\s*=\s*(\{[\s\S]*?\})').firstMatch(html);

    if (match == null) {
      throw Exception('未在 MX动漫 播放页找到有效播放源配置 (Artplayer / player_aaaa)');
    }

    final player = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    var directUrl = (player['url']?.toString() ?? '').trim();
    final encrypt = player['encrypt'] ?? 0;

    if (encrypt == 1) {
      directUrl = jsUnescape(directUrl);
    } else if (encrypt == 2) {
      try {
        final bytes = base64Decode(directUrl);
        final decoded = utf8.decode(bytes, allowMalformed: true);
        directUrl = jsUnescape(decoded);
      } catch (_) {
        directUrl = jsUnescape(directUrl);
      }
    }

    if (!directUrl.startsWith('http')) {
      throw Exception('MX动漫 直链解析失败: $directUrl');
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
