import 'dart:async';
import 'package:dio/dio.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';

/// Animaku 服务端健康检查与连通性结果
class AnimakuHealthResult {
  final bool isOk;
  final int latencyMs;
  final String? version;
  final String? errorMessage;

  const AnimakuHealthResult({
    required this.isOk,
    required this.latencyMs,
    this.version,
    this.errorMessage,
  });
}

/// Animaku 服务端 HTTP 代理客户端
/// 负责在开启“服务端模式”时，与远程 animaku 实例进行搜索、选集与受控流解析
class AnimakuServerClient {
  AnimakuServerClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
                sendTimeout: const Duration(seconds: 8),
                headers: {
                  'Accept': 'application/json',
                  'User-Agent': 'Zakoway/2.0 (CrossPlatform; ServerMode)',
                },
              ),
            );

  static AnimakuServerClient? _instance;
  static AnimakuServerClient get instance => _instance ??= AnimakuServerClient();

  final Dio _dio;

  /// 服务端实际支持的源 ID 缓存池
  Set<String>? _cachedSupportedSources;
  DateTime? _sourcesCacheTime;

  /// 标准化根域名地址（确保无多余尾随斜杠）
  String get baseUrl {
    var raw = AppPreferences.getServerModeApiUrl().trim();
    if (raw.isEmpty) {
      raw = AppPreferences.defaultServerModeApiUrl;
    }
    while (raw.endsWith('/')) {
      raw = raw.substring(0, raw.length - 1);
    }
    return raw;
  }

  /// 归一化源 ID，兼容服务端历史别名
  String normalizeSourceId(String sourceId) {
    final norm = sourceId.trim().toLowerCase();
    if (norm == 'xifan_next' || norm == 'xifannext') return 'xifan-next';
    return norm;
  }

  /// 检查特定源当前是否被 animaku 服务端支持并接管
  bool isSourceSupported(String sourceId) {
    final norm = normalizeSourceId(sourceId);

    // 特殊处理说明：
    // anime1 等全量媒体代拉源（Full Media Proxy）播放时需服务端持续转发全部视频二进制流，
    // 会迅速吃满 VPS 下行带宽与月流量。为保护公共节点稳定性，客户端主动将其排除，保持本地直连。
    if (norm == 'anime1') {
      return false;
    }

    final cached = _cachedSupportedSources;
    if (cached == null || cached.isEmpty) {
      // 若尚未拉取列表，先基于已知服务端 100% 零带宽 CDN 直连固化源清单作初判
      const defaultKnown = {
        'xifan-next',
        'xifan',
        'cycani',
        'moonci',
        'tvtfun',
        'animoe',
      };
      return defaultKnown.contains(norm);
    }
    return cached.contains(norm) || (norm == 'xifan-next' && cached.contains('xifan'));
  }

  /// 连通性与健康度测试
  Future<AnimakuHealthResult> checkHealth() async {
    final stopwatch = Stopwatch()..start();
    final url = '$baseUrl/api/health';
    try {
      final res = await _dio.get(url);
      stopwatch.stop();
      if (res.statusCode == 200 && res.data is Map) {
        final data = res.data as Map;
        final ok = data['ok'] == true;
        final version = data['version']?.toString();
        return AnimakuHealthResult(
          isOk: ok,
          latencyMs: stopwatch.elapsedMilliseconds,
          version: version,
        );
      }
      return AnimakuHealthResult(
        isOk: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        errorMessage: '状态码异常: ${res.statusCode}',
      );
    } catch (e) {
      stopwatch.stop();
      return AnimakuHealthResult(
        isOk: false,
        latencyMs: stopwatch.elapsedMilliseconds,
        errorMessage: e.toString(),
      );
    }
  }

  /// 动态同步服务端已挂载的源清单
  Future<Set<String>> fetchSupportedSources({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedSupportedSources != null &&
        _sourcesCacheTime != null &&
        now.difference(_sourcesCacheTime!) < const Duration(minutes: 30)) {
      return _cachedSupportedSources!;
    }

    final url = '$baseUrl/api/source/list';
    try {
      final res = await _dio.get(url);
      if (res.statusCode == 200 && res.data is Map && res.data['data'] is List) {
        final list = res.data['data'] as List;
        final set = <String>{};
        for (final item in list) {
          if (item is Map && item['id'] != null) {
            set.add(item['id'].toString().trim().toLowerCase());
          }
        }
        if (set.isNotEmpty) {
          _cachedSupportedSources = set;
          _sourcesCacheTime = now;
          return set;
        }
      }
    } catch (_) {}
    return _cachedSupportedSources ?? const {};
  }

  /// 搜索番剧
  Future<List<SourceSearchResult>> search(String sourceId, String keyword) async {
    final normSource = normalizeSourceId(sourceId);
    final url = '$baseUrl/api/source/search';
    final res = await _dio.post(
      url,
      data: {
        'source': normSource,
        'keyword': keyword.trim(),
      },
    );

    if (res.statusCode == 200 && res.data is Map) {
      final data = res.data['data'];
      if (data is Map && data['items'] is List) {
        final items = data['items'] as List;
        final results = <SourceSearchResult>[];
        for (final it in items) {
          if (it is Map) {
            final name = it['name']?.toString() ?? '';
            final src = it['src']?.toString() ?? '';
            if (name.isNotEmpty && src.isNotEmpty) {
              results.add(
                SourceSearchResult(
                  name: name,
                  url: src,
                ),
              );
            }
          }
        }
        return results;
      }
    }
    return const [];
  }

  /// 获取线路与分集列表
  Future<List<SourceChapterRoad>> chapters(String sourceId, String animeUrl) async {
    final normSource = normalizeSourceId(sourceId);
    final url = '$baseUrl/api/source/chapters';
    final res = await _dio.post(
      url,
      data: {
        'source': normSource,
        'url': animeUrl.trim(),
      },
    );

    if (res.statusCode == 200 && res.data is Map) {
      final data = res.data['data'];
      if (data is Map && data['roads'] is List) {
        final roads = data['roads'] as List;
        final results = <SourceChapterRoad>[];
        for (final r in roads) {
          if (r is Map) {
            final roadName = r['name']?.toString() ?? '默认线路';
            final rawData = r['data'];
            final rawId = r['identifier'];

            final epUrls = rawData is List ? rawData.map((e) => e.toString()).toList() : <String>[];
            final epTitles = rawId is List ? rawId.map((e) => e.toString()).toList() : <String>[];

            final episodes = <SourceEpisode>[];
            final count = epUrls.length;
            for (var i = 0; i < count; i++) {
              final epTitle = i < epTitles.length ? epTitles[i] : '第${i + 1}集';
              episodes.add(
                SourceEpisode(
                  name: epTitle,
                  url: epUrls[i],
                ),
              );
            }

            if (episodes.isNotEmpty) {
              results.add(
                SourceChapterRoad(
                  name: roadName,
                  episodes: episodes,
                ),
              );
            }
          }
        }
        return results;
      }
    }
    return const [];
  }

  /// 解析播放直链并组装受控流地址
  Future<SourceResolveResult> resolve(String sourceId, String episodeUrl) async {
    final normSource = normalizeSourceId(sourceId);
    final url = '$baseUrl/api/source/resolve';
    final res = await _dio.post(
      url,
      data: {
        'source': normSource,
        'pageUrl': episodeUrl.trim(),
      },
    );

    if (res.statusCode == 200 && res.data is Map) {
      final data = res.data['data'];
      if (data is Map) {
        final streamUrl = data['streamUrl']?.toString() ?? '';
        final format = data['format']?.toString().toLowerCase() ?? 'hls';

        if (streamUrl.isNotEmpty) {
          final fullStreamUrl = streamUrl.startsWith('http://') || streamUrl.startsWith('https://')
              ? streamUrl
              : '$baseUrl${streamUrl.startsWith('/') ? '' : '/'}$streamUrl';

          return SourceResolveResult(
            url: fullStreamUrl,
            format: format == 'mp4' ? 'mp4' : 'hls',
            headers: const {},
          );
        }
      }
    }
    throw Exception('服务端解析播放地址失败: 未返回有效的 streamUrl');
  }

  /// 清空客户端对服务端的内存状态缓存
  void clearCache() {
    _cachedSupportedSources = null;
    _sourcesCacheTime = null;
  }
}
