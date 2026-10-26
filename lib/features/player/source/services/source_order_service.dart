import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/source_models.dart';

/// 视频源排序与偏好中枢调度服务 (Source Order & Preference Service)
///
/// 架构设计与排序规范：
/// 1. 默认基于权重体系排序：
///    - 权重 60: xifan-next (稀饭Next), neosekai (neosek)
///    - 权重 59: cycani (次元城), girigiri (girigiri), sorani (青空次元), gugu (咕咕番)
///    - 权重 58: mifun (MiFun), tvtfun (TvTFun)
///    - 权重 50: 其他所有源 (默认基础权重)
/// 2. 同权仲裁：权重相同时直接按照源名称 (name) 字母序升序排序，杜绝过度设计；
/// 3. 用户自定义覆盖：预留自定义位序与禁用黑名单接口，用户自定义时绝对优先；
/// 4. 越界安全防护：获取前 N 个源时严格保证不会发生 RangeError。
class SourceOrderService extends ChangeNotifier {
  SourceOrderService._();

  static final SourceOrderService instance = SourceOrderService._();

  static const String _kCustomSourceOrderKey = 'pref_custom_source_order';
  static const String _kDisabledSourcesKey = 'pref_disabled_sources';

  /// 出厂默认预设权重底表
  static const Map<String, int> defaultPresetWeights = {
    'xifan-next': 60,
    'xifan': 60,
    'neosekai': 60,
    'neosek': 60,
    'cycani': 59,
    'girigiri': 59,
    'sorani': 59,
    'gugu': 59,
    'mifun': 58,
    'tvtfun': 58,
  };

  static const int defaultBaseWeight = 50;

  List<String> _customOrder = [];
  Set<String> _disabledSourceIds = {};
  bool _initialized = false;

  bool get isInitialized => _initialized;
  List<String> get customOrder => List.unmodifiable(_customOrder);
  Set<String> get disabledSourceIds => Set.unmodifiable(_disabledSourceIds);

  /// 解析获取指定视频源的计算权重
  int getSourceWeight(SourceMeta s) {
    if (s.weight != defaultBaseWeight) {
      return s.weight;
    }
    return defaultPresetWeights[s.id.toLowerCase()] ?? defaultBaseWeight;
  }

  /// 异步初始化本地偏好配置
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final sp = await SharedPreferences.getInstance();
      _customOrder = sp.getStringList(_kCustomSourceOrderKey) ?? [];
      _disabledSourceIds = (sp.getStringList(_kDisabledSourcesKey) ?? const <String>[]).toSet();
      _initialized = true;
    } catch (e) {
      debugPrint('[SourceOrderService] 初始化持久化配置失败: $e');
      _initialized = true;
    }
  }

  /// 核心决议管道：对传入的原始源列表进行排序与过滤
  ///
  /// 排序规则：
  /// 1. 过滤掉被禁用的源；
  /// 2. 若用户自定义了排序顺序：优先匹配自定义顺序，未在自定义中的源按权重降序+字母序追加在队尾；
  /// 3. 若用户未自定义（默认模式）：
  ///    - 优先按权重从大到小（降序）；
  ///    - 同权重直接按照字母升序（A-Z）排序，无额外冗余判断。
  List<SourceMeta> getOrderedSources(List<SourceMeta> rawSources) {
    if (rawSources.isEmpty) return const [];

    // 1. 过滤被禁用的源
    final available = rawSources.where((s) => !_disabledSourceIds.contains(s.id)).toList();
    if (available.isEmpty) return const [];

    final sorted = List<SourceMeta>.from(available);

    // 2. 用户自定义了排序位序
    if (_customOrder.isNotEmpty) {
      final rankMap = <String, int>{};
      for (int i = 0; i < _customOrder.length; i++) {
        rankMap[_customOrder[i].toLowerCase()] = i;
      }

      sorted.sort((a, b) {
        final rankA = rankMap[a.id.toLowerCase()];
        final rankB = rankMap[b.id.toLowerCase()];

        if (rankA != null && rankB != null) {
          return rankA.compareTo(rankB);
        }
        if (rankA != null) return -1;
        if (rankB != null) return 1;

        // 未在自定义列表中的源，按权重降序，同权按字母升序
        final weightA = getSourceWeight(a);
        final weightB = getSourceWeight(b);
        if (weightA != weightB) {
          return weightB.compareTo(weightA);
        }
        return a.name.compareTo(b.name);
      });

      return sorted;
    }

    // 3. 默认模式：按权重降序，同权重按字母升序
    sorted.sort((a, b) {
      final weightA = getSourceWeight(a);
      final weightB = getSourceWeight(b);

      if (weightA != weightB) {
        return weightB.compareTo(weightA);
      }
      return a.name.compareTo(b.name);
    });

    return sorted;
  }

  /// 安全提取用于并发探测的前 N 个源 (核心方法，自带严密防越界保护)
  ///
  /// 边界保护机制：
  /// - 即使 [maxCount] 传入大于源总数的值（例如总共只有 2 个源），
  ///   内部使用 clamp 与 take 截取，返回安全的实际子列表，绝不发生 RangeError；
  /// - 若提供 [preferredSourceId]（如历史追番指定源），优先将该源置于第 1 位。
  List<SourceMeta> getTopSources(
    List<SourceMeta> rawSources, {
    int maxCount = 5,
    String? preferredSourceId,
  }) {
    if (rawSources.isEmpty || maxCount <= 0) return const [];

    final ordered = getOrderedSources(rawSources);
    if (ordered.isEmpty) return const [];

    final result = <SourceMeta>[];

    // 若有优先指定源，先将其提升到首位
    if (preferredSourceId != null && preferredSourceId.trim().isNotEmpty) {
      final preferred = ordered.where((s) => s.id.toLowerCase() == preferredSourceId.toLowerCase()).firstOrNull;
      if (preferred != null) {
        result.add(preferred);
      }
    }

    // 依序填入其余源，防止重复
    for (final s in ordered) {
      if (result.length >= maxCount) break;
      if (!result.any((item) => item.id.toLowerCase() == s.id.toLowerCase())) {
        result.add(s);
      }
    }

    final safeLimit = math.min(maxCount, result.length);
    return result.take(safeLimit).toList();
  }

  /// 【为后续拖拽排序预留接口】持久化保存用户自定义源顺序
  Future<void> updateCustomOrder(List<String> orderedSourceIds) async {
    _customOrder = List<String>.from(orderedSourceIds);
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_kCustomSourceOrderKey, _customOrder);
    } catch (e) {
      debugPrint('[SourceOrderService] 保存自定义源排序失败: $e');
    }
  }

  /// 【为后续单源开关预留接口】切换源的启用/禁用状态
  Future<void> setSourceEnabled(String sourceId, bool enabled) async {
    final sId = sourceId.trim();
    if (sId.isEmpty) return;

    if (enabled) {
      _disabledSourceIds.remove(sId);
    } else {
      _disabledSourceIds.add(sId);
    }
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_kDisabledSourcesKey, _disabledSourceIds.toList());
    } catch (e) {
      debugPrint('[SourceOrderService] 保存源启用禁用状态失败: $e');
    }
  }

  /// 【为后续一键恢复预留接口】清空自定义配置，恢复出厂默认位序
  Future<void> resetToDefaultOrder() async {
    _customOrder.clear();
    _disabledSourceIds.clear();
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove(_kCustomSourceOrderKey);
      await sp.remove(_kDisabledSourcesKey);
    } catch (e) {
      debugPrint('[SourceOrderService] 重置源排序配置失败: $e');
    }
  }
}
