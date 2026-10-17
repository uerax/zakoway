import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 播放器媒体与弹幕专用磁盘缓存管理器：
/// 1. 基于 flutter_cache_manager，跨全平台稳定持久化到硬盘；
/// 2. 覆盖视频源搜索 (2h)、选集章节 (30m)、直链 (20m) 与弹幕数据 (12h/30m)；
/// 3. 支持 App 重启后从硬盘 0ms 秒级恢复；
/// 4. 支持 LRU 自动淘汰、磁盘容量统计与一键清空。
class PlayerMediaDiskCacheManager extends CacheManager {
  static const key = 'zakoway_player_media_disk_cache';

  static PlayerMediaDiskCacheManager? _instance;

  /// 安全检查当前运行时环境是否已初始化 Flutter 核心绑定（单测环境中自动静默禁用以防定时器超时）
  static bool get isSupported {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return false;
    }
    try {
      WidgetsBinding.instance;
      return true;
    } on Object catch (_) {
      return false;
    }
  }

  static PlayerMediaDiskCacheManager? get instance {
    if (!isSupported) return null;
    return _instance ??= PlayerMediaDiskCacheManager._();
  }

  PlayerMediaDiskCacheManager._()
      : super(
          Config(
            key,
            stalePeriod: const Duration(days: 7),
            maxNrOfCacheObjects: 1000,
          ),
        );

  /// 将 JSON 结构数据以指定 TTL 保存到本地硬盘
  Future<void> putJson(
    String cacheKey,
    dynamic jsonObject, {
    required Duration maxAge,
  }) async {
    try {
      final jsonStr = jsonEncode(jsonObject);
      final bytes = utf8.encode(jsonStr);
      await putFile(
        cacheKey,
        bytes,
        key: cacheKey,
        maxAge: maxAge,
        fileExtension: 'json',
      );
    } catch (_) {
      // 容错: 忽略非阻塞的写盘异常，保障主业务流程顺畅
    }
  }

  /// 从本地硬盘读取未过期的有效 JSON 缓存数据
  Future<dynamic> getJson(String cacheKey) async {
    try {
      final fileInfo = await getFileFromCache(cacheKey);
      if (fileInfo != null && fileInfo.validTill.isAfter(DateTime.now())) {
        final content = await fileInfo.file.readAsString();
        return jsonDecode(content);
      }
    } catch (_) {
      // 容错: 若磁盘文件读取解析失败则静默降级为未命中
    }
    return null;
  }

  /// 获取缓存物理目录
  static Future<Directory?> getCacheDirectory() async {
    try {
      final tempDir = await getTemporaryDirectory();
      return Directory(p.join(tempDir.path, key));
    } catch (_) {
      return null;
    }
  }

  /// 获取当前磁盘缓存的总字节大小
  /// 特殊处理说明：flutter_cache_manager 的 putFile 在写入文件时不会向 SQLite 数据库写入 length 字段，
  /// 导致 store.getCacheSize() 恒返回 0。因此必须直接扫描物理缓存目录下的文件真实字节数。
  Future<int> getDiskSizeBytes() async {
    try {
      final dir = await getCacheDirectory();
      if (dir == null || !await dir.exists()) return 0;
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

  /// 清空硬盘上的全部媒体与弹幕数据缓存
  Future<void> clearAll() async {
    try {
      await emptyCache();
    } catch (_) {}
    try {
      final dir = await getCacheDirectory();
      if (dir != null && await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
