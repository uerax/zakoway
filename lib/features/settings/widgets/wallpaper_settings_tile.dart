import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/utils/appearance_manager.dart';
import '../../common/widgets/wallpaper_crop_dialog.dart';
import 'm3_settings_card.dart';
import 'tg_action_sheet.dart';

class WallpaperSettingsTile extends StatefulWidget {
  const WallpaperSettingsTile({super.key});

  @override
  State<WallpaperSettingsTile> createState() => _WallpaperSettingsTileState();
}

class _WallpaperSettingsTileState extends State<WallpaperSettingsTile> {
  String _wallpaperScope = 'all'; // 'all', 'home', 'category'

  Future<void> _pickCustomWallpaper() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: '选择壁纸图片',
      );

      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      if (!await file.exists()) return;
      if (!mounted) return;

      final appMgr = AppearanceManager.instance;
      final cropResult = await WallpaperCropDialog.show(
        context,
        imageFile: file,
        initialAlignX: appMgr.wallpaperAlignX,
        initialAlignY: appMgr.wallpaperAlignY,
        initialScale: appMgr.wallpaperScale,
      );

      if (cropResult == null || !mounted) return;

      appMgr.setWallpaperPath(file.path, pageKey: _wallpaperScope);
      appMgr.setWallpaperTransform(
        alignX: cropResult.alignX,
        alignY: cropResult.alignY,
        scale: cropResult.scale,
      );

      final scopeName = switch (_wallpaperScope) {
        'all' => '全局',
        'home' => '首页',
        'category' => '分类',
        'profile' => '个人',
        _ => '',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已设置【$scopeName】背景壁纸'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('上传壁纸失败: $e');
    }
  }

  Future<void> _reopenCropDialog() async {
    final appMgr = AppearanceManager.instance;
    final file = appMgr.getWallpaperFileForPage(
      _wallpaperScope == 'all' ? null : _wallpaperScope,
    );
    if (file == null || !mounted) return;

    final cropResult = await WallpaperCropDialog.show(
      context,
      imageFile: file,
      initialAlignX: appMgr.wallpaperAlignX,
      initialAlignY: appMgr.wallpaperAlignY,
      initialScale: appMgr.wallpaperScale,
    );

    if (cropResult != null) {
      appMgr.setWallpaperTransform(
        alignX: cropResult.alignX,
        alignY: cropResult.alignY,
        scale: cropResult.scale,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已更新壁纸取景'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmClearWallpaper() async {
    final scopeName = switch (_wallpaperScope) {
      'all' => '全局壁纸',
      'home' => '首页专属壁纸',
      'category' => '分类页专属壁纸',
      'profile' => '个人模块专属壁纸',
      _ => '背景壁纸',
    };

    final confirmed = await TgActionSheet.showDestructive(
      context,
      title: '确定要清除【$scopeName】吗？',
      destructiveLabel: '清除壁纸',
    );
    if (confirmed) {
      _performClearWallpaper(scopeName);
    }
  }

  void _performClearWallpaper(String scopeName) {
    AppearanceManager.instance.clearWallpaper(pageKey: _wallpaperScope);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已清除【$scopeName】'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _hasCurrentScopeWallpaper(AppearanceManager appMgr) {
    if (_wallpaperScope == 'all') {
      return appMgr.globalWallpaperPath != null;
    }
    return appMgr.isPageOverridden(_wallpaperScope);
  }

  Widget _buildWallpaperScopeSelector(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    const scopes = [
      ('all', '全部'),
      ('home', '首页'),
      ('category', '分类'),
      ('profile', '个人'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final isMobile = width < 500;

        final selector = Container(
          height: 32,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(16) : Colors.black.withAlpha(10),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Row(
            mainAxisSize: isMobile ? MainAxisSize.max : MainAxisSize.min,
            children: scopes.map((item) {
              final isSelected = _wallpaperScope == item.$1;
              final button = GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  setState(() {
                    _wallpaperScope = item.$1;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: isMobile ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(100),
                    color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                  ),
                  child: Center(
                    child: Text(
                      item.$2,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                    ),
                  ),
                ),
              );

              if (isMobile) {
                return Expanded(child: button);
              } else {
                return SizedBox(
                  width: 72,
                  child: button,
                );
              }
            }).toList(),
          ),
        );

        if (!isMobile) {
          return Center(
            child: selector,
          );
        }
        return selector;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appMgr = AppearanceManager.instance;

    // 特殊处理说明：
    // 使用 ListenableBuilder 显式直接监听 AppearanceManager 单例：
    // 规避上层卡片树 const 常量构造引发的 Flutter Element update 短路机制，
    // 确保拖拽不透明度/高斯模糊时，Slider Thumb 与数值百分比能实时 60/120fps 重绘刷新。
    return ListenableBuilder(
      listenable: appMgr,
      builder: (context, _) {
        final hasCurrentScopeImg = _hasCurrentScopeWallpaper(appMgr);
        final activeWallpaperFile = hasCurrentScopeImg
            ? appMgr.getWallpaperFileForPage(
                _wallpaperScope == 'all' ? null : _wallpaperScope,
              )
            : null;
        final hasWallpaperImg = activeWallpaperFile != null;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            M3SettingsTile(
              leading: hasWallpaperImg
                  ? Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(7.2),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.5),
                          width: 1.0,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.file(
                        activeWallpaperFile,
                        fit: BoxFit.cover,
                        cacheWidth: 64,
                        errorBuilder: (context, error, stackTrace) => const M3SettingsIconBox(
                          icon: Icons.wallpaper_rounded,
                          bg: Color(0xFF30B0C7),
                        ),
                      ),
                    )
                  : const M3SettingsIconBox(
                      icon: Icons.wallpaper_rounded,
                      bg: Color(0xFF30B0C7),
                    ),
              title: '背景壁纸',
              showDivider: false,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasCurrentScopeImg)
                    Icon(Icons.check_rounded, color: theme.colorScheme.primary, size: 18),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    size: 18,
                  ),
                ],
              ),
              onTap: _pickCustomWallpaper,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildWallpaperScopeSelector(theme),
                  // 特殊处理说明：
                  // 只有当前作用域真正上传了壁纸图片时，才展示取景、清除与参数调节控件，
                  // 与“清除专属壁纸”按钮的触发条件保持完全一致，避免未上传图片时误显调节项。
                  if (hasCurrentScopeImg) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 340),
                        child: SizedBox(
                          height: 36,
                          child: Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 36,
                                  child: FilledButton.tonalIcon(
                                    onPressed: _reopenCropDialog,
                                    icon: const Icon(Icons.crop_free_rounded, size: 16),
                                    label: const Text('调整画面取景', style: TextStyle(fontSize: 12)),
                                    style: FilledButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: OutlinedButton(
                                  onPressed: _confirmClearWallpaper,
                                  style: OutlinedButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    side: BorderSide(color: Colors.redAccent.withAlpha(100)),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '不透明度',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        Text(
                          '${(appMgr.wallpaperOpacity * 100).toInt()}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    // 特殊处理说明：
                    // onChanged 期间 save: false 仅更新内存通知重绘（流畅 60/120fps），
                    // onChangeEnd 释放时 save: true 执行本地 SharedPreferences 落盘，规避高频 I/O 阻塞。
                    Slider(
                      value: appMgr.wallpaperOpacity,
                      min: 0.05,
                      max: 0.60,
                      divisions: 55,
                      onChanged: (val) => appMgr.setWallpaperOpacity(val, save: false),
                      onChangeEnd: (val) => appMgr.setWallpaperOpacity(val, save: true),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '高斯模糊',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                        Text(
                          '${appMgr.wallpaperBlur.toStringAsFixed(1)} px',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.normal,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: appMgr.wallpaperBlur,
                      min: 0.0,
                      max: 20.0,
                      divisions: 40,
                      onChanged: (val) => appMgr.setWallpaperBlur(val, save: false),
                      onChangeEnd: (val) => appMgr.setWallpaperBlur(val, save: true),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
