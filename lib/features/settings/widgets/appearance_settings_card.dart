import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'display_mode_tile.dart';
import 'm3_settings_card.dart';
import 'theme_color_tile.dart';
import 'wallpaper_settings_tile.dart';

class AppearanceSettingsCard extends StatelessWidget {
  const AppearanceSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isAndroid = !kIsWeb && Platform.isAndroid;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const M3SettingsSectionHeader(title: '个性化外观'),
        M3SettingsCard(
          footerText: isAndroid
              ? '支持自定义主题强调色、Android 屏幕高刷调度及分页面独立壁纸。'
              : '支持对首页、分类与设置页单独覆盖立绘壁纸与裁剪视野。',
          children: [
            const ThemeColorTile(),
            if (isAndroid) const DisplayModeTile(),
            const WallpaperSettingsTile(),
          ],
        ),
      ],
    );
  }
}
