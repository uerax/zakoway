import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/danmaku_item.dart';
import '../models/danmaku_pool_models.dart';
import '../utils/danmaku_text_normalizer.dart';

/// 增量去重计算结果
class DeduplicateIncrementalResult {
  const DeduplicateIncrementalResult({
    required this.incremental,
    required this.duplicatesCount,
  });

  /// 过滤后的增量弹幕列表
  final List<DanmakuItem> incremental;

  /// 被剔除的重复弹幕总数
  final int duplicatesCount;
}

/// 多源弹幕池管理器与交叉去重引擎 (1:1 对齐 animaku danmaku-pools.ts)
class DanmakuPoolsManager extends ChangeNotifier {
  DanmakuPoolsManager() {
    _pools = {
      DanmakuPoolId.dandan: const DanmakuPoolSlice(enabled: true),
      DanmakuPoolId.bilibiliAuto: const DanmakuPoolSlice(enabled: true),
      DanmakuPoolId.bilibiliManual: const DanmakuPoolSlice(enabled: true),
      DanmakuPoolId.upload: const DanmakuPoolSlice(enabled: true),
    };
  }

  late Map<DanmakuPoolId, DanmakuPoolSlice> _pools;
  int _globalTimeOffsetMs = 0;
  int _poolVersion = 0;

  /// 数据池结构版本（写入、切换、清空时递增；单纯时移不递增）
  int get poolVersion => _poolVersion;

  Map<DanmakuPoolId, DanmakuPoolSlice> get pools => Map.unmodifiable(_pools);

  /// 全局时间偏移（作用于所有源，修复视频自带片头时差）
  int get globalTimeOffsetMs => _globalTimeOffsetMs;

  set globalTimeOffsetMs(int value) {
    if (_globalTimeOffsetMs == value) return;
    _globalTimeOffsetMs = value;
    notifyListeners();
  }

  /// 获取指定池的切片状态
  DanmakuPoolSlice getPool(DanmakuPoolId id) {
    return _pools[id] ?? const DanmakuPoolSlice();
  }

  /// 写入指定弹幕池
  /// - replace: true (覆盖重置，常用于选集重新匹配)
  /// - replace: false (增量追加，常用于手动追加 BV 号或 XML 导入)
  void writePool(
    DanmakuPoolId id,
    List<DanmakuItem> items, {
    bool replace = true,
    String? meta,
    bool? enabled,
    int? timeOffsetMs,
  }) {
    final prev = getPool(id);
    final tagged = items.map((c) => c.copyWith(source: c.source ?? id.code)).toList();

    final nextItems = replace
        ? tagged
        : _mergeComments(prev.items, tagged);

    _poolVersion++;
    _pools = Map.of(_pools)
      ..[id] = DanmakuPoolSlice(
        items: nextItems,
        enabled: enabled ?? prev.enabled,
        meta: meta ?? prev.meta,
        timeOffsetMs: timeOffsetMs ?? prev.timeOffsetMs,
      );

    notifyListeners();
  }

  /// 切换指定池的启用/禁用状态
  void togglePool(DanmakuPoolId id) {
    final prev = getPool(id);
    _poolVersion++;
    _pools = Map.of(_pools)
      ..[id] = prev.copyWith(enabled: !prev.enabled);
    notifyListeners();
  }

  /// 更新指定池的独立时移
  void setPoolOffset(DanmakuPoolId id, int offsetMs) {
    final prev = getPool(id);
    if (prev.timeOffsetMs == offsetMs) return;
    _pools = Map.of(_pools)
      ..[id] = prev.copyWith(timeOffsetMs: offsetMs);
    notifyListeners();
  }

  /// 清空指定池
  void clearPool(DanmakuPoolId id) {
    _poolVersion++;
    _pools = Map.of(_pools)
      ..[id] = const DanmakuPoolSlice();
    notifyListeners();
  }

  /// 清空所有池与时移
  void clearAll() {
    _poolVersion++;
    _globalTimeOffsetMs = 0;
    _pools = {
      DanmakuPoolId.dandan: const DanmakuPoolSlice(enabled: true),
      DanmakuPoolId.bilibiliAuto: const DanmakuPoolSlice(enabled: true),
      DanmakuPoolId.bilibiliManual: const DanmakuPoolSlice(enabled: true),
      DanmakuPoolId.upload: const DanmakuPoolSlice(enabled: true),
    };
    notifyListeners();
  }

  /// 获取用于 UI 展示的源池状态列表
  List<DanmakuSourceChip> getSourceChips() {
    return DanmakuPoolId.values.map((id) {
      final slice = getPool(id);
      return DanmakuSourceChip(
        id: id,
        label: id.label,
        count: slice.items.length,
        enabled: slice.enabled,
        loaded: slice.items.isNotEmpty,
        meta: slice.meta,
        timeOffsetMs: slice.timeOffsetMs,
      );
    }).toList();
  }

  /// 总加载弹幕数（包含关闭的源）
  int get totalLoadedCount {
    var sum = 0;
    for (final s in _pools.values) {
      sum += s.items.length;
    }
    return sum;
  }

  /// 参与渲染的已启用弹幕总数（去重前粗略统计）
  int get totalEnabledCount {
    var sum = 0;
    for (final s in _pools.values) {
      if (s.enabled) sum += s.items.length;
    }
    return sum;
  }

  /// 聚合所有启用的源池，应用各自独立时移与全局时移，并执行渐进式 O(1) 交叉增量去重
  List<DanmakuItem> flattenEnabledPools() {
    return _flattenEnabledPoolsWorker(_createFlattenPayload());
  }

  /// 异步在 compute 隔离中执行时移 + 去重 + 排序
  Future<List<DanmakuItem>> flattenEnabledPoolsAsync() {
    return compute(_flattenEnabledPoolsWorker, _createFlattenPayload());
  }

  DanmakuFlattenPayload _createFlattenPayload() {
    return DanmakuFlattenPayload(
      slices: DanmakuPoolId.values.map(getPool).toList(),
      globalTimeOffsetMs: _globalTimeOffsetMs,
    );
  }

  /// 核心去重算法：在 extraComments 中筛除已存在于 baseComments 中的重复弹幕 (1:1 对齐 animaku)
  /// 1. 强特征指纹匹配: senderHash + '_' + normalizedText
  /// 2. 时间窗口模糊匹配: 相同 normalizedText 在 ±windowSeconds (默认 2.5s) 窗口内命中
  static DeduplicateIncrementalResult deduplicateDanmakuIncremental(
    List<DanmakuItem> baseComments,
    List<DanmakuItem> extraComments, {
    double windowSeconds = 2.5,
  }) {
    final windowMs = (windowSeconds * 1000).round();
    final baseStrongFingerprints = <String>{};
    final baseTimeBuckets = <String, List<int>>{};

    for (final c in baseComments) {
      final text = DanmakuTextNormalizer.normalize(c.text);
      if (text.isEmpty) continue;

      if (c.senderHash != null && c.senderHash!.isNotEmpty) {
        baseStrongFingerprints.add('${c.senderHash}_$text');
      }

      baseTimeBuckets.putIfAbsent(text, () => <int>[]).add(c.timeMs);
    }

    // 优化：对每个文本的时间列表进行升序排序，便于二分查找，去掉线性 any(...)
    for (final times in baseTimeBuckets.values) {
      times.sort();
    }

    final incremental = <DanmakuItem>[];
    var duplicatesCount = 0;

    for (final c in extraComments) {
      final text = DanmakuTextNormalizer.normalize(c.text);
      if (text.isEmpty) continue;

      // 规则 1: 强指纹匹配 (相同发送者 Hash + 相同内容)
      if (c.senderHash != null &&
          c.senderHash!.isNotEmpty &&
          baseStrongFingerprints.contains('${c.senderHash}_$text')) {
        duplicatesCount++;
        continue;
      }

      // 规则 2: 时间窗口内容匹配 (同一文本在 ±windowMs 范围内出现)
      // 使用二分查找判断 [c.timeMs - windowMs, c.timeMs + windowMs] 窗口内是否存在时间点
      final existingTimes = baseTimeBuckets[text];
      if (existingTimes != null && existingTimes.isNotEmpty) {
        final targetMin = c.timeMs - windowMs;
        final targetMax = c.timeMs + windowMs;

        var min = 0;
        var max = existingTimes.length;
        while (min < max) {
          final mid = min + ((max - min) >> 1);
          if (existingTimes[mid] < targetMin) {
            min = mid + 1;
          } else {
            max = mid;
          }
        }

        if (min < existingTimes.length && existingTimes[min] <= targetMax) {
          duplicatesCount++;
          continue;
        }
      }

      incremental.add(c);
    }

    return DeduplicateIncrementalResult(
      incremental: incremental,
      duplicatesCount: duplicatesCount,
    );
  }

  /// 内部简单去重合并
  static List<DanmakuItem> _mergeComments(
    List<DanmakuItem> existing,
    List<DanmakuItem> incoming,
  ) {
    if (incoming.isEmpty) return existing;
    if (existing.isEmpty) {
      final list = List.of(incoming);
      list.sort((a, b) => a.timeMs.compareTo(b.timeMs));
      return list;
    }

    String key(DanmakuItem c) =>
        '${c.timeMs}\$${c.mode.name}\$${c.text}\$${c.color.toARGB32()}';

    final seen = existing.map(key).toSet();
    final extra = <DanmakuItem>[];

    for (final c in incoming) {
      final k = key(c);
      if (seen.add(k)) {
        extra.add(c);
      }
    }

    if (extra.isEmpty) return existing;
    final merged = [...existing, ...extra];
    merged.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return merged;
  }
}

/// 聚合计算入参载荷（支持跨 isolate 传递）
class DanmakuFlattenPayload {
  const DanmakuFlattenPayload({
    required this.slices,
    required this.globalTimeOffsetMs,
  });

  final List<DanmakuPoolSlice> slices;
  final int globalTimeOffsetMs;
}

/// 独立 Top-level 隔离区 worker 函数，负责执行时移变换、交叉增量去重与全局时间排序
List<DanmakuItem> _flattenEnabledPoolsWorker(DanmakuFlattenPayload payload) {
  final enabledSlices = <List<DanmakuItem>>[];

  for (final slice in payload.slices) {
    if (!slice.enabled || slice.items.isEmpty) continue;

    final totalOffset = slice.timeOffsetMs + payload.globalTimeOffsetMs;
    if (totalOffset == 0) {
      enabledSlices.add(slice.items);
    } else {
      enabledSlices.add(
        slice.items.map((c) {
          final newTime = math.max(0, c.timeMs + totalOffset);
          return c.copyWith(timeMs: newTime);
        }).toList(),
      );
    }
  }

  if (enabledSlices.isEmpty) return const [];
  if (enabledSlices.length == 1) {
    final single = List.of(enabledSlices.first);
    single.sort((a, b) => a.timeMs.compareTo(b.timeMs));
    return single;
  }

  // 渐进式多源增量交叉去重 (Progressive cross-source deduplication)
  final result = List.of(enabledSlices.first);
  for (var i = 1; i < enabledSlices.length; i++) {
    final dedup = DanmakuPoolsManager.deduplicateDanmakuIncremental(
      result,
      enabledSlices[i],
      windowSeconds: 2.5,
    );
    result.addAll(dedup.incremental);
  }

  result.sort((a, b) => a.timeMs.compareTo(b.timeMs));
  return result;
}
