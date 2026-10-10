import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import '../models/source_models.dart';
import 'video_source.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

// 特殊处理说明：
// Animoe 服务端对 M3U8 播放列表文件实行了私有循环异或加密，魔数头为 'enc!' (0x65 0x6e 0x63 0x21)。
// 经逆向与重合指数分析，加密算法为 10 字节重复 XOR 流混淆，解密后还原出标准的网易云音乐对象存储切片列表。
const List<int> _kAnimoeXorKey = [179, 233, 144, 144, 144, 144, 53, 122, 115, 2];

/// Animoe 动漫 (animoe.org) 专有视频源
/// 1:1 对齐 animaku (apps/server/src/lib/animoe.ts) 规范
class AnimoeSource extends VideoSource {
  AnimoeSource({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;
  static const String _baseUrl = 'https://animoe.org';

  @override
  String get id => 'animoe';

  @override
  String get name => 'Animoe';

  @override
  String get version => '1.3.0';

  @override
  String get description => 'HLS · 网易云音乐 CDN 节点 (多线路字幕组)';

  Map<String, String> _headers([String? referer]) {
    final h = <String, String>{
      'User-Agent': _kDefaultUserAgent,
      'Accept': 'application/json, text/html, */*',
    };
    if (referer != null) h['Referer'] = referer;
    return h;
  }

  @override
  Future<List<SourceSearchResult>> search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) return [];

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
          .map((item) => SourceSearchResult(
                name: item['name']?.toString().trim() ?? '',
                url: '$_baseUrl/info/${item['id']}.html',
                cover: item['pic']?.toString(),
              ))
          .where((s) => s.name.isNotEmpty)
          .toList();
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

    // 1. 提取 Tab 标签（兼容 <a> 或 <div> 容器）
    final tabLabels = <String>[];
    final tabRegex = RegExp(
      r'''<(?:a|div)[^>]*class=["'][^"']*module-tab-item[^"']*["'][^>]*>(?:<span>)?(.*?)(?:</span>)?</(?:a|div)>''',
      caseSensitive: false,
    );
    for (final m in tabRegex.allMatches(html)) {
      final label = m.group(1)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      if (label.isNotEmpty && !RegExp(r'^(?:排序|正序|倒序)$').hasMatch(label)) {
        tabLabels.add(label);
      }
    }

    // 2. 提取分集列表
    final roads = <SourceChapterRoad>[];
    final boxRegex = RegExp(r'''<div[^>]*class=["'][^"']*module-play-list[^"']*["'][^>]*>([\s\S]*?)</div>''', caseSensitive: false);
    final boxMatches = boxRegex.allMatches(html);
    var roadIdx = 0;

    for (final bm in boxMatches) {
      final boxHtml = bm.group(1)!;
      final epRegex = RegExp(r'''<a[^>]*href=["'](/play/[^"']+)["'][^>]*>(.*?)</a>''', caseSensitive: false);
      final episodes = <SourceEpisode>[];

      for (final em in epRegex.allMatches(boxHtml)) {
        final href = em.group(1)!;
        final rawName = em.group(2)!.replaceAll(RegExp(r'<[^>]+>'), '').trim();
        final name = RegExp(r'^\d+$').hasMatch(rawName) ? '第${rawName.padLeft(2, '0')}集' : rawName;
        episodes.add(SourceEpisode(
          name: name,
          url: '$_baseUrl$href',
        ));
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
    final res = await _dio.get<String>(
      episodeUrl,
      options: Options(
        headers: _headers('$_baseUrl/'),
        sendTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    );

    final html = res.data ?? '';
    final match = RegExp(r'var\s+player_aaaa\s*=\s*(\{[\s\S]*?\})\s*<').firstMatch(html) ??
        RegExp(r'player_aaaa\s*=\s*(\{[\s\S]*?\})').firstMatch(html);

    if (match == null) {
      throw Exception('未在 Animoe 播放页提取到 player_aaaa 配置');
    }

    final player = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    var directUrl = (player['url']?.toString() ?? '').trim();

    if (directUrl.contains('*')) {
      directUrl = directUrl.split('*')[0].trim();
    }

    if (!directUrl.startsWith('http')) {
      throw Exception('Animoe 媒体地址无效: $directUrl');
    }

    // 特殊处理说明：
    // Animoe 返回的 m3u8 地址若携带私有 'enc!' 循环异或混淆，
    // 原生播放内核（media_kit / mpv）无法识别该非标流，必须在应用层执行 10 字节 XOR 解密，
    // 还原出标准 #EXTM3U 并落地为本地临时文件交付播放器。
    // 同时网易云音乐对象存储 CDN (p1.music.126.net) 拦截了 Dart 默认 UA（报 403），
    // 必须在请求头显式注入标准现代浏览器 User-Agent。
    var resolvedUrl = directUrl;
    if (directUrl.toLowerCase().contains('.m3u8')) {
      try {
        final cacheFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}animoe_${directUrl.hashCode.abs()}.m3u8',
        );

        // 若本地已有 1 小时内解密就绪的文件，直接复用以实现 0ms 瞬间起播
        final fileExists = await cacheFile.exists();
        final isFresh = fileExists &&
            DateTime.now().difference(await cacheFile.lastModified()).inMinutes < 60;

        if (isFresh) {
          resolvedUrl = cacheFile.uri.toString();
        } else {
          final m3u8Res = await _dio.get<List<int>>(
            directUrl,
            options: Options(
              headers: _headers('$_baseUrl/'),
              responseType: ResponseType.bytes,
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
            ),
          );

          final bytes = m3u8Res.data;
          if (bytes != null && bytes.length > 4) {
            final isEncrypted = bytes[0] == 0x65 &&
                bytes[1] == 0x6e &&
                bytes[2] == 0x63 &&
                bytes[3] == 0x21; // 'enc!'

            if (isEncrypted) {
              final decryptedBytes = Uint8List(bytes.length - 4);
              for (var i = 0; i < decryptedBytes.length; i++) {
                decryptedBytes[i] = bytes[i + 4] ^ _kAnimoeXorKey[i % 10];
              }

              var decryptedText = utf8.decode(decryptedBytes, allowMalformed: true);
              if (!decryptedText.startsWith('#')) {
                decryptedText = '#$decryptedText';
              }

              await cacheFile.writeAsString(decryptedText);
              resolvedUrl = cacheFile.uri.toString();
            }
          }
        }
      } catch (_) {
        // 容错降级：若网络拉取解密过程出现偶发异常，平滑回退直接返回原始链接
        resolvedUrl = directUrl;
      }
    }

    return SourceResolveResult(
      url: resolvedUrl,
      headers: {
        'Referer': '$_baseUrl/',
        'User-Agent': _kDefaultUserAgent,
      },
      format: 'hls',
    );
  }
}
