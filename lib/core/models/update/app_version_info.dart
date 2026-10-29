import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../constants/app_constants.dart';

/// 单个平台的安装包下载资源条目
class AppDownloadAsset {
  final String fileName;
  final String url;
  final int size;
  final String sha256;

  const AppDownloadAsset({
    required this.fileName,
    required this.url,
    required this.size,
    this.sha256 = '',
  });

  factory AppDownloadAsset.fromJson(Map<dynamic, dynamic> json) {
    return AppDownloadAsset(
      fileName: json['fileName'] as String? ?? '',
      url: json['url'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      sha256: (json['sha256'] as String?)?.trim().toLowerCase() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'fileName': fileName,
        'url': url,
        'size': size,
        'sha256': sha256,
      };

  /// 计算生效的下载 URL：
  /// 若用户配置了加速前缀（例如 https://ghproxy.net/），则将官方 Release 直链拼接在其后
  String getEffectiveUrl(String? prefix) {
    final cleanPrefix = prefix?.trim() ?? '';
    if (cleanPrefix.isEmpty) {
      return url;
    }
    final normalized = cleanPrefix.endsWith('/') ? cleanPrefix : '$cleanPrefix/';
    return '$normalized$url';
  }

  /// 格式化为易读的文件大小（如 45.2 MB）
  String get formattedSize {
    if (size <= 0) return '';
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 远程版本元数据模型（支持 latest 稳定版与 beta 测试尝鲜版双通道解析）
class AppVersionInfo {
  final String version;
  final int buildNumber;
  final String releaseDate;
  final String? minSupportedVersion;
  final String title;
  final String changelog;
  final bool isPrerelease;
  final String channel;
  final Map<String, AppDownloadAsset> downloads;

  const AppVersionInfo({
    required this.version,
    required this.buildNumber,
    required this.releaseDate,
    this.minSupportedVersion,
    required this.title,
    required this.changelog,
    this.isPrerelease = false,
    this.channel = 'latest',
    required this.downloads,
  });

  factory AppVersionInfo.fromJson(
    Map<dynamic, dynamic> json, {
    String channel = 'latest',
  }) {
    final rawDownloads = json['downloads'];
    final downloadsMap = <String, AppDownloadAsset>{};
    if (rawDownloads is Map) {
      for (final entry in rawDownloads.entries) {
        if (entry.value is Map) {
          downloadsMap[entry.key.toString()] =
              AppDownloadAsset.fromJson(entry.value as Map);
        }
      }
    }

    final ver = json['version'] as String? ?? '1.0.0';
    final isPre = json['isPrerelease'] as bool? ??
        (channel == 'beta' || ver.contains('-'));

    return AppVersionInfo(
      version: ver,
      buildNumber: (json['buildNumber'] as num?)?.toInt() ?? 1,
      releaseDate: json['releaseDate'] as String? ?? '',
      minSupportedVersion: json['minSupportedVersion'] as String?,
      title: json['title'] as String? ?? (isPre ? '发现新测试版' : '发现新版本'),
      changelog: json['changelog'] as String? ?? '',
      isPrerelease: isPre,
      channel: channel,
      downloads: downloadsMap,
    );
  }

  /// 从可能包含 latest / beta 双通道或旧版单节点的 JSON 中解析出当前应匹配的版本
  static AppVersionInfo? parseManifest(
    Map<dynamic, dynamic> json, {
    required bool includeBeta,
  }) {
    // 1. 判断是否为双通道字典结构
    final hasDualChannel =
        json.containsKey('latest') || json.containsKey('beta');

    if (hasDualChannel) {
      final latestRaw = json['latest'];
      final betaRaw = json['beta'];

      final latestInfo = latestRaw is Map
          ? AppVersionInfo.fromJson(latestRaw, channel: 'latest')
          : null;
      final betaInfo = betaRaw is Map
          ? AppVersionInfo.fromJson(betaRaw, channel: 'beta')
          : null;

      if (!includeBeta) {
        return latestInfo;
      }

      // 用户开启了 Beta 尝鲜通道：挑选版本更新的一个
      if (latestInfo == null) return betaInfo;
      if (betaInfo == null) return latestInfo;

      final cmp = compareSemVer(betaInfo.version, latestInfo.version);
      if (cmp > 0) return betaInfo;
      if (cmp == 0 && betaInfo.buildNumber > latestInfo.buildNumber) {
        return betaInfo;
      }
      return latestInfo;
    }

    // 2. 向下兼容旧版扁平结构
    return AppVersionInfo.fromJson(json, channel: 'latest');
  }

  /// 比较两个版本号（完全符合 SemVer 规范，支持 pre-release 预发布后缀如 1.0.1-beta.1 与 1.0.1 对比）：
  /// 1. 主版本、次版本、修订版本数值比对；
  /// 2. 相同版本下，不带后缀的正式版高于带 -beta 后缀的预发布版（例如 1.0.1 > 1.0.1-beta.1）；
  /// 3. 返回 > 0 表示 v1 > v2；返回 < 0 表示 v1 < v2；返回 0 表示相等。
  static int compareSemVer(String v1, String v2) {
    final clean1 = v1.replaceFirst(RegExp(r'^[vV]'), '').trim();
    final clean2 = v2.replaceFirst(RegExp(r'^[vV]'), '').trim();

    final parts1 = clean1.split('+').first.split('-');
    final parts2 = clean2.split('+').first.split('-');

    final mainParts1 = parts1[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final mainParts2 = parts2[0].split('.').map((e) => int.tryParse(e) ?? 0).toList();

    final maxLen = mainParts1.length > mainParts2.length
        ? mainParts1.length
        : mainParts2.length;

    for (var i = 0; i < maxLen; i++) {
      final p1 = i < mainParts1.length ? mainParts1[i] : 0;
      final p2 = i < mainParts2.length ? mainParts2[i] : 0;
      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }

    // 主版本号完全相等时，根据预发布后缀判定：
    // 无预发布后缀的正式版 > 有预发布后缀的测试版
    final hasPre1 = parts1.length > 1;
    final hasPre2 = parts2.length > 1;
    if (!hasPre1 && hasPre2) return 1;
    if (hasPre1 && !hasPre2) return -1;
    if (hasPre1 && hasPre2) {
      return parts1[1].compareTo(parts2[1]);
    }

    return 0;
  }

  /// 当前远程版本是否较本地版本更新
  bool get hasUpdate {
    final semCompare = compareSemVer(version, AppConstants.appVersion);
    if (semCompare > 0) return true;
    if (semCompare == 0 && buildNumber > AppConstants.buildNumber) return true;
    return false;
  }

  /// 是否为强制更新（本地版本低于最小支持版本要求）
  bool get isForceUpdate {
    final minVer = minSupportedVersion;
    if (minVer == null || minVer.isEmpty) return false;
    return compareSemVer(AppConstants.appVersion, minVer) < 0;
  }

  /// 根据当前运行操作系统自动匹配最优下载安装包
  AppDownloadAsset? getAssetForCurrentPlatform() {
    if (kIsWeb) return null;

    if (Platform.isWindows) {
      return downloads['windows_x64'];
    } else if (Platform.isAndroid) {
      // Android 优先选择 arm64 架构包（体积精简约 40%），其次回退至 universal 通用包
      return downloads['android_arm64'] ?? downloads['android_universal'];
    } else if (Platform.isMacOS) {
      return downloads['macos_universal'];
    } else if (Platform.isIOS) {
      return downloads['ios'];
    }
    return null;
  }
}
