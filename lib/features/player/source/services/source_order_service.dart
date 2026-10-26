import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/source_models.dart';

/// 视频源排序与偏好中枢调度服务 (Source Order & Preference Service)
///
/// 架构设计与职责分离：
/// 1. 解耦底层视频源的物理实现与界面展示/自动选源优先级；
/// 2. 管理出厂默认位序、用户持久化自定义位序及单源禁用黑名单；
/// 3. 提供越界安全防护：获取前 N 个源时严格保证不会发生 RangeError；
/// 4. 预留标准 API，供后续设置页拖拽排序、启用/禁用、一键重置无缝对接。
class SourceOrderService extends ChangeNotifier {
  SourceOrderService._();

  static final SourceOrderService instance = SourceOrderService._();

  static const String _kCustomSourceOrderKey = 'pref_custom_source_order';
  static const String _kDisabledSourcesKey = 'pref_disabled_sources';

  /// 出厂推荐默认位序底表
  static const List<String> defaultPresetOrder = [
    'xifan-next',
    'cycani',
    'mifun',
    'sorani',
    'girigiri',
    'moonci',
    'lzizy',
    'animoe',
    'gugu',
    'mxdm',
    'neosekai',
    'tvtfun',
    'anime1',
    'omofun',
    'libvio',
  ];

  List<String> _customOrder = [];
  Set<String> _disabledSourceIds = {};
  bool _initialized = false;

  bool get isInitialized => _initialized;
  List<String> get customOrder => List.unmodifiable(_customOrder);
  Set<String> get disabledSourceIds => Set.unmodifiable(_disabledSourceIds);

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
  /// 2. 优先匹配用户自定义排序顺序；
  /// 3. 若无自定义配置，采用出厂默认位序；
  /// 4. 未在配置列表中的新源/动态服务端源，自动平滑追加至队尾，绝不丢弃。
  List<SourceMeta> getOrderedSources(List<SourceMeta> rawSources) {
    if (rawSources.isEmpty) return const [];

    // 1. 过滤被禁用的源
    final available = rawSources.where((s) => !_disabledSourceIds.contains(s.id)).toList();
    if (available.isEmpty) return const [];

    // 2. 决定参考基准位序
    final referenceOrder = _customOrder.isNotEmpty ? _customOrder : defaultPresetOrder;

    // 3. 构建权重索引字典
    final rankMap = <String, int>{};
    for (int i = 0; i < referenceOrder.length; i++) {
      rankMap[referenceOrder[i].toLowerCase()] = i;
    }

    // 4. 排序：已知顺序按权重升序；未知新增源按名称字母序追加于队尾
    final sorted = List<SourceMeta>.from(available);
    sorted.sort((a, b) {
      final rankA = rankMap[a.id.toLowerCase()];
      final rankB = rankMap[b.id.toLowerCase()];

      if (rankA != null && rankB != null) {
        return rankA.compareTo(rankB);
      }
      if (rankA != null) return -1;
      if (rankB != null) return 1;
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

    // 严密二次防线：确保返回数量在 [0, math.min(maxCount, ordered.length)] 之间
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
