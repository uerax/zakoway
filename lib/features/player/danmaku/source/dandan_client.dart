import 'dart:convert';
import 'dart:developer' as developer;
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:zakoway/core/network/player_media_disk_cache_manager.dart';
import 'package:zakoway/core/utils/timed_cache.dart';
import '../models/danmaku_item.dart';
import '../utils/danmaku_episode_matcher.dart';
import 'dandan_config_manager.dart';

/// 弹弹 play 番剧搜索结果模型
class DandanAnime {
  const DandanAnime({
    required this.animeId,
    required this.animeTitle,
    this.bangumiId,
    this.episodeCount,
    this.typeDescription,
    this.imageUrl,
  });

  final int animeId;
  final String animeTitle;
  final String? bangumiId;
  final int? episodeCount;
  final String? typeDescription;
  final String? imageUrl;

  factory DandanAnime.fromJson(Map<String, dynamic> json) {
    return DandanAnime(
      animeId: json['animeId'] as int? ?? 0,
      animeTitle: json['animeTitle']?.toString() ?? '',
      bangumiId: json['bangumiId']?.toString(),
      episodeCount: json['episodeCount'] as int?,
      typeDescription: json['typeDescription']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'animeId': animeId,
        'animeTitle': animeTitle,
        if (bangumiId != null) 'bangumiId': bangumiId,
        if (episodeCount != null) 'episodeCount': episodeCount,
        if (typeDescription != null) 'typeDescription': typeDescription,
        if (imageUrl != null) 'imageUrl': imageUrl,
      };
}

/// 弹弹 play 番剧分集模型
class DandanEpisode implements DanmakuEpisodeEntry {
  const DandanEpisode({
    required this.episodeId,
    required this.episodeTitle,
  });

  @override
  final int episodeId;

  @override
  final String episodeTitle;

  factory DandanEpisode.fromJson(Map<String, dynamic> json) {
    return DandanEpisode(
      episodeId: json['episodeId'] as int? ?? 0,
      episodeTitle: json['episodeTitle']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'episodeId': episodeId,
        'episodeTitle': episodeTitle,
      };
}

/// 弹弹 play 番剧详情与分集集合
class DandanBangumiDetails {
  const DandanBangumiDetails({
    required this.bangumiId,
    required this.episodes,
    this.animeTitle,
  });

  final int bangumiId;
  final List<DandanEpisode> episodes;
  final String? animeTitle;

  factory DandanBangumiDetails.fromJson(Map<String, dynamic> json) {
    final rawList = json['episodes'] as List? ?? [];
    return DandanBangumiDetails(
      bangumiId: json['bangumiId'] as int? ?? 0,
      animeTitle: json['animeTitle']?.toString(),
      episodes: rawList
          .whereType<Map<String, dynamic>>()
          .map(DandanEpisode.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'bangumiId': bangumiId,
        if (animeTitle != null) 'animeTitle': animeTitle,
        'episodes': episodes.map((e) => e.toJson()).toList(),
      };
}

/// 弹弹 play 原生 Dio 客户端 (1:1 对齐 animaku dandan.ts)
/// 支持动态配置 AppId/Secret、开放平台 SHA-256 签名以及 L1 内存 + L2 硬盘双层持久化缓存
class DandanClient {
  DandanClient({
    Dio? dio,
    DandanConfigManager? configManager,
  })  : _dio = dio ?? Dio(),
        _config = configManager ?? DandanConfigManager.instance;

  static DandanClient? _instance;
  static DandanClient get instance => _instance ??= DandanClient();

  final Dio _dio;
  final DandanConfigManager _config;

  // L1 内存缓存池 (1:1 严格对齐 animaku DANMAKU_CACHE_TTL 规范)
  // 1. 番剧信息与分集：12 小时
  final TimedKeyedCache<int, DandanBangumiDetails> _bgmSubjectCache =
      TimedKeyedCache(maxAge: const Duration(hours: 12), maxEntries: 200);
  final TimedKeyedCache<int, DandanBangumiDetails> _detailsCache =
      TimedKeyedCache(maxAge: const Duration(hours: 12), maxEntries: 200);

  // 2. 搜索结果：2 小时
  final TimedKeyedCache<String, List<DandanAnime>> _searchCache =
      TimedKeyedCache(maxAge: const Duration(hours: 2), maxEntries: 100);

  // 3. 分集弹幕评论：30 分钟
  final TimedKeyedCache<String, List<DanmakuItem>> _commentsCache =
      TimedKeyedCache(maxAge: const Duration(minutes: 30), maxEntries: 100);

  /// 当前内存缓存预估字节数
  int get memoryCacheSizeBytes =>
      _bgmSubjectCache.totalBytes +
      _detailsCache.totalBytes +
      _searchCache.totalBytes +
      _commentsCache.totalBytes;

  /// 清空所有弹弹内存缓存
  void clearMemoryCache() {
    _bgmSubjectCache.clear();
    _detailsCache.clear();
    _searchCache.clear();
    _commentsCache.clear();
  }

  Map<String, String> _buildHeaders(String path) {
    final headers = <String, String>{
      'User-Agent': 'Zakoway/1.0.0 (Anime Client)',
      'Accept': 'application/json',
    };

    final appId = _config.effectiveAppId;
    final appSecret = _config.effectiveAppSecret;

    if (_config.effectiveAuthMode == DandanAuthMode.open) {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      headers['X-Auth'] = '1';
      headers['X-AppId'] = appId;
      headers['X-Timestamp'] = timestamp.toString();
      headers['X-Signature'] = DandanConfigManager.generateSignature(
        path: path,
        timestamp: timestamp,
        appId: appId,
        appSecret: appSecret,
      );
    } else {
      headers['X-AppId'] = appId;
      headers['X-AppSecret'] = appSecret;
    }

    return headers;
  }

  String _buildUrl(String path) => '${_config.effectiveEndpoint}$path';

  /// 通过 Bangumi.tv 条目 ID 直接查询弹弹关联番剧与分集 (带 L1 内存 + L2 硬盘 12h 缓存)
  Future<DandanBangumiDetails> getBangumiByBgmId(int bgmId, {bool bypassCache = false}) async {
    final diskCacheKey = 'dd_bgm_$bgmId';

    if (!bypassCache) {
      // 1. 查内存
      final hit = _bgmSubjectCache.get(bgmId);
      if (hit != null) return hit;

      // 2. 查硬盘
      final disk = PlayerMediaDiskCacheManager.instance;
      if (disk != null) {
        try {
          final diskJson = await disk.getJson(diskCacheKey);
          if (diskJson is Map<String, dynamic>) {
            final res = DandanBangumiDetails.fromJson(diskJson);
            _bgmSubjectCache.set(bgmId, res, res.episodes.length * 96 + 128);
            return res;
          }
        } catch (_) {}
      }
    }

    const path = '/api/v2/bangumi/bgmtv';
    final fullPath = '$path/$bgmId';
    final url = _buildUrl(fullPath);

    try {
      final res = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(
          headers: _buildHeaders(fullPath),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final data = res.data ?? <String, dynamic>{};
      final success = data['success'] as bool? ?? false;
      if (!success) {
        final errorCode = data['errorCode'] as int?;
        final errorMessage = data['errorMessage']?.toString() ?? '';
        // errorCode 7: 无法找到指定的资源（新番未收录正常情况，缓存空结果保护配额并消除重复打上游）
        if (errorCode == 7 || errorMessage.contains('无法找到')) {
          const empty = DandanBangumiDetails(bangumiId: 0, episodes: []);
          _bgmSubjectCache.set(bgmId, empty, 64);
          PlayerMediaDiskCacheManager.instance?.putJson(
            diskCacheKey,
            empty.toJson(),
            maxAge: const Duration(hours: 12),
          ).ignore();
          return empty;
        }
        throw Exception(errorMessage.isNotEmpty ? errorMessage : '弹弹 BGM 查询失败');
      }

      final bangumiMap = (data['bangumi'] as Map<String, dynamic>?) ?? data;
      final rawEpisodes = bangumiMap['episodes'] as List<dynamic>? ?? const [];
      final episodes = rawEpisodes
          .whereType<Map<String, dynamic>>()
          .map(DandanEpisode.fromJson)
          .toList();

      final animeId = (bangumiMap['animeId'] as int?) ??
          (bangumiMap['bangumiId'] as int?) ??
          0;
      final animeTitle = (bangumiMap['animeTitle'] ?? bangumiMap['bangumiTitle'])?.toString();

      final result = DandanBangumiDetails(
        bangumiId: animeId,
        episodes: episodes,
        animeTitle: animeTitle,
      );
      final estimatedBytes = episodes.length * 96 + 128;
      _bgmSubjectCache.set(bgmId, result, estimatedBytes);

      // 持久化保存到硬盘 (12 小时)
      PlayerMediaDiskCacheManager.instance?.putJson(
        diskCacheKey,
        result.toJson(),
        maxAge: const Duration(hours: 12),
      ).ignore();

      return result;
    } catch (e) {
      developer.log('[DandanClient] getBangumiByBgmId failed: $e');
      rethrow;
    }
  }

  /// 关键字搜索番剧 (带 L1 内存 + L2 硬盘 2h 缓存)
  Future<List<DandanAnime>> searchAnime(String keyword, {bool bypassCache = false}) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return const [];

    final cacheKey = kw.toLowerCase();
    final kwHash = md5.convert(utf8.encode(cacheKey)).toString();
    final diskCacheKey = 'dd_search_$kwHash';

    if (!bypassCache) {
      // 1. 查内存
      final hit = _searchCache.get(cacheKey);
      if (hit != null) return hit;

      // 2. 查硬盘
      final disk = PlayerMediaDiskCacheManager.instance;
      if (disk != null) {
        try {
          final diskJson = await disk.getJson(diskCacheKey);
          if (diskJson is List && diskJson.isNotEmpty) {
            final list = diskJson
                .whereType<Map<String, dynamic>>()
                .map(DandanAnime.fromJson)
                .toList();
            if (list.isNotEmpty) {
              _searchCache.set(cacheKey, list, list.length * 160 + 64);
              return list;
            }
          }
        } catch (_) {}
      }
    }

    const path = '/api/v2/search/anime';
    final url = _buildUrl(path);

    try {
      final res = await _dio.get<Map<String, dynamic>>(
        url,
        queryParameters: {'keyword': kw},
        options: Options(
          headers: _buildHeaders(path),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final data = res.data ?? <String, dynamic>{};
      final success = data['success'] as bool? ?? false;
      if (!success) {
        final errorMessage = data['errorMessage']?.toString() ?? '弹弹搜索失败';
        throw Exception(errorMessage);
      }

      final rawAnimes = data['animes'] as List<dynamic>? ?? const [];
      final list = rawAnimes
          .whereType<Map<String, dynamic>>()
          .map(DandanAnime.fromJson)
          .toList();

      final estimatedBytes = list.length * 160 + 64;
      _searchCache.set(cacheKey, list, estimatedBytes);

      // 写入硬盘 (2 小时)
      if (list.isNotEmpty) {
        PlayerMediaDiskCacheManager.instance?.putJson(
          diskCacheKey,
          list.map((a) => a.toJson()).toList(),
          maxAge: const Duration(hours: 2),
        ).ignore();
      }

      return list;
    } catch (e) {
      developer.log('[DandanClient] searchAnime failed: $e');
      rethrow;
    }
  }

  /// 获取指定番剧详情与全部剧集 (带 L1 内存 + L2 硬盘 12h 缓存)
  Future<DandanBangumiDetails> getBangumiDetails(int animeId, {bool bypassCache = false}) async {
    final diskCacheKey = 'dd_det_$animeId';

    if (!bypassCache) {
      final hit = _detailsCache.get(animeId);
      if (hit != null) return hit;

      final disk = PlayerMediaDiskCacheManager.instance;
      if (disk != null) {
        try {
          final diskJson = await disk.getJson(diskCacheKey);
          if (diskJson is Map<String, dynamic>) {
            final res = DandanBangumiDetails.fromJson(diskJson);
            _detailsCache.set(animeId, res, res.episodes.length * 96 + 128);
            return res;
          }
        } catch (_) {}
      }
    }

    final path = '/api/v2/bangumi/$animeId';
    final url = _buildUrl(path);

    try {
      final res = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(
          headers: _buildHeaders(path),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final data = res.data ?? <String, dynamic>{};
      final success = data['success'] as bool? ?? false;
      if (!success) {
        final errorCode = data['errorCode'] as int?;
        final errorMessage = data['errorMessage']?.toString() ?? '';
        if (errorCode == 7 || errorMessage.contains('无法找到')) {
          final empty = DandanBangumiDetails(bangumiId: animeId, episodes: const []);
          _detailsCache.set(animeId, empty, 64);
          PlayerMediaDiskCacheManager.instance?.putJson(
            diskCacheKey,
            empty.toJson(),
            maxAge: const Duration(hours: 12),
          ).ignore();
          return empty;
        }
        throw Exception(errorMessage.isNotEmpty ? errorMessage : '弹弹番剧详情查询失败');
      }

      final bangumiMap = (data['bangumi'] as Map<String, dynamic>?) ?? data;
      final rawEpisodes = bangumiMap['episodes'] as List<dynamic>? ?? const [];
      final episodes = rawEpisodes
          .whereType<Map<String, dynamic>>()
          .map(DandanEpisode.fromJson)
          .toList();
      final animeTitle = (bangumiMap['animeTitle'] ?? bangumiMap['bangumiTitle'])?.toString();

      final result = DandanBangumiDetails(
        bangumiId: animeId,
        episodes: episodes,
        animeTitle: animeTitle,
      );
      final estimatedBytes = episodes.length * 96 + 128;
      _detailsCache.set(animeId, result, estimatedBytes);

      // 写入硬盘 (12 小时)
      PlayerMediaDiskCacheManager.instance?.putJson(
        diskCacheKey,
        result.toJson(),
        maxAge: const Duration(hours: 12),
      ).ignore();

      return result;
    } catch (e) {
      developer.log('[DandanClient] getBangumiDetails failed: $e');
      rethrow;
    }
  }

  /// 拉取指定分集的弹幕评论列表 (带 L1 内存 + L2 硬盘 30min 缓存)
  Future<List<DanmakuItem>> getComments(
    int episodeId, {
    bool withRelated = true,
    int chConvert = 1,
    bool bypassCache = false,
  }) async {
    final cacheKey = '$episodeId:$withRelated:$chConvert';
    final diskCacheKey = 'dd_cm_${episodeId}_${withRelated}_$chConvert';

    if (!bypassCache) {
      final hit = _commentsCache.get(cacheKey);
      if (hit != null) return hit;

      final disk = PlayerMediaDiskCacheManager.instance;
      if (disk != null) {
        try {
          final diskJson = await disk.getJson(diskCacheKey);
          if (diskJson is List && diskJson.isNotEmpty) {
            final list = diskJson
                .whereType<Map<String, dynamic>>()
                .map(DanmakuItem.fromJson)
                .toList();
            if (list.isNotEmpty) {
              _commentsCache.set(cacheKey, list, list.length * 120 + 64);
              return list;
            }
          }
        } catch (_) {}
      }
    }

    final path = '/api/v2/comment/$episodeId';
    final url = _buildUrl(path);

    try {
      final res = await _dio.get<Map<String, dynamic>>(
        url,
        queryParameters: {
          'withRelated': withRelated.toString(),
          'chConvert': chConvert.toString(),
        },
        options: Options(
          headers: _buildHeaders(path),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final data = res.data ?? <String, dynamic>{};
      final rawComments = data['comments'] as List<dynamic>? ?? const [];
      final comments = _parseDandanComments(rawComments);

      final estimatedBytes = comments.length * 120 + 64;
      _commentsCache.set(cacheKey, comments, estimatedBytes);

      // 写入硬盘 (30 分钟)
      if (comments.isNotEmpty) {
        PlayerMediaDiskCacheManager.instance?.putJson(
          diskCacheKey,
          comments.map((c) => c.toJson()).toList(),
          maxAge: const Duration(minutes: 30),
        ).ignore();
      }

      return comments;
    } catch (e) {
      developer.log('[DandanClient] getComments failed: $e');
      rethrow;
    }
  }

  /// 解析弹弹原始 comments (m: text, p: "time,type,color,senderHash")
  List<DanmakuItem> _parseDandanComments(List<dynamic> comments) {
    final out = <DanmakuItem>[];

    for (final item in comments) {
      if (item is! Map<String, dynamic>) continue;
      final m = item['m']?.toString() ?? '';
      final p = item['p']?.toString() ?? '';
      if (m.trim().isEmpty || p.isEmpty) continue;

      final parts = p.split(',');
      if (parts.isEmpty) continue;

      final timeSec = double.tryParse(parts[0]);
      if (timeSec == null || !timeSec.isFinite || timeSec < 0) continue;
      final timeMs = (timeSec * 1000).round();

      final typeStr = parts.length > 1 ? parts[1].trim() : '1';
      final colorStr = parts.length > 2 ? parts[2].trim() : '';
      final senderHash = parts.length > 3 ? parts[3].trim() : null;

      final mode = switch (typeStr) {
        '4' => DanmakuMode.bottom,
        '5' => DanmakuMode.top,
        _ => DanmakuMode.scroll,
      };

      final color = _parseColorInt(colorStr);

      out.add(DanmakuItem(
        text: m,
        timeMs: timeMs,
        mode: mode,
        color: color,
        source: 'dandan',
        senderHash: (senderHash != null && senderHash.isNotEmpty) ? senderHash : null,
      ));
    }

    out.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return out;
  }

  Color _parseColorInt(String? colorStr) {
    if (colorStr == null || colorStr.isEmpty) return Colors.white;
    final n = int.tryParse(colorStr);
    if (n == null) return Colors.white;
    return Color(0xFF000000 | (n & 0x00FFFFFF));
  }
}
