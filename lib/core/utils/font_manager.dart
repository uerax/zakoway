import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import '../services/app_preferences.dart';

/// 全局字体安全排版构建函数：
/// 1. 自动注入当前活跃字体（自定义字体 / 系统默认 / MiSans）；
/// 2. 自动注入全平台字体安全回退链（防止 Windows DirectWrite 跌入中易宋体）；
/// 3. 收敛样板代码，杜绝手动拼接 fontFamily 与 fontFamilyFallback。
TextStyle appTextStyle({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? height,
  double? letterSpacing,
  double? wordSpacing,
  List<FontFeature>? fontFeatures,
  List<Shadow>? shadows,
  TextDecoration? decoration,
  Color? decorationColor,
  TextOverflow? overflow,
  Paint? background,
  Paint? foreground,
}) {
  return TextStyle(
    fontFamily: FontManager.instance.activeFontFamily ?? 'MiSans',
    fontFamilyFallback: FontManager.fallbackFontFamilies,
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    wordSpacing: wordSpacing,
    fontFeatures: fontFeatures,
    shadows: shadows,
    decoration: decoration,
    decorationColor: decorationColor,
    overflow: overflow,
    background: background,
    foreground: foreground,
  );
}

enum AppFontType {
  misans('MiSans', 'MiSans'),
  system('Microsoft YaHei', '系统默认'),
  custom('CustomFont', '自定义导入字体');

  final String fontFamily;
  final String label;

  const AppFontType(this.fontFamily, this.label);
}

/// 全局字体管理器：
/// 1. 默认内置使用小米字体 (MiSans)；
/// 2. 支持切回系统默认无衬线字体（Windows 采用微软雅黑，规避回退至中易宋体）；
/// 3. 支持在运行时通过 FontLoader 动态载入用户上传的本地 .ttf / .otf 字体文件，免重启即时全局生效；
/// 4. 接入 AppPreferences 实现字体偏好与自定义字体路径落盘持久化。
class FontManager extends ChangeNotifier {
  static final FontManager instance = FontManager._internal();

  FontManager._internal();

  static const List<String> fallbackFontFamilies = [
    'Microsoft YaHei UI',
    'Microsoft YaHei',
    '微软雅黑',
    'Segoe UI Variable Text',
    'Segoe UI',
    'PingFang SC',
    'Noto Sans SC',
    'sans-serif',
  ];

  AppFontType _currentType = AppFontType.misans;
  String? _customFontPath;
  String _customFontName = '未选择文件';

  AppFontType get currentType => _currentType;
  String? get customFontPath => _customFontPath;
  String get customFontName => _customFontName;

  /// 当前生效的全局 fontFamily 标识符
  String? get activeFontFamily {
    switch (_currentType) {
      case AppFontType.misans:
        return AppFontType.misans.fontFamily;
      case AppFontType.system:
        if (kIsWeb) return 'sans-serif';
        if (defaultTargetPlatform == TargetPlatform.windows) {
          return 'Microsoft YaHei UI';
        } else if (defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.iOS) {
          return 'PingFang SC';
        }
        return 'Noto Sans SC';
      case AppFontType.custom:
        return AppFontType.custom.fontFamily;
    }
  }

  /// 切换字体类型
  void setFontType(AppFontType type) {
    if (_currentType == type) return;
    _currentType = type;
    AppPreferences.saveFontType(type);
    notifyListeners();
  }

  /// 从本地文件动态热加载字体
  Future<bool> loadFontFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final bytes = await file.readAsBytes();
      final fontLoader = FontLoader(AppFontType.custom.fontFamily);
      fontLoader.addFont(Future.value(ByteData.view(bytes.buffer)));
      await fontLoader.load();

      _customFontPath = filePath;
      _customFontName = file.uri.pathSegments.last;
      _currentType = AppFontType.custom;
      AppPreferences.saveCustomFont(path: filePath, name: _customFontName);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('加载自定义字体失败: $e');
      return false;
    }
  }

  /// 移除已导入的自定义字体并自动切回默认推荐字体
  void clearCustomFont() {
    _customFontPath = null;
    _customFontName = '未选择文件';
    if (_currentType == AppFontType.custom) {
      _currentType = AppFontType.misans;
    }
    AppPreferences.clearCustomFont();
    AppPreferences.saveFontType(_currentType);
    notifyListeners();
  }
}
