import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// LIBVIO (libvio.app 发布页动态探活镜像) 专有视频源
/// 1:1 对齐 animaku 架构规范：
/// 1. 动态访问发布页 (https://www.libvio.app/)，逆向 XOR 混淆算法提取最新动态镜像群；
/// 2. 并发探活自动检测可用镜像地址并设立 2 小时缓存；
/// 3. 全量支持 MacCMS stui 模板的搜索、选集与直链解析。
class LibvioSource extends VideoSource {
  LibvioSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  // 永久发布页与备选发布页列表
  static const String _defaultReleasePage = 'https://www.libvio.app/';
  static const List<String> _fallbackReleasePages = [
    'https://libviogroup.github.io/',
    'https://libviofabu.com/',
  ];

  // 默认保底镜像（当发布页因网络原因彻底无法访问时使用）
  static const List<String> _defaultMirrors = [
    'https://libvio.host',
    'https://www.libvio.to',
    'https://libviobd.com',
  ];

  String? _cachedActiveBaseUrl;
  int _cacheTime = 0;
  Future<String>? _resolvingFuture;

  @override
  String get id => 'libvio';

  @override
  String get name => 'LIBVIO';

  @override
  String get version => '1.3.0';

  @override
  String get description => '1080P · 动态发布页实时探活镜像 (全品类影视/动漫)';

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

  /// XOR 混淆解密算法（对齐 libvio.app 发布的 xorDecode 逻辑）
  String _xorDecode(String encoded, String key) {
    final bytes = encoded.split(',').map((n) => int.tryParse(n.trim()) ?? 0).toList();
    final out = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      final kChar = key.codeUnitAt(i % key.length);
      out.writeCharCode(bytes[i] ^ kChar);
    }
    return out.toString();
  }

  /// 从发布页 HTML 中提取 XOR Key 并逆向解码可用网址 (_BACKUP)
  List<String> _extractMirrorsFromReleaseHtml(String html) {
    final kMatch = RegExp(r'''const\s+_K\s*=\s*['"]([^'"]+)['"]''').firstMatch(html);
    final key = kMatch?.group(1) ?? 'lv2025';

    final backupMatch = RegExp(r'''(?:const|let|var)\s+_BACKUP\s*=\s*\[([\s\S]*?)\];''').firstMatch(html);
    final backupBlock = backupMatch?.group(1) ?? html;

    final decodeRegex = RegExp(r'''xorDecode\s*\(\s*['"]([^'"]+)['"]\s*,\s*_K\s*\)''');
    final domains = <String>[];

    for (final m in decodeRegex.allMatches(backupBlock)) {
      final encodedStr = m.group(1)!;
      final decoded = _xorDecode(encodedStr, key).trim();
      if (decoded.isNotEmpty) {
        final fullUrl = decoded.startsWith('http') ? decoded : 'https://$decoded';
        if (!domains.contains(fullUrl)) {
          domains.add(fullUrl);
        }
      }
    }

    return domains;
  }

  /// 自动检测探活镜像，挑选延迟最低或最先响应的有效地址
  Future<String?> _probeFirstActiveMirror(List<String> candidates) async {
    if (candidates.isEmpty) return null;

    final futures = candidates.map((url) async {
      try {
        final res = await _dio.get<dynamic>(
          url,
          options: Options(
            headers: _headers(),
            sendTimeout: const Duration(seconds: 3),
            receiveTimeout: const Duration(seconds: 3),
            validateStatus: (_) => true,
          ),
        );
        // 服务器只要有握手响应（哪怕是 403 地区限制也证明服务器在线活体），均属于有效镜像
        if (res.statusCode != null && res.statusCode! > 0) {
          return url;
        }
      } catch (_) {}
      return null;
    });

    try {
      final results = await Future.wait(futures);
      final active = results.whereType<String>().firstOrNull;
      return active;
    } catch (_) {
      return null;
    }
  }

  /// 动态解析并返回当前最高可用的 LIBVIO 镜像 Base URL
  Future<String> _ensureActiveBaseUrl({bool forceRefresh = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!forceRefresh && _cachedActiveBaseUrl != null && (now - _cacheTime) < 2 * 3600 * 1000) {
      return _cachedActiveBaseUrl!;
    }

    if (_resolvingFuture != null) {
      return _resolvingFuture!;
    }

    _resolvingFuture = () async {
      final releasePages = [_defaultReleasePage, ..._fallbackReleasePages];
      List<String> decodedMirrors = [];

      for (final pageUrl in releasePages) {
        try {
          final res = await _dio.get<String>(
            pageUrl,
            options: Options(
              headers: _headers(),
              sendTimeout: const Duration(seconds: 4),
              receiveTimeout: const Duration(seconds: 4),
            ),
          );
          final html = res.data ?? '';
          final mirrors = _extractMirrorsFromReleaseHtml(html);
          if (mirrors.isNotEmpty) {
            decodedMirrors = mirrors;
            break;
          }
        } catch (_) {}
      }

      final allCandidates = {
        ...decodedMirrors,
        ..._defaultMirrors,
      }.toList();

      final active = await _probeFirstActiveMirror(allCandidates);
      final finalUrl = active ?? allCandidates.firstOrNull ?? _defaultMirrors.first;

      _cachedActiveBaseUrl = finalUrl.replaceAll(RegExp(r'/+$'), '');
      _cacheTime = DateTime.now().millisecondsSinceEpoch;
      return _cachedActiveBaseUrl!;
    }();

    try {
      return await _resolvingFuture!;
    } finally {
      _resolvingFuture = null;
    }
  }

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    try {
      final base = await _ensureActiveBaseUrl();
      final res = await _dio.get<String>(
        '$base/search/-------------.html?wd=${Uri.encodeComponent(q)}',
        options: Options(
          headers: _headers('$base/'),
          sendTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );

      final html = res.data ?? '';
      final items = <SourceSearchResult>[];
      final seen = <String>{};

      // 匹配 stui-vodlist 卡片: <a class="stui-vodlist__thumb ... href="/detail/1234.html" title="xxx" data-original="xxx"
      final thumbRegex = RegExp(
        r'''<a[^>]*class=["'][^"']*stui-vodlist__thumb[^"']*["'][^>]*href=["'](/detail/[^"']+)["'][^>]*title=["']([^"']+)["'][^>]*(?:data-original|data-src)=["']([^"']+)["']''',
        caseSensitive: false,
      );

      for (final m in thumbRegex.allMatches(html)) {
        final path = m.group(1)!;
        final title = m.group(2)!.trim();
        final cover = m.group(3)?.trim();
        final detailUrl = '$base$path';
        if (title.isNotEmpty && seen.add(detailUrl)) {
          items.add(SourceSearchResult(name: title, url: detailUrl, cover: cover));
        }
      }

      // 回退解析：若未命中 thumb，解析通用 title 链接
      if (items.isEmpty) {
        final linkRegex = RegExp(r'''<h4[^>]*class=["']title["'][^>]*>\s*<a[^>]*href=["'](/detail/[^"']+)["'][^>]*>([^<]+)</a>''', caseSensitive: false);
        for (final m in linkRegex.allMatches(html)) {
          final path = m.group(1)!;
          final title = m.group(2)!.trim();
          final detailUrl = '$base$path';
          if (title.isNotEmpty && seen.add(detailUrl)) {
            items.add(SourceSearchResult(name: title, url: detailUrl));
          }
        }
      }

      return items;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async {
    final base = await _ensureActiveBaseUrl();
    final detailUrl = animeUrl.startsWith('http') ? animeUrl : '$base$animeUrl';

    final res = await _dio.get<String>(
      detailUrl,
      options: Options(
        headers: _headers('$base/'),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final html = res.data ?? '';

    // 1. 提取多线路 Tab 名称
    final tabLabels = <String>[];
    final tabRegex = RegExp(r'''<li[^>]*>\s*<a[^>]*data-toggle=["']tab["'][^>]*>(.*?)</a>''', caseSensitive: false);
    for (final tm in tabRegex.allMatches(html)) {
      final name = tm.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (name.isNotEmpty) tabLabels.add(name);
    }

    // 2. 提取分集播放列表
    final roads = <SourceChapterRoad>[];
    final boxRegex = RegExp(
      r'''<ul[^>]*class=["'][^"']*stui-content__playlist[^"']*["'][^>]*>([\s\S]*?)</ul>''',
      caseSensitive: false,
    );
    final boxMatches = boxRegex.allMatches(html);
    var roadIdx = 0;

    for (final bm in boxMatches) {
      final boxHtml = bm.group(1)!;
      final epRegex = RegExp(r'''<a[^>]*href=["']((?:/play/|/w/)[^"']+)["'][^>]*>([^<]+)</a>''', caseSensitive: false);
      final episodes = <SourceEpisode>[];

      for (final em in epRegex.allMatches(boxHtml)) {
        final href = em.group(1)!;
        final name = em.group(2)!.trim();
        if (href.isNotEmpty && name.isNotEmpty) {
          final absUrl = href.startsWith('http') ? href : '$base$href';
          episodes.add(SourceEpisode(name: name, url: absUrl));
        }
      }

      if (episodes.isNotEmpty) {
        final roadName = roadIdx < tabLabels.length ? tabLabels[roadIdx] : '线路 ${roadIdx + 1}';
        roads.add(SourceChapterRoad(name: roadName, episodes: episodes));
        roadIdx++;
      }
    }

    return roads;
  }

  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    final base = await _ensureActiveBaseUrl();
    final playUrl = episodeUrl.startsWith('http') ? episodeUrl : '$base$episodeUrl';

    final res = await _dio.get<String>(
      playUrl,
      options: Options(
        headers: _headers('$base/'),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final html = res.data ?? '';
    final match = RegExp(r'var\s+player_aaaa\s*=\s*(\{[\s\S]*?\})\s*<').firstMatch(html) ??
        RegExp(r'player_aaaa\s*=\s*(\{[\s\S]*?\})').firstMatch(html);

    if (match == null) {
      throw Exception('未在 LIBVIO 播放页提取到 player_aaaa 配置: $playUrl');
    }

    final player = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    var directUrl = (player['url']?.toString() ?? '').trim();
    final encrypt = player['encrypt'] ?? 0;

    if (encrypt == 1) {
      try {
        directUrl = Uri.decodeQueryComponent(directUrl);
      } catch (_) {}
    } else if (encrypt == 2) {
      try {
        final bytes = base64Decode(directUrl);
        final decoded = utf8.decode(bytes, allowMalformed: true);
        try {
          directUrl = Uri.decodeQueryComponent(decoded);
        } catch (_) {
          directUrl = decoded;
        }
      } catch (_) {}
    }

    if (directUrl.contains('*')) {
      directUrl = directUrl.split('*')[0].trim();
    }

    if (!directUrl.startsWith('http')) {
      throw Exception('LIBVIO 直链解析失败: $directUrl');
    }

    return SourceResolveResult(
      url: directUrl,
      headers: {
        'Referer': '$base/',
        'User-Agent': _kDefaultUserAgent,
      },
      format: directUrl.contains('.m3u8') ? 'hls' : 'mp4',
    );
  }
}
