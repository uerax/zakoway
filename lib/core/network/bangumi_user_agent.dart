import '../constants/app_constants.dart';

/// 遵循 Bangumi API 开发者准则规范配置合规的 User-Agent
class BangumiUserAgent {
  BangumiUserAgent._();

  static String get defaultUserAgent => AppConstants.bangumiUserAgent;

  /// 支持按动态版本号与可选平台标识构造合规 User-Agent
  static String build({
    String? version,
    String? platform,
  }) {
    final v = version ?? AppConstants.appVersion;
    final platformInfo = platform != null ? ' ($platform)' : '';
    return '${AppConstants.developerId}/${AppConstants.appName}/$v$platformInfo (${AppConstants.projectUrl})';
  }
}
