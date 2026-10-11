import 'dart:async';
import 'dart:developer' as developer;
import 'package:dio/dio.dart';
import '../constants/app_constants.dart';
import '../models/bangumi/bangumi_calendar.dart';
import '../models/bangumi/bangumi_collection.dart';
import '../models/bangumi/bangumi_comment.dart';
import '../models/bangumi/bangumi_episode.dart';
import '../models/bangumi/bangumi_item.dart';
import '../models/bangumi/bangumi_search_result.dart';
import '../models/bangumi/bangumi_user.dart';
import '../models/network/custom_network_route.dart';
import '../services/app_preferences.dart';
import '../services/daily_recommend_service.dart';
import '../utils/image_utils.dart';
import '../utils/timed_cache.dart';
import 'bangumi_api_exception.dart';
import 'bangumi_data_disk_cache_manager.dart';
import 'bangumi_search_query_builder.dart';
import 'bangumi_source_preset.dart';
import 'bangumi_user_agent.dart';

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
    String version = AppConstants.appVersion,
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
      _commentsCache.length;

  /// O(1) 极速获取当前客户端在内存中缓存的 API 响应数据字节大小，彻底避免在 UI 线程全量 JSON 序列化导致卡顿
  int get dataCacheSizeBytes =>
      _calendarCache.estimatedBytes +
      _trendingCache.estimatedBytes +
      _searchCache.totalBytes +
      _subjectCache.totalBytes +
      _episodesCache.totalBytes +
      _commentsCache.totalBytes;

  void clearCache() {
    _calendarCache.clear();
    _trendingCache.clear();
    _searchCache.clear();
    _subjectCache.clear();
    _episodesCache.clear();
    _commentsCache.clear();
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
  Future<List<BangumiItem>> getTrending({int limit = 18, bool forceRefresh = false}) async {
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
      // 1. 优先尝试 next.bgm.tv /p1/trending/subjects (若无跨域限制或在原生平台)
      try {
        final res = await _dio.get(
          'https://next.bgm.tv/p1/trending/subjects',
          queryParameters: {'type': 2, 'limit': limit, 'offset': 0},
        );
        final rawData = res.data;
        if (rawData is Map<String, dynamic> && rawData['data'] is List) {
          final list = rawData['data'] as List;
          final items = list
              .whereType<Map<String, dynamic>>()
              .map((entry) {
                final subject = entry['subject'] is Map<String, dynamic>
                    ? Map<String, dynamic>.from(entry['subject'] as Map<String, dynamic>)
                    : Map<String, dynamic>.from(entry);
                // 关键：next.bgm.tv 返回的热度值保存在外层 entry['count'] 中，需合并注入到 subject 中以正确生成 item.heat
                if (entry['count'] != null) {
                  subject['heat'] = entry['count'];
                }
                if (entry['watchers'] != null) {
                  subject['watchers'] = entry['watchers'];
                }
                return BangumiItem.fromJson(subject);
              })
              .toList();
          if (items.isNotEmpty) {
            _trendingCache.set(items, items.length * 1500);
            unawaited(_diskCache?.putJson(
              'bangumi_trending_$limit',
              items.map((i) => i.toJson()).toList(),
              maxAge: const Duration(hours: 12),
            ) ?? Future.value());
            return items;
          }
        }
      } catch (_) {
        // 容错降级（如 Web 端 CORS 限制拦截时自动平滑走标准检索接口）
      }

      // 2. 降级使用标准 v0 接口按近半年时间 + 热度排行检索 (全端/跨域 100% 兼容)
      try {
        final now = DateTime.now();
        final halfYearAgo = now.subtract(const Duration(days: 180));
        final dateStr =
            '${halfYearAgo.year}-${halfYearAgo.month.toString().padLeft(2, '0')}-01';

        final items = await search(
          '',
          sort: 'heat',
          airDate: ['>=$dateStr'],
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
      } catch (_) {}

      if (_trendingCache.staleValue != null) return _trendingCache.staleValue!;

      // 特殊处理说明：网络异常时从磁盘缓存兜底，坚决避免返回空列表导致页面货架空白
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
  Future<List<BangumiItem>> getHotMovies({int limit = 18, bool forceRefresh = false}) async {
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
  Future<List<BangumiItem>> getHotOva({int limit = 18, bool forceRefresh = false}) async {
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

  /// 获取条目吐槽与讨论 (带 3 小时内存缓存)
  Future<List<BangumiComment>> getComments(
    int subjectId, {
    int limit = 20,
    int offset = 0,
    bool forceRefresh = false,
  }) async {
    final cacheKey = '${subjectId}_${limit}_$offset';
    if (!forceRefresh) {
      final cached = _commentsCache.get(cacheKey);
      if (cached != null) return cached;
    }

    final inflightKey = 'comments_$cacheKey';
    if (_inflight.containsKey(inflightKey)) {
      return await (_inflight[inflightKey] as Future<List<BangumiComment>>);
    }

    final Future<List<BangumiComment>> future = () async {
      try {
        final res = await _dio.get(
          '/v0/subjects/$subjectId/comments',
          queryParameters: {
            'limit': limit,
            'offset': offset,
          },
        );

        final data = res.data;
        if (data is Map<String, dynamic> && data['data'] is List) {
          final list = data['data'] as List;
          final comments = list
              .whereType<Map<String, dynamic>>()
              .map((c) => BangumiComment.fromJson(c))
              .toList();
          _commentsCache.set(cacheKey, comments, comments.length * 600 + 256);
          return comments;
        }
        return const <BangumiComment>[];
      } on DioException catch (e) {
        final stale = _commentsCache.getStale(cacheKey);
        if (stale != null) return stale;
        throw _handleDioError('获取评论失败 (ID: $subjectId)', e);
      }
    }();

    _inflight[inflightKey] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(inflightKey);
    }
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

  /// 获取用户对某条目的收藏状态
  Future<BangumiCollectionEntry?> getCollection(int subjectId, String token) async {
    try {
      final res = await _dio.get(
        '/v0/users/-/collections/$subjectId',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
        ),
      );
      if (res.data is Map<String, dynamic>) {
        return BangumiCollectionEntry.fromJson(res.data as Map<String, dynamic>);
      }
      return null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        return null; // 未收藏
      }
      throw _handleDioError('获取条目收藏状态失败', e);
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
      return res.statusCode == 200 || res.statusCode == 202;
    } on DioException catch (e) {
      throw _handleDioError('更新收藏状态失败', e);
    }
  }

  /// 获取用户收藏列表 (遵循 Bangumi v0 API 规范: /v0/users/{username}/collections)
  Future<List<Map<String, dynamic>>> getUserCollections(
    String username, {
    String? token,
    int subjectType = 2, // 2 = 动画
    CollectType? type,
    int limit = 30,
    int offset = 0,
  }) async {
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
          return data.whereType<Map<String, dynamic>>().toList();
        }
      }
      return [];
    } on DioException catch (e) {
      throw _handleDioError('获取用户收藏列表失败', e);
    }
  }

  BangumiApiException _handleDioError(String prefix, DioException e) =>
      BangumiApiException.fromDio(prefix, e);
}
