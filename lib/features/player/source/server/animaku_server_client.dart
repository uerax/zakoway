import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/server/adapters/animaku_source_adapter.dart';

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
            ) {
    // 优先从本地持久化缓存恢复上一轮已探明的服务端源清单
    final persisted = AppPreferences.getServerModeCachedSources();
    if (persisted.isNotEmpty) {
      _cachedSupportedSources = persisted.map(normalizeSourceId).toSet();
      supportedSourcesNotifier.value = _cachedSupportedSources!;
    }
  }

  static AnimakuServerClient? _instance;
  static AnimakuServerClient get instance => _instance ??= AnimakuServerClient();

  final Dio _dio;

  /// 全局支持的源动态响应式监听器（供 UI 实时感知源变动并刷新徽章）
  final ValueNotifier<Set<String>> supportedSourcesNotifier =
      ValueNotifier<Set<String>>({});

  /// 服务端实际支持的源名称映射（供动态生成 RemoteServerSource 时读取显示名称）
  final Map<String, String> _serverSourceNames = {};
  Map<String, String> get serverSourceNames => Map.unmodifiable(_serverSourceNames);

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
    if (norm == 'xifan_next' || norm == 'xifannext' || norm == 'xifan') return 'xifan-next';
    if (norm == 'neosek') return 'neosekai';
    return norm;
  }

  /// 检查特定源当前是否被 animaku 服务端支持并接管（100% 动态探测匹配，不硬编码）
  bool isSourceSupported(String sourceId) {
    final norm = normalizeSourceId(sourceId);

    // 优先读取内存或持久化缓存
    final cached = _cachedSupportedSources ??=
        AppPreferences.getServerModeCachedSources().map(normalizeSourceId).toSet();

    if (cached.isEmpty) {
      // 若尚未拉取过列表，后台自动触发一次异步静默拉取
      fetchSupportedSources().ignore();
      return false;
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

  /// 动态同步服务端已挂载的源清单（从服务端 GET /api/source/list 探测并持久化）
  Future<Set<String>> fetchSupportedSources({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedSupportedSources != null &&
        _cachedSupportedSources!.isNotEmpty &&
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
        _serverSourceNames.clear();
        for (final item in list) {
          if (item is Map && item['id'] != null) {
            final id = normalizeSourceId(item['id'].toString());
            final name = item['name']?.toString() ?? id;
            set.add(id);
            _serverSourceNames[id] = name;
          }
        }
        if (set.isNotEmpty) {
          _cachedSupportedSources = set;
          _sourcesCacheTime = now;
          supportedSourcesNotifier.value = set;
          await AppPreferences.setServerModeCachedSources(set.toList());
          return set;
        }
      }
    } catch (_) {}
    return _cachedSupportedSources ?? const {};
  }

  /// 搜索番剧
  Future<List<SourceSearchResult>> search(String sourceId, String keyword) async {
    final normSource = normalizeSourceId(sourceId);
    final adapter = AnimakuAdapterRegistry.get(normSource);
    final url = '$baseUrl/api/source/search';

    try {
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
          return adapter.transformSearch(results, keyword: keyword);
        }
      }
      return adapter.transformSearch(const [], keyword: keyword);
    } catch (e) {
      final fallback = await adapter.onSearchFallback(e, keyword: keyword);
      if (fallback != null) {
        return fallback;
      }
      rethrow;
    }
  }

  /// 获取线路与分集列表
  Future<List<SourceChapterRoad>> chapters(String sourceId, String animeUrl) async {
    final normSource = normalizeSourceId(sourceId);
    final adapter = AnimakuAdapterRegistry.get(normSource);
    final url = '$baseUrl/api/source/chapters';

    try {
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

          final transformed = adapter.transformChapters(results, animeUrl: animeUrl);
          if (transformed.isEmpty || transformed.every((r) => r.episodes.isEmpty)) {
            final fallback = await adapter.onChaptersFallback(
              Exception('服务端未返回有效分集数据'),
              animeUrl: animeUrl,
            );
            if (fallback != null) return fallback;
          }
          return transformed;
        }
      }

      final transformed = adapter.transformChapters(const [], animeUrl: animeUrl);
      if (transformed.isNotEmpty && transformed.any((r) => r.episodes.isNotEmpty)) {
        return transformed;
      }
      final fallback = await adapter.onChaptersFallback(
        Exception('服务端分集响应异常: 状态码 ${res.statusCode}'),
        animeUrl: animeUrl,
      );
      if (fallback != null) return fallback;
      return const [];
    } catch (e) {
      final fallback = await adapter.onChaptersFallback(e, animeUrl: animeUrl);
      if (fallback != null) {
        return fallback;
      }
      rethrow;
    }
  }

  /// 解析播放直链并组装媒体地址
  /// 遵循 Animaku 原生 App 接入协议：优先直连源站原始 playUrl 配合 headers（零服务器带宽），
  /// 仅当 playUrl 为空时才降级回退至服务端受控流地址 streamUrl。
  Future<SourceResolveResult> resolve(String sourceId, String episodeUrl) async {
    final normSource = normalizeSourceId(sourceId);
    final adapter = AnimakuAdapterRegistry.get(normSource);
    final url = '$baseUrl/api/source/resolve';

    try {
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
          final playUrl = data['playUrl']?.toString() ?? '';
          final streamUrl = data['streamUrl']?.toString() ?? '';
          final format = data['format']?.toString().toLowerCase() ?? 'hls';
          final headers = <String, String>{};

          if (data['headers'] is Map) {
            (data['headers'] as Map).forEach((k, v) {
              if (k != null && v != null && v.toString().isNotEmpty) {
                headers[k.toString()] = v.toString();
              }
            });
          }

          SourceResolveResult? rawResult;
          // 1. 优先源站原始播放地址直连（零服务器代理带宽原则，原生注入 Referer/Cookie/UA）
          if (playUrl.isNotEmpty) {
            rawResult = SourceResolveResult(
              url: playUrl,
              format: format == 'mp4' ? 'mp4' : 'hls',
              headers: headers,
            );
          } else if (streamUrl.isNotEmpty) {
            // 2. 兜底回退：若服务端未给出原始 playUrl，使用受控代理流地址
            final fullStreamUrl = streamUrl.startsWith('http://') || streamUrl.startsWith('https://')
                ? streamUrl
                : '$baseUrl${streamUrl.startsWith('/') ? '' : '/'}$streamUrl';

            rawResult = SourceResolveResult(
              url: fullStreamUrl,
              format: format == 'mp4' ? 'mp4' : 'hls',
              headers: headers,
            );
          }

          if (rawResult != null) {
            return await adapter.transformResolve(rawResult, episodeUrl: episodeUrl);
          }
        }
      }
      throw Exception('服务端解析播放地址失败: 未返回有效的 playUrl 或 streamUrl');
    } catch (e) {
      final fallback = await adapter.onResolveFallback(e, episodeUrl: episodeUrl);
      if (fallback != null) {
        return fallback;
      }
      rethrow;
    }
  }

  /// 清空客户端对服务端的内存状态缓存
  void clearCache() {
    _cachedSupportedSources = null;
    _sourcesCacheTime = null;
    final persisted = AppPreferences.getServerModeCachedSources();
    if (persisted.isNotEmpty) {
      _cachedSupportedSources = persisted.map(normalizeSourceId).toSet();
      supportedSourcesNotifier.value = _cachedSupportedSources!;
    } else {
      supportedSourcesNotifier.value = const {};
    }
  }
}
