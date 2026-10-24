import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:zakoway/core/network/player_media_disk_cache_manager.dart';
import 'package:zakoway/core/utils/timed_cache.dart';
import '../models/danmaku_item.dart';
import 'bangumi_bilibili_mapping_service.dart';
import 'bilibili_input_parser.dart';
import 'bilibili_xml_parser.dart';

/// B 站分 P 简要信息
class BilibiliPageInfo {
  const BilibiliPageInfo({
    required this.page,
    required this.cid,
    required this.part,
    this.epId,
    this.bvid,
  });

  final int page;
  final int cid;
  final String part;
  final int? epId;
  final String? bvid;

  factory BilibiliPageInfo.fromJson(Map<String, dynamic> json) {
    return BilibiliPageInfo(
      page: json['page'] as int? ?? 1,
      cid: json['cid'] as int? ?? 0,
      part: json['part']?.toString() ?? 'P1',
      epId: json['epId'] as int?,
      bvid: json['bvid']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'page': page,
        'cid': cid,
        'part': part,
        if (epId != null) 'epId': epId,
        if (bvid != null) 'bvid': bvid,
      };
}

/// B 站弹幕拉取结果
class BilibiliDanmakuResult {
  const BilibiliDanmakuResult({
    required this.comments,
    required this.cid,
    required this.page,
    this.title,
    this.part,
    this.bvid,
    this.epId,
    this.seasonId,
    this.pages = const [],
  });

  final List<DanmakuItem> comments;
  final int cid;
  final int page;
  final String? title;
  final String? part;
  final String? bvid;
  final int? epId;
  final int? seasonId;
  final List<BilibiliPageInfo> pages;

  Map<String, dynamic> toJson() => {
        'comments': comments.map((c) => c.toJson()).toList(),
        'cid': cid,
        'page': page,
        if (title != null) 'title': title,
        if (part != null) 'part': part,
        if (bvid != null) 'bvid': bvid,
        if (epId != null) 'epId': epId,
        if (seasonId != null) 'seasonId': seasonId,
        'pages': pages.map((p) => p.toJson()).toList(),
      };

  factory BilibiliDanmakuResult.fromJson(Map<String, dynamic> json) {
    final rawComments = json['comments'] as List? ?? [];
    final comments = rawComments
        .whereType<Map<String, dynamic>>()
        .map(DanmakuItem.fromJson)
        .toList();
    final rawPages = json['pages'] as List? ?? [];
    final pages = rawPages
        .whereType<Map<String, dynamic>>()
        .map(BilibiliPageInfo.fromJson)
        .toList();

    return BilibiliDanmakuResult(
      comments: comments,
      cid: json['cid'] as int? ?? 0,
      page: json['page'] as int? ?? 1,
      title: json['title']?.toString(),
      part: json['part']?.toString(),
      bvid: json['bvid']?.toString(),
      epId: json['epId'] as int?,
      seasonId: json['seasonId'] as int?,
      pages: pages,
    );
  }
}

/// 原生 Bilibili 弹幕客户端 (1:1 对齐 animaku bilibili-danmaku.ts)
/// 具备 L1 内存 + L2 硬盘双层缓存与请求单飞去重
class BilibiliDanmakuClient {
  BilibiliDanmakuClient({Dio? dio}) : _dio = dio ?? Dio();

  static BilibiliDanmakuClient? _instance;
  static BilibiliDanmakuClient get instance => _instance ??= BilibiliDanmakuClient();

  final Dio _dio;

  // L1 内存缓存 (30 分钟)
  final TimedKeyedCache<String, BilibiliDanmakuResult> _memoryCache =
      TimedKeyedCache(maxAge: const Duration(minutes: 30), maxEntries: 100);

  // 单飞请求锁
  final Map<String, Future<BilibiliDanmakuResult>> _inflight = {};

  int get memoryCacheSizeBytes => _memoryCache.totalBytes;
  void clearMemoryCache() => _memoryCache.clear();

  static const String _kDefaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  Map<String, String> _buildHeaders() {
    return {
      'User-Agent': _kDefaultUserAgent,
      'Accept': '*/*',
      'Referer': 'https://www.bilibili.com/',
    };
  }

  /// 拉取 B 站弹幕的主入口 (支持 BV/AV/ep/ss/md/b23短链及带 ?p= 分页的链接，带双层 30min 缓存)
  Future<BilibiliDanmakuResult> fetchDanmaku(
    String rawInput, {
    int? pageOverride,
    bool bypassCache = false,
  }) async {
    final cacheKey = '$rawInput:${pageOverride ?? 1}';
    final keyHash = md5.convert(utf8.encode(cacheKey)).toString();
    final diskCacheKey = 'bili_dm_$keyHash';

    if (!bypassCache) {
      // 1. 查内存
      final memHit = _memoryCache.get(cacheKey);
      if (memHit != null) return memHit;

      // 2. 查硬盘
      final disk = PlayerMediaDiskCacheManager.instance;
      if (disk != null) {
        try {
          final diskJson = await disk.getJson(diskCacheKey);
          if (diskJson is Map<String, dynamic>) {
            final res = BilibiliDanmakuResult.fromJson(diskJson);
            _memoryCache.set(cacheKey, res, res.comments.length * 128 + 256);
            return res;
          }
        } catch (_) {}
      }
    }

    if (_inflight.containsKey(cacheKey)) {
      return _inflight[cacheKey]!;
    }

    final future = () async {
      final result = await _fetchDanmakuInternal(rawInput, pageOverride: pageOverride);
      if (result.comments.isNotEmpty || result.cid > 0) {
        _memoryCache.set(cacheKey, result, result.comments.length * 128 + 256);
        PlayerMediaDiskCacheManager.instance?.putJson(
          diskCacheKey,
          result.toJson(),
          maxAge: const Duration(minutes: 30),
        ).ignore();
      }
      return result;
    }();

    _inflight[cacheKey] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(cacheKey);
    }
  }

  Future<BilibiliDanmakuResult> _fetchDanmakuInternal(
    String rawInput, {
    int? pageOverride,
  }) async {
    var target = BilibiliInputParser.parse(rawInput);
    if (target == null) {
      throw Exception('请提供有效的 B 站链接或标识 (支持 BV号 / ep番剧 / ss季度 / av号 / b23短链)');
    }

    final page = pageOverride ?? target.page ?? 1;

    // 1. 处理 b23.tv 短链重定向
    if (target.type == BilibiliTargetType.b23 && target.url != null) {
      final resolved = await _resolveB23ShortLink(target.url!);
      if (resolved != null) {
        target = resolved.copyWith(page: target.page);
      } else {
        throw Exception('未能解析该 b23.tv 短链接目标');
      }
    }

    // 2. 处理 bgm 跨站映射 (1:1 对齐 animaku bangumi-data)
    if (target.type == BilibiliTargetType.bgm && target.bangumiId != null) {
      final mappedTargetId = await BangumiBilibiliMappingService.instance.getBilibiliTargetId(target.bangumiId!);
      if (mappedTargetId == null || mappedTargetId.isEmpty) {
        return BilibiliDanmakuResult(
          comments: const [],
          cid: 0,
          page: page,
        );
      }

      final parsedMapped = BilibiliInputParser.parse(mappedTargetId);
      if (parsedMapped != null && parsedMapped.type != BilibiliTargetType.bgm) {
        target = parsedMapped.copyWith(
          page: pageOverride ?? parsedMapped.page ?? target.page,
        );
      } else {
        final numId = int.tryParse(mappedTargetId);
        if (numId != null && numId > 0) {
          target = BilibiliTarget(
            type: BilibiliTargetType.md,
            mediaId: numId,
            page: pageOverride ?? target.page,
            raw: 'md$numId',
          );
        } else {
          return BilibiliDanmakuResult(
            comments: const [],
            cid: 0,
            page: page,
          );
        }
      }
    }

    // 3. 处理 md (media_id) -> season_id
    if (target.type == BilibiliTargetType.md && target.mediaId != null) {
      final resolvedSsId = await _resolveMediaIdToSeasonId(target.mediaId!);
      target = target.copyWith(
        type: BilibiliTargetType.ss,
        seasonId: resolvedSsId ?? target.mediaId,
      );
    }

    int cid = 0;
    String title = '';
    String part = '';
    String? bvid = target.bvid;
    int? epId = target.epId;
    int? seasonId = target.seasonId;
    final pages = <BilibiliPageInfo>[];

    // 4. PGC 番剧 (ep 或 ss)
    if (target.type == BilibiliTargetType.ep || target.type == BilibiliTargetType.ss) {
      final pgcUrl = target.type == BilibiliTargetType.ep
          ? 'https://api.bilibili.com/pgc/view/web/season?ep_id=${target.epId}'
          : 'https://api.bilibili.com/pgc/view/web/season?season_id=${target.seasonId}';

      final res = await _dio.get<Map<String, dynamic>>(
        pgcUrl,
        options: Options(
          headers: _buildHeaders(),
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final root = res.data ?? <String, dynamic>{};
      final code = root['code'] as int? ?? -1;
      final result = root['result'] as Map<String, dynamic>?;

      if (code != 0 || result == null) {
        final message = root['message']?.toString() ?? 'B站返回 code=$code';
        throw Exception(message);
      }

      title = result['title']?.toString() ?? result['season_title']?.toString() ?? '';
      seasonId = (result['season_id'] as int?) ?? seasonId;

      final mainEps = (result['episodes'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
      final sectionEps = (result['section'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .expand((s) => (s['episodes'] as List<dynamic>? ?? const []).whereType<Map<String, dynamic>>())
          .toList();

      final allEps = [...mainEps, ...sectionEps];

      Map<String, dynamic>? matchedEp;

      if (target.type == BilibiliTargetType.ep) {
        matchedEp = allEps.firstWhere(
          (e) => e['id'] == target?.epId || e['ep_id'] == target?.epId,
          orElse: () => allEps.isNotEmpty ? allEps.first : const <String, dynamic>{},
        );
      } else {
        // 智能匹配集数标题 (支持 0话, 00, 1, 01 等)
        final targetNumStr = page.toString();
        final targetPaddedStr = page < 10 ? '0$page' : page.toString();

        matchedEp = allEps.firstWhere(
          (e) {
            final t = (e['title']?.toString() ?? '').trim();
            final st = (e['show_title']?.toString() ?? '').trim();
            return t == targetNumStr || t == targetPaddedStr || st == targetNumStr || st == targetPaddedStr;
          },
          orElse: () => const <String, dynamic>{},
        );

        // 未命中降级为索引 (page == 0 ? mainEps[0] : mainEps[page - 1])
        if (matchedEp.isEmpty && mainEps.isNotEmpty) {
          final idx = page == 0 ? 0 : (page - 1);
          if (idx >= 0 && idx < mainEps.length) {
            matchedEp = mainEps[idx];
          } else {
            matchedEp = mainEps.first;
          }
        }
      }

      if (matchedEp.isEmpty) {
        throw Exception('未找到对应剧集或 cid');
      }

      cid = matchedEp['cid'] as int? ?? 0;
      bvid = matchedEp['bvid']?.toString() ?? bvid;
      epId = (matchedEp['ep_id'] as int?) ?? (matchedEp['id'] as int?) ?? epId;

      final epShowTitle = matchedEp['show_title']?.toString();
      final epLongTitle = matchedEp['long_title']?.toString();
      final epTitle = matchedEp['title']?.toString();
      part = epShowTitle?.isNotEmpty == true
          ? epShowTitle!
          : epLongTitle?.isNotEmpty == true
              ? epLongTitle!
              : (epTitle?.isNotEmpty == true ? '第$epTitle话' : 'P$page');

      for (var i = 0; i < mainEps.length; i++) {
        final p = mainEps[i];
        final pShow = p['show_title']?.toString();
        final pLong = p['long_title']?.toString();
        final pTitle = p['title']?.toString();
        final pName = pShow?.isNotEmpty == true
            ? pShow!
            : pLong?.isNotEmpty == true
                ? pLong!
                : (pTitle?.isNotEmpty == true ? '第$pTitle话' : 'P${i + 1}');

        pages.add(BilibiliPageInfo(
          page: i + 1,
          cid: p['cid'] as int? ?? 0,
          part: pName,
          epId: (p['ep_id'] as int?) ?? (p['id'] as int?),
          bvid: p['bvid']?.toString(),
        ));
      }
    } else {
      // 5. UGC 视频 (bv 或 av)
      final targetBvid = target.type == BilibiliTargetType.bv ? target.bvid : null;
      final targetAid = target.type == BilibiliTargetType.av ? target.aid : null;

      if (targetBvid == null && targetAid == null) {
        return BilibiliDanmakuResult(
          comments: const [],
          cid: 0,
          page: page,
        );
      }

      var ugcPages = <BilibiliPageInfo>[];

      // 4.1 优先走轻量级 pagelist API (防 412 WAF)
      final pagelistUrl = targetBvid != null
          ? 'https://api.bilibili.com/x/player/pagelist?bvid=$targetBvid'
          : targetAid != null
              ? 'https://api.bilibili.com/x/player/pagelist?aid=$targetAid'
              : null;

      if (pagelistUrl != null) {
        try {
          final res = await _dio.get<Map<String, dynamic>>(
            pagelistUrl,
            options: Options(
              headers: _buildHeaders(),
              sendTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 15),
            ),
          );
          final data = res.data ?? <String, dynamic>{};
          final code = data['code'] as int? ?? -1;
          final rawList = data['data'] as List<dynamic>? ?? const [];
          if (code == 0 && rawList.isNotEmpty) {
            ugcPages = rawList
                .whereType<Map<String, dynamic>>()
                .map((p) => BilibiliPageInfo(
                      page: p['page'] as int? ?? 1,
                      cid: p['cid'] as int? ?? 0,
                      part: p['part']?.toString() ?? 'P1',
                    ))
                .toList();
          }
        } catch (_) {}
      }

      // 4.2 降级走 web-interface/view API
      if (ugcPages.isEmpty) {
        final viewUrl = targetBvid != null
            ? 'https://api.bilibili.com/x/web-interface/view?bvid=$targetBvid'
            : 'https://api.bilibili.com/x/web-interface/view?aid=$targetAid';

        final res = await _dio.get<Map<String, dynamic>>(
          viewUrl,
          options: Options(
            headers: _buildHeaders(),
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );
        final root = res.data ?? <String, dynamic>{};
        final code = root['code'] as int? ?? -1;
        final data = root['data'] as Map<String, dynamic>?;

        if (code != 0 || data == null) {
          final message = root['message']?.toString() ?? 'B站返回 code=$code';
          throw Exception(message);
        }

        title = data['title']?.toString() ?? '';
        bvid = data['bvid']?.toString() ?? targetBvid;
        final rawPages = data['pages'] as List<dynamic>? ?? const [];
        ugcPages = rawPages
            .whereType<Map<String, dynamic>>()
            .map((p) => BilibiliPageInfo(
                  page: p['page'] as int? ?? 1,
                  cid: p['cid'] as int? ?? 0,
                  part: p['part']?.toString() ?? 'P1',
                ))
            .toList();
      }

      if (ugcPages.isEmpty) {
        throw Exception('未找到分 P 列表');
      }

      pages.addAll(ugcPages);

      final matchedPage = ugcPages.firstWhere(
        (p) => p.page == page,
        orElse: () => ugcPages.first,
      );

      cid = matchedPage.cid;
      part = matchedPage.part;
      title = title.isNotEmpty ? title : part;
    }

    if (cid <= 0) {
      throw Exception('未解析到有效的视频 cid');
    }

    // 5. 拉取 XML 弹幕 (带 Gzip / Deflate 自动解码，后台 Worker Isolate 异步解析)
    final xmlContent = await _fetchXmlDanmaku(cid);
    final comments = await BilibiliXmlParser.parseAsync(xmlContent);

    return BilibiliDanmakuResult(
      comments: comments,
      cid: cid,
      page: page,
      title: title,
      part: part,
      bvid: bvid,
      epId: epId,
      seasonId: seasonId,
      pages: pages,
    );
  }

  /// 拉取并解码 XML 弹幕字节流
  Future<String> _fetchXmlDanmaku(int cid) async {
    final candidateUrls = [
      'https://comment.bilibili.com/$cid.xml',
      'https://api.bilibili.com/x/v1/dm/list.so?oid=$cid',
    ];

    String lastErr = '';
    for (final url in candidateUrls) {
      try {
        final res = await _dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: _buildHeaders(),
            sendTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 15),
          ),
        );

        final bytes = res.data;
        if (bytes == null || bytes.isEmpty) {
          lastErr = '$url 返回空字节';
          continue;
        }

        final xml = _decompressBytes(bytes);
        if (xml.contains('<d ') || xml.contains('<i') || xml.contains('</chatserver>')) {
          return xml;
        }
        lastErr = '$url XML 不包含弹幕标签';
      } catch (e) {
        lastErr = '$url 请求失败: $e';
      }
    }

    throw Exception('拉取 B 站弹幕失败: $lastErr');
  }

  /// 自动识别并解压 Raw Deflate / Gzip / Zlib / 纯文本 UTF-8
  String _decompressBytes(List<int> bytes) {
    if (bytes.isEmpty) return '';

    // 1. Gzip 魔数: 0x1f 0x8b
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      try {
        return utf8.decode(gzip.decode(bytes), allowMalformed: true);
      } catch (_) {}
    }

    // 2. 标准 Zlib (包含 0x78 头部)
    if (bytes[0] == 0x78) {
      try {
        return utf8.decode(zlib.decode(bytes), allowMalformed: true);
      } catch (_) {}
    }

    // 3. 核心：B 站原生 Raw Deflate (RFC 1951，无头压缩流，最常见)
    try {
      final rawInflated = ZLibDecoder(raw: true).convert(bytes);
      final xml = utf8.decode(rawInflated, allowMalformed: true);
      if (xml.contains('<d ') || xml.contains('<i') || xml.contains('</chatserver>')) {
        return xml;
      }
    } catch (_) {}

    // 4. 标准 Zlib 容错尝试
    try {
      final zlibInflated = ZLibDecoder(raw: false).convert(bytes);
      final xml = utf8.decode(zlibInflated, allowMalformed: true);
      if (xml.contains('<d ') || xml.contains('<i') || xml.contains('</chatserver>')) {
        return xml;
      }
    } catch (_) {}

    // 5. Gzip 容错尝试
    try {
      final gzipInflated = gzip.decode(bytes);
      final xml = utf8.decode(gzipInflated, allowMalformed: true);
      if (xml.contains('<d ') || xml.contains('<i') || xml.contains('</chatserver>')) {
        return xml;
      }
    } catch (_) {}

    // 6. 纯文本 utf8 尝试
    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {}

    return '';
  }

  /// 解析 b23 短链真实地址
  Future<BilibiliTarget?> _resolveB23ShortLink(String shortUrl) async {
    try {
      final res = await _dio.get<dynamic>(
        shortUrl,
        options: Options(
          headers: _buildHeaders(),
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      final location = res.headers.value('location');
      if (location != null && location.isNotEmpty && location != shortUrl) {
        return BilibiliInputParser.parse(location);
      }
    } catch (e) {
      developer.log('[BilibiliDanmakuClient] resolve b23 failed: $e');
    }
    return null;
  }

  /// media_id (md...) 解析为 season_id
  Future<int?> _resolveMediaIdToSeasonId(int mediaId) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'https://api.bilibili.com/pgc/review/user?media_id=$mediaId',
        options: Options(
          headers: _buildHeaders(),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final root = res.data ?? <String, dynamic>{};
      final result = root['result'] as Map<String, dynamic>?;
      final media = result?['media'] as Map<String, dynamic>?;
      return media?['season_id'] as int?;
    } catch (_) {
      return null;
    }
  }
}
