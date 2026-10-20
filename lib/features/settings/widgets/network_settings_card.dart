import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/bangumi_client.dart';
import '../../../core/services/app_preferences.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/image_utils.dart';
import '../../common/widgets/ios_swipe_action_tile.dart';
import 'm3_settings_card.dart';
import 'tg_action_sheet.dart';
import 'tg_form_sheet.dart';

class NetworkSettingsCard extends StatefulWidget {
  final BangumiClient client;
  final BangumiSourcePreset currentPreset;
  final ValueChanged<BangumiSourcePreset> onPresetChanged;
  final VoidCallback? onRouteChanged;

  const NetworkSettingsCard({
    super.key,
    required this.client,
    required this.currentPreset,
    required this.onPresetChanged,
    this.onRouteChanged,
  });

  @override
  State<NetworkSettingsCard> createState() => _NetworkSettingsCardState();
}

class _NetworkSettingsCardState extends State<NetworkSettingsCard> {
  late String _activeRouteId;
  late List<CustomNetworkRoute> _customRoutes;

  @override
  void initState() {
    super.initState();
    _activeRouteId = widget.client.activeRouteId;
    _customRoutes = AppPreferences.getCustomNetworkRoutes();
  }

  @override
  void didUpdateWidget(covariant NetworkSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client.activeRouteId != widget.client.activeRouteId) {
      _activeRouteId = widget.client.activeRouteId;
    }
  }

  void _handlePresetChanged(
    BuildContext context,
    BangumiSourcePreset preset, {
    bool showSnack = true,
  }) {
    if (_activeRouteId == preset.name) return;

    setState(() {
      _activeRouteId = preset.name;
    });
    widget.onPresetChanged(preset);
    widget.client.setSourcePreset(preset);
    widget.onRouteChanged?.call();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    debugPrint(
      '【网络线路切换成功】生效预设: ${preset.name}, API Base: ${widget.client.baseUrl}, 当前图片Host: $currentBangumiImageHost',
    );

    if (showSnack) {
      AppToast.info(
        preset == BangumiSourcePreset.mirror ? '已切换至镜像加速' : '已切换至官方直连',
        context: context,
      );
    }
  }

  void _handleCustomRouteChanged(BuildContext context, CustomNetworkRoute route) {
    if (_activeRouteId == route.id) return;

    setState(() {
      _activeRouteId = route.id;
    });
    widget.client.setCustomRoute(route);
    widget.onPresetChanged(widget.client.sourcePreset);
    widget.onRouteChanged?.call();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    debugPrint(
      '【网络线路切换成功】生效自定义线路: ${route.name}, URL: ${route.url}, 当前图片Host: $currentBangumiImageHost',
    );

    AppToast.info('已切换至自定义线路【${route.name}】', context: context);
  }

  Future<void> _confirmDeleteRoute(CustomNetworkRoute route) async {
    final confirmed = await TgActionSheet.showDestructive(
      context,
      header: '移除自定义线路',
      title: '确定要移除【${route.name}】吗？',
      destructiveLabel: '确认移除',
    );
    if (confirmed) {
      _deleteRoute(route);
    }
  }

  void _deleteRoute(CustomNetworkRoute route) {
    setState(() {
      _customRoutes.removeWhere((r) => r.id == route.id);
    });
    AppPreferences.saveCustomNetworkRoutes(_customRoutes);

    final wasActive = _activeRouteId == route.id;
    if (wasActive) {
      _handlePresetChanged(context, BangumiSourcePreset.mirror, showSnack: false);
    }

    AppToast.info(
      wasActive ? '已移除线路【${route.name}】，并恢复至镜像加速' : '已移除线路【${route.name}】',
      context: context,
    );
  }

  void _showAddRouteDialog() {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    BuildContext? currentSheetContext;

    Future<void> submit() async {
      var rawUrl = urlController.text.trim();
      if (rawUrl.isEmpty) {
        AppToast.warning('请输入反代 URL 或链接', context: context);
        return;
      }

      if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
        rawUrl = 'https://$rawUrl';
      }
      rawUrl = rawUrl.replaceFirst(RegExp(r'/+$'), '');

      final rawName = nameController.text.trim();

      // 【核心区分】：判断是 JSON 仓库配置文件，还是普通反代 Base URL
      final isJsonRepo = rawUrl.endsWith('.json') ||
          rawUrl.contains('routes.json') ||
          rawUrl == AppConstants.defaultRoutesRepoUrl;

      if (isJsonRepo) {
        // 分支 A：从 JSON 仓库配置文件导入线路
        List<CustomNetworkRoute> parsedRoutes = [];
        try {
          final dio = Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 5),
            ),
          );
          final res = await dio.get(rawUrl);
          final data = res.data;
          List<dynamic> items = [];
          if (data is List) {
            items = data;
          } else if (data is Map && data['routes'] is List) {
            items = data['routes'] as List;
          }

          final now = DateTime.now().millisecondsSinceEpoch;
          for (var i = 0; i < items.length; i++) {
            final item = items[i];
            if (item is Map) {
              final n = (item['name'] ?? item['label'] ?? '仓库节点 ${i + 1}').toString().trim();
              final u = (item['url'] ?? item['apiBase'] ?? '').toString().trim();
              if (u.isNotEmpty) {
                parsedRoutes.add(CustomNetworkRoute(
                  id: 'custom_${now}_$i',
                  name: n,
                  url: u,
                ));
              }
            }
          }
        } catch (_) {
          // 远端仓库尚未编写/暂不可达时的安全占位回退
          if (rawUrl == AppConstants.defaultRoutesRepoUrl) {
            final now = DateTime.now().millisecondsSinceEpoch;
            parsedRoutes = [
              CustomNetworkRoute(
                id: 'custom_${now}_0',
                name: rawName.isNotEmpty ? rawName : '内置社区线路 (占位)',
                url: 'https://bgmapi.anibt.net',
              ),
            ];
          }
        }

        if (parsedRoutes.isEmpty) {
          if (mounted) {
            AppToast.error('解析仓库链接失败，未找到有效节点', context: context);
          }
          return;
        }

        if (currentSheetContext != null && currentSheetContext!.mounted) {
          Navigator.of(currentSheetContext!).pop();
        }

        if (!mounted) return;

        setState(() {
          _customRoutes.addAll(parsedRoutes);
        });
        AppPreferences.saveCustomNetworkRoutes(_customRoutes);

        AppToast.success('已成功从仓库导入 ${parsedRoutes.length} 条线路', context: context);
      } else {
        // 分支 B：普通反代 Base URL（如 https://my-proxy.com）
        final displayName = rawName.isNotEmpty
            ? rawName
            : (Uri.tryParse(rawUrl)?.host.isNotEmpty == true
                ? Uri.tryParse(rawUrl)!.host
                : '自定义线路 ${_customRoutes.length + 1}');

        final newRoute = CustomNetworkRoute(
          id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
          name: displayName,
          url: rawUrl,
        );

        if (currentSheetContext != null && currentSheetContext!.mounted) {
          Navigator.of(currentSheetContext!).pop();
        }

        setState(() {
          _customRoutes.add(newRoute);
        });
        AppPreferences.saveCustomNetworkRoutes(_customRoutes);

        AppToast.success('已添加线路【$displayName】', context: context);
      }
    }

    TgFormSheet.show(
      context: context,
      title: '添加自定义线路',
      onConfirm: submit,
      bodyBuilder: (sheetCtx) {
        currentSheetContext = sheetCtx;
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final theme = Theme.of(sheetCtx);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const TgInputSectionHeader(title: '线路信息'),
                TgInputGroup(
                  children: [
                    TgInputField(
                      controller: nameController,
                      placeholder: '线路名称（选填）',
                    ),
                    TgInputField(
                      controller: urlController,
                      placeholder: '反代 URL 或仓库链接',
                    ),
                    // 填入内置仓库链接快捷行（优雅整合在卡片内）
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setDialogState(() {
                            urlController.text = AppConstants.defaultRoutesRepoUrl;
                            if (nameController.text.trim().isEmpty) {
                              nameController.text = '内置仓库线路';
                            }
                          });
                        },
                        child: Container(
                          height: 48,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Icon(
                                Icons.link_rounded,
                                size: 18,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '点击填入内置仓库链接',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 15,
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                  child: Text(
                    '支持填入单节点反代地址或 routes.json 仓库订阅链接。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                      fontSize: 12.5,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const M3SettingsSectionHeader(title: '网络线路'),
        M3SettingsCard(
          footerText: '线路切换仅对番剧元数据与海报 CDN 生效，视频播放走自建嗅探流媒体源。',
          children: [
            M3SettingsTile(
              leading: const M3SettingsIconBox(
                icon: Icons.bolt_rounded,
                bg: Color(0xFF007AFF),
              ),
              title: '镜像加速',
              subtitle: '国内 CDN 加速',
              trailing: _activeRouteId == BangumiSourcePreset.mirror.name
                  ? Icon(Icons.check_rounded, color: theme.colorScheme.primary, size: 20)
                  : null,
              onTap: () => _handlePresetChanged(context, BangumiSourcePreset.mirror),
            ),
            M3SettingsTile(
              leading: const M3SettingsIconBox(
                icon: Icons.public_rounded,
                bg: Color(0xFF0A84FF),
              ),
              title: '官方直连',
              subtitle: '海外直连官方源',
              trailing: _activeRouteId == BangumiSourcePreset.official.name
                  ? Icon(Icons.check_rounded, color: theme.colorScheme.primary, size: 20)
                  : null,
              onTap: () => _handlePresetChanged(context, BangumiSourcePreset.official),
            ),
            ..._customRoutes.map((route) {
              return IosSwipeActionTile(
                onDelete: () => _confirmDeleteRoute(route),
                child: M3SettingsTile(
                  leading: const M3SettingsIconBox(
                    icon: Icons.alt_route_rounded,
                    bg: Color(0xFF5AC8FA),
                  ),
                  title: route.name,
                  subtitle: route.url,
                  trailing: _activeRouteId == route.id
                      ? Icon(Icons.check_rounded, color: theme.colorScheme.primary, size: 20)
                      : null,
                  onTap: () => _handleCustomRouteChanged(context, route),
                ),
              );
            }),
            M3SettingsTile(
              leading: const M3SettingsIconBox(
                icon: Icons.add_rounded,
                bg: Color(0xFF34C759),
              ),
              title: '添加自定义线路',
              subtitle: '输入反代或从 URL 导入',
              showDivider: false,
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                size: 20,
              ),
              onTap: _showAddRouteDialog,
            ),
          ],
        ),
      ],
    );
  }
}
