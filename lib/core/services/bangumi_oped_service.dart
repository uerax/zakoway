import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../utils/timed_cache.dart';

/// 单集片头片尾时间戳区间
@immutable
class EpisodeOpedSegment {
  const EpisodeOpedSegment({
    required this.episode,
    this.opStart,
    this.opEnd,
    this.edStart,
    this.edEnd,
  });

  final int episode;
  final int? opStart; // 秒数
  final int? opEnd; // 秒数
  final int? edStart; // 秒数
  final int? edEnd; // 秒数

  bool get hasOp => opStart != null && opEnd != null && opEnd! > opStart!;
  bool get hasEd => edStart != null && edEnd != null && edEnd! > edStart!;

  Duration? get opStartDuration => hasOp ? Duration(seconds: opStart!) : null;
  Duration? get opEndDuration => hasOp ? Duration(seconds: opEnd!) : null;
  Duration? get edStartDuration => hasEd ? Duration(seconds: edStart!) : null;
  Duration? get edEndDuration => hasEd ? Duration(seconds: edEnd!) : null;
}

/// Bangumi OP/ED 片头片尾时间戳服务
/// 数据源同步自 uerax/bangumi-oped (通过 jsDelivr CDN 高速分发)
/// 数据格式：`ep;opStart;opEnd;edStart;edEnd` (-1 表示缺失哨兵值)
class BangumiOpedService {
  BangumiOpedService._();
  static final BangumiOpedService instance = BangumiOpedService._();

  static const String _kBaseUrl =
      'https://cdn.jsdelivr.net/gh/uerax/bangumi-oped@data';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 6),
      responseType: ResponseType.plain,
      // 使用 Cache-Control: no-cache 强制向 CDN 发起条件请求 (304 协商)，
      // 规避 Web/代理等环境下 jsDelivr 默认响应头 max-age=604800 导致的 7 天强缓存更新滞后
      headers: const {
        'Cache-Control': 'no-cache',
      },
    ),
  );

  // 正向打点数据缓存池：24 小时 TTL，上限 200 部番剧 (LRU 淘汰)
  // 确保当日播放毫秒级秒开，同时兼顾新番每周增量补充新集打点的自动拉取
  final TimedKeyedCache<int, Map<int, EpisodeOpedSegment>> _cache =
      TimedKeyedCache(maxAge: const Duration(hours: 24), maxEntries: 200);

  // 负缓存池 (404/暂未收录)：2 小时短 TTL，上限 100 部
  // 特殊处理说明：新番刚开播时仓库尚未录入打点，若永久缓存空结果会导致后续补录后客户端永远无法自愈；
  // 设置 2 小时短 TTL 既杜绝播放切集时的反复 CDN 404 击穿，又能在 2 小时后自动重新探查最新打点。
  final TimedKeyedCache<int, bool> _negativeCache =
      TimedKeyedCache(maxAge: const Duration(hours: 2), maxEntries: 100);

  // Single-Flight 并发请求锁
  final Map<int, Future<Map<int, EpisodeOpedSegment>>> _inflight = {};

  /// 获取指定 Bangumi 番剧 ID 的全集 OP/ED 时间标记映射 (Key 为集数编号 1, 2, 3...)
  Future<Map<int, EpisodeOpedSegment>> getOpedData(int subjectId) async {
    if (subjectId <= 0) return const {};

    // 1. 优先查正向有效缓存 (LRU 命中并刷新访问顺序)
    final hit = _cache.get(subjectId);
    if (hit != null) return hit;

    // 2. 查负缓存 (未收录状态在 2 小时内直接拦截，防止频繁 404)
    if (_negativeCache.get(subjectId) == true) {
      return const {};
    }

    // 3. 并发单飞去重
    if (_inflight.containsKey(subjectId)) {
      return await _inflight[subjectId]!;
    }

    final future = () async {
      final url = '$_kBaseUrl/$subjectId/$subjectId.txt';
      try {
        final response = await _dio.get<String>(url);
        if (response.statusCode == 200 && response.data != null && response.data!.trim().isNotEmpty) {
          final parsed = parseOpedData(response.data!);
          if (parsed.isNotEmpty) {
            _cache.set(subjectId, parsed, parsed.length * 64 + 64);
            return parsed;
          }
        }
      } catch (_) {
        // 404 或网络异常
      }

      // 写入负缓存，2 小时内避免重复请求
      _negativeCache.set(subjectId, true, 16);
      return const <int, EpisodeOpedSegment>{};
    }();

    _inflight[subjectId] = future;
    try {
      return await future;
    } finally {
      _inflight.remove(subjectId);
    }
  }

  /// 解析远端文本
  Map<int, EpisodeOpedSegment> parseOpedData(String rawText) {
    final result = <int, EpisodeOpedSegment>{};
    final lines = const LineSplitter().convert(rawText);

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final parts = trimmed.split(';');
      if (parts.length != 5) continue;

      final nums = parts.map((p) => int.tryParse(p) ?? -1).toList();
      final ep = nums[0];
      final opStart = nums[1];
      final opEnd = nums[2];
      final edStart = nums[3];
      final edEnd = nums[4];

      if (ep <= 0) continue;

      // 重复集数按第一条优先
      if (!result.containsKey(ep)) {
        result[ep] = EpisodeOpedSegment(
          episode: ep,
          opStart: opStart >= 0 && opEnd > opStart ? opStart : null,
          opEnd: opStart >= 0 && opEnd > opStart ? opEnd : null,
          edStart: edStart >= 0 && edEnd > edStart ? edStart : null,
          edEnd: edStart >= 0 && edEnd > edStart ? edEnd : null,
        );
      }
    }

    return result;
  }
}
