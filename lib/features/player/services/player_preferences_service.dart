import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../controller/playback_state.dart';
import '../danmaku/models/danmaku_item.dart';

/// 播放器底部控制条尺寸规格偏好
enum PlayerControlBarScale {
  /// 自动适应（手机紧凑小号，Windows 桌面与平板采用舒适标准大号）
  auto,

  /// 紧凑小号（按钮 22，图标 15）
  compact,

  /// 舒适标准（按钮 32，图标 20）
  standard,

  /// 醒目大号（按钮 38，图标 24）
  large;

  static PlayerControlBarScale fromString(String? name) {
    if (name == null) return PlayerControlBarScale.auto;
    return PlayerControlBarScale.values.firstWhere(
      (e) => e.name == name,
      orElse: () => PlayerControlBarScale.auto,
    );
  }
}

/// 播放器用户偏好设置持久化服务
/// 记录上次的播放倍速、音量与弹幕外观偏好，应用重启后保持记忆
class PlayerPreferencesService extends ChangeNotifier {
  PlayerPreferencesService._();
  static final PlayerPreferencesService instance = PlayerPreferencesService._();

  static const String _kPlaybackRateKey = 'zakoway_player_playback_rate';
  static const String _kVolumeKey = 'zakoway_player_volume';
  static const String _kDanmakuSettingsKey = 'zakoway_player_danmaku_settings';
  static const String _kAutoPlayNextKey = 'zakoway_player_auto_play_next';
  static const String _kControlBarScaleKey = 'zakoway_player_control_bar_scale';
  static const String _kSuperResolutionModeKey = 'zakoway_player_super_resolution_mode';
  static const String _kDisableSuperResolutionWarningKey = 'zakoway_player_disable_super_res_warning';
  static const String _kAutoSkipOpedKey = 'zakoway_player_auto_skip_oped';

  double _playbackRate = 1.0;
  double _volume = 0.5;
  DanmakuSettings _danmakuSettings = const DanmakuSettings();
  bool _autoPlayNext = true;
  bool _autoSkipOped = true; // 默认开启
  PlayerControlBarScale _controlBarScale = PlayerControlBarScale.auto;
  SuperResolutionMode _superResolutionMode = SuperResolutionMode.off;
  bool _disableSuperResolutionWarning = false;
  bool _initialized = false;

  double get playbackRate => _playbackRate;
  double get volume => _volume;
  DanmakuSettings get danmakuSettings => _danmakuSettings;
  bool get autoPlayNext => _autoPlayNext;
  bool get autoSkipOped => _autoSkipOped;
  PlayerControlBarScale get controlBarScale => _controlBarScale;
  SuperResolutionMode get superResolutionMode => _superResolutionMode;
  bool get disableSuperResolutionWarning => _disableSuperResolutionWarning;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final sp = await SharedPreferences.getInstance();
      _playbackRate = sp.getDouble(_kPlaybackRateKey) ?? 1.0;
      _volume = sp.getDouble(_kVolumeKey) ?? 0.5;
      _autoPlayNext = sp.getBool(_kAutoPlayNextKey) ?? true;
      _autoSkipOped = sp.getBool(_kAutoSkipOpedKey) ?? true;
      final scaleRaw = sp.getString(_kControlBarScaleKey);
      _controlBarScale = PlayerControlBarScale.fromString(scaleRaw);

      final srVal = sp.getInt(_kSuperResolutionModeKey);
      _superResolutionMode = SuperResolutionMode.fromStorageValue(srVal);
      _disableSuperResolutionWarning = sp.getBool(_kDisableSuperResolutionWarningKey) ?? false;

      final danmakuRaw = sp.getString(_kDanmakuSettingsKey);
      if (danmakuRaw != null && danmakuRaw.isNotEmpty) {
        final decoded = jsonDecode(danmakuRaw);
        if (decoded is Map<String, dynamic>) {
          _danmakuSettings = DanmakuSettings.fromJson(decoded);
        }
      }
    } catch (_) {}
    _initialized = true;
    notifyListeners();
  }

  Future<void> savePlaybackRate(double rate) async {
    if ((_playbackRate - rate).abs() < 0.01) return;
    _playbackRate = rate;
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble(_kPlaybackRateKey, rate);
    } catch (_) {}
  }

  Future<void> saveVolume(double vol) async {
    if ((_volume - vol).abs() < 0.01) return;
    _volume = vol;
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setDouble(_kVolumeKey, vol);
    } catch (_) {}
  }

  Future<void> saveAutoPlayNext(bool val) async {
    if (_autoPlayNext == val) return;
    _autoPlayNext = val;
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kAutoPlayNextKey, val);
    } catch (_) {}
  }

  Future<void> saveControlBarScale(PlayerControlBarScale scale) async {
    if (_controlBarScale == scale) return;
    _controlBarScale = scale;
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_kControlBarScaleKey, scale.name);
    } catch (_) {}
  }

  /// 仅更新内存中的弹幕设置并通知监听者（不阻塞等待 I/O，用于高频防抖配合）
  void updateDanmakuSettingsMemory(DanmakuSettings settings) {
    if (_danmakuSettings == settings) return;
    _danmakuSettings = settings;
    notifyListeners();
  }

  /// 将弹幕设置实际写入本地持久化存储
  Future<void> writeDanmakuSettingsToDisk(DanmakuSettings settings) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final jsonStr = jsonEncode(settings.toJson());
      await sp.setString(_kDanmakuSettingsKey, jsonStr);
    } catch (_) {}
  }

  /// 全量保存弹幕设置：立即更新内存与通知，并持久化写入本地存储
  Future<void> saveDanmakuSettings(DanmakuSettings settings) async {
    updateDanmakuSettingsMemory(settings);
    await writeDanmakuSettingsToDisk(settings);
  }

  Future<void> saveSuperResolutionMode(SuperResolutionMode mode) async {
    if (_superResolutionMode == mode) return;
    _superResolutionMode = mode;
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_kSuperResolutionModeKey, mode.storageValue);
    } catch (_) {}
  }

  Future<void> saveDisableSuperResolutionWarning(bool disabled) async {
    if (_disableSuperResolutionWarning == disabled) return;
    _disableSuperResolutionWarning = disabled;
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kDisableSuperResolutionWarningKey, disabled);
    } catch (_) {}
  }

  /// 保存全局自动跳过片头片尾偏好设置并持久化落盘
  Future<void> saveAutoSkipOped(bool val) async {
    if (_autoSkipOped == val) return;
    _autoSkipOped = val;
    notifyListeners();

    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool(_kAutoSkipOpedKey, val);
    } catch (_) {}
  }

  /// 重置状态（用于测试隔离）
  @visibleForTesting
  void resetForTest() {
    _playbackRate = 1.0;
    _volume = 0.5;
    _danmakuSettings = const DanmakuSettings();
    _autoPlayNext = true;
    _autoSkipOped = true;
    _controlBarScale = PlayerControlBarScale.auto;
    _superResolutionMode = SuperResolutionMode.off;
    _disableSuperResolutionWarning = false;
    _initialized = false;
  }
}
