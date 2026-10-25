import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/server/animaku_server_client.dart';
import 'package:zakoway/features/player/source/sources/remote_server_source.dart';
import 'package:zakoway/features/player/source/sources/video_source.dart';

/// Animaku 服务端代理与动态源执行引擎
/// 100% 独立管理服务端动态扩展源，负责服务端状态监听、源生命周期同步以及服务端接口交互
class AnimakuServerEngine {
  AnimakuServerEngine({
    AnimakuServerClient? serverClient,
    VoidCallback? onSourcesChanged,
    bool Function(String sourceId)? isLocalSourceChecker,
  })  : _serverClient = serverClient ?? AnimakuServerClient.instance,
        _onSourcesChanged = onSourcesChanged,
        _isLocalSourceChecker = isLocalSourceChecker {
    _serverClient.supportedSourcesNotifier.addListener(_syncRemoteSources);
    _syncRemoteSources();
    if (AppPreferences.isServerModeEnabled()) {
      _serverClient.fetchSupportedSources().ignore();
    }
  }

  final AnimakuServerClient _serverClient;
  final VoidCallback? _onSourcesChanged;
  final bool Function(String sourceId)? _isLocalSourceChecker;
  final Map<String, VideoSource> _remoteSources = {};

  AnimakuServerClient get client => _serverClient;

  /// 检查特定源当前是否处于服务端模式且由服务端支持接管
  bool isSourceSupported(String sourceId) {
    if (!AppPreferences.isServerModeEnabled()) return false;
    return _serverClient.isSourceSupported(sourceId);
  }

  /// 同步服务端动态扩展源：开则扩充挂载，关则纯净卸载
  void _syncRemoteSources() {
    if (!AppPreferences.isServerModeEnabled()) {
      if (_remoteSources.isNotEmpty) {
        _remoteSources.clear();
        _onSourcesChanged?.call();
      }
      return;
    }

    final supportedSet = _serverClient.supportedSourcesNotifier.value;
    final serverNames = _serverClient.serverSourceNames;
    bool changed = false;

    // 清理已不再支持的动态源
    _remoteSources.removeWhere((id, _) {
      final keep = supportedSet.contains(id);
      if (!keep) changed = true;
      return !keep;
    });

    // 为本地尚未收录的服务端专属源，动态挂载 RemoteServerSource
    for (final id in supportedSet) {
      final isLocal = _isLocalSourceChecker?.call(id) ?? false;
      if (!isLocal && !_remoteSources.containsKey(id)) {
        final name = serverNames[id] ?? id;
        _remoteSources[id] = RemoteServerSource(id: id, name: name);
        changed = true;
      }
    }

    if (changed) {
      _onSourcesChanged?.call();
    }
  }

  /// 模式切换时的生命周期处理
  void onServerModeChanged() {
    _syncRemoteSources();
    if (AppPreferences.isServerModeEnabled()) {
      _serverClient.fetchSupportedSources(forceRefresh: true).ignore();
    }
  }

  /// 当前所有可用的服务端动态扩展源元数据列表
  List<SourceMeta> get dynamicSources {
    if (!AppPreferences.isServerModeEnabled()) return const [];
    return _remoteSources.values.map((s) => s.toMeta()).toList();
  }

  /// 动态扩展源适配器清单
  Map<String, String> get adapters {
    if (!AppPreferences.isServerModeEnabled()) return const {};
    return {for (final s in _remoteSources.values) s.id: s.version};
  }

  /// 获取指定的服务端动态源实例
  VideoSource? getRemoteSource(String sourceId) {
    if (!AppPreferences.isServerModeEnabled()) return null;
    final norm = _serverClient.normalizeSourceId(sourceId);
    return _remoteSources[norm];
  }

  /// 服务端代理执行搜索
  Future<List<SourceSearchResult>> search(String sourceId, String keyword) {
    return _serverClient.search(sourceId, keyword);
  }

  /// 服务端代理获取选集线路
  Future<List<SourceChapterRoad>> chapters(String sourceId, String animeUrl) {
    return _serverClient.chapters(sourceId, animeUrl);
  }

  /// 服务端代理解析直链
  Future<SourceResolveResult> resolve(String sourceId, String episodeUrl) {
    return _serverClient.resolve(sourceId, episodeUrl);
  }

  /// 清空服务端模式相关缓存
  void clearCache() {
    _serverClient.clearCache();
    for (final s in _remoteSources.values) {
      s.clearCache();
    }
  }

  void dispose() {
    _serverClient.supportedSourcesNotifier.removeListener(_syncRemoteSources);
  }
}
