import 'package:flutter/material.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/core/utils/font_manager.dart';
import 'package:zakoway/features/player/source/server/animaku_server_client.dart';
import 'm3_settings_card.dart';
import 'tg_form_sheet.dart';

/// Animaku 服务端模式与代理设置卡片
class AnimakuServerSettingsCard extends StatefulWidget {
  const AnimakuServerSettingsCard({super.key});

  @override
  State<AnimakuServerSettingsCard> createState() => _AnimakuServerSettingsCardState();
}

class _AnimakuServerSettingsCardState extends State<AnimakuServerSettingsCard> {
  @override
  void initState() {
    super.initState();
    AppPreferences.serverModeNotifier.addListener(_onServerModeChanged);
  }

  @override
  void dispose() {
    AppPreferences.serverModeNotifier.removeListener(_onServerModeChanged);
    super.dispose();
  }

  void _onServerModeChanged() {
    if (mounted) setState(() {});
  }

  void _openConfigDialog() {
    final currentUrl = AppPreferences.getServerModeApiUrl();
    final urlController = TextEditingController(
      text: currentUrl == AppPreferences.defaultServerModeApiUrl ? '' : currentUrl,
    );

    bool isTesting = false;
    String? testResult;
    bool? testSuccess;
    BuildContext? currentSheetContext;

    Future<void> saveAndClose() async {
      final input = urlController.text.trim();
      final effectiveUrl = input.isEmpty ? AppPreferences.defaultServerModeApiUrl : input;
      await AppPreferences.setServerModeApiUrl(effectiveUrl);
      if (currentSheetContext != null && currentSheetContext!.mounted) {
        Navigator.of(currentSheetContext!).pop();
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              effectiveUrl == AppPreferences.defaultServerModeApiUrl
                  ? '已恢复并启用默认官方节点 (bakasine.eu.org)'
                  : '已保存自定义服务端地址',
              style: const TextStyle(
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
            ),
          ),
        );
      }
    }

    TgFormSheet.show(
      context: context,
      title: 'Animaku 服务端配置',
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

              final input = urlController.text.trim();
              final targetUrl = input.isEmpty ? AppPreferences.defaultServerModeApiUrl : input;
              // 临时修改持久化以执行针对目标节点的探活
              await AppPreferences.setServerModeApiUrl(targetUrl);
              final res = await AnimakuServerClient.instance.checkHealth();

              setDialogState(() {
                isTesting = false;
                testSuccess = res.isOk;
                if (res.isOk) {
                  testResult = '连接成功 (${res.latencyMs}ms)${res.version != null ? ' · v${res.version}' : ''}';
                } else {
                  testResult = res.errorMessage ?? '连接失败，请检查网络或地址';
                }
              });
            }

            void resetDefault() {
              urlController.text = '';
              setDialogState(() {
                testResult = null;
                testSuccess = null;
              });
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TgInputSectionHeader(title: '节点地址'),
                TgInputGroup(
                  children: [
                    TgInputField(
                      controller: urlController,
                      placeholder: '留空默认: bakasine.eu.org',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const TgInputSectionHeader(title: '操作与测试'),
                TgInputGroup(
                  children: [
                    // 测试连接按钮行
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
                                style: TextStyle(
                                  fontFamily: theme.textTheme.bodyMedium?.fontFamily ?? 'MiSans',
                                  fontFamilyFallback: FontManager.fallbackFontFamilies,
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
                                      fontFamily: 'MiSans',
                                      fontFamilyFallback: FontManager.fallbackFontFamilies,
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
                    // 恢复默认按钮行
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: resetDefault,
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '恢复默认公共节点 (bakasine.eu.org)',
                            style: TextStyle(
                              fontFamily: theme.textTheme.bodyMedium?.fontFamily ?? 'MiSans',
                              fontFamilyFallback: FontManager.fallbackFontFamilies,
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
    final isServerMode = AppPreferences.isServerModeEnabled();
    final currentUrl = AppPreferences.getServerModeApiUrl();
    final isCustomUrl = currentUrl != AppPreferences.defaultServerModeApiUrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const M3SettingsSectionHeader(title: 'Animaku 服务端模式'),
        M3SettingsCard(
          footerText: '开启后受限源由服务端中继解析；不支持的源自动降级走本地直连。默认内置公开节点 (bakasine.eu.org)，支持自定义或自建。',
          children: [
            // 开关行
            M3SettingsTile(
              leading: const M3SettingsIconBox(
                icon: Icons.cloud_sync_rounded,
                bg: Color(0xFF007AFF),
              ),
              title: '服务端解析代理',
              subtitle: isServerMode ? '已开启（解决海外/受限源访问障碍）' : '已关闭（使用纯原生本地直连）',
              showDivider: true,
              trailing: Switch.adaptive(
                value: isServerMode,
                activeTrackColor: theme.colorScheme.primary,
                onChanged: (val) {
                  AppPreferences.setServerModeEnabled(val);
                },
              ),
            ),
            // 服务端节点设置行
            M3SettingsTile(
              leading: const M3SettingsIconBox(
                icon: Icons.dns_rounded,
                bg: Color(0xFF5856D6),
              ),
              title: '服务端节点地址',
              subtitle: currentUrl,
              showDivider: false,
              onTap: _openConfigDialog,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isCustomUrl ? const Color(0xFF34C759) : theme.colorScheme.primary)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isCustomUrl ? '自定义' : '默认公共',
                      style: TextStyle(
                        fontFamily: theme.textTheme.bodySmall?.fontFamily ?? 'MiSans',
                        fontFamilyFallback: FontManager.fallbackFontFamilies,
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: isCustomUrl ? const Color(0xFF34C759) : theme.colorScheme.primary,
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
