import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_file_plus/open_file_plus.dart';

import '../models/update/app_version_info.dart';
import 'app_preferences.dart';
import 'update_service.dart';

enum UpdateStatus {
  idle,
  checking,
  updateAvailable,
  upToDate,
  downloading,
  readyToInstall,
  failed,
}

/// 全局多端应用更新管理器：
/// 维护当前版本检测状态、下载流进度与安装就绪事件，支持响应式更新
class UpdateManager extends ChangeNotifier {
  UpdateManager._();
  static final UpdateManager instance = UpdateManager._();

  UpdateStatus _status = UpdateStatus.idle;
  UpdateStatus get status => _status;

  AppVersionInfo? _latestVersion;
  AppVersionInfo? get latestVersion => _latestVersion;

  double _downloadProgress = 0.0;
  double get downloadProgress => _downloadProgress;

  int _receivedBytes = 0;
  int get receivedBytes => _receivedBytes;

  int _totalBytes = 0;
  int get totalBytes => _totalBytes;

  File? _downloadedFile;
  File? get downloadedFile => _downloadedFile;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  CancelToken? _cancelToken;

  /// 获取当前加速前缀
  String get downloadPrefix => AppPreferences.getUpdateDownloadPrefix();

  /// 保存加速前缀
  Future<void> setDownloadPrefix(String prefix) async {
    await AppPreferences.setUpdateDownloadPrefix(prefix);
    notifyListeners();
  }

  /// 是否接收测试尝鲜版 (Beta)
  bool get includeBetaChannel => AppPreferences.getIncludeBetaChannel();

  /// 设置是否接收测试尝鲜版
  Future<void> setIncludeBetaChannel(bool enabled) async {
    await AppPreferences.setIncludeBetaChannel(enabled);
    notifyListeners();
    // 切换通道后自动重新触发一次静默检查
    await checkUpdate(isManual: false);
  }

  /// 检查新版本（isManual=true 时即使是最新版也会触发提示，且不被忽略策略拦截）
  Future<AppVersionInfo?> checkUpdate({bool isManual = false}) async {
    if (_status == UpdateStatus.checking || _status == UpdateStatus.downloading) {
      return _latestVersion;
    }

    _status = UpdateStatus.checking;
    _errorMessage = null;
    notifyListeners();

    try {
      final versionInfo = await UpdateService.instance.checkUpdate(
        isManualCheck: isManual,
        includeBeta: includeBetaChannel,
      );
      if (versionInfo != null && versionInfo.hasUpdate) {
        _latestVersion = versionInfo;
        _status = UpdateStatus.updateAvailable;
      } else {
        _status = UpdateStatus.upToDate;
      }
    } catch (e) {
      _status = UpdateStatus.failed;
      _errorMessage = '检测更新失败: $e';
    }

    notifyListeners();
    return _latestVersion;
  }

  /// 启动安装包下载
  Future<void> startDownload(AppDownloadAsset asset) async {
    if (_status == UpdateStatus.downloading) return;

    _status = UpdateStatus.downloading;
    _downloadProgress = 0.0;
    _receivedBytes = 0;
    _totalBytes = asset.size;
    _errorMessage = null;
    _cancelToken = CancelToken();
    notifyListeners();

    try {
      final file = await UpdateService.instance.downloadAsset(
        asset: asset,
        cancelToken: _cancelToken,
        onProgress: (received, total) {
          _receivedBytes = received;
          _totalBytes = total > 0 ? total : asset.size;
          if (_totalBytes > 0) {
            _downloadProgress = (_receivedBytes / _totalBytes).clamp(0.0, 1.0);
          }
          notifyListeners();
        },
      );

      _downloadedFile = file;
      _status = UpdateStatus.readyToInstall;
      notifyListeners();

      // 下载完成后自动尝试拉起安装
      await installOrOpen();
    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        _status = UpdateStatus.updateAvailable;
        _errorMessage = '下载已取消';
      } else if (e is UpdateChecksumException) {
        _status = UpdateStatus.failed;
        _errorMessage = e.message;
      } else {
        _status = UpdateStatus.failed;
        _errorMessage = '下载失败: $e';
      }
      notifyListeners();
    } finally {
      _cancelToken = null;
    }
  }

  /// 取消当前下载
  void cancelDownload() {
    _cancelToken?.cancel('User cancelled download');
    _cancelToken = null;
    _status = UpdateStatus.updateAvailable;
    _downloadProgress = 0.0;
    notifyListeners();
  }

  /// 安装或打开已就绪的更新文件
  Future<OpenResult?> installOrOpen() async {
    final file = _downloadedFile;
    if (file == null || !await file.exists()) {
      _errorMessage = '未找到已下载的安装文件';
      notifyListeners();
      return null;
    }

    try {
      final result = await UpdateService.instance.installOrOpenDownloadedFile(file);
      return result;
    } catch (e) {
      _errorMessage = '唤起安装器失败: $e';
      notifyListeners();
      return null;
    }
  }

  /// 忽略当前新版本更新
  Future<void> ignoreCurrentUpdate() async {
    final ver = _latestVersion?.version;
    if (ver != null) {
      await AppPreferences.setIgnoredUpdateVersion(ver);
    }
    _status = UpdateStatus.idle;
    notifyListeners();
  }
}
