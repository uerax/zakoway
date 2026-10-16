import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/app_preferences.dart';
import '../theme/app_theme_color.dart';

/// 全局外观与个性化管理器：
/// 1. 管理应用图标（默认内置泡面猫耳 Logo，支持上传自定义图片与一键恢复默认）；
/// 2. 管理全屏背景壁纸（支持“全局一键应用”或“各页面单独设置”多级继承）；
/// 3. 支持壁纸视窗垂直对齐/裁剪定位（AlignmentY: -1.0 偏顶 .. 1.0 偏底，避免二次元插画人物被裁面部）；
/// 4. 支持壁纸不透明度 (Opacity) 与高斯模糊 (Blur) 平滑微调；
/// 5. 管理应用主题色彩（支持预设二次元色彩方案一键无缝全局热切换）；
/// 6. 继承 ChangeNotifier，通过全局 ListenableBuilder 即时响应，免重启生效；
/// 7. 整合 AppPreferences 实现配置全量落盘持久化。
class AppearanceManager extends ChangeNotifier {
  static final AppearanceManager instance = AppearanceManager._internal();

  AppearanceManager._internal();

  static const String defaultLogoAsset = 'assets/images/app_logo.png';

  // 当前全局主题色预设（默认薄荷绿）
  AppThemePreset _currentThemePreset = AppThemePreset.presets.first;

  // 自定义应用图标 / Logo 本地文件路径（null 表示使用内置默认 Logo）
  String? _customIconPath;

  // 全局默认壁纸路径（所有未单独指定壁纸的页面将自动继承它）
  String? _globalWallpaperPath;

  // 各子页面专属壁纸字典：key 为 'home', 'category', 'settings'
  final Map<String, String> _pageWallpapers = {};

  // 壁纸视窗交互式裁剪与平移矩阵参数 (由 WallpaperCropDialog 自由拖拽生成)
  double _wallpaperAlignX = 0.0;
  double _wallpaperAlignY = -0.5;
  double _wallpaperScale = 1.0;

  // 壁纸视觉调节参数
  double _wallpaperOpacity = 0.18;
  double _wallpaperBlur = 1.0;

  AppThemePreset get currentThemePreset => _currentThemePreset;
  Color get primaryColor => _currentThemePreset.color;

  String? get customIconPath => _customIconPath;
  String? get globalWallpaperPath => _globalWallpaperPath;
  Map<String, String> get pageWallpapers => Map.unmodifiable(_pageWallpapers);
  double get wallpaperAlignX => _wallpaperAlignX;
  double get wallpaperAlignY => _wallpaperAlignY;
  double get wallpaperScale => _wallpaperScale;
  double get wallpaperOpacity => _wallpaperOpacity;
  double get wallpaperBlur => _wallpaperBlur;

  bool get hasCustomIcon => _customIconPath != null;

  /// 获取指定页面实际生效的壁纸路径（优先级：页面独立指定 > 全局默认壁纸）
  String? getWallpaperForPage(String? pageKey) {
    if (pageKey != null) {
      if (_pageWallpapers.containsKey(pageKey)) {
        return _pageWallpapers[pageKey];
      }
      // 向前兼容：profile 与旧 settings 作用域互通
      if (pageKey == 'profile' && _pageWallpapers.containsKey('settings')) {
        return _pageWallpapers['settings'];
      }
      if (pageKey == 'settings' && _pageWallpapers.containsKey('profile')) {
        return _pageWallpapers['profile'];
      }
    }
    return _globalWallpaperPath;
  }

  /// 检查某页面是否有壁纸生效（包含继承全局）
  bool hasWallpaperForPage(String? pageKey) {
    return getWallpaperForPage(pageKey) != null;
  }

  /// 检查某页面是否单独设置了专属壁纸（覆盖全局）
  bool isPageOverridden(String pageKey) {
    if (_pageWallpapers.containsKey(pageKey)) return true;
    if (pageKey == 'profile' && _pageWallpapers.containsKey('settings')) return true;
    if (pageKey == 'settings' && _pageWallpapers.containsKey('profile')) return true;
    return false;
  }

  // --- 持久化恢复方法（供 AppPreferences 初始化时调用） ---

  void restoreThemePreset(String presetId, {Color? customColor}) {
    _currentThemePreset = AppThemePreset.findById(presetId, customColor: customColor);
  }

  void restoreCustomIcon(String path) {
    _customIconPath = path;
  }

  void restoreWallpaperConfig({
    String? globalWallpaper,
    Map<String, String>? pageWallpapers,
    double? alignX,
    double? alignY,
    double? scale,
    double? opacity,
    double? blur,
  }) {
    if (globalWallpaper != null) _globalWallpaperPath = globalWallpaper;
    if (pageWallpapers != null) {
      _pageWallpapers.clear();
      _pageWallpapers.addAll(pageWallpapers);
    }
    if (alignX != null) _wallpaperAlignX = alignX;
    if (alignY != null) _wallpaperAlignY = alignY;
    if (scale != null) _wallpaperScale = scale;
    if (opacity != null) _wallpaperOpacity = opacity;
    if (blur != null) _wallpaperBlur = blur;
  }

  // --- 主题颜色相关方法 ---

  /// 设置并持久化全局预设主题色
  void setThemePreset(AppThemePreset preset) {
    if (_currentThemePreset.id == preset.id) return;
    _currentThemePreset = preset;
    AppPreferences.saveThemePreset(preset.id);
    notifyListeners();
  }

  /// 设置并持久化自定义主题色
  void setCustomColor(Color color) {
    _currentThemePreset = AppThemePreset.custom(color);
    AppPreferences.saveThemePreset(AppThemePreset.customId);
    AppPreferences.saveCustomThemeColor(color.toARGB32());
    notifyListeners();
  }

  // --- 应用图标相关方法 ---

  Future<bool> pickAndSetCustomIcon() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: '选择应用图标图片 (.png / .jpg / .webp)',
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final file = File(path);
        if (await file.exists()) {
          _customIconPath = path;
          AppPreferences.saveCustomIcon(path);
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('选择自定义图标失败: $e');
      return false;
    }
  }

  void resetDefaultIcon() {
    if (_customIconPath == null) return;
    _customIconPath = null;
    AppPreferences.saveCustomIcon(null);
    notifyListeners();
  }

  // --- 背景壁纸相关方法 ---

  /// 直接设置已选中的壁纸路径（避免二次唤起 FilePicker）
  void setWallpaperPath(String path, {String? pageKey}) {
    if (pageKey == null || pageKey == 'all') {
      _globalWallpaperPath = path;
    } else {
      _pageWallpapers[pageKey] = path;
    }
    AppPreferences.saveWallpapers(
      globalWallpaper: _globalWallpaperPath,
      pageWallpapers: _pageWallpapers,
    );
    notifyListeners();
  }

  /// 为全局或指定页面选择并设置壁纸（pageKey 为 null 或 'all' 时代表设置全局）
  Future<bool> pickAndSetWallpaper({String? pageKey}) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: '选择壁纸图片 (.png / .jpg / .webp)',
      );

      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final file = File(path);
        if (await file.exists()) {
          if (pageKey == null || pageKey == 'all') {
            _globalWallpaperPath = path;
          } else {
            _pageWallpapers[pageKey] = path;
          }
          AppPreferences.saveWallpapers(
            globalWallpaper: _globalWallpaperPath,
            pageWallpapers: _pageWallpapers,
          );
          notifyListeners();
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('选择自定义壁纸失败: $e');
      return false;
    }
  }

  /// 清除壁纸（若 pageKey 为 'all' 或 null 则清除全局，否则清除对应页面的单独覆盖）
  void clearWallpaper({String? pageKey}) {
    if (pageKey == null || pageKey == 'all') {
      _globalWallpaperPath = null;
    } else {
      _pageWallpapers.remove(pageKey);
    }
    AppPreferences.saveWallpapers(
      globalWallpaper: _globalWallpaperPath,
      pageWallpapers: _pageWallpapers,
    );
    notifyListeners();
  }

  /// 获取指定页面实际生效的壁纸文件对象（不阻塞执行同步 I/O，由图像加载器自身异步处理）
  File? getWallpaperFileForPage(String? pageKey) {
    final path = getWallpaperForPage(pageKey);
    if (path == null) return null;
    return File(path);
  }

  /// 设置壁纸视窗交互式裁剪平移与缩放矩阵
  void setWallpaperTransform({
    required double alignX,
    required double alignY,
    required double scale,
  }) {
    _wallpaperAlignX = alignX.clamp(-1.0, 1.0);
    _wallpaperAlignY = alignY.clamp(-1.0, 1.0);
    _wallpaperScale = scale.clamp(1.0, 3.5);
    AppPreferences.saveWallpaperTransform(
      alignX: _wallpaperAlignX,
      alignY: _wallpaperAlignY,
      scale: _wallpaperScale,
    );
    notifyListeners();
  }

  /// 设置壁纸不透明度 (0.05 ~ 0.60)
  /// [save] 为 false 时仅更新内存并通知监听器，供拖拽交互实时渲染，提升流畅度并规避高频 I/O
  void setWallpaperOpacity(double val, {bool save = true}) {
    _wallpaperOpacity = val.clamp(0.05, 0.60);
    if (save) {
      AppPreferences.saveWallpaperOpacity(_wallpaperOpacity);
    }
    notifyListeners();
  }

  /// 设置壁纸高斯模糊度 (0.0 ~ 20.0)
  /// [save] 为 false 时仅更新内存并通知监听器，供拖拽交互实时渲染，提升流畅度并规避高频 I/O
  void setWallpaperBlur(double val, {bool save = true}) {
    _wallpaperBlur = val.clamp(0.0, 20.0);
    if (save) {
      AppPreferences.saveWallpaperBlur(_wallpaperBlur);
    }
    notifyListeners();
  }

  /// 统一图标构建器：自动依据当前配置渲染圆形或圆角 App Logo
  Widget buildAppLogoWidget({
    double size = 32,
    double borderRadius = 8,
    BoxBorder? border,
  }) {
    Widget imageWidget;
    if (_customIconPath != null) {
      imageWidget = Image.file(
        File(_customIconPath!),
        width: size,
        height: size,
        cacheWidth: (size * 2).toInt(),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Image.asset(
          defaultLogoAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    } else {
      imageWidget = Image.asset(
        defaultLogoAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
      ),
      clipBehavior: Clip.antiAlias,
      child: imageWidget,
    );
  }

  /// 全屏背景壁纸层构建器：
  /// 1. 按页面解析有效壁纸，结合用户在取景框中的 Transform 与 ImageFiltered 滤镜稳定呈现；
  /// 2. 限制 cacheWidth: 1080 进行下采样，杜绝 4K/8K 照片全量解压爆显存；
  /// 3. 包裹 RepaintBoundary 建立独立绘制边界，阻断上层列表滑动触发的重复重绘与重滤波。
  Widget buildWallpaperLayer({String? pageKey}) {
    final wallpaperPath = getWallpaperForPage(pageKey);
    if (wallpaperPath == null) {
      // 特殊处理说明：
      // 在外层 Stack(fit: StackFit.expand) 容器中，非 Positioned 组件会被强制拉伸参与尺寸测算；
      // 显式包裹 Positioned.fill(child: SizedBox.shrink()) 并指定明确 key，
      // 确保无壁纸时始终以明确的零开销定位层占位，彻底杜绝图层切换时的布局测算跳跃或渲染缓存残留。
      return const Positioned.fill(
        key: ValueKey('wallpaper_layer_none'),
        child: SizedBox.shrink(),
      );
    }

    final file = File(wallpaperPath);

    Widget imageWidget = Transform.scale(
      scale: _wallpaperScale,
      alignment: Alignment(_wallpaperAlignX, _wallpaperAlignY),
      child: Image.file(
        file,
        cacheWidth: 1080,
        fit: BoxFit.cover,
        alignment: Alignment(_wallpaperAlignX, _wallpaperAlignY),
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      ),
    );

    if (_wallpaperBlur > 0) {
      imageWidget = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: _wallpaperBlur,
          sigmaY: _wallpaperBlur,
        ),
        child: imageWidget,
      );
    }

    return Positioned.fill(
      key: ValueKey('wallpaper_layer_$wallpaperPath'),
      child: IgnorePointer(
        child: RepaintBoundary(
          child: Opacity(
            opacity: _wallpaperOpacity,
            child: imageWidget,
          ),
        ),
      ),
    );
  }
}
