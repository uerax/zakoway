import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'package:dio/dio.dart';
import '../models/bangumi/bangumi_calendar.dart';
import '../models/bangumi/bangumi_collection.dart';
import '../models/bangumi/bangumi_comment.dart';
import '../models/bangumi/bangumi_comment_item.dart';
import '../models/bangumi/bangumi_episode.dart';
import '../models/bangumi/bangumi_item.dart';
import '../models/bangumi/bangumi_recommendation_item.dart';
import '../models/bangumi/bangumi_search_result.dart';
import '../models/bangumi/bangumi_user.dart';
import '../models/network/custom_network_route.dart';
import '../services/app_preferences.dart';
import '../services/daily_recommend_service.dart';
import '../utils/anime_tag_filter.dart';
import '../utils/image_utils.dart';
import '../utils/timed_cache.dart';
import 'bangumi_api_exception.dart';
import 'bangumi_data_disk_cache_manager.dart';
import 'bangumi_search_query_builder.dart';
import 'bangumi_source_preset.dart';
import 'bangumi_user_agent.dart';

export '../models/bangumi/bangumi_comment_item.dart';
export '../models/bangumi/bangumi_recommendation_item.dart';
export '../models/bangumi/bangumi_search_result.dart';
export '../models/network/custom_network_route.dart';
export 'bangumi_api_exception.dart';
export 'bangumi_source_preset.dart';
export 'bangumi_user_agent.dart';

class BangumiClient {
  /// 遵循 Bangumi API 开发者准则规范配置合规的 User-Agent
  static String get defaultUserAgent => BangumiUserAgent.defaultUserAgent;

  /// 支持按动态版本号与可选平台标识构造合规 User-Agent
  static String buildUserAgent({
    String? version,
    String? platform,
  }) =>
      BangumiUserAgent.build(version: version, platform: platform);

  final Dio _dio;
  late String _baseUrl;
  BangumiSourcePreset _sourcePreset = BangumiSourcePreset.mirror;
  String _activeRouteId = BangumiSourcePreset.mirror.name;
  String? _customRouteName;

  // 按照 Animaku 规范对齐 TTL 的内存缓存池
  // 1. 每日放送：按季更替，24 小时缓存
  final _calendarCache = TimedCache<List<BangumiCalendarDay>>(maxAge: const Duration(hours: 24));
  // 2. 热门 TV 番剧：12 小时缓存
  final _trendingCache = TimedCache<List<BangumiItem>>(maxAge: const Duration(hours: 12));

  // 3. 搜索与分类检索分页缓存：2 小时缓存（剧场版/OVA 经由 L2 磁盘维持 12 小时 TTL），最多保留 150 条分页查询
  final _searchCache = TimedKeyedCache<String, BangumiSearchResult>(
    maxAge: const Duration(hours: 2),
    maxEntries: 150,
  );
  // 4. 条目详情：6 小时缓存，最多保留 100 条
  final _subjectCache = TimedKeyedCache<int, BangumiItem>(
    maxAge: const Duration(hours: 6),
    maxEntries: 100,
  );
  // 5. 剧集列表：2 小时缓存，最多保留 100 条
  final _episodesCache = TimedKeyedCache<String, List<BangumiEpisode>>(
    maxAge: const Duration(hours: 2),
    maxEntries: 100,
  );
  // 6. 吐槽与评论列表：3 小时缓存，最多保留 100 条
  final _commentsCache = TimedKeyedCache<String, List<BangumiComment>>(
    maxAge: const Duration(hours: 3),
    maxEntries: 100,
  );
  // 7. 吐槽与评论分块列表 (每块 30 条)：3 小时缓存，最多保留 100 块
  final _commentsChunkCache = TimedKeyedCache<String, ({List<BangumiCommentItem> items, int total})>(
    maxAge: const Duration(hours: 3),
    maxEntries: 100,
  );
  // 8. 条目关联与相似推荐：24 小时缓存，最多保留 60 条
  final _recommendationsCache = TimedKeyedCache<int, List<BangumiRecommendationItem>>(
    maxAge: const Duration(hours: 24),
    maxEntries: 60,
  );
  // 8.1 续作/前传关联推荐条目：24 小时缓存，最多保留 100 条
  final _relationCache = TimedKeyedCache<int, BangumiRecommendationItem?>(
    maxAge: const Duration(hours: 24),
    maxEntries: 100,
  );
  // 8.2 相似推荐候选池：24 小时缓存，最多保留 60 条
  final _similarPoolCache = TimedKeyedCache<String, List<BangumiRecommendationItem>>(
    maxAge: const Duration(hours: 24),
    maxEntries: 60,
  );
  // 8.4 用户单条目收藏状态缓存：10 分钟缓存，最多保留 100 条 (通过 CollectType.none 负缓存防止频繁 404)
  final _collectionStatusCache = TimedKeyedCache<String, BangumiCollectionEntry>(
    maxAge: const Duration(minutes: 10),
    maxEntries: 100,
  );
  // 8.5 用户收藏列表分页缓存：10 分钟缓存，最多保留 50 个分页查询
  final _userCollectionsCache = TimedKeyedCache<String, List<Map<String, dynamic>>>(
    maxAge: const Duration(minutes: 10),
    maxEntries: 50,
  );

  // 8.3 题材作品总量长期磁盘/内存缓存 (180 天超长 TTL，全库真随机 offset 必备)
  static final Map<String, int> _tagTotalMemoryCache = {};
  static const String _tagTotalDiskCacheKey = 'bangumi_tag_totals_v1';
  static bool _hasLoadedTagTotalDiskCache = false;

  /// 获取指定题材在 Bangumi 平台的作品总数（支持磁盘恢复与安全预设）
  Future<int> getTagTotal(String tag) async {
    final clean = tag.trim();
    if (clean.isEmpty) return 400;

    if (!_hasLoadedTagTotalDiskCache) {
      _hasLoadedTagTotalDiskCache = true;
      try {
        final diskJson = await _diskCache?.getJson(_tagTotalDiskCacheKey);
        if (diskJson is Map<String, dynamic>) {
          diskJson.forEach((k, v) {
            if (v is num) _tagTotalMemoryCache[k] = v.toInt();
          });
        }
      } catch (_) {}
    }

    if (_tagTotalMemoryCache.containsKey(clean)) {
      return _tagTotalMemoryCache[clean]!;
    }

    // 安全预设容量基准（白名单主流题材基础容量通常为 300 ~ 1000）
    return 400;
  }

  /// 记录并异步持久化题材总数
  void recordTagTotal(String tag, int total) {
    final clean = tag.trim();
    if (clean.isEmpty || total <= 0) return;
    final capped = total.clamp(10, 1000);
    _tagTotalMemoryCache[clean] = capped;

    unawaited(_diskCache?.putJson(
      _tagTotalDiskCacheKey,
      _tagTotalMemoryCache,
      maxAge: const Duration(days: 180),
    ) ?? Future.value());
  }

  // L2 磁盘持久化缓存池（安全惰性加载，规避无 UI 绑定的测试环境崩溃）
  BangumiDataDiskCacheManager? get _diskCache {
    try {
      return BangumiDataDiskCacheManager.instance;
    } catch (_) {
      return null;
    }
  }

  // Single-Flight 机制：并发重复请求去重
  final Map<String, Future<dynamic>> _inflight = {};

  BangumiClient({
    String? baseUrl,
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 15),
                headers: {
                  'User-Agent': defaultUserAgent,
                  'Accept': 'application/json',
                },
              ),
            ) {
    if (baseUrl != null) {
      _baseUrl = baseUrl;
      if (baseUrl == BangumiSourcePreset.official.apiBase) {
        _activeRouteId = BangumiSourcePreset.official.name;
        _sourcePreset = BangumiSourcePreset.official;
        setBangumiImageHost(BangumiSourcePreset.official.imageHost);
      } else if (baseUrl == BangumiSourcePreset.mirror.apiBase) {
        _activeRouteId = BangumiSourcePreset.mirror.name;
        _sourcePreset = BangumiSourcePreset.mirror;
        setBangumiImageHost(BangumiSourcePreset.mirror.imageHost);
      } else {
        _activeRouteId = 'custom';
        _sourcePreset = BangumiSourcePreset.mirror;
        final host = Uri.tryParse(baseUrl)?.host;
        if (host != null && host.isNotEmpty) {
          setBangumiImageHost(host);
        }
      }
    } else {
      final activeId = AppPreferences.getActiveRouteId();
      _activeRouteId = activeId;
      if (activeId == BangumiSourcePreset.official.name) {
        _sourcePreset = BangumiSourcePreset.official;
        _baseUrl = BangumiSourcePreset.official.apiBase;
        setBangumiImageHost(BangumiSourcePreset.official.imageHost);
      } else if (activeId == BangumiSourcePreset.mirror.name) {
        _sourcePreset = BangumiSourcePreset.mirror;
        _baseUrl = BangumiSourcePreset.mirror.apiBase;
        setBangumiImageHost(BangumiSourcePreset.mirror.imageHost);
      } else {
        // 自定义线路
        final customRoutes = AppPreferences.getCustomNetworkRoutes();
        final matched = customRoutes.where((r) => r.id == activeId).firstOrNull;
        if (matched != null) {
          _sourcePreset = BangumiSourcePreset.mirror;
          _baseUrl = matched.url;
          _customRouteName = matched.name;
          final host = Uri.tryParse(matched.url)?.host;
          if (host != null && host.isNotEmpty) {
            setBangumiImageHost(host);
          }
        } else {
          _activeRouteId = BangumiSourcePreset.mirror.name;
          _sourcePreset = BangumiSourcePreset.mirror;
          _baseUrl = BangumiSourcePreset.mirror.apiBase;
          setBangumiImageHost(BangumiSourcePreset.mirror.imageHost);
        }
      }
    }
    _dio.options.baseUrl = _baseUrl;
  }

  String get baseUrl => _baseUrl;
  BangumiSourcePreset get sourcePreset => _sourcePreset;
  String get activeRouteId => _activeRouteId;
  String? get customRouteName => _customRouteName;

  /// 切换到内置预设线路（镜像加速 / 官方直连）
  void setSourcePreset(BangumiSourcePreset preset) {
    _activeRouteId = preset.name;
    _customRouteName = null;
    _sourcePreset = preset;
    updateBaseUrl(preset.apiBase);
    setBangumiImageHost(preset.imageHost);
    AppPreferences.saveActiveRouteId(preset.name);
    clearCache();
  }

  /// 切换到用户自定义网络线路
  void setCustomRoute(CustomNetworkRoute route) {
    _activeRouteId = route.id;
    _customRouteName = route.name;
    _sourcePreset = BangumiSourcePreset.mirror; // 兼容现有检查
    updateBaseUrl(route.url);
    final host = Uri.tryParse(route.url)?.host;
    if (host != null && host.isNotEmpty) {
      setBangumiImageHost(host);
    }
    AppPreferences.saveActiveRouteId(route.id);
    clearCache();
  }

  void updateBaseUrl(String newBaseUrl) {
    _baseUrl = newBaseUrl;
    _dio.options.baseUrl = newBaseUrl;
  }

  /// 获取当前客户端在内存中缓存的 API 查询响应总数
  int get totalCachedQueries =>
      (_calendarCache.value != null ? 1 : 0) +
      (_trendingCache.value != null ? 1 : 0) +
      _searchCache.length +
      _subjectCache.length +
      _episodesCache.length +
      _commentsCache.length +
      _commentsChunkCache.length +
      _recommendationsCache.length +
      _relationCache.length +
      _similarPoolCache.length +
      _collectionStatusCache.length +
      _userCollectionsCache.length;

  /// O(1) 极速获取当前客户端在内存中缓存的 API 响应数据字节大小，彻底避免在 UI 线程全量 JSON 序列化导致卡顿
  int get dataCacheSizeBytes =>
      _calendarCache.estimatedBytes +
      _trendingCache.estimatedBytes +
      _searchCache.totalBytes +
      _subjectCache.totalBytes +
      _episodesCache.totalBytes +
      _commentsCache.totalBytes +
      _commentsChunkCache.totalBytes +
      _recommendationsCache.totalBytes +
      _relationCache.totalBytes +
      _similarPoolCache.totalBytes +
      _collectionStatusCache.totalBytes +
      _userCollectionsCache.totalBytes;

  void clearCache() {
    _calendarCache.clear();
    _trendingCache.clear();
    _searchCache.clear();
    _subjectCache.clear();
    _episodesCache.clear();
    _commentsCache.clear();
    _commentsChunkCache.clear();
    _recommendationsCache.clear();
    _relationCache.clear();
    _similarPoolCache.clear();
    _collectionStatusCache.clear();
    _userCollectionsCache.clear();
    _inflight.clear();
    DailyRecommendService.clearCache();
    unawaited(_diskCache?.clearAll() ?? Future.value());
  }

  /// 获取当前磁盘数据缓存的总字节大小
  Future<int> getDiskDataCacheSizeBytes() async =>
      (await _diskCache?.getDiskSizeBytes()) ?? 0;

  /// 获取每日放送时间表 (周一至周日)，带 24 小时磁盘与内存多级持久化缓存与 Single-Flight 并发去重
  Future<List<BangumiCalendarDay>> getCalendar({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      if (_calendarCache.value != null) {
        return _calendarCache.value!;
      }
      final diskData = await _diskCache?.getJson('bangumi_calendar');
      if (diskData is List) {
        final days = diskData
            .whereType<Map<String, dynamic>>()
            .map((day) => BangumiCalendarDay.fromJson(day))
            .toList();
        if (days.isNotEmpty) {
          _calendarCache.set(days, days.length * 1500);
          return days;
        }
      }
    }

    const inflightKey = 'calendar';
    if (_inflight.containsKey(inflightKey)) {
      return await (_inflight[inflightKey] as Future<List<BangumiCalendarDay>>);
    }

    final Future<List<BangumiCalendarDay>> future = () async {
      try {
        final res = await _dio.get('/calendar');
        final rawList = res.data;
        if (rawList is! List) return _calendarCache.value ?? const <BangumiCalendarDay>[];

        final days = rawList.map((day) {
          if (day is Map<String, dynamic>) {
            return BangumiCalendarDay.fromJson(day);
          }
          return null;
        }).whereType<BangumiCalendarDay>().toList();

        if (days.isNotEmpty) {
          _calendarCache.set(days, days.length * 1500);
          unawaited(_diskCache?.putJson(
            'bangumi_calendar',
            days.map((d) => d.toJson()).toList(),
            maxAge: const Duration(hours: 24),
          ) ?? Future.value());
        }
        return days;
      } on DioException catch (e) {
        if (_calendarCache.staleValue != null) return _calendarCache.staleValue!;
        // 特殊处理说明：网络异常（如断网或 TLS 握手失败）时，若内存已无陈旧缓存，优先回退到磁盘缓存，避免主页抛错崩溃
        final diskData = await _diskCache?.getJson('bangumi_calendar');
        if (diskData is List) {
          final days = diskData
              .whereType<Map<String, dynamic>>()
              .map((d) => BangumiCalendarDay.fromJson(d))
              .toList();
          if (days.isNotEmpty) {
            _calendarCache.set(days, days.length * 1500);
            return days;
          }
        }
        throw _handleDioError('获取每日放送失败', e);
      }
    }();

    _inflight[inflightKey] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(inflightKey);
    }
  }

  /// 获取首页热门番剧列表 (带 12 小时磁盘与内存多级持久化缓存与 Single-Flight 并发去重)
  Future<List<BangumiItem>> getTrending({int limit = 12, bool forceRefresh = false}) async {
    if (!forceRefresh) {
      if (_trendingCache.value != null) {
        return _trendingCache.value!;
      }
      final diskData = await _diskCache?.getJson('bangumi_trending_$limit');
      if (diskData is List) {
        final items = diskData
            .whereType<Map<String, dynamic>>()
            .map((item) => BangumiItem.fromJson(item))
            .toList();
        if (items.isNotEmpty) {
          _trendingCache.set(items, items.length * 1500);
          return items;
        }
      }
    }

    final inflightKey = 'trending_$limit';
    if (_inflight.containsKey(inflightKey)) {
      return await (_inflight[inflightKey] as Future<List<BangumiItem>>);
    }

    final Future<List<BangumiItem>> future = () async {
      try {
        // 特殊处理说明：计算当前季度首日（1/4/7/10月1日），对齐 animaku 检索当季番剧
        final now = DateTime.now();
        final seasonMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        final seasonStart =
            '${now.year}-${seasonMonth.toString().padLeft(2, '0')}-01';

        // 默认直接走当前激活线路（mirror 或 official）的 /v0/search/subjects，不做第三方接口降级
        final items = await search(
          '*',
          sort: 'heat',
          airDate: ['>=$seasonStart'],
          limit: limit,
        );
        if (items.isNotEmpty) {
          _trendingCache.set(items, items.length * 1500);
          unawaited(_diskCache?.putJson(
            'bangumi_trending_$limit',
            items.map((i) => i.toJson()).toList(),
            maxAge: const Duration(hours: 12),
          ) ?? Future.value());
          return items;
        }
      } catch (e) {
        developer.log('获取热门 TV 失败: $e');
      }

      if (_trendingCache.staleValue != null) return _trendingCache.staleValue!;

      // 特殊处理说明：网络异常时从磁盘缓存读取，坚决避免返回空列表导致页面货架空白
      final diskFallback = await _diskCache?.getJson('bangumi_trending_$limit');
      if (diskFallback is List) {
        final items = diskFallback
            .whereType<Map<String, dynamic>>()
            .map((item) => BangumiItem.fromJson(item))
            .toList();
        if (items.isNotEmpty) {
          return items;
        }
      }

      return const <BangumiItem>[];
    }();

    _inflight[inflightKey] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(inflightKey);
    }
  }

  /// 获取热门剧场版列表 (复用结构化搜索的 12 小时多级缓存与 Single-Flight，与分类页数据互通)
  Future<List<BangumiItem>> getHotMovies({int limit = 12, bool forceRefresh = false}) async {
    try {
      return await search(
        '',
        tags: const ['剧场版'],
        sort: 'heat',
        limit: limit,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      developer.log('获取热门剧场版失败: $e');
      return const [];
    }
  }

  /// 获取热门 OVA 列表 (复用结构化搜索的 12 小时多级缓存与 Single-Flight，与分类页数据互通)
  Future<List<BangumiItem>> getHotOva({int limit = 12, bool forceRefresh = false}) async {
    try {
      return await search(
        '',
        tags: const ['OVA'],
        sort: 'heat',
        limit: limit,
        forceRefresh: forceRefresh,
      );
    } catch (e) {
      developer.log('获取热门 OVA 失败: $e');
      return const [];
    }
  }

  /// 获取番剧条目详情 (带 6 小时内存与磁盘多级缓存与 Single-Flight 并发合并)
  Future<BangumiItem> getSubject(int subjectId, {bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _subjectCache.get(subjectId);
      if (cached != null) return cached;

      final diskJson = await _diskCache?.getJson('bangumi_subject_$subjectId');
      if (diskJson is Map<String, dynamic>) {
        final item = BangumiItem.fromJson(diskJson);
        _subjectCache.set(subjectId, item, 4096);
        return item;
      }
    }

    final inflightKey = 'subject_$subjectId';
    if (_inflight.containsKey(inflightKey)) {
      return await (_inflight[inflightKey] as Future<BangumiItem>);
    }

    final future = () async {
      try {
        final res = await _dio.get('/v0/subjects/$subjectId');
        if (res.data is Map<String, dynamic>) {
          final item = BangumiItem.fromJson(res.data as Map<String, dynamic>);
          _subjectCache.set(subjectId, item, 4096);
          unawaited(_diskCache?.putJson(
            'bangumi_subject_$subjectId',
            item.toJson(),
            maxAge: const Duration(hours: 6),
          ) ?? Future.value());
          return item;
        }
        throw const BangumiApiException('响应格式不正确');
      } on DioException catch (e) {
        final stale = _subjectCache.getStale(subjectId);
        if (stale != null) return stale;
        // 特殊处理说明：网络异常时回退磁盘持久化缓存，保障断网或弱网下的详情页秒开与离线可用
        final diskJson = await _diskCache?.getJson('bangumi_subject_$subjectId');
        if (diskJson is Map<String, dynamic>) {
          final item = BangumiItem.fromJson(diskJson);
          _subjectCache.set(subjectId, item, 4096);
          return item;
        }
        throw _handleDioError('获取番剧详情失败 (ID: $subjectId)', e);
      }
    }();

    _inflight[inflightKey] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(inflightKey);
    }
  }

  /// 获取番剧剧集列表 (默认 type=0 为正片，1 为 SP，带 2 小时内存与磁盘多级缓存)
  Future<List<BangumiEpisode>> getEpisodes(
    int subjectId, {
    int type = 0,
    int limit = 100,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${subjectId}_${type}_${limit}_$offset';
    final diskCacheKey = 'bangumi_episodes_$cacheKey';
    if (!forceRefresh) {
      final cached = _episodesCache.get(cacheKey);
      if (cached != null) return cached;

      final diskData = await _diskCache?.getJson(diskCacheKey);
      if (diskData is List) {
        final eps = diskData
            .whereType<Map<String, dynamic>>()
            .map((ep) => BangumiEpisode.fromJson(ep))
            .toList();
        if (eps.isNotEmpty) {
          _episodesCache.set(cacheKey, eps, eps.length * 400 + 256);
          return eps;
        }
      }
    }

    final inflightKey = 'episodes_$cacheKey';
    if (_inflight.containsKey(inflightKey)) {
      return await (_inflight[inflightKey] as Future<List<BangumiEpisode>>);
    }

    final Future<List<BangumiEpisode>> future = () async {
      try {
        final res = await _dio.get(
          '/v0/episodes',
          queryParameters: {
            'subject_id': subjectId,
            'type': type,
            'limit': limit,
            'offset': offset,
          },
        );

        final data = res.data;
        if (data is Map<String, dynamic> && data['data'] is List) {
          final list = data['data'] as List;
          final eps = list
              .whereType<Map<String, dynamic>>()
              .map((ep) => BangumiEpisode.fromJson(ep))
              .toList();
          _episodesCache.set(cacheKey, eps, eps.length * 400 + 256);
          if (eps.isNotEmpty) {
            unawaited(_diskCache?.putJson(
              diskCacheKey,
              eps.map((e) => e.toJson()).toList(),
              maxAge: const Duration(hours: 2),
            ) ?? Future.value());
          }
          return eps;
        }
        return const <BangumiEpisode>[];
      } on DioException catch (e) {
        final stale = _episodesCache.getStale(cacheKey);
        if (stale != null) return stale;
        // 特殊处理说明：网络异常时回退磁盘持久化缓存，保障剧集选集面板弱网可用
        final diskData = await _diskCache?.getJson(diskCacheKey);
        if (diskData is List) {
          final eps = diskData
              .whereType<Map<String, dynamic>>()
              .map((ep) => BangumiEpisode.fromJson(ep))
              .toList();
          if (eps.isNotEmpty) {
            _episodesCache.set(cacheKey, eps, eps.length * 400 + 256);
            return eps;
          }
        }
        throw _handleDioError('获取剧集列表失败 (ID: $subjectId)', e);
      }
    }();

    _inflight[inflightKey] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(inflightKey);
    }
  }

  /// 搜索番剧条目 (优先使用 v0 结构化搜索，必要时降级旧版搜索)
  Future<List<BangumiItem>> search(
    String keyword, {
    int limit = 20,
    int offset = 0,
    String? sort,
    List<String>? tags,
    int? year,
    List<String>? airDate,
    int? type = 2, // 2 = 动画
    List<int>? types,
    bool forceRefresh = false,
  }) async {
    final result = await searchWithTotal(
      keyword,
      limit: limit,
      offset: offset,
      sort: sort,
      tags: tags,
      year: year,
      airDate: airDate,
      type: type,
      types: types,
      forceRefresh: forceRefresh,
    );
    return result.items;
  }

  String _buildSearchCacheKey({
    required String keyword,
    required String? sort,
    required List<String>? tags,
    required int? year,
    required List<String>? airDate,
    required int? type,
    List<int>? types,
    required int limit,
    required int offset,
  }) {
    final sortedTags = tags != null ? ([...tags]..sort()).join(',') : '';
    final sortedAirDate = airDate != null ? ([...airDate]..sort()).join(',') : '';
    final typesStr = types != null ? ([...types]..sort()).join(',') : (type?.toString() ?? 'all');
    return '$keyword|$sort|$sortedTags|$year|$sortedAirDate|$typesStr|$limit|$offset';
  }

  /// 同步检查是否有未过期的搜索/分类缓存结果（用于切换分类时 0ms 瞬间呈现，消除骨架屏闪烁）
  BangumiSearchResult? peekSearchCache(
    String keyword, {
    int limit = 20,
    int offset = 0,
    String? sort,
    List<String>? tags,
    int? year,
    List<String>? airDate,
    int? type = 2,
    List<int>? types,
  }) {
    final cacheKey = _buildSearchCacheKey(
      keyword: keyword.trim(),
      sort: sort,
      tags: tags,
      year: year,
      airDate: airDate,
      type: type,
      types: types,
      limit: limit,
      offset: offset,
    );
    return _searchCache.peek(cacheKey);
  }

  /// 结构化搜索并返回分页与总数结果 (供分类/探索瀑布流与高级筛选使用，带 2 小时内存缓存与容灾)
  Future<BangumiSearchResult> searchWithTotal(
    String keyword, {
    int limit = 20,
    int offset = 0,
    String? sort,
    List<String>? tags,
    int? year,
    List<String>? airDate,
    int? type = 2, // 2 = 动画
    List<int>? types,
    bool forceRefresh = false,
    CancelToken? cancelToken,
  }) async {
    final trimmed = keyword.trim();
    final cacheKey = _buildSearchCacheKey(
      keyword: trimmed,
      sort: sort,
      tags: tags,
      year: year,
      airDate: airDate,
      type: type,
      types: types,
      limit: limit,
      offset: offset,
    );

    if (!forceRefresh) {
      final cached = _searchCache.get(cacheKey);
      if (cached != null) return cached;

      // 尝试从 L2 磁盘缓存读取（未过期则直接命中，回填 L1）
      final diskJson = await _diskCache?.getJson(cacheKey);
      if (diskJson is Map<String, dynamic>) {
        final result = BangumiSearchResult.fromJson(diskJson);
        _searchCache.set(cacheKey, result, result.items.length * 1500 + 512);
        return result;
      }
    }

    final inflightKey = 'search_$cacheKey';
    if (_inflight.containsKey(inflightKey)) {
      return await (_inflight[inflightKey] as Future<BangumiSearchResult>);
    }

    final future = () async {
      final payload = BangumiSearchQueryBuilder.buildPayload(
        keyword: keyword,
        sort: sort,
        tags: tags,
        year: year,
        airDate: airDate,
        type: type,
        types: types,
      );

      if (payload == null) {
        return BangumiSearchResult.empty;
      }

      final isSortByDate = sort == 'date' || sort == 'airdate';

      try {
        final res = await _dio.post(
          '/v0/search/subjects',
          data: payload,
          queryParameters: {
            'limit': limit,
            'offset': offset,
          },
          cancelToken: cancelToken,
        );

        final data = res.data;
        if (data is Map<String, dynamic> && data['data'] is List) {
          final list = data['data'] as List;
          final items = list
              .whereType<Map<String, dynamic>>()
              .map((item) => BangumiItem.fromJson(item))
              .toList();

          if (isSortByDate) {
            items.sort((a, b) => b.airDate.compareTo(a.airDate));
          }

          final total = (data['total'] is num)
              ? (data['total'] as num).toInt()
              : (offset + items.length);

          final result = BangumiSearchResult(
            items: items,
            total: total,
            limit: limit,
            offset: offset,
          );
          _searchCache.set(cacheKey, result, result.items.length * 1500 + 512);

          // 异步写入 L2 磁盘缓存：剧场版/OVA 设为 12 小时 TTL，常规搜索与分类设为 2 小时 TTL
          final isHotList = tags != null && (tags.contains('剧场版') || tags.contains('OVA'));
          final ttl = isHotList ? const Duration(hours: 12) : const Duration(hours: 2);
          unawaited(_diskCache?.putJson(cacheKey, result.toJson(), maxAge: ttl) ?? Future.value());

          // 自动学习记录该题材在 Bangumi 的真实作品容量上限
          if (tags != null && tags.isNotEmpty && total > 0) {
            for (final t in tags) {
              if (t != '日本' && t != '剧场版' && t != 'OVA') {
                recordTagTotal(t, total);
                break;
              }
            }
          }

          return result;
        }
        return BangumiSearchResult.empty;
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) {
          rethrow;
        }
        final stale = _searchCache.getStale(cacheKey);
        if (stale != null) return stale;

        // 特殊处理说明：当网络异常且无陈旧内存时，优先从磁盘缓存读取兜底，保障离线与弱网可用性
        final diskFallback = await _diskCache?.getJson(cacheKey);
        if (diskFallback is Map<String, dynamic>) {
          final result = BangumiSearchResult.fromJson(diskFallback);
          _searchCache.set(cacheKey, result, result.items.length * 1500 + 512);
          return result;
        }

        if (trimmed.isEmpty) {
          throw _handleDioError('筛选番剧列表失败', e);
        }
        // 容错: 关键词搜索失败时尝试旧版搜索接口作为回退
        developer.log('v0 search 失败，尝试旧版回退: ${e.message}');
        try {
          final fallbackRes = await _dio.get(
            '/search/subject/${Uri.encodeComponent(trimmed)}',
            queryParameters: {
              'type': type,
              'responseGroup': 'small',
              'max_results': limit,
              'start': offset,
            },
            cancelToken: cancelToken,
          );
          final list = fallbackRes.data?['list'];
          if (list is List) {
            final items = list
                .whereType<Map<String, dynamic>>()
                .map((item) => BangumiItem.fromJson(item))
                .toList();
            final total = (fallbackRes.data?['results'] is num)
                ? (fallbackRes.data['results'] as num).toInt()
                : (offset + items.length);
            final result = BangumiSearchResult(
              items: items,
              total: total,
              limit: limit,
              offset: offset,
            );
            _searchCache.set(cacheKey, result, result.items.length * 1500 + 512);
            unawaited(_diskCache?.putJson(cacheKey, result.toJson(), maxAge: const Duration(hours: 2)) ?? Future.value());
            return result;
          }
        } catch (_) {
          // 忽略回退失败，抛出主要异常
        }
        throw _handleDioError('搜索番剧失败: "$trimmed"', e);
      }
    }();

    _inflight[inflightKey] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(inflightKey);
    }
  }

  /// 过滤并映射搜索条目为推荐结果（剔除非日本番剧、过滤无评分作品，取消死板人数门槛）
  static List<BangumiRecommendationItem> _filterAndMapSearchResult(
    List<BangumiItem> items, {
    required int excludeSubjectId,
    Set<int>? additionalExcludeIds,
  }) {
    final results = <BangumiRecommendationItem>[];
    final seen = <int>{
      excludeSubjectId,
      ...?additionalExcludeIds,
    };

    for (final item in items) {
      if (item.id <= 0 || seen.contains(item.id)) continue;

      // 1. 过滤非动画类型 (0: 未知/通用, 2: 动画)
      if (item.type != 0 && item.type != 2) continue;

      // 2. 必须具备有效封面
      if (item.coverUrl.isEmpty) continue;

      // 3. 严格限制仅日本番剧：过滤含非日本地区标签的条目
      final hasForeignTag = item.tags.any((t) =>
          t.name == '国产' ||
          t.name == '中国' ||
          t.name == '欧美' ||
          t.name == '韩国');
      if (hasForeignTag) continue;

      // 4. 过滤无评分条目（取消生硬的人数限制，放宽让 6~8.5+ 各类宝藏作品自然涌现）
      if (item.ratingScore <= 0.0) continue;

      final totalEps = item.totalEpisodes > 0 ? item.totalEpisodes : item.eps;
      final epsLabel = totalEps > 0 ? '全$totalEps话' : '';
      final year = item.airDate.length >= 4 ? item.airDate.substring(0, 4) : '';

      results.add(BangumiRecommendationItem(
        id: item.id,
        name: item.name,
        nameCn: item.preferredName,
        cover: item.coverUrl,
        score: double.parse(item.ratingScore.toStringAsFixed(1)),
        year: year,
        epsLabel: epsLabel,
      ));
      seen.add(item.id);
    }

    return results;
  }

  /// 获取番剧前传/续作/主线故事条目 (Slot 0，单次独立轻量请求，提前返回展示)
  Future<BangumiRecommendationItem?> getRelationItem(
    int subjectId, {
    bool forceRefresh = false,
  }) async {
    if (subjectId <= 0) return null;

    final diskCacheKey = 'bangumi_rel_$subjectId';

    if (!forceRefresh) {
      final cached = _relationCache.get(subjectId);
      if (cached != null) return cached;

      final diskJson = await _diskCache?.getJson(diskCacheKey);
      if (diskJson is Map<String, dynamic>) {
        if (diskJson['none'] == true) return null;
        final item = BangumiRecommendationItem.fromJson(diskJson);
        _relationCache.set(subjectId, item, 512);
        return item;
      }
    }

    final inflightKey = 'rel_$subjectId';
    if (_inflight.containsKey(inflightKey)) {
      return await (_inflight[inflightKey] as Future<BangumiRecommendationItem?>);
    }

    final future = () async {
      try {
        final now = DateTime.now();
        final todayStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

        final relRes = await _dio.get('/v0/subjects/$subjectId/subjects');
        if (relRes.data is! List) {
          unawaited(_diskCache?.putJson(diskCacheKey, {'none': true}, maxAge: const Duration(hours: 24)) ?? Future.value());
          return null;
        }

        final relList = (relRes.data as List)
            .whereType<Map<String, dynamic>>()
            .where((r) => ((r['type'] is num ? (r['type'] as num).toInt() : int.tryParse('${r['type']}')) == 2))
            .toList();

        // 优先级 1: 续作 / 主线故事 / 不同演绎
        Map<String, dynamic>? nextRel = relList.where((r) {
          final rel = r['relation']?.toString() ?? '';
          return rel == '续集' || rel == '主线故事' || rel == '不同演绎';
        }).firstOrNull;

        // 优先级 2: 前传 (当当前为最新季/终季时)
        Map<String, dynamic>? prevRel;
        if (nextRel == null) {
          prevRel = relList.where((r) => r['relation']?.toString() == '前传').firstOrNull;
        }

        final chosenRel = nextRel ?? prevRel;
        if (chosenRel == null) {
          unawaited(_diskCache?.putJson(diskCacheKey, {'none': true}, maxAge: const Duration(hours: 24)) ?? Future.value());
          return null;
        }

        final chosenId = (chosenRel['id'] is num)
            ? (chosenRel['id'] as num).toInt()
            : (int.tryParse('${chosenRel['id']}') ?? 0);

        if (chosenId <= 0) return null;

        // 读取 Slot 0 条目详情
        BangumiItem? chosenDetail;
        try {
          chosenDetail = await getSubject(chosenId);
        } catch (_) {}

        final airDate = chosenDetail?.airDate ?? chosenRel['date']?.toString() ?? '';
        final isFuture = airDate.trim().isNotEmpty &&
            airDate.trim().length >= 10 &&
            airDate.trim().substring(0, 10).compareTo(todayStr) > 0;

        if (isFuture) {
          return null;
        }

        final relTitle = (chosenRel['name_cn']?.toString().isNotEmpty ?? false)
            ? chosenRel['name_cn'].toString()
            : (chosenRel['name']?.toString() ?? '');
        final isMovieTitle = relTitle.contains('剧场版') || relTitle.contains('电影');

        var relationBadge = '续作';
        if (nextRel != null) {
          relationBadge = isMovieTitle ? '剧场版' : '续作';
        } else if (prevRel != null) {
          relationBadge = '前传';
        }

        final rawImages = (chosenRel['images'] is Map) ? (chosenRel['images'] as Map) : const {};
        var cover = rawImages['large']?.toString() ??
            rawImages['common']?.toString() ??
            rawImages['medium']?.toString() ??
            chosenDetail?.coverUrl ??
            '';

        final score = chosenDetail?.ratingScore ?? 0.0;
        final totalEps = chosenDetail?.totalEpisodes ?? chosenDetail?.eps ?? 0;
        final epsLabel = totalEps > 0 ? '全$totalEps话' : '';
        final year = (chosenDetail?.airDate.length ?? 0) >= 4
            ? chosenDetail!.airDate.substring(0, 4)
            : (airDate.length >= 4 ? airDate.substring(0, 4) : '');

        final item = BangumiRecommendationItem(
          id: chosenId,
          name: chosenRel['name']?.toString() ?? '',
          nameCn: chosenRel['name_cn']?.toString() ?? chosenRel['name']?.toString() ?? '',
          cover: cover,
          score: score,
          year: year,
          epsLabel: epsLabel,
          relationBadge: relationBadge,
        );

        _relationCache.set(subjectId, item, 512);
        unawaited(_diskCache?.putJson(
          diskCacheKey,
          item.toJson(),
          maxAge: const Duration(hours: 24),
        ) ?? Future.value());

        return item;
      } catch (_) {
        return null;
      }
    }();

    _inflight[inflightKey] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(inflightKey);
    }
  }

  /// 分批获取相似日本番剧推荐（基于多维题材互斥切面 + 质数散列深度大跨度散落 + heat/score交替错落）
  ///
  /// 特殊处理说明：
  /// 1. 白名单题材互斥切面：通过 AnimeTagFilter.genreAllowList 过滤噪音，将番剧的多个核心题材分别赋予 5 个独立槽位，
  ///    杜绝单一赛道扎堆；
  /// 2. 排序交替打破 7 分扎堆：交替采用 score（高分口碑神作）与 heat（高热流行新番），拉开评分层次；
  /// 3. 质数散列深度大跨度散落：每个槽位使用独立质数散列 offset，深度拉开，杜绝抓取局部连号；
  /// 4. 槽位交错穿插（Interleaving）：首屏 5 部自然涵盖 5 个不同题材切面与口碑/热度组合，翻页顺畅。
  Future<({List<BangumiRecommendationItem> items, bool hasMore})> getSimilarRecommendations(
    int subjectId, {
    List<String>? tags,
    bool? isMovie,
    int page = 1,
    int pageSize = 5,
    int refreshIndex = 0,
    Set<int>? excludeIds,
    bool forceRefresh = false,
  }) async {
    if (subjectId <= 0) return (items: const <BangumiRecommendationItem>[], hasMore: false);

    final poolCacheKey = '${subjectId}_$refreshIndex';
    final diskCacheKey = 'bangumi_similar_pool_${subjectId}_$refreshIndex';

    // 优先检查内存中是否已有缓冲候选池
    List<BangumiRecommendationItem>? pool;
    if (!forceRefresh) {
      pool = _similarPoolCache.get(poolCacheKey);
      if (pool == null) {
        final diskJson = await _diskCache?.getJson(diskCacheKey);
        if (diskJson is List) {
          pool = diskJson
              .whereType<Map<String, dynamic>>()
              .map((e) => BangumiRecommendationItem.fromJson(e))
              .toList();
          if (pool.isNotEmpty) {
            _similarPoolCache.set(poolCacheKey, pool, pool.length * 800 + 256);
          }
        }
      }
    }

    if (pool == null || pool.isEmpty || forceRefresh) {
      final inflightKey = 'sim_pool_${subjectId}_$refreshIndex';
      if (_inflight.containsKey(inflightKey)) {
        pool = await (_inflight[inflightKey] as Future<List<BangumiRecommendationItem>>);
      } else {
        final future = () async {
          try {
            var effectiveTags = tags != null ? List<String>.from(tags) : <String>[];
            var effectiveIsMovie = isMovie;

            if (effectiveTags.isEmpty || effectiveIsMovie == null) {
              BangumiItem? detail;
              try {
                detail = await getSubject(subjectId);
              } catch (_) {}
              if (detail != null) {
                if (effectiveTags.isEmpty && detail.tags.isNotEmpty) {
                  effectiveTags = detail.tags.map((t) => t.name).where((t) => t.isNotEmpty).toList();
                }
                if (effectiveIsMovie == null) {
                  final title = detail.nameCn.isNotEmpty ? detail.nameCn : detail.name;
                  final hasMovieTag = detail.tags.any((t) => t.name.contains('剧场版') || t.name.contains('动画电影'));
                  effectiveIsMovie = hasMovieTag || title.contains('剧场版') || (detail.totalEpisodes == 1 && detail.eps == 1);
                }
              }
            }
            effectiveIsMovie ??= false;

            // 1. 白名单题材清洗
            final cleanGenres = <String>[];
            for (final raw in effectiveTags) {
              final t = raw.trim();
              if (t.isEmpty) continue;
              if (AnimeTagFilter.isAllowedGenre(t) && !cleanGenres.contains(t)) {
                cleanGenres.add(t);
              }
            }

            // 2. 槽位题材互斥投影规划 (5 个槽位互斥切面)
            final movieTag = effectiveIsMovie ? ['剧场版'] : const <String>[];
            final slotTagsList = <List<String>>[];

            if (cleanGenres.length >= 3) {
              slotTagsList.add([cleanGenres[0], '日本', ...movieTag]);
              slotTagsList.add([cleanGenres[1], '日本', ...movieTag]);
              slotTagsList.add([cleanGenres[2], '日本', ...movieTag]);
              slotTagsList.add([cleanGenres[0], cleanGenres[1], '日本', ...movieTag]);
              final slot4Tag = cleanGenres.length >= 4 ? cleanGenres[3] : cleanGenres[0];
              slotTagsList.add([slot4Tag, '日本', ...movieTag]);
            } else if (cleanGenres.length == 2) {
              slotTagsList.add([cleanGenres[0], '日本', ...movieTag]);
              slotTagsList.add([cleanGenres[1], '日本', ...movieTag]);
              slotTagsList.add([cleanGenres[0], cleanGenres[1], '日本', ...movieTag]);
              slotTagsList.add([cleanGenres[0], '日本', ...movieTag]);
              slotTagsList.add([cleanGenres[1], '日本', ...movieTag]);
            } else if (cleanGenres.length == 1) {
              for (var i = 0; i < 5; i++) {
                slotTagsList.add([cleanGenres[0], '日本', ...movieTag]);
              }
            } else {
              final itemTags = AnimeTagFilter.cleanItemTags(effectiveTags);
              final fallbackTag = itemTags.isNotEmpty ? itemTags.first : '日本';
              for (var i = 0; i < 5; i++) {
                if (fallbackTag != '日本') {
                  slotTagsList.add([fallbackTag, '日本', ...movieTag]);
                } else {
                  slotTagsList.add(['日本', ...movieTag]);
                }
              }
            }

            // 3. 5 路槽位在 1 ~ tagTotal 全库大纵深内真随机漫游 (score 排序保底品质，全随机 offset 彻底拉开层次)
            final rng = Random();
            final slotFutures = <Future<List<BangumiRecommendationItem>>>[];

            for (var i = 0; i < 5; i++) {
              final searchTags = slotTagsList[i];
              final mainTag = searchTags.firstWhere(
                (t) => t != '日本' && t != '剧场版',
                orElse: () => '日本',
              );

              slotFutures.add(
                () async {
                  final tagTotal = await getTagTotal(mainTag);
                  final maxOffset = max(0, tagTotal - 6);
                  // 直接在 0 ~ (total - 6) 的全库大纵深内真随机摇号
                  final slotOffset = maxOffset > 0 ? rng.nextInt(maxOffset + 1) : 0;

                  var res = await searchWithTotal(
                    '',
                    tags: searchTags,
                    sort: 'score',
                    limit: 6,
                    offset: slotOffset,
                  );

                  // 自适应防空保底：若冷门题材因过大 offset 返回空，平滑退回 offset: 0
                  if (res.items.isEmpty && slotOffset > 0) {
                    res = await searchWithTotal(
                      '',
                      tags: searchTags,
                      sort: 'score',
                      limit: 6,
                      offset: 0,
                    );
                  }

                  return _filterAndMapSearchResult(
                    res.items,
                    excludeSubjectId: subjectId,
                    additionalExcludeIds: excludeIds,
                  );
                }().catchError((_) => <BangumiRecommendationItem>[]),
              );
            }

            final slotResults = await Future.wait(slotFutures);

            // 5. 跨槽位交错穿插（Interleaving）与全局去重，输出自然散落的条目池
            final poolCandidates = <BangumiRecommendationItem>[];
            final seenPoolIds = <int>{
              subjectId,
              ...?excludeIds,
            };

            int maxDepth = 0;
            for (final list in slotResults) {
              if (list.length > maxDepth) maxDepth = list.length;
            }

            for (var depth = 0; depth < maxDepth; depth++) {
              for (var slot = 0; slot < slotResults.length; slot++) {
                final list = slotResults[slot];
                if (depth < list.length) {
                  final item = list[depth];
                  if (!seenPoolIds.contains(item.id)) {
                    seenPoolIds.add(item.id);
                    poolCandidates.add(item);
                  }
                }
              }
            }

            // 6. 兜底平滑补充（若偏门题材或重度去重后不足 15 部，通过随机 offset 从热门日本榜补充）
            if (poolCandidates.length < 15) {
              try {
                final fallbackOffset = rng.nextInt(50);
                final fallbackRes = await searchWithTotal(
                  '',
                  tags: ['日本', ...movieTag],
                  sort: 'heat',
                  limit: 15,
                  offset: fallbackOffset,
                );
                final mapped = _filterAndMapSearchResult(
                  fallbackRes.items,
                  excludeSubjectId: subjectId,
                  additionalExcludeIds: seenPoolIds,
                );
                for (final item in mapped) {
                  if (!seenPoolIds.contains(item.id)) {
                    seenPoolIds.add(item.id);
                    poolCandidates.add(item);
                    if (poolCandidates.length >= 20) break;
                  }
                }
              } catch (_) {}
            }

            // 7. 回填缓存
            if (poolCandidates.isNotEmpty) {
              _similarPoolCache.set(poolCacheKey, poolCandidates, poolCandidates.length * 800 + 256);
              unawaited(_diskCache?.putJson(
                diskCacheKey,
                poolCandidates.map((e) => e.toJson()).toList(),
                maxAge: const Duration(hours: 24),
              ) ?? Future.value());
            }

            return poolCandidates;
          } catch (_) {
            return const <BangumiRecommendationItem>[];
          }
        }();

        _inflight[inflightKey] = future;
        try {
          pool = await future;
        } finally {
          _inflight.remove(inflightKey);
        }
      }
    }

    final validPool = pool.where((item) => excludeIds == null || !excludeIds.contains(item.id)).toList();
    final startIndex = (page - 1) * pageSize;
    if (startIndex >= validPool.length) {
      return (items: const <BangumiRecommendationItem>[], hasMore: false);
    }

    final pageItems = validPool.skip(startIndex).take(pageSize).toList();
    final hasMore = startIndex + pageItems.length < validPool.length;
    return (items: pageItems, hasMore: hasMore);
  }

  /// 获取番剧推荐 (向下兼容旧接口，内部并发拉取前作续作与高分日本推荐)
  Future<List<BangumiRecommendationItem>> getRecommendations(
    int subjectId, {
    List<String>? tags,
    String? country,
    bool? isMovie,
    bool forceRefresh = false,
  }) async {
    if (subjectId <= 0) return const [];

    final relationFuture = getRelationItem(subjectId, forceRefresh: forceRefresh);
    final similarRes = await getSimilarRecommendations(
      subjectId,
      tags: tags,
      isMovie: isMovie,
      page: 1,
      pageSize: 15,
      forceRefresh: forceRefresh,
    );
    final relationItem = await relationFuture;

    if (relationItem != null) {
      return [
        relationItem,
        ...similarRes.items.where((it) => it.id != relationItem.id),
      ];
    }
    return similarRes.items;
  }

  /// 获取条目吐槽与讨论 Chunk (每 Chunk 30 条 = 3 个标准前端页，1:1 对齐 animaku 规范，带 3 小时多层缓存)
  Future<({List<BangumiCommentItem> items, int total})> getCommentsChunk(
    int subjectId, {
    int chunkIndex = 0,
    int? type,
    bool forceRefresh = false,
  }) async {
    if (subjectId <= 0) return (items: const <BangumiCommentItem>[], total: 0);

    const chunkSize = 30;
    final chunkStartOffset = chunkIndex * chunkSize;
    final cacheKey = 'comments_chunk_${subjectId}_${chunkIndex}_${type ?? 'all'}';

    if (!forceRefresh) {
      final cached = _commentsChunkCache.get(cacheKey);
      if (cached != null) return cached;

      final diskJson = await _diskCache?.getJson(cacheKey);
      if (diskJson is Map<String, dynamic> && diskJson['items'] is List) {
        final rawList = diskJson['items'] as List;
        final tot = (diskJson['total'] is num) ? (diskJson['total'] as num).toInt() : 0;
        final list = rawList
            .whereType<Map<String, dynamic>>()
            .map((e) => BangumiCommentItem.fromJson(e))
            .toList();
        final entry = (items: list, total: tot);
        _commentsChunkCache.set(cacheKey, entry, list.length * 600 + 256);
        return entry;
      }
    }

    final inflightKey = 'inflight_$cacheKey';
    if (_inflight.containsKey(inflightKey)) {
      return await (_inflight[inflightKey] as Future<({List<BangumiCommentItem> items, int total})>);
    }

    final future = () async {
      try {
        final url = 'https://next.bgm.tv/p1/subjects/$subjectId/comments';
        final queryParams = <String, dynamic>{
          'limit': chunkSize,
          'offset': chunkStartOffset,
          'type': ?type,
        };

        // 特殊处理说明：官方 Next 评论服务若网络不通或受限，设置 4 秒快速超时，避免详情页无限转圈加载
        final res = await _dio.get(
          url,
          queryParameters: queryParams,
          options: Options(
            sendTimeout: const Duration(seconds: 4),
            receiveTimeout: const Duration(seconds: 4),
          ),
        );

        final data = res.data;
        if (data is Map<String, dynamic>) {
          final rawList = (data['data'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
          final total = (data['total'] is num)
              ? (data['total'] as num).toInt()
              : (int.tryParse('${data['total']}') ?? 0);

          final items = <BangumiCommentItem>[];
          for (var i = 0; i < rawList.length; i++) {
            items.add(BangumiCommentItem.fromJson(rawList[i], chunkStartOffset + i));
          }

          final result = (items: items, total: total);
          _commentsChunkCache.set(cacheKey, result, items.length * 600 + 256);
          unawaited(_diskCache?.putJson(
            cacheKey,
            {
              'total': total,
              'items': items.map((e) => e.toJson()).toList(),
            },
            maxAge: const Duration(hours: 3),
          ) ?? Future.value());

          return result;
        }

        return (items: const <BangumiCommentItem>[], total: 0);
      } catch (e) {
        final stale = _commentsChunkCache.getStale(cacheKey);
        if (stale != null) return stale;
        final diskJson = await _diskCache?.getJson(cacheKey);
        if (diskJson is Map<String, dynamic> && diskJson['items'] is List) {
          final rawList = diskJson['items'] as List;
          final tot = (diskJson['total'] is num) ? (diskJson['total'] as num).toInt() : 0;
          final list = rawList
              .whereType<Map<String, dynamic>>()
              .map((e) => BangumiCommentItem.fromJson(e))
              .toList();
          return (items: list, total: tot);
        }
        return (items: const <BangumiCommentItem>[], total: 0);
      }
    }();

    _inflight[inflightKey] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(inflightKey);
    }
  }

  /// 获取条目标准分页吐槽列表 (单页 10 条，底层基于 30 条 Chunk 缓存实现 0ms 翻页)
  Future<({List<BangumiCommentItem> items, int total})> getCommentsPage(
    int subjectId, {
    int page = 1,
    int pageSize = 10,
    int? type,
    bool forceRefresh = false,
  }) async {
    // 防刷安全上限页码：超大页码直接秒回空列表，绝不上游网络穿透
    if (page < 1 || page > 2000 || subjectId <= 0) {
      return (items: const <BangumiCommentItem>[], total: 0);
    }

    const chunkSize = 30;
    final targetOffset = (page - 1) * pageSize;
    final chunkIndex = targetOffset ~/ chunkSize;
    final chunkStartOffset = chunkIndex * chunkSize;
    final relativeIndex = targetOffset - chunkStartOffset;

    final chunk = await getCommentsChunk(
      subjectId,
      chunkIndex: chunkIndex,
      type: type,
      forceRefresh: forceRefresh,
    );

    if (relativeIndex >= chunk.items.length) {
      return (items: const <BangumiCommentItem>[], total: chunk.total);
    }

    final end = min(relativeIndex + pageSize, chunk.items.length);
    final pageRows = chunk.items.sublist(relativeIndex, end);

    return (items: pageRows, total: chunk.total);
  }

  /// 获取条目吐槽与讨论 (兼容旧版调用，底层对齐 30 条 Chunk 架构)
  Future<List<BangumiComment>> getComments(
    int subjectId, {
    int limit = 20,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    final page = (offset ~/ limit) + 1;
    final res = await getCommentsPage(
      subjectId,
      page: page,
      pageSize: limit,
      forceRefresh: forceRefresh,
    );
    return res.items
        .map((c) => BangumiComment(
              user: c.author,
              rate: c.rate ?? 0,
              comment: c.content,
              updatedAt: c.updatedAt,
            ))
        .toList();
  }

  /// 获取当前登录用户信息 (需要 Bearer Token)
  Future<BangumiUser> getCurrentUser(String token) async {
    try {
      final res = await _dio.get(
        '/v0/me',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      if (res.data is Map<String, dynamic>) {
        return BangumiUser.fromJson(res.data as Map<String, dynamic>);
      }
      throw const BangumiApiException('用户资料解析失败');
    } on DioException catch (e) {
      throw _handleDioError('获取当前用户信息失败', e);
    }
  }

  /// 获取用户对某条目的收藏状态 (带 10 分钟 L1 内存缓存、Single-Flight 并发去重与负缓存)
  Future<BangumiCollectionEntry?> getCollection(
    int subjectId,
    String token, {
    bool forceRefresh = false,
  }) async {
    if (subjectId <= 0) return null;
    final cacheKey = '$subjectId:${token.hashCode}';

    if (!forceRefresh) {
      final cached = _collectionStatusCache.get(cacheKey);
      if (cached != null) {
        return cached.type == CollectType.none ? null : cached;
      }
    }

    final inflightKey = 'col_status_$cacheKey';
    if (_inflight.containsKey(inflightKey)) {
      return await (_inflight[inflightKey] as Future<BangumiCollectionEntry?>);
    }

    final future = () async {
      try {
        final res = await _dio.get(
          '/v0/users/-/collections/$subjectId',
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
          ),
        );
        if (res.data is Map<String, dynamic>) {
          final entry = BangumiCollectionEntry.fromJson(res.data as Map<String, dynamic>);
          _collectionStatusCache.set(cacheKey, entry, 256);
          return entry;
        }
        _collectionStatusCache.set(
          cacheKey,
          BangumiCollectionEntry(subjectId: subjectId, type: CollectType.none),
          32,
        );
        return null;
      } on DioException catch (e) {
        if (e.response?.statusCode == 404) {
          // 负缓存：未收藏状态也保留 10 分钟，防止详情弹窗反复打 404
          _collectionStatusCache.set(
            cacheKey,
            BangumiCollectionEntry(subjectId: subjectId, type: CollectType.none),
            32,
          );
          return null; // 未收藏
        }
        final stale = _collectionStatusCache.getStale(cacheKey);
        if (stale != null) {
          return stale.type == CollectType.none ? null : stale;
        }
        throw _handleDioError('获取条目收藏状态失败', e);
      }
    }();

    _inflight[inflightKey] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(inflightKey);
    }
  }

  /// 修改/保存用户对某条目的收藏状态
  Future<bool> setCollection(
    int subjectId,
    CollectType type,
    String token, {
    int? rate,
    String? comment,
  }) async {
    final bangumiType = type.toBangumiType();
    if (bangumiType == null) {
      return false;
    }

    try {
      final payload = <String, dynamic>{
        'type': bangumiType,
      };
      if (rate != null) payload['rate'] = rate;
      if (comment != null) payload['comment'] = comment;

      final res = await _dio.post(
        '/v0/users/-/collections/$subjectId',
        data: payload,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      final success = res.statusCode == 200 || res.statusCode == 202;
      if (success) {
        // 特殊处理说明：更新成功后自动使单项收藏与列表缓存失效，确保数据一致
        _collectionStatusCache.remove('$subjectId:${token.hashCode}');
        _userCollectionsCache.clear();
      }
      return success;
    } on DioException catch (e) {
      throw _handleDioError('更新收藏状态失败', e);
    }
  }

  /// 获取用户收藏列表 (遵循 Bangumi v0 API 规范: /v0/users/{username}/collections，带 10 分钟 L1 内存缓存与 Single-Flight)
  Future<List<Map<String, dynamic>>> getUserCollections(
    String username, {
    String? token,
    int subjectType = 2, // 2 = 动画
    CollectType? type,
    int limit = 30,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '$username|${type?.name ?? 'all'}|$subjectType|$limit|$offset';

    if (!forceRefresh) {
      final cached = _userCollectionsCache.get(cacheKey);
      if (cached != null) return cached;
    }

    final inflightKey = 'user_cols_$cacheKey';
    if (_inflight.containsKey(inflightKey)) {
      return await (_inflight[inflightKey] as Future<List<Map<String, dynamic>>>);
    }

    final future = () async {
      try {
        final query = <String, dynamic>{
          'subject_type': subjectType,
          'limit': limit,
          'offset': offset,
        };
        final bangumiType = type?.toBangumiType();
        if (bangumiType != null) {
          query['type'] = bangumiType;
        }

        final res = await _dio.get(
          '/v0/users/$username/collections',
          queryParameters: query,
          options: Options(
            headers: token != null && token.isNotEmpty
                ? {'Authorization': 'Bearer $token'}
                : null,
          ),
        );

        if (res.data is Map<String, dynamic>) {
          final data = res.data['data'];
          if (data is List) {
            final list = data.whereType<Map<String, dynamic>>().toList();
            _userCollectionsCache.set(cacheKey, list, list.length * 512 + 64);
            return list;
          }
        }
        return const <Map<String, dynamic>>[];
      } on DioException catch (e) {
        final stale = _userCollectionsCache.getStale(cacheKey);
        if (stale != null) return stale;
        throw _handleDioError('获取用户收藏列表失败', e);
      }
    }();

    _inflight[inflightKey] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(inflightKey);
    }
  }

  BangumiApiException _handleDioError(String prefix, DioException e) =>
      BangumiApiException.fromDio(prefix, e);
}
