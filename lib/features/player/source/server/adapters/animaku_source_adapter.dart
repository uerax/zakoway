import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/server/adapters/xifan_next_animaku_adapter.dart';
import 'package:zakoway/features/player/source/server/animaku_server_client.dart';

/// Animaku 服务端源专属适配器基类
///
/// 特殊处理说明：
/// 所有源默认使用 [DefaultAnimakuSourceAdapter]，保持原始数据纯透传且不作任何侵入性处理。
/// 只有当特定源在服务端模式下需要特殊数据清洗（如补齐防盗链 Referer/UA headers、纠正媒体格式、规整分集名）
/// 或进行源维度的局部 Fallback 兜底时，才继承此类实现专属适配逻辑并注册到 [AnimakuAdapterRegistry]，
/// 彻底避免在核心客户端中硬编码堆叠 if-else。
abstract class AnimakuSourceAdapter {
  const AnimakuSourceAdapter();

  /// 适配器绑定的源唯一标识（如 'cycani', 'xifan-next'）
  String get sourceId;

  /// 搜索结果后处理/清洗钩子（默认直接透传）
  List<SourceSearchResult> transformSearch(
    List<SourceSearchResult> results, {
    required String keyword,
  }) => results;

  /// 选集线路后处理/清洗钩子（默认直接透传）
  List<SourceChapterRoad> transformChapters(
    List<SourceChapterRoad> roads, {
    required String animeUrl,
  }) => roads;

  /// 播放直链解析后处理/清洗钩子（默认直接透传，常用于补齐 Referer/UA headers 或纠正媒体格式，支持异步预检）
  Future<SourceResolveResult> transformResolve(
    SourceResolveResult result, {
    required String episodeUrl,
  }) async => result;

  /// 搜索异常时的源级专属 Fallback 兜底钩子（返回非 null 代表兜底成功，null 代表无法兜底将向上抛出异常）
  Future<List<SourceSearchResult>?> onSearchFallback(
    Object error, {
    required String keyword,
  }) async => null;

  /// 选集获取异常或返回空有效集时的源级专属 Fallback 兜底钩子
  Future<List<SourceChapterRoad>?> onChaptersFallback(
    Object error, {
    required String animeUrl,
  }) async => null;

  /// 播放直链解析异常时的源级专属 Fallback 兜底钩子
  Future<SourceResolveResult?> onResolveFallback(
    Object error, {
    required String episodeUrl,
  }) async => null;
}

/// 默认的通用服务端源适配器（所有源默认使用，保持 100% 原始数据透传，不作任何额外处理）
class DefaultAnimakuSourceAdapter extends AnimakuSourceAdapter {
  const DefaultAnimakuSourceAdapter([this._sourceId = '*']);

  final String _sourceId;

  @override
  String get sourceId => _sourceId;
}

/// Animaku 服务端源适配器注册表与调度中心
class AnimakuAdapterRegistry {
  AnimakuAdapterRegistry._();

  static final Map<String, AnimakuSourceAdapter> _adapters = {};
  static const DefaultAnimakuSourceAdapter _defaultAdapter = DefaultAnimakuSourceAdapter();
  static bool _defaultsInitialized = false;

  static void _ensureDefaults() {
    if (_defaultsInitialized) return;
    _defaultsInitialized = true;
    register(XifanNextAnimakuAdapter());
  }

  /// 注册源专属的服务端适配器
  static void register(AnimakuSourceAdapter adapter) {
    final norm = AnimakuServerClient.instance.normalizeSourceId(adapter.sourceId);
    _adapters[norm] = adapter;
  }

  /// 获取指定源的服务端适配器；未显式注册的源自动使用 [DefaultAnimakuSourceAdapter]
  static AnimakuSourceAdapter get(String sourceId) {
    _ensureDefaults();
    final norm = AnimakuServerClient.instance.normalizeSourceId(sourceId);
    return _adapters[norm] ?? _defaultAdapter;
  }

  /// 检查特定源是否有注册专属适配器
  static bool hasCustomAdapter(String sourceId) {
    _ensureDefaults();
    final norm = AnimakuServerClient.instance.normalizeSourceId(sourceId);
    return _adapters.containsKey(norm);
  }

  @visibleForTesting
  static void resetForTesting({bool reinitializeDefaults = false}) {
    _adapters.clear();
    _defaultsInitialized = false;
    if (reinitializeDefaults) {
      _ensureDefaults();
    }
  }
}
