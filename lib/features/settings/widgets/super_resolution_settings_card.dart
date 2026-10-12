import 'package:flutter/material.dart';
import '../../../core/utils/font_manager.dart';
import '../../player/controller/playback_state.dart';
import '../../player/services/player_preferences_service.dart';
import 'm3_settings_card.dart';

/// 动漫超分辨率 (Anime4K) 设置卡片
class SuperResolutionSettingsCard extends StatefulWidget {
  const SuperResolutionSettingsCard({super.key});

  @override
  State<SuperResolutionSettingsCard> createState() => _SuperResolutionSettingsCardState();
}

class _SuperResolutionSettingsCardState extends State<SuperResolutionSettingsCard> {
  final PlayerPreferencesService _prefs = PlayerPreferencesService.instance;

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  void _showModeSelectSheet() {
    final theme = Theme.of(context);
    final fontMgr = FontManager.instance;
    final activeFont = fontMgr.activeFontFamily;
    final fontFallback = FontManager.fallbackFontFamilies;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Text(
                    '选择默认超分辨率模式',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                      fontFamily: activeFont,
                      fontFamilyFallback: fontFallback,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  child: Text(
                    '超分辨率基于 Anime4K 着色器，播放动漫视频时起播自动应用：',
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: activeFont,
                      fontFamilyFallback: fontFallback,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ...SuperResolutionMode.values.map((mode) {
                  final isSelected = _prefs.superResolutionMode == mode;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    title: Text(
                      mode.label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                        fontFamily: activeFont,
                        fontFamilyFallback: fontFallback,
                      ),
                    ),
                    subtitle: Text(
                      mode.description,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: activeFont,
                        fontFamilyFallback: fontFallback,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                        : null,
                    onTap: () {
                      _prefs.saveSuperResolutionMode(mode);
                      Navigator.of(sheetCtx).pop();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final mode = _prefs.superResolutionMode;
    final disableWarning = _prefs.disableSuperResolutionWarning;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const M3SettingsSectionHeader(title: '画质与超分辨率 (Anime4K)'),
        M3SettingsCard(
          footerText: '超分辨率需要 GPU 硬件解码与 OpenGL/Direct3D 着色器支持。若低端设备出现卡顿掉帧，建议切换为关闭或效率档。',
          children: [
            M3SettingsTile(
              leading: M3SettingsIconBox(
                icon: Icons.auto_awesome_rounded,
                bg: Colors.amber.shade700,
              ),
              title: '默认超分辨率模式',
              subtitle: '${mode.label}（${mode.description}）',
              trailing: const Icon(Icons.chevron_right, size: 20),
              onTap: _showModeSelectSheet,
              showDivider: true,
            ),
            M3SettingsTile(
              leading: M3SettingsIconBox(
                icon: Icons.notifications_off_rounded,
                bg: Colors.indigo.shade500,
              ),
              title: '关闭性能提示',
              subtitle: '关闭每次启用超分辨率（质量档）时的性能警告',
              trailing: Switch(
                value: disableWarning,
                onChanged: (val) {
                  _prefs.saveDisableSuperResolutionWarning(val);
                },
              ),
              showDivider: false,
            ),
          ],
        ),
      ],
    );
  }
}
