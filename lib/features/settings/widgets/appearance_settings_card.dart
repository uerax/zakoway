import 'package:flutter/material.dart';
import 'm3_settings_card.dart';
import 'theme_color_tile.dart';
import 'wallpaper_settings_tile.dart';

class AppearanceSettingsCard extends StatelessWidget {
  const AppearanceSettingsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        M3SettingsSectionHeader(title: '个性化外观'),
        M3SettingsCard(
          footerText: '支持对首页、分类与设置页单独覆盖立绘壁纸与裁剪视野。',
          children: [
            ThemeColorTile(),
            WallpaperSettingsTile(),
          ],
        ),
      ],
    );
  }
}
