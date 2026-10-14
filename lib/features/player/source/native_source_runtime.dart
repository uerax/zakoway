import 'dart:convert';
import 'dart:developer' as developer;
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:zakoway/core/network/player_media_disk_cache_manager.dart';
import 'package:zakoway/core/utils/timed_cache.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/sources/anime1_source.dart';
import 'package:zakoway/features/player/source/sources/animoe_source.dart';
import 'package:zakoway/features/player/source/sources/cycani_source.dart';
import 'package:zakoway/features/player/source/sources/girigiri_source.dart';
import 'package:zakoway/features/player/source/sources/gugu_source.dart';
import 'package:zakoway/features/player/source/sources/libvio_source.dart';
import 'package:zakoway/features/player/source/sources/lzizy_source.dart';
import 'package:zakoway/features/player/source/sources/mifun_source.dart';
import 'package:zakoway/features/player/source/sources/moonci_source.dart';
import 'package:zakoway/features/player/source/sources/mxdm_source.dart';
import 'package:zakoway/features/player/source/sources/omofun_source.dart';
import 'package:zakoway/features/player/source/sources/sorani_source.dart';
import 'package:zakoway/features/player/source/sources/tvtfun_source.dart';
import 'package:zakoway/features/player/source/sources/video_source.dart';
import 'package:zakoway/features/player/source/sources/xifan_next_source.dart';

/// 100% 纯原生 Dart 视频源运行时与统一缓存调度中心
/// 涵盖 animaku 全部 12 个核心视频源，配备 L1 内存 + L2 硬盘持久化双层缓存体系
class NativeSourceRuntime {
  // 默认 Dio 显式注入 connectTimeout 与 receiveTimeout，防止境外源在 TCP 握手时陷入系统底层 20~60 秒假死
  NativeSourceRuntime({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 8),
                sendTimeout: const Duration(seconds: 5),
              ),
            ) {
    _registerDefaultSources();
  }

  final Dio _dio;
  final Map<String, VideoSource> _sources = {};

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

  void _registerDefaultSources() {
    // 特殊处理说明：
    // 视频源默认注册位序直接决定了 UI 排序与自动选源的优先级：
    // 1. xifan-next（综合主线首选）
    // 2. cycani（次元城，多线路原画）
    // 3. mifun / sorani（青空次元与 mifun 同级优质主线）
    // 4. girigiri（Cloudflare CDN 原画直连）
    // 5. moonci（月之祠，降权至 girigiri 之后作为备选多线路源）
    // 6. lzizy / animoe / gugu（全品类与备用多线路源）
    registerSource(XifanNextSource(dio: _dio));
    registerSource(CycaniSource(dio: _dio));
    registerSource(MifunSource(dio: _dio));
    registerSource(SoraniSource(dio: _dio));
    registerSource(GirigiriSource(dio: _dio));
    registerSource(MoonciSource(dio: _dio));
    registerSource(LzizySource(dio: _dio));
    registerSource(AnimoeSource(dio: _dio));
    registerSource(GuguSource(dio: _dio));
    registerSource(MxdmSource(dio: _dio));
    registerSource(TvTFunSource(dio: _dio));
    registerSource(Anime1Source(dio: _dio));
    registerSource(OmofunSource(dio: _dio));
    registerSource(LibvioSource(dio: _dio));
  }

  void registerSource(VideoSource source) {
    _sources[source.id] = source;
  }

  bool get isInitialized => true;

  SourceBundleMeta get bundleMeta => SourceBundleMeta(
        version: '2.0.0-native',
        buildTime: DateTime.now().toIso8601String(),
        minApiLevel: 1,
        adapters: {for (final s in _sources.values) s.id: s.version},
      );

  List<SourceMeta> get availableSources =>
      _sources.values.map((s) => s.toMeta()).toList();

  VideoSource? getSource(String sourceId) => _sources[sourceId];

  Future<void> initialize({String? bundleCode}) async {
    // 原生运行时瞬时就绪
  }

  /// 搜索番剧 (带 L1 内存 + L2 硬盘双层缓存与请求去重)
  Future<List<SourceSearchResult>> search(
    String sourceId,
    String keyword, {
    bool bypassCache = false,
  }) async {
    final s = _sources[sourceId];
    if (s == null) {
      throw Exception('未找到视频源: $sourceId');
    }

    final kw = keyword.trim();
    if (kw.isEmpty) return const [];

    final cacheKey = '$sourceId:${kw.toLowerCase()}';
    final safeKw = base64Url.encode(utf8.encode(kw.toLowerCase()));
    final diskCacheKey = 'src_search_${sourceId}_$safeKw';

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
        final results = await s.search(kw);
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
        developer.log('[NativeRuntime] search error ($sourceId, $kw): $e');
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

  /// 获取选集线路 (带 L1 内存 + L2 硬盘双层缓存与请求去重)
  Future<List<SourceChapterRoad>> chapters(
    String sourceId,
    String animeUrl, {
    bool bypassCache = false,
  }) async {
    final s = _sources[sourceId];
    if (s == null) {
      throw Exception('未找到视频源: $sourceId');
    }

    final cacheKey = '$sourceId:$animeUrl';
    final urlHash = md5.convert(utf8.encode(animeUrl)).toString();
    final diskCacheKey = 'src_ch_${sourceId}_$urlHash';

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
        final roads = await s.chapters(animeUrl);
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
        developer.log('[NativeRuntime] chapters error ($sourceId, $animeUrl): $e');
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

  /// 解析播放直链 (带 L1 内存 1 分钟短时防抖缓存与 Single-Flight 请求去重)
  ///
  /// 特殊处理说明：视频直链通常包含临时鉴权令牌、短期 CDN 签名或会话 Cookie，
  /// 跨进程持久化到磁盘或较长缓存极易导致读取过期废链引发 403 播放失败。
  /// 因此直链仅保留 1 分钟短时 L1 内存缓存（防止用户频繁刷新/快速连点重复请求）与单飞去重，不进行 L2 磁盘持久化。
  Future<SourceResolveResult> resolve(
    String sourceId,
    String episodeUrl, {
    bool bypassCache = false,
  }) async {
    final s = _sources[sourceId];
    if (s == null) {
      throw Exception('未找到视频源: $sourceId');
    }

    final cacheKey = '$sourceId:$episodeUrl';

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
        final result = await s.resolve(episodeUrl);
        if (result.url.isNotEmpty) {
          // 回填 L1 内存 (1 分钟短时防抖)
          _resolveMemoryCache.set(cacheKey, result, 256);
        }
        return result;
      } catch (e) {
        developer.log('[NativeRuntime] resolve error ($sourceId, $episodeUrl): $e');
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
    for (final s in _sources.values) {
      s.clearCache();
    }
  }

  void dispose() {
    clearMemoryCache();
  }
}
