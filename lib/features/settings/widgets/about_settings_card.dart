import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/update_manager.dart';
import '../../../core/services/update_service.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/font_manager.dart';
import 'app_update_dialog.dart';
import 'm3_settings_card.dart';
import 'update_prefix_dialog.dart';

/// 设置页 - 关于应用分组卡片：
/// 1. 版本号（集成当前版本与更新检测，右侧红点指示新版本）；
/// 2. 加入测试计划（Beta 通道开关）；
/// 3. 下载加速镜像配置；
/// 4. 开源仓库快捷跳转。
class AboutSettingsCard extends StatefulWidget {
  const AboutSettingsCard({super.key});

  @override
  State<AboutSettingsCard> createState() => _AboutSettingsCardState();
}

class _AboutSettingsCardState extends State<AboutSettingsCard> {
  final UpdateManager _updateMgr = UpdateManager.instance;

  @override
  void initState() {
    super.initState();
    // 首次进入关于界面时触发一次静默检测（非强提示）
    if (_updateMgr.status == UpdateStatus.idle) {
      _updateMgr.checkUpdate(isManual: false);
    }
  }

  Future<void> _handleCheckUpdate(BuildContext context) async {
    if (_updateMgr.status == UpdateStatus.checking) return;

    // 若已经处于有更新或就绪状态，点击直接弹出更新对话框
    final hasUpdate = (_updateMgr.status == UpdateStatus.updateAvailable ||
            _updateMgr.status == UpdateStatus.readyToInstall ||
            _updateMgr.status == UpdateStatus.downloading) &&
        _updateMgr.latestVersion != null &&
        _updateMgr.latestVersion!.hasUpdate;

    if (hasUpdate) {
      AppUpdateDialog.show(context, _updateMgr.latestVersion!);
      return;
    }

    final newVer = await _updateMgr.checkUpdate(isManual: true);
    if (!context.mounted) return;

    if (newVer != null && newVer.hasUpdate) {
      AppUpdateDialog.show(context, newVer);
    } else if (_updateMgr.status == UpdateStatus.upToDate) {
      AppToast.success(
        '当前已是最新版本 (v${AppConstants.appVersion})',
        context: context,
      );
    } else if (_updateMgr.status == UpdateStatus.failed) {
      AppToast.error(
        _updateMgr.errorMessage ?? '检查更新失败，请检查网络或加速配置',
        context: context,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const M3SettingsSectionHeader(title: '关于应用'),
        ListenableBuilder(
          listenable: _updateMgr,
          builder: (context, _) {
            final prefix = _updateMgr.downloadPrefix;
            final isBeta = _updateMgr.includeBetaChannel;
            final hasUpdate = (_updateMgr.status == UpdateStatus.updateAvailable ||
                    _updateMgr.status == UpdateStatus.readyToInstall) ||
                (_updateMgr.latestVersion != null &&
                    _updateMgr.latestVersion!.hasUpdate);

            return M3SettingsCard(
              footerText: 'Zakoway - 跨平台动漫流媒体播放与番剧追踪客户端',
              children: [
                // 1. 版本号（右侧形态 1：版本号 + 红点指示 + 箭头，点击检测更新，无转圈动画）
                M3SettingsTile(
                  leading: const M3SettingsIconBox(
                    icon: Icons.info_outline_rounded,
                    bg: Color(0xFF8E8E93),
                  ),
                  title: '版本号',
                  trailing: _buildVersionTrailing(
                    context,
                    primaryColor,
                    hasUpdate,
                  ),
                  onTap: () => _handleCheckUpdate(context),
                  showDivider: true,
                ),

                // 2. 加入测试计划 (Beta / 尝鲜通道)
                M3SettingsTile(
                  leading: const M3SettingsIconBox(
                    icon: Icons.science_rounded,
                    bg: Color(0xFFFF9500),
                  ),
                  title: '加入测试计划',
                  trailing: Switch.adaptive(
                    value: isBeta,
                    activeTrackColor: primaryColor,
                    onChanged: (val) {
                      _updateMgr.setIncludeBetaChannel(val);
                    },
                  ),
                  showDivider: true,
                ),

                // 3. 下载加速镜像配置
                M3SettingsTile(
                  leading: const M3SettingsIconBox(
                    icon: Icons.speed_rounded,
                    bg: Color(0xFF5856D6),
                  ),
                  title: '下载加速镜像',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        prefix.isEmpty ? '去配置' : '修改',
                        style: appTextStyle(
                          fontSize: 13,
                          color: prefix.isEmpty
                              ? theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7)
                              : primaryColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                  onTap: () => UpdatePrefixDialog.show(context),
                  showDivider: true,
                ),

                // 4. 开源仓库
                M3SettingsTile(
                  leading: const M3SettingsIconBox(
                    icon: Icons.code_rounded,
                    bg: Color(0xFF24292E),
                  ),
                  title: '开源仓库',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${AppConstants.developerId}/${AppConstants.appName}',
                        style: appTextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.5),
                      ),
                    ],
                  ),
                  onTap: () {
                    UpdateService.instance
                        .launchInBrowser(AppConstants.projectUrl);
                  },
                  showDivider: false,
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildVersionTrailing(
    BuildContext context,
    Color primaryColor,
    bool hasUpdate,
  ) {
    final theme = Theme.of(context);
    final status = _updateMgr.status;

    if (status == UpdateStatus.downloading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${(_updateMgr.downloadProgress * 100).toInt()}% 下载中',
            style: appTextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: primaryColor,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ],
      );
    }

    // 形态 1：当前版本号 + 右侧小红点（检测到新版本时）+ 展开箭头
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'v${AppConstants.appVersion}',
          style: appTextStyle(
            fontSize: 14,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
          ),
        ),
        if (hasUpdate) ...[
          const SizedBox(width: 6),
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFFFF3B30),
              shape: BoxShape.circle,
            ),
          ),
        ],
        const SizedBox(width: 4),
        Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ],
    );
  }
}
