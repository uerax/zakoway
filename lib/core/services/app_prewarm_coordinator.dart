import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../features/category/controllers/category_controller.dart';
import '../../features/category/controllers/category_state.dart';
import '../../features/search/controllers/search_history_notifier.dart';
import '../network/anime_image_cache_manager.dart';
import '../network/bangumi_client.dart';
import '../network/player_media_disk_cache_manager.dart';

/// 应用后台异步预热协调器（AppPrewarmCoordinator）
/// 特殊处理说明：
/// 1. 采用单飞（Single-Flight）幂等状态机，彻底消除用户启动应用瞬时点击与后台预热产生的并发与重复执行；
/// 2. 首帧渲染完成后排队在空闲微任务中静默执行，绝不抢占首屏 CPU 与关键帧渲染管线；
/// 3. 分别覆盖【分类数据预取】、【搜索历史/状态预热】与【设置页磁盘缓存体积统计】三大模块。
class AppPrewarmCoordinator {
  static final AppPrewarmCoordinator instance = AppPrewarmCoordinator._();
  AppPrewarmCoordinator._();

  // 1. 分类预热状态
  bool _categoryPrewarmed = false;
  Future<void>? _categoryFuture;

  // 2. 搜索预热状态
  bool _searchPrewarmed = false;
  Future<void>? _searchFuture;

  // 3. 设置预热状态与缓存数据
  bool _settingsPrewarmed = false;
  Future<({int imgBytes, int dataBytes})>? _settingsFuture;
  int? cachedImageBytes;
  int? cachedDataBytes;

  bool get isCategoryPrewarmed => _categoryPrewarmed;
  bool get isSearchPrewarmed => _searchPrewarmed;
  bool get isSettingsPrewarmed => _settingsPrewarmed;

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0.0 MB';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 启动后台静默调度队列（在首页完成首帧构建后调用）
  void startBackgroundPrewarm(WidgetRef ref, BangumiClient client) {
    // 1. 延迟 120ms 避开首页首屏最密集的组件构建，先预热纯本地数据（搜索历史、磁盘缓存统计，零网络开销）
    Future.delayed(const Duration(milliseconds: 120), () {
      prewarmSearch(ref);
      prewarmSettings(client);
    });

    // 2. 延迟 2500ms 等待首页首屏核心网络请求平稳发起后再静默预取分类数据，杜绝弱网冷启动时并发抢占带宽
    Future.delayed(const Duration(milliseconds: 2500), () {
      prewarmCategory(ref);
    });
  }

  /// 预热分类数据（具备防重机制）
  Future<void> prewarmCategory(WidgetRef ref) {
    if (_categoryFuture != null) return _categoryFuture!;
    final completer = Completer<void>();
    _categoryFuture = completer.future;

    Future<void>(() async {
      try {
        ref
            .read(categoryControllerProvider(const CategoryInitialArgs()).notifier)
            .ensureLoaded();
        _categoryPrewarmed = true;
      } catch (e) {
        developer.log('预热分类失败: $e');
      } finally {
        completer.complete();
      }
    });

    return _categoryFuture!;
  }

  /// 预热搜索模块（具备防重机制）
  Future<void> prewarmSearch(WidgetRef ref) {
    if (_searchFuture != null) return _searchFuture!;
    final completer = Completer<void>();
    _searchFuture = completer.future;

    Future<void>(() async {
      try {
        // 读取持久化搜索历史至内存中，消除首次进入读取磁盘的 I/O 阻塞
        ref.read(searchHistoryProvider);
        _searchPrewarmed = true;
      } catch (e) {
        developer.log('预热搜索失败: $e');
      } finally {
        completer.complete();
      }
    });

    return _searchFuture!;
  }

  static Future<int> _getDirectorySizeByKey(String key) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory(p.join(tempDir.path, key));
      if (!await dir.exists()) return 0;
      int total = 0;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {}
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// 预热设置页磁盘体积统计（具备防重机制）
  Future<({int imgBytes, int dataBytes})> prewarmSettings(
    BangumiClient client, {
    bool forceRefresh = false,
  }) {
    if (!forceRefresh && _settingsFuture != null) return _settingsFuture!;
    final completer = Completer<({int imgBytes, int dataBytes})>();
    _settingsFuture = completer.future;

    Future<void>(() async {
      try {
        int imgBytes = 0;
        try {
          final defaultSize = await _getDirectorySizeByKey('libCachedImageData');
          final animeSize = await _getDirectorySizeByKey(AnimeImageCacheManager.key);
          imgBytes = defaultSize + animeSize;
          if (imgBytes == 0) {
            imgBytes += await DefaultCacheManager().store.getCacheSize();
            imgBytes += await AnimeImageCacheManager.instance.store.getCacheSize();
          }
        } catch (_) {}

        int dataBytes = 0;
        try {
          dataBytes += await client.getDiskDataCacheSizeBytes();
        } catch (_) {}

        try {
          final playerDisk = PlayerMediaDiskCacheManager.instance;
          if (playerDisk != null) {
            dataBytes += await playerDisk.getDiskSizeBytes();
          }
        } catch (_) {}

        cachedImageBytes = imgBytes;
        cachedDataBytes = dataBytes;
        _settingsPrewarmed = true;

        completer.complete((imgBytes: imgBytes, dataBytes: dataBytes));
      } catch (e) {
        developer.log('预热设置缓存失败: $e');
        completer.complete((
          imgBytes: cachedImageBytes ?? 0,
          dataBytes: cachedDataBytes ?? 0,
        ));
      }
    });

    return _settingsFuture!;
  }

  /// 读取已在后台计算完成的格式化体积字符串（0ms 同步返回）
  ({String image, String data})? getCachedSizeStrings() {
    if (cachedImageBytes != null && cachedDataBytes != null) {
      return (
        image: formatBytes(cachedImageBytes!),
        data: formatBytes(cachedDataBytes!),
      );
    }
    return null;
  }

  /// 用户执行清空缓存后使缓存失效
  void invalidateCacheSizes() {
    cachedImageBytes = null;
    cachedDataBytes = null;
    _settingsPrewarmed = false;
    _settingsFuture = null;
  }
}
