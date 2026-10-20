import 'package:flutter/material.dart';
import 'package:zakoway/core/utils/app_toast.dart';
import 'package:zakoway/features/player/danmaku/source/dandan_config_manager.dart';
import 'm3_settings_card.dart';
import 'tg_action_sheet.dart';
import 'tg_form_sheet.dart';

/// 弹弹 play 弹幕服务设置卡片
class DanmakuSettingsCard extends StatefulWidget {
  const DanmakuSettingsCard({super.key});

  @override
  State<DanmakuSettingsCard> createState() => _DanmakuSettingsCardState();
}

class _DanmakuSettingsCardState extends State<DanmakuSettingsCard> {
  final DandanConfigManager _config = DandanConfigManager.instance;

  @override
  void initState() {
    super.initState();
    if (!_config.isInitialized) {
      _config.initialize();
    }
    _config.addListener(_onConfigChanged);
  }

  @override
  void dispose() {
    _config.removeListener(_onConfigChanged);
    super.dispose();
  }

  void _onConfigChanged() {
    if (mounted) setState(() {});
  }

  void _openConfigDialog() {
    final appIdController = TextEditingController(text: _config.appId);
    final appSecretController = TextEditingController(text: _config.appSecret);
    final endpointController = TextEditingController(
      text: _config.apiEndpoint == DandanConfigManager.defaultEndpoint ? '' : _config.apiEndpoint,
    );

    bool isTesting = false;
    String? testResult;
    bool? testSuccess;
    BuildContext? currentSheetContext;

    Future<void> saveAndClose() async {
      await _config.saveConfig(
        appId: appIdController.text,
        appSecret: appSecretController.text,
        apiEndpoint: endpointController.text,
      );
      if (currentSheetContext != null && currentSheetContext!.mounted) {
        Navigator.of(currentSheetContext!).pop();
      }
      if (mounted) {
        AppToast.success(
          _config.isCustomCredentials
              ? '已启用自定义弹弹 play 开放平台凭证'
              : '已保存（使用内置通用凭据）',
          context: context,
        );
      }
    }

    TgFormSheet.show(
      context: context,
      title: '弹弹 play 凭证配置',
      onConfirm: saveAndClose,
      bodyBuilder: (sheetCtx) {
        currentSheetContext = sheetCtx;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final theme = Theme.of(sheetCtx);

            Future<void> runTest() async {
              setDialogState(() {
                isTesting = true;
                testResult = null;
                testSuccess = null;
              });

              final res = await _config.testConnection(
                testAppId: appIdController.text,
                testAppSecret: appSecretController.text,
                testEndpoint: endpointController.text,
              );

              setDialogState(() {
                isTesting = false;
                testSuccess = res.success;
                testResult = res.message;
              });
            }

            Future<void> resetCredentials() async {
              final confirmed = await TgActionSheet.showDestructive(
                sheetCtx,
                title: '确定要恢复为内置默认弹弹 play 凭证吗？',
                destructiveLabel: '恢复默认凭据',
              );
              if (confirmed) {
                await _config.resetToDefault();
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
                if (mounted) {
                  AppToast.success('已恢复为内置默认弹弹凭证', context: context);
                }
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const TgInputSectionHeader(title: '凭证信息'),
                TgInputGroup(
                  children: [
                    TgInputField(
                      controller: appIdController,
                      placeholder: 'App ID，如 hvf6pzvxcm',
                    ),
                    TgInputField(
                      controller: appSecretController,
                      placeholder: 'App Secret 开放平台私钥',
                      obscureText: true,
                    ),
                    TgInputField(
                      controller: endpointController,
                      placeholder: 'API 节点（选填，默认官方节点）',
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: Text(
                    '留空使用内置通用凭据；若失效可前往 open.dandanplay.com 申请独立凭据。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                      fontSize: 12.5,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ),
                const TgInputSectionHeader(title: '操作与测试'),
                TgInputGroup(
                  children: [
                    // 测试连接行
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: isTesting ? null : runTest,
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            children: [
                              Text(
                                '测试连接状态',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.normal,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const Spacer(),
                              if (isTesting)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else if (testResult != null)
                                Flexible(
                                  child: Text(
                                    testResult!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: testSuccess == true
                                          ? const Color(0xFF34C759)
                                          : theme.colorScheme.error,
                                      fontWeight: FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // 恢复默认行
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: resetCredentials,
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '恢复为内置默认凭据',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontSize: 15.5,
                              color: const Color(0xFFFF3B30),
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCustom = _config.isCustomCredentials;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const M3SettingsSectionHeader(title: '弹幕服务'),
        M3SettingsCard(
          footerText: '留空使用内置通用凭据；若内置失效可前往 open.dandanplay.com 申请独立凭证填入。',
          children: [
            M3SettingsTile(
              leading: const M3SettingsIconBox(
                icon: Icons.subtitles_rounded,
                bg: Color(0xFF34C759),
              ),
              title: '弹弹 play API',
              subtitle: isCustom ? '已启用自定义凭证' : '使用内置通用凭证',
              showDivider: false,
              onTap: _openConfigDialog,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isCustom ? const Color(0xFF34C759) : theme.colorScheme.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isCustom ? '自定义' : '默认',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: isCustom ? const Color(0xFF34C759) : theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    size: 18,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}
