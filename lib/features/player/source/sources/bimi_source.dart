import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/source_models.dart';
import '../utils/aes_gcm_decryptor.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// 哔咪动漫 (bimiacg14.net) 专有视频源
/// 适配器 ID: bimi, 权重: 60 (对齐 xifan-next), 归属于纯直连组 (isDirect: true)
class BimiSource extends VideoSource {
  BimiSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _baseUrl = 'https://www.bimiacg14.net';

  @override
  String get id => 'bimi';

  @override
  int get weight => 60;

  @override
  String get name => '哔咪';

  @override
  String get version => '1.0.0';

  @override
  String get description => '1080P · 字节/快手/电信 CDN 极速直链 (权重 60)';

  @override
  bool get isDirect => true;

  void _log(String message) {
    debugPrint('[BimiSource] $message');
  }

  Map<String, String> _headers([String? referer, String? cookie]) {
    final h = <String, String>{
      'User-Agent': _kDefaultUserAgent,
      'Accept': 'application/json, text/html, application/xhtml+xml, */*',
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    };
    if (referer != null) h['Referer'] = referer;
    if (cookie != null) h['Cookie'] = cookie;
    return h;
  }

  /// 1. 搜索番剧 (Suggest JSON API 极速检索)
  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

    try {
      final res = await _dio.get<dynamic>(
        '$_baseUrl/index.php/ajax/suggest?mid=1&wd=${Uri.encodeComponent(q)}',
        options: Options(
          headers: _headers('$_baseUrl/'),
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );

      final data = parseJsonMap(res.data);
      final list = (data?['list'] as List?) ?? [];
      final results = <SourceSearchResult>[];
      final seenIds = <String>{};

      for (final it in list.whereType<Map<String, dynamic>>()) {
        final id = it['id']?.toString() ?? '';
        final name = it['name']?.toString().trim() ?? '';
        if (id.isEmpty || name.isEmpty || seenIds.contains(id)) continue;
        seenIds.add(id);

        results.add(SourceSearchResult(
          name: name,
          url: '$_baseUrl/bangumi/bi/$id/',
          cover: it['pic']?.toString(),
        ));
      }

      return results;
    } catch (e) {
      _log('搜索异常 "$q": $e');
      return [];
    }
  }

  /// 2. 获取分集线路 (过滤掉仅支持客户端播放的 APP 专用线路)
  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async {
    final match = RegExp(r'/bangumi/bi/(\d+)').firstMatch(animeUrl) ??
        RegExp(r'(\d+)$').firstMatch(animeUrl);
    if (match == null) {
      throw Exception('无法从链接提取 Bimi 番剧 ID: $animeUrl');
    }
    final animeId = match.group(1)!;

    final detailUrl = '$_baseUrl/bangumi/bi/$animeId/';
    final res = await _dio.get<String>(
      detailUrl,
      options: Options(
        headers: _headers('$_baseUrl/'),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final html = res.data ?? '';

    // 1. 提取线路 Tab：<button ... data-source-tab="3">线路名<span>集数</span></button>
    final tabRegex = RegExp(
      r'''data-source-tab=["'](\d+)["'][^>]*>(.*?)<\/button>''',
      caseSensitive: false,
    );
    final tabs = <({String sid, String name})>[];

    for (final m in tabRegex.allMatches(html)) {
      final sid = m.group(1)!;
      final rawText = m.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      // 过滤 APP 专属客户端线路
      if (rawText.toUpperCase().contains('APP')) continue;
      tabs.add((sid: sid, name: rawText.isNotEmpty ? rawText : '线路 $sid'));
    }

    final roads = <SourceChapterRoad>[];

    // 2. 依次提取各线路面板分集
    for (final tab in tabs) {
      // 查找面板：data-source-panel="{sid}"
      final panelRegex = RegExp(
        '''data-source-panel=["']${tab.sid}["'][^>]*>([\\s\\S]*?)(?:<\\/div>\\s*(?:<div|\\Z)|<div class=["']episode-panel["']|id=["']source-panel-)''',
        caseSensitive: false,
      );
      final panelMatch = panelRegex.firstMatch(html);
      final panelHtml = panelMatch != null ? panelMatch.group(1)! : html;

      final epRegex = RegExp(
        '''href=["']([^"']*\\/play\\/${tab.sid}\\/\\d+\\/?)["'][^>]*>(.*?)<\\/a>''',
        caseSensitive: false,
      );
      final episodes = <SourceEpisode>[];

      for (final em in epRegex.allMatches(panelHtml)) {
        final href = em.group(1)!.trim();
        final rawTitle = em.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        final title = rawTitle.isNotEmpty ? rawTitle : '第 ${episodes.length + 1} 话';
        final absUrl = href.startsWith('http') ? href : '$_baseUrl$href';
        episodes.add(SourceEpisode(name: title, url: absUrl));
      }

      if (episodes.isNotEmpty) {
        roads.add(SourceChapterRoad(name: tab.name, episodes: episodes));
      }
    }

    // 兜底：如果上面的面板提取未匹配，尝试通用 play 链接分组
    if (roads.isEmpty) {
      final generalEpRegex = RegExp(
        r'''href=["']([^"']*/play/(\d+)/(\d+)/?)["'][^>]*>(.*?)</a>''',
        caseSensitive: false,
      );
      final grouped = <String, List<SourceEpisode>>{};

      for (final gm in generalEpRegex.allMatches(html)) {
        final href = gm.group(1)!.trim();
        final sid = gm.group(2)!;
        final rawTitle = gm.group(4)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        final title = rawTitle.isNotEmpty ? rawTitle : '第 ${grouped[sid]?.length ?? 1} 话';
        final absUrl = href.startsWith('http') ? href : '$_baseUrl$href';

        grouped.putIfAbsent(sid, () => []).add(SourceEpisode(name: title, url: absUrl));
      }

      for (final entry in grouped.entries) {
        roads.add(SourceChapterRoad(name: '线路 ${entry.key}', episodes: entry.value));
      }
    }

    if (roads.isEmpty) {
      throw Exception('未在 Bimi 详情页找到有效选集（该作品可能仅支持在客户端播放）');
    }

    return roads;
  }

  /// 3. 解析播放直链 (兑换凭证并执行 AES-256-GCM 本地解密)
  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async {
    final absUrl = episodeUrl.startsWith('http') ? episodeUrl : '$_baseUrl$episodeUrl';

    // 1. 请求播放页，提取 PHPSESSID Cookie 与页面配置中的 Token
    final pageRes = await _dio.get<String>(
      absUrl,
      options: Options(
        headers: _headers('$_baseUrl/'),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final rawCookie = pageRes.headers['set-cookie']?.join('; ') ?? '';
    final sessionMatch = RegExp(r'PHPSESSID=([^;]+)', caseSensitive: false).firstMatch(rawCookie);
    final sessionCookie = sessionMatch != null ? 'PHPSESSID=${sessionMatch.group(1)}' : '';

    final html = pageRes.data ?? '';
    final tokenMatch = RegExp(r'''"token"\s*:\s*"([^"]+)"''').firstMatch(html);
    if (tokenMatch == null || tokenMatch.group(1) == null) {
      throw Exception('未在 Bimi 播放页找到播放凭证（该剧集可能仅支持在客户端播放）');
    }
    final token = tokenMatch.group(1)!;

    // 2. 生成 32 字节 (64 位 hex) 随机挑战码
    final random = Random.secure();
    final challengeBytes = List<int>.generate(32, (_) => random.nextInt(256));
    final challenge = challengeBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // 3. 向 play.php?resolve=1 兑换密文数据包
    final resolveUrl = '$_baseUrl/static/danmu/play.php?resolve=1';
    final postRes = await _dio.post<dynamic>(
      resolveUrl,
      data: 'token=${Uri.encodeComponent(token)}&challenge=${Uri.encodeComponent(challenge)}',
      options: Options(
        contentType: 'application/x-www-form-urlencoded;charset=UTF-8',
        headers: {
          'User-Agent': _kDefaultUserAgent,
          'Origin': _baseUrl,
          'Referer': absUrl,
          if (sessionCookie.isNotEmpty) 'Cookie': sessionCookie,
        },
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final resData = parseJsonMap(postRes.data);
    if (resData?['code'] != 1 || resData?['data'] == null) {
      throw Exception('Bimi 凭证兑换失败: ${resData?['msg'] ?? "源站无响应"}');
    }

    final data = resData!['data'] as Map<String, dynamic>;
    final iv = data['iv']?.toString() ?? '';
    final ciphertext = data['ciphertext']?.toString() ?? '';

    if (iv.isEmpty || ciphertext.isEmpty) {
      throw Exception('Bimi 加密数据包格式不完整');
    }

    // 4. 本地 AES-256-GCM / CTR 解密出直链
    final decrypted = AesGcmDecryptor.decryptBimiPayload(
      token: token,
      challenge: challenge,
      ivBase64: iv,
      ciphertextBase64: ciphertext,
    );

    final playUrl = decrypted['url']?.toString().trim() ?? '';
    if (playUrl.isEmpty) {
      throw Exception('Bimi 解密明文中缺少视频直链');
    }

    final format = playUrl.contains('.m3u8') ? 'hls' : 'mp4';

    return SourceResolveResult(
      url: playUrl,
      headers: {
        'User-Agent': _kDefaultUserAgent,
      },
      format: format,
    );
  }
}
