import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'app_preferences.dart';

/// Android 平台屏幕刷新率调度服务（对齐 Kazumi 架构实现）：
/// 负责在应用启动时恢复用户的屏幕刷新率偏好（默认 auto），
/// 并提供动态查询与切换物理显示模式（60Hz/90Hz/120Hz/144Hz 等）的能力。
class DisplayModeService {
  DisplayModeService._();

  static final ValueNotifier<DisplayMode?> preferredModeNotifier =
      ValueNotifier<DisplayMode?>(null);

  /// 初始化屏幕刷新率配置，对齐 Kazumi 逻辑：
  /// 默认采用 DisplayMode.auto，若本地存储有选定的模式，则匹配并应用
  static Future<void> initialize() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final modes = await FlutterDisplayMode.supported;
      final savedDisplay = AppPreferences.getDisplayMode();
      DisplayMode selectedMode = DisplayMode.auto;
      if (savedDisplay != null && savedDisplay.isNotEmpty) {
        selectedMode = modes.firstWhere(
          (e) => e.toString() == savedDisplay,
          orElse: () => DisplayMode.auto,
        );
      }
      final preferred = modes.firstWhere(
        (el) => el == selectedMode,
        orElse: () => DisplayMode.auto,
      );
      await FlutterDisplayMode.setPreferredMode(preferred);
      preferredModeNotifier.value = preferred;
    } catch (e) {
      debugPrint('DisplayModeService: 初始化屏幕显示模式失败: $e');
    }
  }

  /// 设置并持久化偏好的显示模式
  static Future<void> setPreferredMode(DisplayMode mode) async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      await FlutterDisplayMode.setPreferredMode(mode);
      await AppPreferences.saveDisplayMode(mode.toString());
      preferredModeNotifier.value = mode;
    } catch (e) {
      debugPrint('DisplayModeService: 设置屏幕显示模式失败: $e');
    }
  }

  /// 获取设备硬件支持的全部显示模式列表
  static Future<List<DisplayMode>> getSupportedModes() async {
    if (kIsWeb || !Platform.isAndroid) return const [];
    try {
      return await FlutterDisplayMode.supported;
    } catch (e) {
      debugPrint('DisplayModeService: 获取支持模式失败: $e');
      return const [];
    }
  }

  /// 获取当前系统实际正在激活生效的显示模式
  static Future<DisplayMode?> getActiveMode() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      return await FlutterDisplayMode.active;
    } catch (e) {
      return null;
    }
  }

  /// 获取当前已请求偏好的显示模式
  static Future<DisplayMode?> getPreferredMode() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      return await FlutterDisplayMode.preferred;
    } catch (e) {
      return null;
    }
  }
}
