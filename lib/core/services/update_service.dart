import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file_plus/open_file_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/app_constants.dart';
import '../models/update/app_version_info.dart';
import 'app_preferences.dart';

/// 安装包文件完整性校验失败异常
class UpdateChecksumException implements Exception {
  final String message;
  const UpdateChecksumException(this.message);

  @override
  String toString() => message;
}

/// 全局多端应用更新服务单例：
/// 1. 负责通过 jsDelivr CDN 拉取版本元数据（支持 latest 稳定版与 beta 尝鲜版双通道）；
/// 2. 负责安装包流式下载与 SHA-256 完整性哈希校验；
/// 3. 负责唤起原生系统安装器或目录。
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
      },
    ),
  );

  /// 缓存最近一次检测到的版本信息
  AppVersionInfo? _cachedVersionInfo;
  AppVersionInfo? get cachedVersionInfo => _cachedVersionInfo;

  /// 检测新版本（支持通过 force 跳过忽略版本检查，并支持 beta 尝鲜通道过滤）
  Future<AppVersionInfo?> checkUpdate({
    bool isManualCheck = false,
    bool includeBeta = false,
  }) async {
    try {
      // 附加时间戳参数破坏 CDN 边缘强缓存，确保用户手动点击时能立刻检测到刚发布的版本
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = '${AppConstants.updateManifestCdnUrl}?t=$timestamp';

      final response = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(responseType: ResponseType.json),
      );

      final data = response.data;
      if (data == null) return null;

      final versionInfo = AppVersionInfo.parseManifest(
        data,
        includeBeta: includeBeta,
      );
      if (versionInfo == null) return null;

      _cachedVersionInfo = versionInfo;

      if (!versionInfo.hasUpdate) {
        return null;
      }

      // 非手动点击检查且当前版本被用户标记为“跳过此版本”时忽略
      if (!isManualCheck && !versionInfo.isForceUpdate) {
        final ignoredVer = AppPreferences.getIgnoredUpdateVersion();
        if (ignoredVer == versionInfo.version) {
          return null;
        }
      }

      return versionInfo;
    } catch (e) {
      debugPrint('[UpdateService] checkUpdate failed: $e');
      return null;
    }
  }

  /// 采用低内存流式计算比对文件的 SHA-256 哈希值
  Future<bool> verifyFileSha256(File file, String expectedSha256) async {
    final expected = expectedSha256.trim().toLowerCase();
    if (expected.isEmpty) return true; // 若元数据未配置哈希则跳过比对

    if (!await file.exists()) return false;

    try {
      final digest = await sha256.bind(file.openRead()).first;
      final actual = digest.toString().toLowerCase();
      final isMatched = actual == expected;
      if (!isMatched) {
        debugPrint(
          '[UpdateService] SHA-256 mismatch! Expected: $expected, Actual: $actual',
        );
      }
      return isMatched;
    } catch (e) {
      debugPrint('[UpdateService] verifyFileSha256 error: $e');
      return false;
    }
  }

  /// 下载指定平台的安装文件并在下载完成后执行 SHA-256 完整性校验
  Future<File> downloadAsset({
    required AppDownloadAsset asset,
    required void Function(int received, int total) onProgress,
    CancelToken? cancelToken,
  }) async {
    // 1. 获取拼接加速前缀后的实际有效下载地址
    final prefix = AppPreferences.getUpdateDownloadPrefix();
    final downloadUrl = asset.getEffectiveUrl(prefix);

    // 2. 解析本地文件存放路径
    final targetDir = await _resolveDownloadDirectory();
    final fileName = asset.fileName.isNotEmpty
        ? asset.fileName
        : 'zakoway-update-${DateTime.now().millisecondsSinceEpoch}';
    final filePath = p.join(targetDir.path, fileName);
    final targetFile = File(filePath);

    // 若旧文件已存在则先清理
    if (await targetFile.exists()) {
      try {
        await targetFile.delete();
      } catch (_) {}
    }

    // 3. 执行 Dio 流式文件下载并监听进度
    await _dio.download(
      downloadUrl,
      filePath,
      cancelToken: cancelToken,
      onReceiveProgress: onProgress,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
      ),
    );

    // 4. 下载完成：执行 SHA-256 哈希完整性校验
    if (asset.sha256.isNotEmpty) {
      final isValid = await verifyFileSha256(targetFile, asset.sha256);
      if (!isValid) {
        try {
          await targetFile.delete();
        } catch (_) {}
        throw const UpdateChecksumException(
          '安装包完整性校验失败 (SHA-256 不匹配)，文件可能损坏，已终止安装。',
        );
      }
    }

    return targetFile;
  }

  /// 打开安装或定位安装包
  Future<OpenResult> installOrOpenDownloadedFile(File file) async {
    if (!await file.exists()) {
      return OpenResult(
        type: ResultType.fileNotFound,
        message: '更新文件不存在',
      );
    }

    if (Platform.isAndroid) {
      // Android 调用系统 PackageInstaller 安装器
      return await OpenFile.open(
        file.path,
        type: 'application/vnd.android.package-archive',
      );
    } else if (Platform.isWindows) {
      // Windows 平台：如果是 zip 压缩包，尝试打开所在文件夹以便用户解压覆盖
      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done) {
        return await OpenFile.open(file.parent.path);
      }
      return result;
    } else {
      // macOS 等其他平台
      return await OpenFile.open(file.path);
    }
  }

  /// 调用系统默认浏览器直连下载或打开 Release 页面
  Future<bool> launchInBrowser(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      debugPrint('[UpdateService] launchInBrowser error: $e');
    }
    return false;
  }

  /// 寻找当前平台最合适的文件下载保存目录
  Future<Directory> _resolveDownloadDirectory() async {
    if (Platform.isAndroid) {
      final cacheDir = await getTemporaryDirectory();
      final updatesDir = Directory(p.join(cacheDir.path, 'updates'));
      if (!await updatesDir.exists()) {
        await updatesDir.create(recursive: true);
      }
      return updatesDir;
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      final downloadsDir = await getDownloadsDirectory();
      if (downloadsDir != null && await downloadsDir.exists()) {
        return downloadsDir;
      }
    }
    return await getApplicationSupportDirectory();
  }
}
