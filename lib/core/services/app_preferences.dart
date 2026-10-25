import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/network/custom_network_route.dart';
import '../network/bangumi_source_preset.dart';
import '../utils/appearance_manager.dart';
import '../utils/font_manager.dart';

/// 全局本地配置持久化服务：
/// 负责保存与恢复用户的网络线路、字体偏好以及个性化外观设置（壁纸、图标、裁剪矩阵等）
class AppPreferences {
  AppPreferences._();

  static const _kSourcePreset = 'pref_network_source_preset';
  static const _kCustomNetworkRoutes = 'pref_custom_network_routes';
  static const _kFontType = 'pref_font_type';
  static const _kCustomFontPath = 'pref_custom_font_path';
  static const _kCustomFontName = 'pref_custom_font_name';

  static const _kThemePreset = 'pref_theme_preset';
  static const _kCustomThemeColor = 'pref_custom_theme_color';
  static const _kCustomIconPath = 'pref_custom_icon_path';
  static const _kGlobalWallpaperPath = 'pref_global_wallpaper_path';
  static const _kPageWallpapers = 'pref_page_wallpapers';
  static const _kWallpaperAlignX = 'pref_wallpaper_align_x';
  static const _kWallpaperAlignY = 'pref_wallpaper_align_y';
  static const _kWallpaperScale = 'pref_wallpaper_scale';
  static const _kWallpaperOpacity = 'pref_wallpaper_opacity';
  static const _kWallpaperBlur = 'pref_wallpaper_blur';
  static const _kSearchHistory = 'pref_search_history';
  static const _kWatchHistory = 'pref_watch_history';
  static const _kWatchedEpisodes = 'pref_watched_episodes';
  static const _kDeviceInstallId = 'pref_device_install_id';
  static const _kAuthToken = 'pref_auth_token';
  static const _kAuthUserJson = 'pref_auth_user_json';
  static const _kAuthSessionJson = 'pref_auth_session_json';
  static const _kAnimeCollections = 'pref_anime_collections';
  static const _kServerModeEnabled = 'pref_server_mode_enabled';
  static const _kServerModeApiUrl = 'pref_server_mode_api_url';
  static const _kServerModeCachedSources = 'pref_server_mode_cached_sources';
  static const _kPreferWebviewSniff = 'pref_prefer_webview_sniff';
  static const _kDisplayMode = 'pref_display_mode';

  /// 默认公开免费 Animaku 服务端地址
  static const String defaultServerModeApiUrl = 'https://bakasine.eu.org';

  /// 全局服务端模式状态响应式监听器
  static final ValueNotifier<bool> serverModeNotifier = ValueNotifier<bool>(false);

  /// 全局优先 WebView 嗅探状态响应式监听器
  static final ValueNotifier<bool> preferWebviewSniffNotifier = ValueNotifier<bool>(false);

  static SharedPreferences? _prefs;

  /// 初始化本地持久化实例，并在应用启动时自动还原各项用户偏好
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _restorePreferences();
  }

  /// 恢复持久化配置到对应的单例管理器中
  static Future<void> _restorePreferences() async {
    final prefs = _prefs;
    if (prefs == null) return;

    // 1. 恢复字体偏好
    final fontTypeStr = prefs.getString(_kFontType);
    final customFontPath = prefs.getString(_kCustomFontPath);
    final customFontName = prefs.getString(_kCustomFontName);
    if (fontTypeStr != null) {
      final matchedType = AppFontType.values.firstWhere(
        (t) => t.name == fontTypeStr,
        orElse: () => AppFontType.misans,
      );
      if (matchedType == AppFontType.custom && customFontPath != null) {
        await FontManager.instance.loadFontFromFile(customFontPath);
      } else {
        FontManager.instance.setFontType(matchedType);
      }
      if (customFontName != null && FontManager.instance.customFontPath != null) {
        // 保留之前选取的字体名称
      }
    }

    // 2. 恢复外观偏好（主题色、图标、壁纸、参数）
    final appMgr = AppearanceManager.instance;

    final themePresetId = prefs.getString(_kThemePreset);
    final customColorVal = prefs.getInt(_kCustomThemeColor);
    final customColor = customColorVal != null ? Color(customColorVal) : null;
    if (themePresetId != null) {
      appMgr.restoreThemePreset(themePresetId, customColor: customColor);
    }

    final customIcon = prefs.getString(_kCustomIconPath);
    if (customIcon != null) {
      appMgr.restoreCustomIcon(customIcon);
    }

    final globalWallpaper = prefs.getString(_kGlobalWallpaperPath);
    final pageWallpapersJson = prefs.getString(_kPageWallpapers);
    Map<String, String>? pageWallpapers;
    if (pageWallpapersJson != null) {
      try {
        final decoded = jsonDecode(pageWallpapersJson) as Map<String, dynamic>;
        pageWallpapers = decoded.map((k, v) => MapEntry(k, v.toString()));
      } catch (_) {}
    }

    final alignX = prefs.getDouble(_kWallpaperAlignX);
    final alignY = prefs.getDouble(_kWallpaperAlignY);
    final scale = prefs.getDouble(_kWallpaperScale);
    final opacity = prefs.getDouble(_kWallpaperOpacity);
    final blur = prefs.getDouble(_kWallpaperBlur);

    appMgr.restoreWallpaperConfig(
      globalWallpaper: globalWallpaper,
      pageWallpapers: pageWallpapers,
      alignX: alignX,
      alignY: alignY,
      scale: scale,
      opacity: opacity,
      blur: blur,
    );

    // 4. 恢复服务端模式偏好
    serverModeNotifier.value = prefs.getBool(_kServerModeEnabled) ?? false;

    // 5. 恢复 WebView 视频流嗅探偏好 (当前重构期间强制禁用)
    preferWebviewSniffNotifier.value = false;
  }

  // --- 网络线路持久化 ---

  static String getActiveRouteId() {
    return _prefs?.getString(_kSourcePreset) ?? BangumiSourcePreset.mirror.name;
  }

  static Future<void> saveActiveRouteId(String routeId) async {
    await _prefs?.setString(_kSourcePreset, routeId);
  }

  static List<CustomNetworkRoute> getCustomNetworkRoutes() {
    final raw = _prefs?.getString(_kCustomNetworkRoutes);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw);
      if (list is List) {
        return list
            .whereType<Map<String, dynamic>>()
            .map((e) => CustomNetworkRoute.fromJson(e))
            .where((e) => e.id.isNotEmpty && e.url.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<void> saveCustomNetworkRoutes(List<CustomNetworkRoute> routes) async {
    final raw = jsonEncode(routes.map((e) => e.toJson()).toList());
    await _prefs?.setString(_kCustomNetworkRoutes, raw);
  }

  static BangumiSourcePreset getInitialSourcePreset() {
    final presetName = _prefs?.getString(_kSourcePreset);
    if (presetName == BangumiSourcePreset.official.name) {
      return BangumiSourcePreset.official;
    }
    return BangumiSourcePreset.mirror;
  }

  static Future<void> saveSourcePreset(BangumiSourcePreset preset) async {
    await _prefs?.setString(_kSourcePreset, preset.name);
  }

  // --- 字体持久化 ---

  static Future<void> saveFontType(AppFontType type) async {
    await _prefs?.setString(_kFontType, type.name);
  }

  static Future<void> saveCustomFont({required String path, required String name}) async {
    await _prefs?.setString(_kFontType, AppFontType.custom.name);
    await _prefs?.setString(_kCustomFontPath, path);
    await _prefs?.setString(_kCustomFontName, name);
  }

  static Future<void> clearCustomFont() async {
    await _prefs?.remove(_kCustomFontPath);
    await _prefs?.remove(_kCustomFontName);
  }

  // --- 外观持久化 ---

  static Future<void> saveThemePreset(String presetId) async {
    await _prefs?.setString(_kThemePreset, presetId);
  }

  static Future<void> saveCustomThemeColor(int colorValue) async {
    await _prefs?.setInt(_kCustomThemeColor, colorValue);
  }

  static Future<void> saveCustomIcon(String? iconPath) async {
    if (iconPath != null) {
      await _prefs?.setString(_kCustomIconPath, iconPath);
    } else {
      await _prefs?.remove(_kCustomIconPath);
    }
  }

  static Future<void> saveWallpapers({
    String? globalWallpaper,
    Map<String, String>? pageWallpapers,
  }) async {
    if (globalWallpaper != null) {
      await _prefs?.setString(_kGlobalWallpaperPath, globalWallpaper);
    } else {
      await _prefs?.remove(_kGlobalWallpaperPath);
    }

    if (pageWallpapers != null && pageWallpapers.isNotEmpty) {
      await _prefs?.setString(_kPageWallpapers, jsonEncode(pageWallpapers));
    } else {
      await _prefs?.remove(_kPageWallpapers);
    }
  }

  static Future<void> saveWallpaperTransform({
    required double alignX,
    required double alignY,
    required double scale,
  }) async {
    await _prefs?.setDouble(_kWallpaperAlignX, alignX);
    await _prefs?.setDouble(_kWallpaperAlignY, alignY);
    await _prefs?.setDouble(_kWallpaperScale, scale);
  }

  static Future<void> saveWallpaperOpacity(double opacity) async {
    await _prefs?.setDouble(_kWallpaperOpacity, opacity);
  }

  static Future<void> saveWallpaperBlur(double blur) async {
    await _prefs?.setDouble(_kWallpaperBlur, blur);
  }

  // --- 搜索历史持久化 ---

  static List<String> getSearchHistory() {
    return _prefs?.getStringList(_kSearchHistory) ?? const [];
  }

  static Future<void> saveSearchHistory(List<String> history) async {
    await _prefs?.setStringList(_kSearchHistory, history);
  }

  // --- 播放历史持久化 ---

  static String? getWatchHistoryJson() {
    return _prefs?.getString(_kWatchHistory);
  }

  static Future<void> saveWatchHistoryJson(String jsonStr) async {
    await _prefs?.setString(_kWatchHistory, jsonStr);
  }

  static Future<void> clearWatchHistory() async {
    await _prefs?.remove(_kWatchHistory);
  }

  // --- 已观看集数持久化 (Map<bangumiId, Map<ep, timestamp>>) ---

  static String? getWatchedEpisodesJson() {
    return _prefs?.getString(_kWatchedEpisodes);
  }

  static Future<void> saveWatchedEpisodesJson(String jsonStr) async {
    await _prefs?.setString(_kWatchedEpisodes, jsonStr);
  }

  static Future<void> clearWatchedEpisodes() async {
    await _prefs?.remove(_kWatchedEpisodes);
  }

  // --- 设备唯一标识持久化（用于每日推荐确定性种子生成） ---

  static String getOrCreateDeviceInstallId() {
    final prefs = _prefs;
    if (prefs == null) return 'device_default_seed';
    var id = prefs.getString(_kDeviceInstallId);
    if (id == null || id.isEmpty) {
      final now = DateTime.now();
      id = 'dev_${now.millisecondsSinceEpoch}_${now.microsecondsSinceEpoch % 999999}';
      prefs.setString(_kDeviceInstallId, id);
    }
    return id;
  }

  /// 获取当前设备的游客专属短机器码（例如 6 位大写 Hex：8F3A19）
  static String getGuestMachineCode() {
    final rawId = getOrCreateDeviceInstallId();
    final hash = rawId.hashCode.abs();
    final hex = hash.toRadixString(16).toUpperCase().padLeft(6, '0');
    return hex.length > 6 ? hex.substring(hex.length - 6) : hex;
  }

  // --- 登录会话与用户认证持久化 ---

  static String? getAuthToken() {
    return _prefs?.getString(_kAuthToken);
  }

  static String? getAuthUserJson() {
    return _prefs?.getString(_kAuthUserJson);
  }

  static String? getAuthSessionJson() {
    return _prefs?.getString(_kAuthSessionJson);
  }

  static Future<void> saveAuthData({
    required String token,
    required String userJson,
    required String sessionJson,
  }) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await Future.wait([
      prefs.setString(_kAuthToken, token),
      prefs.setString(_kAuthUserJson, userJson),
      prefs.setString(_kAuthSessionJson, sessionJson),
    ]);
  }

  static Future<void> clearAuthData() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await Future.wait([
      prefs.remove(_kAuthToken),
      prefs.remove(_kAuthUserJson),
      prefs.remove(_kAuthSessionJson),
    ]);
  }

  // --- 我的追番本地持久化 ---

  static String? getAnimeCollectionsJson() {
    return _prefs?.getString(_kAnimeCollections);
  }

  static Future<void> saveAnimeCollectionsJson(String jsonStr) async {
    await _prefs?.setString(_kAnimeCollections, jsonStr);
  }

  static Future<void> clearAnimeCollections() async {
    await _prefs?.remove(_kAnimeCollections);
  }

  // --- Animaku 服务端模式配置 ---

  static bool isServerModeEnabled() {
    return _prefs?.getBool(_kServerModeEnabled) ?? false;
  }

  static Future<void> setServerModeEnabled(bool enabled) async {
    serverModeNotifier.value = enabled;
    await _prefs?.setBool(_kServerModeEnabled, enabled);
  }

  static String getServerModeApiUrl() {
    final url = _prefs?.getString(_kServerModeApiUrl);
    if (url != null && url.trim().isNotEmpty) {
      return url.trim();
    }
    return defaultServerModeApiUrl;
  }

  static Future<void> setServerModeApiUrl(String url) async {
    var cleanUrl = url.trim();
    while (cleanUrl.endsWith('/')) {
      cleanUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    }
    if (cleanUrl.isEmpty || cleanUrl == defaultServerModeApiUrl) {
      await _prefs?.remove(_kServerModeApiUrl);
    } else {
      await _prefs?.setString(_kServerModeApiUrl, cleanUrl);
    }
  }

  static List<String> getServerModeCachedSources() {
    return _prefs?.getStringList(_kServerModeCachedSources) ?? const [];
  }

  static Future<void> setServerModeCachedSources(List<String> sources) async {
    await _prefs?.setStringList(_kServerModeCachedSources, sources);
  }

  // --- WebView 视频流嗅探偏好配置 (当前重构期间强制禁用) ---

  static bool isPreferWebviewSniffEnabled() {
    return false;
  }

  static Future<void> setPreferWebviewSniff(bool enabled) async {
    preferWebviewSniffNotifier.value = false;
    await _prefs?.setBool(_kPreferWebviewSniff, false);
  }

  // --- 屏幕刷新率偏好配置 (Android 平台) ---

  static String? getDisplayMode() {
    return _prefs?.getString(_kDisplayMode);
  }

  static Future<void> saveDisplayMode(String modeStr) async {
    await _prefs?.setString(_kDisplayMode, modeStr);
  }
}
