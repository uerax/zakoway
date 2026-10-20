import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/ios_swipe_action_tile.dart';
import 'm3_settings_card.dart';
import 'tg_action_sheet.dart';

class FontSettingsCard extends StatefulWidget {
  const FontSettingsCard({super.key});

  @override
  State<FontSettingsCard> createState() => _FontSettingsCardState();
}

class _FontSettingsCardState extends State<FontSettingsCard> {
  Future<void> _pickAndLoadCustomFont() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf'],
        dialogTitle: '选择字体文件 (.ttf / .otf)',
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final success = await FontManager.instance.loadFontFromFile(path);
        if (!mounted) return;
        if (success) {
          setState(() {});
          AppToast.success('已导入字体：${FontManager.instance.customFontName}', context: context);
        } else {
          AppToast.error('字体解析失败，请检查文件格式', context: context);
        }
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.error('选择字体失败: $e', context: context);
    }
  }

  Future<void> _confirmDeleteCustomFont(FontManager fontMgr) async {
    final confirmed = await TgActionSheet.showDestructive(
      context,
      title: '确定要移除【${fontMgr.customFontName}】吗？字体将恢复为默认 MiSans。',
      destructiveLabel: '移除自定义字体',
    );
    if (confirmed) {
      fontMgr.clearCustomFont();
      if (!mounted) return;
      AppToast.info('已移除自定义字体', context: context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontMgr = FontManager.instance;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const M3SettingsSectionHeader(title: '字体设置'),
        M3SettingsCard(
          footerText: '字体设置全端实时生效，Windows 平台已全量锁定防中易宋体降级保护。',
          children: [
            M3SettingsTile(
              leading: const M3SettingsIconBox(
                icon: Icons.font_download_rounded,
                bg: Color(0xFFAF52DE),
              ),
              title: 'MiSans',
              trailing: fontMgr.currentType == AppFontType.misans
                  ? Icon(Icons.check_rounded, color: theme.colorScheme.primary, size: 20)
                  : null,
              onTap: () => fontMgr.setFontType(AppFontType.misans),
            ),
            M3SettingsTile(
              leading: const M3SettingsIconBox(
                icon: Icons.text_fields_rounded,
                bg: Color(0xFF5856D6),
              ),
              title: '系统默认',
              trailing: fontMgr.currentType == AppFontType.system
                  ? Icon(Icons.check_rounded, color: theme.colorScheme.primary, size: 20)
                  : null,
              onTap: () => fontMgr.setFontType(AppFontType.system),
            ),
            if (fontMgr.customFontPath != null)
              IosSwipeActionTile(
                onDelete: () => _confirmDeleteCustomFont(fontMgr),
                child: M3SettingsTile(
                  leading: const M3SettingsIconBox(
                    icon: Icons.dashboard_customize_rounded,
                    bg: Color(0xFFBF5AF2),
                  ),
                  title: fontMgr.customFontName,
                  trailing: fontMgr.currentType == AppFontType.custom
                      ? Icon(Icons.check_rounded, color: theme.colorScheme.primary, size: 20)
                      : null,
                  onTap: () => fontMgr.setFontType(AppFontType.custom),
                ),
              ),
            M3SettingsTile(
              leading: const M3SettingsIconBox(
                icon: Icons.file_upload_outlined,
                bg: Color(0xFF8E8E93),
              ),
              title: fontMgr.customFontPath != null ? '更换字体文件' : '导入字体文件',
              subtitle: '支持 .ttf / .otf 格式',
              showDivider: false,
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                size: 18,
              ),
              onTap: _pickAndLoadCustomFont,
            ),
          ],
        ),
        const SizedBox(height: 8),
        // 极简字体预览行
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: M3Surface.container(context, level: M3ContainerLevel.lowest, pageKey: 'settings'),
            borderRadius: BorderRadius.circular(12),
            border: M3Surface.border(context, pageKey: 'settings'),
          ),
          child: Row(
            children: [
              Icon(
                Icons.remove_red_eye_outlined,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '预览：10月新番 · 热门排行 · OVA · 剧场版',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
