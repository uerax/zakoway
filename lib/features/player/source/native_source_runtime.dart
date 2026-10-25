import 'dart:convert';
import 'dart:developer' as developer;
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:zakoway/core/network/player_media_disk_cache_manager.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/core/utils/timed_cache.dart';
import 'package:zakoway/features/player/source/engines/animaku_server_engine.dart';
import 'package:zakoway/features/player/source/engines/local_source_engine.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/source_bundle_manager.dart';
import 'package:zakoway/features/player/source/sources/video_source.dart';

/// 统一视频源调度中心与双模路由协调器 (Source Routing Coordinator)
///
/// 架构职责划分：
/// 1. 负责 L1 内存缓存 + L2 硬盘持久化缓存的统一维护与前缀命名空间物理隔离；
/// 2. 负责 In-Flight 单飞请求去重锁，杜绝并发探测时的网络风暴；
/// 3. 作为门面协调器，将底层执行解耦并平级委派给：
///    - [LocalSourceEngine]：负责 15 个本地原生 Dart 爬虫源与 WebView 视频流嗅探；
///    - [AnimakuServerEngine]：负责 Animaku 服务端代理交互与动态扩展源生命周期管理。
class NativeSourceRuntime {
  NativeSourceRuntime({
    Dio? dio,
    LocalSourceEngine? localEngine,
    AnimakuServerEngine? serverEngine,
  }) : _localEngine = localEngine ?? LocalSourceEngine(dio: dio) {
    _serverEngine = serverEngine ??
        AnimakuServerEngine(
          onSourcesChanged: () => SourceBundleManager.instance.notifySourceChanges(),
          isLocalSourceChecker: _localEngine.isLocalSource,
        );
    AppPreferences.serverModeNotifier.addListener(_onServerModeChanged);
  }

  final LocalSourceEngine _localEngine;
  late final AnimakuServerEngine _serverEngine;

  void _onServerModeChanged() {
    clearMemoryCache();
    _serverEngine.onServerModeChanged();
  }

  /// 检查特定源是否为本地内置的原生 Dart 源
  bool isLocalSource(String sourceId) => _localEngine.isLocalSource(sourceId);

  /// 注册本地源（用于测试或动态追加）
  void registerSource(VideoSource source) => _localEngine.registerSource(source);

  /// 获取指定视频源（优先查找本地源，未命中则查找服务端动态扩展源）
  VideoSource? getSource(String sourceId) =>
      _localEngine.getSource(sourceId) ?? _serverEngine.getRemoteSource(sourceId);

  bool get isInitialized => true;

  /// 全局视频源包元数据
  SourceBundleMeta get bundleMeta => SourceBundleMeta(
        version: '2.0.0-native',
        buildTime: DateTime.now().toIso8601String(),
        minApiLevel: 1,
        adapters: {
          ..._localEngine.adapters,
          ..._serverEngine.adapters,
        },
      );

  /// 当前所有可用的视频源元数据列表（本地源 + 服务端动态扩展源）
  List<SourceMeta> get availableSources => [
        ..._localEngine.availableSources,
        ..._serverEngine.dynamicSources,
      ];

  Future<void> initialize({String? bundleCode}) async {
    // 瞬时就绪
  }

  // ================= 缓存基础设施与单飞锁 =================

  // L1 内存缓存池 (O(1) 毫秒级秒开)
  // 1. 搜索结果: 2 小时
  final TimedKeyedCache<String, List<SourceSearchResult>> _searchMemoryCache =
      TimedKeyedCache(maxAge: const Duration(hours: 2), maxEntries: 200);

  // 2. 选集线路: 30 分钟
  final TimedKeyedCache<String, List<SourceChapterRoad>> _chaptersMemoryCache =
      TimedKeyedCache(maxAge: const Duration(minutes: 30), maxEntries: 200);

  // 3. 直链解析: 1 分钟短时防抖缓存 (绝不做 L2 磁盘持久化)
  final TimedKeyedCache<String, SourceResolveResult> _resolveMemoryCache =
      TimedKeyedCache(maxAge: const Duration(minutes: 1), maxEntries: 100);

  // 并发去重单飞锁 (杜绝并发探测时的重复网络请求)
  final Map<String, Future<List<SourceSearchResult>>> _inflightSearch = {};
  final Map<String, Future<List<SourceChapterRoad>>> _inflightChapters = {};
  final Map<String, Future<SourceResolveResult>> _inflightResolve = {};

  // ================= 核心双模路由调度方法 =================

  /// 搜索番剧 (带 L1 内存 + L2 硬盘双层缓存与请求去重，支持服务端代理双模路由)
  Future<List<SourceSearchResult>> search(
    String sourceId,
    String keyword, {
    bool bypassCache = false,
  }) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return const [];

    final useServer = _serverEngine.isSourceSupported(sourceId);

    // 服务端模式专属前缀隔离，避免与本地模式历史结果脏互串
    final cachePrefix = useServer ? 'srv_' : '';
    final cacheKey = '$cachePrefix$sourceId:${kw.toLowerCase()}';
    final safeKw = base64Url.encode(utf8.encode(kw.toLowerCase()));
    final diskCacheKey = '${cachePrefix}src_search_${sourceId}_$safeKw';

    if (!bypassCache) {
      // 1. L1 内存缓存
      final memHit = _searchMemoryCache.get(cacheKey);
      if (memHit != null) return memHit;

      // 2. L2 本地硬盘持久化缓存
      final disk = PlayerMediaDiskCacheManager.instance;
      if (disk != null) {
        try {
          final diskData = await disk.getJson(diskCacheKey);
          if (diskData is List && diskData.isNotEmpty) {
            final list = diskData
                .whereType<Map<String, dynamic>>()
                .map(SourceSearchResult.fromJson)
                .toList();
            if (list.isNotEmpty) {
              _searchMemoryCache.set(cacheKey, list, list.length * 128 + 64);
              return list;
            }
          }
        } catch (_) {}
      }
    }

    // 3. 并发单飞去重
    if (_inflightSearch.containsKey(cacheKey)) {
      return _inflightSearch[cacheKey]!;
    }

    final future = () async {
      try {
        List<SourceSearchResult> results;
        if (useServer) {
          developer.log('[SourceRouting] 🚀 [服务端代理] 源: $sourceId | 动作: search | 关键词: $kw');
          results = await _serverEngine.search(sourceId, kw);
        } else {
          developer.log('[SourceRouting] 🏠 [本地直连] 源: $sourceId | 动作: search | 关键词: $kw');
          results = await _localEngine.search(sourceId, kw);
        }

        // 回填 L1 内存缓存 (2 小时)
        final estBytes = results.length * 128 + 64;
        _searchMemoryCache.set(cacheKey, results, estBytes);

        // 回填 L2 本地硬盘 (2 小时)
        if (results.isNotEmpty) {
          final disk = PlayerMediaDiskCacheManager.instance;
          disk?.putJson(
            diskCacheKey,
            results.map((r) => r.toJson()).toList(),
            maxAge: const Duration(hours: 2),
          ).ignore();
        }

        return results;
      } catch (e) {
        developer.log('[NativeRuntime] search error ($sourceId, $kw, useServer=$useServer): $e');
        rethrow;
      }
    }();

    _inflightSearch[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inflightSearch.remove(cacheKey);
    }
  }

  /// 获取选集线路 (带 L1 内存 + L2 硬盘双层缓存与请求去重，支持服务端代理双模路由)
  Future<List<SourceChapterRoad>> chapters(
    String sourceId,
    String animeUrl, {
    bool bypassCache = false,
  }) async {
    final useServer = _serverEngine.isSourceSupported(sourceId);

    // 服务端模式专属前缀隔离
    final cachePrefix = useServer ? 'srv_' : '';
    final cacheKey = '$cachePrefix$sourceId:$animeUrl';
    final urlHash = md5.convert(utf8.encode(animeUrl)).toString();
    final diskCacheKey = '${cachePrefix}src_ch_${sourceId}_$urlHash';

    if (!bypassCache) {
      // 1. L1 内存缓存
      final memHit = _chaptersMemoryCache.get(cacheKey);
      if (memHit != null) return memHit;

      // 2. L2 本地硬盘持久化缓存
      final disk = PlayerMediaDiskCacheManager.instance;
      if (disk != null) {
        try {
          final diskData = await disk.getJson(diskCacheKey);
          if (diskData is List && diskData.isNotEmpty) {
            final roads = diskData
                .whereType<Map<String, dynamic>>()
                .map(SourceChapterRoad.fromJson)
                .toList();
            if (roads.isNotEmpty && roads.any((r) => r.episodes.isNotEmpty)) {
              _chaptersMemoryCache.set(cacheKey, roads, roads.length * 512 + 128);
              return roads;
            }
          }
        } catch (_) {}
      }
    }

    // 3. 并发单飞去重
    if (_inflightChapters.containsKey(cacheKey)) {
      return _inflightChapters[cacheKey]!;
    }

    final future = () async {
      try {
        List<SourceChapterRoad> roads;
        if (useServer) {
          developer.log('[SourceRouting] 🚀 [服务端代理] 源: $sourceId | 动作: chapters | url: $animeUrl');
          roads = await _serverEngine.chapters(sourceId, animeUrl);
        } else {
          developer.log('[SourceRouting] 🏠 [本地直连] 源: $sourceId | 动作: chapters | url: $animeUrl');
          roads = await _localEngine.chapters(sourceId, animeUrl);
        }

        if (roads.isNotEmpty && roads.any((r) => r.episodes.isNotEmpty)) {
          // 回填 L1 内存 (30 分钟)
          final estBytes = roads.length * 512 + 128;
          _chaptersMemoryCache.set(cacheKey, roads, estBytes);

          // 回填 L2 本地硬盘 (30 分钟)
          final disk = PlayerMediaDiskCacheManager.instance;
          disk?.putJson(
            diskCacheKey,
            roads.map((r) => r.toJson()).toList(),
            maxAge: const Duration(minutes: 30),
          ).ignore();
        }
        return roads;
      } catch (e) {
        developer.log('[NativeRuntime] chapters error ($sourceId, $animeUrl, useServer=$useServer): $e');
        rethrow;
      }
    }();

    _inflightChapters[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inflightChapters.remove(cacheKey);
    }
  }

  /// 解析播放直链 (带 L1 内存 1 分钟短时防抖缓存与 Single-Flight 请求去重，支持服务端代理双模路由)
  Future<SourceResolveResult> resolve(
    String sourceId,
    String episodeUrl, {
    bool bypassCache = false,
  }) async {
    final useServer = _serverEngine.isSourceSupported(sourceId);

    final cachePrefix = useServer ? 'srv_' : '';
    final cacheKey = '$cachePrefix$sourceId:$episodeUrl';

    if (!bypassCache) {
      // 1. L1 内存缓存
      final memHit = _resolveMemoryCache.get(cacheKey);
      if (memHit != null && memHit.url.isNotEmpty) return memHit;
    }

    // 2. 并发单飞去重
    if (_inflightResolve.containsKey(cacheKey)) {
      return _inflightResolve[cacheKey]!;
    }

    final future = () async {
      try {
        SourceResolveResult result;
        if (useServer) {
          developer.log('[SourceRouting] 🚀 [服务端代理] 源: $sourceId | 动作: resolve | ep: $episodeUrl');
          result = await _serverEngine.resolve(sourceId, episodeUrl);
          developer.log('[SourceRouting] 🎬 [服务端直链] -> ${result.url}');
        } else {
          developer.log('[SourceRouting] 🏠 [本地直连] 源: $sourceId | 动作: resolve | ep: $episodeUrl');
          result = await _localEngine.resolve(sourceId, episodeUrl);
        }

        if (result.url.isNotEmpty) {
          // 回填 L1 内存 (1 分钟短时防抖)
          _resolveMemoryCache.set(cacheKey, result, 256);
        }
        return result;
      } catch (e) {
        developer.log('[NativeRuntime] resolve error ($sourceId, $episodeUrl, useServer=$useServer): $e');
        rethrow;
      }
    }();

    _inflightResolve[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inflightResolve.remove(cacheKey);
    }
  }

  /// 获取当前所有视频源缓存的内存预估字节数
  int get memoryCacheSizeBytes =>
      _searchMemoryCache.totalBytes +
      _chaptersMemoryCache.totalBytes +
      _resolveMemoryCache.totalBytes;

  /// 清空视频源运行时全部内存缓存
  void clearMemoryCache() {
    _searchMemoryCache.clear();
    _chaptersMemoryCache.clear();
    _resolveMemoryCache.clear();
    _serverEngine.clearCache();
    _localEngine.clearCache();
  }

  void dispose() {
    AppPreferences.serverModeNotifier.removeListener(_onServerModeChanged);
    _serverEngine.dispose();
    clearMemoryCache();
  }
}
