import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 全局应用常量配置与版本声明
class AppConstants {
  const AppConstants._();

  static String _appVersion = '0.0.1';
  static int _buildNumber = 1;

  /// 应用语义化版本号（优先从平台原生运行环境中动态获取，默认 fallback 为 0.0.1）
  static String get appVersion => _appVersion;

  /// 应用构建版本号
  static int get buildNumber => _buildNumber;

  /// 异步从原生平台（通过 package_info_plus，底层读取 pubspec.yaml 打包配置）初始化实际版本号
  static Future<void> initialize() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) {
        _appVersion = info.version;
      }
      final parsedBuild = int.tryParse(info.buildNumber);
      if (parsedBuild != null) {
        _buildNumber = parsedBuild;
      }
    } catch (e) {
      debugPrint('[AppConstants] PackageInfo.fromPlatform 初始化跳过 (使用回退版本 $_appVersion): $e');
    }
  }

  /// 供单元测试或离线 Mock 注入版本号
  @visibleForTesting
  static void setMockVersion({String? version, int? build}) {
    if (version != null) _appVersion = version;
    if (build != null) _buildNumber = build;
  }

  /// 应用标识名称
  static const String appName = 'zakoway';

  /// 开发者个人/组织 ID
  static const String developerId = 'uerax';

  /// 开源项目主页仓库地址
  static const String projectUrl = 'https://github.com/uerax/zakoway';

  /// 开源项目 GitHub Releases 发布页地址
  static const String projectReleasesUrl =
      'https://github.com/uerax/zakoway/releases';

  /// 借助 jsDelivr CDN 加速拉取版本检测元数据 JSON 的全球分发地址
  static const String updateManifestCdnUrl =
      'https://cdn.jsdelivr.net/gh/uerax/zakoway@master/version.json';

  /// 遵循 Bangumi 官方 API 开发者准则规范生成的合规 User-Agent:
  /// 格式: <开发者ID>/<应用名>/<版本号> (<项目主页URL>)
  static String get bangumiUserAgent =>
      '$developerId/$appName/$appVersion ($projectUrl)';

  /// 内置默认网络线路仓库链接（用于从远程或内置源导入社区反代节点）
  static const String defaultRoutesRepoUrl =
      'https://raw.githubusercontent.com/uerax/zakoway/master/routes.json';
}
