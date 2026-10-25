import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import '../../../core/services/display_mode_service.dart';
import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/app_toast.dart';
import '../../../core/utils/font_manager.dart';
import 'm3_settings_card.dart';

/// Android 平台屏幕帧率设置入口与弹窗面板（对齐 Kazumi 交互与架构规范）
class DisplayModeTile extends StatefulWidget {
  final bool showDivider;

  const DisplayModeTile({
    super.key,
    this.showDivider = true,
  });

  @override
  State<DisplayModeTile> createState() => _DisplayModeTileState();
}

class _DisplayModeTileState extends State<DisplayModeTile> {
  DisplayMode? _preferred;
  DisplayMode? _active;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetchModes();
  }

  Future<void> _fetchModes() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final preferred = await DisplayModeService.getPreferredMode();
      final active = await DisplayModeService.getActiveMode();
      if (!mounted) return;
      setState(() {
        _preferred = preferred;
        _active = active;
      });
    } catch (_) {}
  }

  String _formatModeTitle(DisplayMode mode) {
    if (mode == DisplayMode.auto) {
      return '自动';
    }
    return '${mode.width}×${mode.height} @ ${mode.refreshRate.round()}Hz';
  }

  String _formatCurrentSubtitle() {
    final pref = _preferred;
    final act = _active;
    if (pref == null) {
      return '自适应调度';
    }
    if (pref == DisplayMode.auto) {
      if (act != null && act != DisplayMode.auto) {
        return '自动 (系统当前: ${act.refreshRate.round()}Hz)';
      }
      return '自动 (自适应调度)';
    }
    final hz = pref.refreshRate.round();
    if (act != null && act != DisplayMode.auto && act.refreshRate.round() != hz) {
      return '${hz}Hz (系统当前: ${act.refreshRate.round()}Hz)';
    }
    return '${hz}Hz (${pref.width}×${pref.height})';
  }

  void _showDisplayModePickerModal() async {
    if (_loading) return;
    setState(() => _loading = true);

    List<DisplayMode> supportedModes = [];
    DisplayMode? activeMode;
    DisplayMode? currentPreferred;

    try {
      supportedModes = await DisplayModeService.getSupportedModes();
      activeMode = await DisplayModeService.getActiveMode();
      currentPreferred = await DisplayModeService.getPreferredMode();
    } catch (e) {
      if (mounted) {
        AppToast.error('获取屏幕显示模式失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }

    if (!mounted) return;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fontMgr = FontManager.instance;
    final fontFamily = fontMgr.activeFontFamily;
    final fontFallback = FontManager.fallbackFontFamilies;

    // 确保 auto 模式在列表最顶端，其他模式按分辨率和刷新率降序排列
    final List<DisplayMode> displayList = [
      DisplayMode.auto,
      ...supportedModes.where((m) => m != DisplayMode.auto).toList()
        ..sort((a, b) {
          final cmpRes = (b.width * b.height).compareTo(a.width * a.height);
          if (cmpRes != 0) return cmpRes;
          return b.refreshRate.compareTo(a.refreshRate);
        }),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      showDragHandle: true,
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final selected = _preferred ?? currentPreferred ?? DisplayMode.auto;

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 顶部标题
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Row(
                            children: [
                              Text(
                                '屏幕帧率设置',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontFamily: fontFamily,
                                  fontFamilyFallback: fontFallback,
                                ),
                              ),
                              const Spacer(),
                              if (activeMode != null && activeMode != DisplayMode.auto)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '当前 ${activeMode!.refreshRate.round()}Hz',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 11.5,
                                      fontFamily: fontFamily,
                                      fontFamilyFallback: fontFallback,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // 模式列表容器
                        Flexible(
                          child: Container(
                            decoration: BoxDecoration(
                              color: M3Surface.container(
                                ctx,
                                level: M3ContainerLevel.low,
                                pageKey: 'settings',
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: M3Surface.cardBorder(ctx),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: ListView.separated(
                                shrinkWrap: true,
                                padding: EdgeInsets.zero,
                                itemCount: displayList.length,
                                separatorBuilder: (_, _) => Divider(
                                  height: 0.5,
                                  thickness: 0.5,
                                  indent: 16,
                                  endIndent: 16,
                                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
                                ),
                                itemBuilder: (itemCtx, index) {
                                  final mode = displayList[index];
                                  final isSelected = mode == selected;
                                  final isActive = mode == activeMode && mode != DisplayMode.auto;

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () async {
                                        await DisplayModeService.setPreferredMode(mode);
                                        // 延迟片刻获取最新系统激活模式
                                        await Future<void>.delayed(const Duration(milliseconds: 120));
                                        final newActive = await DisplayModeService.getActiveMode();
                                        if (mounted) {
                                          setState(() {
                                            _preferred = mode;
                                            _active = newActive;
                                          });
                                        }
                                        setModalState(() {
                                          currentPreferred = mode;
                                          activeMode = newActive;
                                        });
                                        if (itemCtx.mounted) {
                                          Navigator.of(itemCtx).pop();
                                          AppToast.success(
                                            mode == DisplayMode.auto
                                                ? '已切换为自动刷新率'
                                                : '已切换为 ${mode.refreshRate.round()}Hz',
                                            context: itemCtx,
                                          );
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Text(
                                                        _formatModeTitle(mode),
                                                        style: theme.textTheme.bodyMedium?.copyWith(
                                                          fontSize: 15,
                                                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                                          color: isDark ? Colors.white : Colors.black87,
                                                          fontFamily: fontFamily,
                                                          fontFamilyFallback: fontFallback,
                                                        ),
                                                      ),
                                                      if (isActive) ...[
                                                        const SizedBox(width: 8),
                                                        Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                          decoration: BoxDecoration(
                                                            color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.7),
                                                            borderRadius: BorderRadius.circular(4),
                                                          ),
                                                          child: Text(
                                                            '系统当前',
                                                            style: theme.textTheme.labelSmall?.copyWith(
                                                              fontSize: 10,
                                                              color: theme.colorScheme.onSecondaryContainer,
                                                              fontWeight: FontWeight.w500,
                                                              fontFamily: fontFamily,
                                                              fontFamilyFallback: fontFallback,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                  if (mode == DisplayMode.auto) ...[
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      '由系统自动根据场景自适应调节刷新率',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        fontSize: 12,
                                                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                                        fontFamily: fontFamily,
                                                        fontFamilyFallback: fontFallback,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                            if (isSelected)
                                              Icon(
                                                Icons.check_rounded,
                                                color: theme.colorScheme.primary,
                                                size: 20,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // 底部说明文案（对齐 Kazumi 提醒）
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: Text(
                            '提示：若选择后刷新率未立即生效，请重启 App。部分国产机型（澎湃OS/ColorOS/OriginOS等）需在系统设置的“应用自定义高刷”中将本应用允许设为 120Hz。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              height: 1.35,
                              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                              fontFamily: fontFamily,
                              fontFamilyFallback: fontFallback,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || !Platform.isAndroid) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return M3SettingsTile(
      leading: const M3SettingsIconBox(
        icon: Icons.speed_rounded,
        bg: Color(0xFF007AFF),
      ),
      title: '屏幕刷新率',
      subtitle: _formatCurrentSubtitle(),
      showDivider: widget.showDivider,
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        size: 18,
      ),
      onTap: _showDisplayModePickerModal,
    );
  }
}
