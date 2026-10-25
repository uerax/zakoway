import 'package:flutter/material.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/core/services/bangumi_oped_service.dart';
import 'package:zakoway/core/utils/font_manager.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/controller/playback_state.dart';
import 'package:zakoway/features/player/services/player_preferences_service.dart';
import '../../desktop/desktop_shortcut_help_dialog.dart';
import '../super_resolution_dialog_helper.dart';
import 'player_panel_widgets.dart';

/// 播放器设置面板主体（连播与跳过、播放速度、超分辨率 Anime4K、画幅比例、屏幕亮度）
class PlayerSettingsPanelBody extends StatelessWidget {
  const PlayerSettingsPanelBody({
    super.key,
    required this.controller,
    required this.primaryColor,
    required this.autoSkipOpedNotifier,
    this.autoPlayNextNotifier,
    this.brightnessNotifier,
    this.opedSegment,
    this.isCurrentlyInOp = false,
    this.isCurrentlyInEd = false,
    this.onSkipCurrentSegment,
    this.onDismiss,
    this.onTriggerSkipToast,
  });

  final ZakowayPlaybackController controller;
  final Color primaryColor;
  final ValueNotifier<bool> autoSkipOpedNotifier;
  final ValueNotifier<bool>? autoPlayNextNotifier;
  final ValueNotifier<double>? brightnessNotifier;
  final EpisodeOpedSegment? opedSegment;
  final bool isCurrentlyInOp;
  final bool isCurrentlyInEd;
  final VoidCallback? onSkipCurrentSegment;
  final VoidCallback? onDismiss;
  final ValueChanged<String>? onTriggerSkipToast;

  static String _formatSeconds(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final seg = opedSegment;
    String opedSubtitle = '未配置片头片尾时间戳';
    if (seg != null && (seg.hasOp || seg.hasEd)) {
      final List<String> parts = [];
      if (seg.hasOp) {
        parts.add('OP ${_formatSeconds(seg.opStart!)}-${_formatSeconds(seg.opEnd!)}');
      }
      if (seg.hasEd) {
        parts.add('ED ${_formatSeconds(seg.edStart!)}-${_formatSeconds(seg.edEnd!)}');
      }
      opedSubtitle = parts.join(' · ');
    }

    final isInside = isCurrentlyInOp || isCurrentlyInEd;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. 播放连播与片头片尾跳过
          const PanelSectionHeader(title: '连播与跳过'),
          if (autoPlayNextNotifier != null) ...[
            ValueListenableBuilder<bool>(
              valueListenable: autoPlayNextNotifier!,
              builder: (context, autoPlayNext, _) {
                return PanelSwitchRow(
                  title: '自动播放下一集',
                  subtitle: '当前集播放完毕后自动切换至下一集',
                  value: autoPlayNext,
                  primaryColor: primaryColor,
                  onChanged: (val) {
                    autoPlayNextNotifier!.value = val;
                    PlayerPreferencesService.instance.saveAutoPlayNext(val);
                    onTriggerSkipToast?.call(val ? '已开启自动播放下一集' : '已关闭自动播放下一集');
                  },
                );
              },
            ),
            const SizedBox(height: 6),
          ],
          ValueListenableBuilder<bool>(
            valueListenable: autoSkipOpedNotifier,
            builder: (context, autoSkip, _) {
              return PanelSwitchRow(
                title: '自动跳过片头片尾',
                subtitle: opedSubtitle,
                value: autoSkip,
                primaryColor: primaryColor,
                onChanged: (val) {
                  autoSkipOpedNotifier.value = val;
                  onTriggerSkipToast?.call(val ? '已开启自动跳过片头片尾' : '已关闭自动跳过片头片尾');
                },
              );
            },
          ),
          if (isInside) ...[
            const SizedBox(height: 4),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber.withValues(alpha: 0.22),
                foregroundColor: Colors.amber,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: const BorderSide(color: Colors.amber, width: 0.5),
                ),
                padding: const EdgeInsets.symmetric(vertical: 6),
              ),
              icon: const Icon(Icons.fast_forward_rounded, size: 15),
              label: Text(
                isCurrentlyInOp ? '立即跳过片头' : '立即跳过片尾',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              onPressed: () {
                onSkipCurrentSegment?.call();
                onDismiss?.call();
              },
            ),
          ],

          const SizedBox(height: 10),

          // 网络与解析代理模式快速切换
          const PanelSectionHeader(title: '网络与解析'),
          ValueListenableBuilder<bool>(
            valueListenable: AppPreferences.serverModeNotifier,
            builder: (context, serverMode, _) {
              return PanelSwitchRow(
                title: 'Animaku 服务端模式',
                subtitle: serverMode ? '已开启服务端中继代理，加速受限源' : '当前为本地直连，受限源可开启代理',
                value: serverMode,
                primaryColor: primaryColor,
                onChanged: (val) {
                  AppPreferences.setServerModeEnabled(val);
                  onTriggerSkipToast?.call(val ? '已开启 Animaku 服务端模式' : '已切换为本地直连模式');
                },
              );
            },
          ),
          const SizedBox(height: 6),
          ValueListenableBuilder<bool>(
            valueListenable: AppPreferences.preferWebviewSniffNotifier,
            builder: (context, preferWebview, _) {
              return PanelSwitchRow(
                title: '强兼容模式',
                subtitle: '暂不可开启 (维护重构中)',
                value: false,
                primaryColor: primaryColor,
                onChanged: null,
              );
            },
          ),

          const SizedBox(height: 10),

          // 2. 播放速度
          const PanelSectionHeader(title: '播放速度'),
          ValueListenableBuilder<PlaybackCoreState>(
            valueListenable: controller.core,
            builder: (context, coreState, _) {
              final cur = coreState.playbackRate;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    for (final speed in const [0.75, 1.0, 1.25, 1.5, 2.0])
                      PanelOptionChip(
                        label: '${speed}x',
                        selected: (cur - speed).abs() < 0.01,
                        primaryColor: primaryColor,
                        onTap: () => controller.setPlaybackRate(speed),
                      ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 10),

          // 3. 动漫超分辨率 Anime4K
          const PanelSectionHeader(title: '动漫超分辨率 (Anime4K)'),
          ValueListenableBuilder<PlaybackCoreState>(
            valueListenable: controller.core,
            builder: (context, coreState, _) {
              final cur = coreState.superResolution;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    PanelOptionChip(
                      label: '关闭',
                      selected: cur == SuperResolutionMode.off,
                      primaryColor: primaryColor,
                      onTap: () => SuperResolutionDialogHelper.handleModeSelection(
                        context: context,
                        controller: controller,
                        mode: SuperResolutionMode.off,
                      ),
                    ),
                    PanelOptionChip(
                      label: '效率档',
                      selected: cur == SuperResolutionMode.efficiency,
                      primaryColor: primaryColor,
                      onTap: () => SuperResolutionDialogHelper.handleModeSelection(
                        context: context,
                        controller: controller,
                        mode: SuperResolutionMode.efficiency,
                      ),
                    ),
                    PanelOptionChip(
                      label: '质量档',
                      selected: cur == SuperResolutionMode.quality,
                      primaryColor: primaryColor,
                      onTap: () => SuperResolutionDialogHelper.handleModeSelection(
                        context: context,
                        controller: controller,
                        mode: SuperResolutionMode.quality,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 10),

          // 4. 画面画幅比例
          const PanelSectionHeader(title: '画面填充比例'),
          ValueListenableBuilder<PlaybackCoreState>(
            valueListenable: controller.core,
            builder: (context, coreState, _) {
              final cur = coreState.videoFit;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    PanelOptionChip(
                      label: '默认(16:9)',
                      selected: cur == BoxFit.contain,
                      primaryColor: primaryColor,
                      onTap: () => controller.setVideoFit(BoxFit.contain),
                    ),
                    PanelOptionChip(
                      label: '铺满裁剪',
                      selected: cur == BoxFit.cover,
                      primaryColor: primaryColor,
                      onTap: () => controller.setVideoFit(BoxFit.cover),
                    ),
                    PanelOptionChip(
                      label: '全屏拉伸',
                      selected: cur == BoxFit.fill,
                      primaryColor: primaryColor,
                      onTap: () => controller.setVideoFit(BoxFit.fill),
                    ),
                  ],
                ),
              );
            },
          ),

          // 5. 屏幕亮度调节
          if (brightnessNotifier != null) ...[
            const SizedBox(height: 10),
            const PanelSectionHeader(title: '屏幕亮度'),
            ValueListenableBuilder<double>(
              valueListenable: brightnessNotifier!,
              builder: (context, brightness, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PanelSliderRow(
                      title: '亮度调节',
                      valText: '${(brightness * 100).round()}%',
                      value: brightness,
                      min: 0.05,
                      max: 1.0,
                      primaryColor: primaryColor,
                      onChanged: (val) => brightnessNotifier!.value = val,
                    ),
                    const SizedBox(height: 2),
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          PanelOptionChip(
                            label: '暗室 (30%)',
                            selected: (brightness - 0.3).abs() < 0.05,
                            primaryColor: primaryColor,
                            onTap: () => brightnessNotifier!.value = 0.3,
                          ),
                          PanelOptionChip(
                            label: '柔和 (70%)',
                            selected: (brightness - 0.7).abs() < 0.05,
                            primaryColor: primaryColor,
                            onTap: () => brightnessNotifier!.value = 0.7,
                          ),
                          PanelOptionChip(
                            label: '标准 (100%)',
                            selected: brightness >= 0.98,
                            primaryColor: primaryColor,
                            onTap: () => brightnessNotifier!.value = 1.0,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ],

          // 6. 控制栏图标大小（手机端保持紧凑，Windows桌面和平板可单独调整或跟随自适应）
          const SizedBox(height: 10),
          const PanelSectionHeader(title: '控制栏图标大小'),
          ListenableBuilder(
            listenable: PlayerPreferencesService.instance,
            builder: (context, _) {
              final cur = PlayerPreferencesService.instance.controlBarScale;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    PanelOptionChip(
                      label: '自适应',
                      selected: cur == PlayerControlBarScale.auto,
                      primaryColor: primaryColor,
                      onTap: () {
                        PlayerPreferencesService.instance
                            .saveControlBarScale(PlayerControlBarScale.auto);
                        onTriggerSkipToast?.call('控制栏大小：跟随设备自适应');
                      },
                    ),
                    PanelOptionChip(
                      label: '紧凑',
                      selected: cur == PlayerControlBarScale.compact,
                      primaryColor: primaryColor,
                      onTap: () {
                        PlayerPreferencesService.instance
                            .saveControlBarScale(PlayerControlBarScale.compact);
                        onTriggerSkipToast?.call('控制栏大小：紧凑小号');
                      },
                    ),
                    PanelOptionChip(
                      label: '标准',
                      selected: cur == PlayerControlBarScale.standard,
                      primaryColor: primaryColor,
                      onTap: () {
                        PlayerPreferencesService.instance
                            .saveControlBarScale(PlayerControlBarScale.standard);
                        onTriggerSkipToast?.call('控制栏大小：舒适标准');
                      },
                    ),
                    PanelOptionChip(
                      label: '大号',
                      selected: cur == PlayerControlBarScale.large,
                      primaryColor: primaryColor,
                      onTap: () {
                        PlayerPreferencesService.instance
                            .saveControlBarScale(PlayerControlBarScale.large);
                        onTriggerSkipToast?.call('控制栏大小：醒目大号');
                      },
                    ),
                  ],
                ),
              );
            },
          ),

          // 7. 快捷键指南
          const SizedBox(height: 10),
          const PanelSectionHeader(title: '快捷键'),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => DesktopShortcutHelpDialog.show(context),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.keyboard_outlined, size: 16, color: primaryColor),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '快捷键指南',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'MiSans',
                        fontFamilyFallback: FontManager.fallbackFontFamilies,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, size: 16, color: Colors.white54),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
