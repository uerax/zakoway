import 'package:flutter/material.dart';
import '../../../../core/utils/font_manager.dart';
import '../../controller/playback_controller.dart';
import '../../controller/playback_state.dart';
import '../../services/player_preferences_service.dart';

/// 动漫超分辨率质量档确认弹窗与切换协同辅助类
class SuperResolutionDialogHelper {
  SuperResolutionDialogHelper._();

  /// 弹出质量档性能防卡顿确认弹窗（严格遵循项目 Windows 字体防宋体规范）
  static Future<bool> showQualityConfirmationDialog(BuildContext context) async {
    final fontMgr = FontManager.instance;
    final activeFont = fontMgr.activeFontFamily;
    final fontFallback = FontManager.fallbackFontFamilies;

    bool confirmed = false;
    bool dontAskAgain = false;

    await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        final theme = Theme.of(dialogCtx);
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Text(
                '性能提示',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  fontFamily: activeFont,
                  fontFamilyFallback: fontFallback,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '启用超分辨率（质量档）会使用高负载卷积神经网络着色器，在部分低配设备上可能会造成发热或掉帧卡顿，是否继续？',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: theme.colorScheme.onSurface,
                      fontFamily: activeFont,
                      fontFamilyFallback: fontFallback,
                    ),
                  ),
                  const SizedBox(height: 16),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => dontAskAgain = !dontAskAgain),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Checkbox(
                            value: dontAskAgain,
                            onChanged: (v) => setState(() => dontAskAgain = v ?? false),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '下次不再询问',
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: activeFont,
                              fontFamilyFallback: fontFallback,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(false),
                  child: Text(
                    '取消',
                    style: TextStyle(
                      fontFamily: activeFont,
                      fontFamilyFallback: fontFallback,
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () {
                    confirmed = true;
                    Navigator.of(dialogCtx).pop(true);
                  },
                  child: Text(
                    '确认开启',
                    style: TextStyle(
                      fontFamily: activeFont,
                      fontFamilyFallback: fontFallback,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (dontAskAgain) {
      await PlayerPreferencesService.instance.saveDisableSuperResolutionWarning(true);
    }

    return confirmed;
  }

  /// 统一调度超分辨率档位切换（直接切换，不弹告警提示干扰观影）
  static Future<void> handleModeSelection({
    required BuildContext context,
    required ZakowayPlaybackController controller,
    required SuperResolutionMode mode,
  }) async {
    await controller.setSuperResolution(mode);
  }
}
