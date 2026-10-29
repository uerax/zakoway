import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/update/app_version_info.dart';
import '../../../core/services/update_manager.dart';
import '../../../core/services/update_service.dart';
import '../../../core/utils/font_manager.dart';
import 'update_prefix_dialog.dart';

/// 跨平台 M3 风格应用更新模态弹窗（严格遵循字体安全规范，支持 Beta 标识与 SHA-256 安全指示）
class AppUpdateDialog extends StatefulWidget {
  final AppVersionInfo versionInfo;

  const AppUpdateDialog({
    super.key,
    required this.versionInfo,
  });

  static Future<void> show(BuildContext context, AppVersionInfo versionInfo) {
    return showDialog<void>(
      context: context,
      barrierDismissible: !versionInfo.isForceUpdate,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (context) => AppUpdateDialog(versionInfo: versionInfo),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  final UpdateManager _updateMgr = UpdateManager.instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final isBeta = widget.versionInfo.isPrerelease;
    final channelBadgeColor =
        isBeta ? const Color(0xFFFF9500) : primaryColor;

    final asset = widget.versionInfo.getAssetForCurrentPlatform();
    final effectiveUrl = asset?.getEffectiveUrl(_updateMgr.downloadPrefix) ??
        AppConstants.projectReleasesUrl;

    return PopScope(
      canPop: !widget.versionInfo.isForceUpdate,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Container(
                width: 460,
                constraints: const BoxConstraints(maxHeight: 620),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xF21C1C24)
                      : Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.2),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: ListenableBuilder(
                    listenable: _updateMgr,
                    builder: (context, _) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 顶部图标与标题徽章
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: channelBadgeColor
                                        .withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    isBeta
                                        ? Icons.science_rounded
                                        : Icons.rocket_launch_rounded,
                                    color: channelBadgeColor,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            isBeta ? '发现新测试版' : '发现新版本',
                                            style: appTextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: channelBadgeColor,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'v${widget.versionInfo.version}',
                                              style: appTextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        widget.versionInfo.title,
                                        style: appTextStyle(
                                          fontSize: 13,
                                          color: theme
                                              .colorScheme.onSurfaceVariant
                                              .withValues(alpha: 0.8),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // 版本元数据标签条（通道类型 / 发布日期 / 安装包大小 / SHA-256 安全验证 / 加速状态）
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (isBeta)
                                  _buildTag(
                                    context,
                                    icon: Icons.science_outlined,
                                    label: 'Beta 尝鲜',
                                    color: const Color(0xFFFF9500),
                                  ),
                                if (widget.versionInfo.releaseDate.isNotEmpty)
                                  _buildTag(
                                    context,
                                    icon: Icons.calendar_today_outlined,
                                    label: widget.versionInfo.releaseDate,
                                  ),
                                if (asset != null && asset.formattedSize.isNotEmpty)
                                  _buildTag(
                                    context,
                                    icon: Icons.folder_zip_outlined,
                                    label: asset.formattedSize,
                                  ),
                                if (asset != null && asset.sha256.isNotEmpty)
                                  _buildTag(
                                    context,
                                    icon: Icons.verified_user_outlined,
                                    label: 'SHA-256 校验',
                                    color: const Color(0xFF34C759),
                                  ),
                                GestureDetector(
                                  onTap: () {
                                    UpdatePrefixDialog.show(context);
                                  },
                                  child: _buildTag(
                                    context,
                                    icon: Icons.speed_rounded,
                                    label: _updateMgr.downloadPrefix.isNotEmpty
                                        ? '已启用加速'
                                        : '直连(点此配置加速)',
                                    color: _updateMgr.downloadPrefix.isNotEmpty
                                        ? Colors.teal
                                        : null,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 14),

                            // 更新日志文本卡片
                            Flexible(
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.black.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.05),
                                    width: 0.5,
                                  ),
                                ),
                                child: SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '更新内容：',
                                        style: appTextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        widget.versionInfo.changelog.isNotEmpty
                                            ? widget.versionInfo.changelog
                                            : '日常维护与体验优化',
                                        style: appTextStyle(
                                          fontSize: 13,
                                          height: 1.5,
                                          color: isDark
                                              ? Colors.white.withValues(alpha: 0.9)
                                              : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // 下载中进度条与状态展示
                            if (_updateMgr.status == UpdateStatus.downloading) ...[
                              const SizedBox(height: 16),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '正在下载更新包并执行安全校验...',
                                    style: appTextStyle(
                                      fontSize: 12.5,
                                      color: primaryColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${(_updateMgr.downloadProgress * 100).toStringAsFixed(1)}%',
                                    style: appTextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: primaryColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicator(
                                  value: _updateMgr.downloadProgress,
                                  minHeight: 6,
                                  backgroundColor:
                                      primaryColor.withValues(alpha: 0.15),
                                  valueColor:
                                      AlwaysStoppedAnimation(primaryColor),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_formatBytes(_updateMgr.receivedBytes)} / ${_formatBytes(_updateMgr.totalBytes)}',
                                style: appTextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.65),
                                ),
                              ),
                            ],

                            // 错误提示
                            if (_updateMgr.status == UpdateStatus.failed &&
                                _updateMgr.errorMessage != null) ...[
                              const SizedBox(height: 10),
                              Text(
                                _updateMgr.errorMessage!,
                                style: appTextStyle(
                                  fontSize: 12,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ],

                            const SizedBox(height: 20),

                            // 底部操作按钮区域
                            _buildActionButtons(context, asset, effectiveUrl),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTag(
    BuildContext context, {
    required IconData icon,
    required String label,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveColor = color ?? theme.colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: effectiveColor.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: effectiveColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: appTextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    AppDownloadAsset? asset,
    String effectiveUrl,
  ) {
    final theme = Theme.of(context);
    final status = _updateMgr.status;

    // iOS 平台引导至浏览器下载/更新
    if (!kIsWeb && Platform.isIOS) {
      return Row(
        children: [
          if (!widget.versionInfo.isForceUpdate)
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  '稍后再说',
                  style: appTextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: () {
                UpdateService.instance.launchInBrowser(effectiveUrl);
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.open_in_browser_rounded, size: 18),
              label: Text(
                '前往 Safari 更新',
                style: appTextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      );
    }

    // 下载中状态：展示取消下载
    if (status == UpdateStatus.downloading) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => _updateMgr.cancelDownload(),
          child: Text(
            '取消下载',
            style: appTextStyle(fontSize: 14, color: Colors.redAccent),
          ),
        ),
      );
    }

    // 下载完成待安装状态
    if (status == UpdateStatus.readyToInstall) {
      return Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                '稍后安装',
                style: appTextStyle(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              onPressed: () => _updateMgr.installOrOpen(),
              icon: const Icon(Icons.system_update_alt_rounded, size: 18),
              label: Text(
                Platform.isAndroid ? '立即安装' : '打开安装文件',
                style: appTextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      );
    }

    // 默认展示立即更新与浏览器下载
    return Row(
      children: [
        if (!widget.versionInfo.isForceUpdate) ...[
          TextButton(
            onPressed: () {
              _updateMgr.ignoreCurrentUpdate();
              Navigator.of(context).pop();
            },
            child: Text(
              '忽略本次',
              style: appTextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ),
          const Spacer(),
        ],
        IconButton(
          tooltip: '浏览器直接下载',
          icon: const Icon(Icons.open_in_browser_rounded, size: 20),
          onPressed: () {
            UpdateService.instance.launchInBrowser(effectiveUrl);
          },
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: asset != null
              ? () => _updateMgr.startDownload(asset)
              : () => UpdateService.instance.launchInBrowser(effectiveUrl),
          child: Text(
            '立即更新',
            style: appTextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
