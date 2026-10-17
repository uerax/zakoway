import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/core/utils/font_manager.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/server/animaku_server_client.dart';
import 'package:zakoway/features/player/source/source_aggregator.dart';
import 'package:zakoway/features/player/source/source_bundle_manager.dart';
import '../../common/widgets/bouncing_scale_card.dart';

/// 视频源实体项
class VideoSourceItem {
  final String id;
  final String name;
  final String description;
  final String statusText;
  final bool isReady;
  final bool isDefault;
  final bool isDirect;

  const VideoSourceItem({
    required this.id,
    required this.name,
    required this.description,
    this.statusText = '已就绪',
    this.isReady = true,
    this.isDefault = false,
    this.isDirect = true,
  });
}

/// 默认从 SourceBundleManager 生成的标准视频源列表
List<VideoSourceItem> getDefaultSourceItems() {
  const directMap = {
    'mifun': true,
    'sorani': true,
    'gugu': true,
    'lzizy': true,
    'animoe': true,
    'tvtfun': true,
    'xifan-next': false,
    'cycani': false,
    'girigiri': false,
    'moonci': false,
    'mxdm': false,
    'anime1': false,
    'omofun': false,
    'libvio': false,
  };

  const descriptions = {
    'xifan-next': '1080P · 官方推荐综合主线',
    'cycani': '1080P · 纯净 REST API 多线路',
    'mifun': '1080P · 字节/百度 CDN 高速切片',
    'sorani': '1080P · 官方原生 API 直出 (最高画质)',
    'girigiri': '1080P · Cloudflare CDN 原画直连',
    'moonci': '1080P · 备用多线路直连',
    'lzizy': 'HLS · 全品类影视 0ms 纯直链',
    'animoe': 'HLS · 网易云音乐 CDN 节点',
    'gugu': '1080P · 字节 TOS 国内极速直链 (咕咕新线/A线)',
    'mxdm': 'HLS · 备用多线路模板解析',
    'tvtfun': '1080P · 官方 BytePlus/Akamai 全球 CDN 极速主线',
    'anime1': 'MP4 · 动画全集带鉴权直连',
    'omofun': '1080P · 备用解析线路',
    'libvio': '1080P · 动态发布页实时探活镜像',
  };

  const sourceNames = {
    'xifan-next': '稀饭Next',
    'cycani': '次元城',
    'mifun': 'MiFun',
    'sorani': '青空次元',
    'girigiri': 'girigiri',
    'moonci': '月之祠',
    'lzizy': '量子资源',
    'animoe': 'Animoe',
    'gugu': '咕咕番',
    'mxdm': 'MX动漫',
    'tvtfun': 'TvTFun',
    'anime1': 'Anime1',
    'omofun': 'OmoFun',
    'libvio': 'LIBVIO',
  };

  final dynamicSources = SourceBundleManager.instance.sources;
  if (dynamicSources.isEmpty) {
    return descriptions.entries.map((e) {
      return VideoSourceItem(
        id: e.key,
        name: sourceNames[e.key] ?? e.key,
        description: e.value,
        isDefault: e.key == 'xifan-next',
        isDirect: directMap[e.key] ?? true,
      );
    }).toList();
  }

  return dynamicSources.map((s) {
    return VideoSourceItem(
      id: s.id,
      name: s.name,
      description: descriptions[s.id] ?? 'v${s.version} · 动态解析',
      isDefault: s.id == 'xifan-next',
      isDirect: s.isDirect,
    );
  }).toList();
}

typedef SourceHitSelectCallback = void Function(
  VideoSourceItem src,
  SourceSearchResult hit, [
  List<SourceChapterRoad>? cachedRoads,
]);

/// iOS 现代化视频源看板 (1:1 严格对齐 animaku SourceBoard 交互与视觉设计)
class VideoSourceView extends StatefulWidget {
  const VideoSourceView({
    super.key,
    required this.sources,
    required this.selectedSourceId,
    required this.onSourceSelected,
    this.onSelectHit,
    this.aggregator,
    this.hintMessage,
    this.keywordOptions = const [],
    this.onUserAction,
    this.currentEpisodeNumber,
  });

  final List<VideoSourceItem> sources;
  final String selectedSourceId;
  final ValueChanged<VideoSourceItem> onSourceSelected;
  final SourceHitSelectCallback? onSelectHit;
  final SourceAggregator? aggregator;
  final String? hintMessage;
  final List<String> keywordOptions;
  final VoidCallback? onUserAction;
  final int? currentEpisodeNumber;

  @override
  State<VideoSourceView> createState() => _VideoSourceViewState();
}

/// 视频源分类过滤选项
enum SourceFilterCategory {
  all,
  direct,
  proxy,
}

class _VideoSourceViewState extends State<VideoSourceView> {
  String? _expandedSourceId;
  SourceFilterCategory _selectedCategory = SourceFilterCategory.all;
  final Set<String> _showAdvancedSearch = {};
  final Map<String, TextEditingController> _controllers = {};

  static const Color _kOrangeColor = Color(0xFFF97316);

  @override
  void initState() {
    super.initState();
    AppPreferences.serverModeNotifier.addListener(_onServerStateUpdate);
    AnimakuServerClient.instance.supportedSourcesNotifier.addListener(_onServerStateUpdate);
    if (AppPreferences.isServerModeEnabled()) {
      AnimakuServerClient.instance.fetchSupportedSources().ignore();
    }
  }

  @override
  void dispose() {
    AppPreferences.serverModeNotifier.removeListener(_onServerStateUpdate);
    AnimakuServerClient.instance.supportedSourcesNotifier.removeListener(_onServerStateUpdate);
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _onServerStateUpdate() {
    if (mounted) setState(() {});
  }

  TextEditingController _getController(String sourceId) {
    return _controllers.putIfAbsent(sourceId, () => TextEditingController());
  }

  Widget _buildFilterTab({
    required BuildContext context,
    required SourceFilterCategory category,
    required String label,
    IconData? icon,
  }) {
    final isSelected = _selectedCategory == category;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_selectedCategory != category) {
            setState(() {
              _selectedCategory = category;
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.fastOutSlowIn,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? primaryColor.withValues(alpha: 0.28) : primaryColor)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: isSelected && !isDark
                ? [
                    BoxShadow(
                      color: primaryColor.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 13,
                  color: isSelected
                      ? Colors.white
                      : (theme.textTheme.bodySmall?.color ?? Colors.grey),
                ),
                const SizedBox(width: 3),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: theme.textTheme.labelMedium?.fontFamily ?? 'MiSans',
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (theme.textTheme.bodySmall?.color ?? Colors.grey),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final effectiveSources = widget.sources.isEmpty ? getDefaultSourceItems() : widget.sources;
    final directCount = effectiveSources.where((s) => s.isDirect).length;
    final proxyCount = effectiveSources.where((s) => !s.isDirect).length;

    final filteredSources = effectiveSources.where((s) {
      switch (_selectedCategory) {
        case SourceFilterCategory.all:
          return true;
        case SourceFilterCategory.direct:
          return s.isDirect;
        case SourceFilterCategory.proxy:
          return !s.isDirect;
      }
    }).toList();

    final probeStates = widget.aggregator?.states ?? const <String, AggregatedSourceState>{};
    final totalCount = effectiveSources.length;
    final filteredTotal = filteredSources.length;
    final readyCount = filteredSources.where((s) => probeStates[s.id]?.status == SourceProbeStatus.ready).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // 1. 顶部提示条 (默认源未搜到或全灭时的醒目提示，使用柔和橙色)
        if (widget.hintMessage != null)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _kOrangeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _kOrangeColor.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: _kOrangeColor, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.hintMessage!,
                    style: TextStyle(
                      fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                      fontFamilyFallback: theme.textTheme.bodyMedium?.fontFamilyFallback,
                      fontSize: 12.5,
                      color: _kOrangeColor,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // 2. 标题与状态栏 (展示 X/Y 就绪数)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  '视频源列表',
                  style: TextStyle(
                    fontFamily: theme.textTheme.titleMedium?.fontFamily,
                    fontFamilyFallback: theme.textTheme.titleMedium?.fontFamilyFallback,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '($readyCount/$filteredTotal 就绪)',
                  style: TextStyle(
                    fontFamily: theme.textTheme.bodySmall?.fontFamily,
                    fontFamilyFallback: theme.textTheme.bodySmall?.fontFamilyFallback,
                    fontSize: 11.5,
                    fontWeight: FontWeight.normal,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
                if (widget.aggregator?.isAutoProbing == true) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CupertinoActivityIndicator(radius: 6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '并发探测中...',
                    style: TextStyle(
                      fontFamily: theme.textTheme.bodySmall?.fontFamily,
                      fontFamilyFallback: theme.textTheme.bodySmall?.fontFamilyFallback,
                      fontSize: 11,
                      color: primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),

        // 2.5 分类过滤胶囊 (全部 / ⚡ 可直连 / 🌐 需代理)
        Container(
          height: 34,
          margin: const EdgeInsets.only(top: 10, bottom: 12),
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              _buildFilterTab(
                context: context,
                category: SourceFilterCategory.all,
                label: '全部 $totalCount',
                icon: null,
              ),
              _buildFilterTab(
                context: context,
                category: SourceFilterCategory.direct,
                label: '直连 $directCount',
                icon: Icons.bolt_rounded,
              ),
              _buildFilterTab(
                context: context,
                category: SourceFilterCategory.proxy,
                label: '代理 $proxyCount',
                icon: Icons.public_rounded,
              ),
            ],
          ),
        ),

        if (filteredSources.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: Text(
                '当前分类下暂无视频源',
                style: TextStyle(
                  fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  fontSize: 13,
                  color: theme.textTheme.bodySmall?.color,
                ),
              ),
            ),
          ),

        // 3. 视频源卡片列表 (含硬件加速丝滑展开抽屉 Drawer)
        ...filteredSources.map((src) {
          final isSelected = src.id == widget.selectedSourceId;
          final state = probeStates[src.id] ??
              AggregatedSourceState(
                meta: SourceMeta(id: src.id, name: src.name, version: '1.0.0'),
                status: SourceProbeStatus.idle,
              );

          final isExpanded = _expandedSourceId == src.id;
          final matchedTitle = state.matchedHit?.name ?? state.binding?.title ?? '';

          // 状态徽标与药丸按钮文本
          Widget statusDot;
          Widget pillButton;

          switch (state.status) {
            case SourceProbeStatus.probing:
              statusDot = Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                ),
              );
              pillButton = _buildPill(
                context: context,
                label: '探活中',
                color: primaryColor,
                isLoading: true,
                onTap: null,
              );
              break;

            case SourceProbeStatus.ready:
              statusDot = Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withValues(alpha: 0.6),
                      blurRadius: 4,
                      spreadRadius: 1,
                    )
                  ],
                ),
              );
              pillButton = _buildPill(
                context: context,
                label: isSelected ? '在播' : '切换',
                color: isSelected ? primaryColor : Colors.green,
                isFilled: isSelected,
                onTap: () {
                  widget.onUserAction?.call();
                  if (isSelected) {
                    setState(() {
                      _expandedSourceId = isExpanded ? null : src.id;
                    });
                  } else {
                    if (state.matchedHit != null) {
                      widget.onSelectHit != null
                          ? widget.onSelectHit!(src, state.matchedHit!, state.roads)
                          : widget.onSourceSelected(src);
                    } else {
                      widget.onSourceSelected(src);
                    }
                  }
                },
              );
              break;

            case SourceProbeStatus.needsPick:
              statusDot = Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _kOrangeColor,
                  shape: BoxShape.circle,
                ),
              );
              pillButton = _buildPill(
                context: context,
                label: '选版本',
                color: _kOrangeColor,
                onTap: () {
                  widget.onUserAction?.call();
                  setState(() {
                    _expandedSourceId = isExpanded ? null : src.id;
                  });
                },
              );
              break;

            case SourceProbeStatus.empty:
            case SourceProbeStatus.error:
              statusDot = Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              );
              pillButton = _buildPill(
                context: context,
                label: '换词',
                color: Colors.redAccent,
                onTap: () {
                  widget.onUserAction?.call();
                  setState(() {
                    _expandedSourceId = isExpanded ? null : src.id;
                  });
                },
              );
              break;

            case SourceProbeStatus.idle:
              statusDot = Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: theme.disabledColor,
                  shape: BoxShape.circle,
                ),
              );
              pillButton = _buildPill(
                context: context,
                label: '探活',
                color: theme.textTheme.bodySmall?.color ?? Colors.grey,
                onTap: () {
                  widget.onUserAction?.call();
                  widget.aggregator?.prioritizeSource(src.id, isUserAction: true);
                },
              );
              break;
          }

          // 副标题提示文字
          String statusDescription;
          Color statusDescriptionColor = theme.textTheme.bodySmall?.color ?? Colors.grey;

          if (state.status == SourceProbeStatus.probing) {
            statusDescription = '探活检索中...';
            statusDescriptionColor = primaryColor;
          } else if (state.status == SourceProbeStatus.ready) {
            statusDescription = matchedTitle.isNotEmpty ? matchedTitle : '已命中番剧条目';
            statusDescriptionColor = isSelected ? primaryColor : Colors.green;
          } else if (state.status == SourceProbeStatus.needsPick) {
            statusDescription = '搜到 ${state.items.length} 个候选版本 · 点击挑选';
            statusDescriptionColor = _kOrangeColor;
          } else if (state.status == SourceProbeStatus.empty) {
            statusDescription = '未搜到结果 (点击展开换词)';
          } else if (state.status == SourceProbeStatus.error) {
            statusDescription = state.errorMsg ?? '请求异常 (点击换词)';
            statusDescriptionColor = Colors.redAccent;
          } else {
            statusDescription = '待探活 (点击探活)';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 8.0),
            decoration: BoxDecoration(
              color: isSelected
                  ? primaryColor.withValues(alpha: isDark ? 0.16 : 0.08)
                  : (isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(7)),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? primaryColor.withValues(alpha: 0.5)
                    : (isDark ? Colors.white.withAlpha(18) : Colors.black.withAlpha(12)),
                width: isSelected ? 1.2 : 0.5,
              ),
            ),
            child: Column(
              children: [
                // 卡片主行：采用即时响应的 InkWell，消除按压回弹等待锁（~300ms），实现 0ms 极速触发展开
                InkWell(
                  borderRadius: isExpanded
                      ? const BorderRadius.vertical(top: Radius.circular(14))
                      : BorderRadius.circular(14),
                  onTap: () {
                    widget.onUserAction?.call();
                    if (state.status == SourceProbeStatus.idle) {
                      widget.aggregator?.prioritizeSource(src.id, isUserAction: true);
                    }
                    setState(() {
                      _expandedSourceId = isExpanded ? null : src.id;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    child: Row(
                      children: [
                        // 首字母头像 + 状态指示灯
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? primaryColor
                                    : (isDark ? Colors.white.withAlpha(16) : Colors.black.withAlpha(10)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                (src.name.isNotEmpty ? src.name[0] : '?').toUpperCase(),
                                style: TextStyle(
                                  fontFamily: theme.textTheme.titleMedium?.fontFamily,
                                  fontFamilyFallback: theme.textTheme.titleMedium?.fontFamilyFallback,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : theme.textTheme.bodySmall?.color,
                                ),
                              ),
                            ),
                            Positioned(
                              right: -2,
                              bottom: -2,
                              child: statusDot,
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        // 视频源名称与命中条目
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      src.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: theme.textTheme.titleMedium?.fontFamily,
                                        fontFamilyFallback: theme.textTheme.titleMedium?.fontFamilyFallback,
                                        fontSize: 14,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                        letterSpacing: -0.2,
                                        color: isSelected
                                            ? primaryColor
                                            : (src.isDirect
                                                ? (isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D))
                                                : (isDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED))),
                                      ),
                                    ),
                                  ),
                                  if (AppPreferences.isServerModeEnabled() &&
                                      AnimakuServerClient.instance.isSourceSupported(src.id)) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: primaryColor.withValues(alpha: isDark ? 0.22 : 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: primaryColor.withValues(alpha: 0.35),
                                          width: 0.5,
                                        ),
                                      ),
                                      child: Text(
                                        '服务端',
                                        style: TextStyle(
                                          fontFamily: theme.textTheme.labelSmall?.fontFamily,
                                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w600,
                                          color: primaryColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                statusDescription,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: theme.textTheme.bodySmall?.fontFamily,
                                  fontFamilyFallback: theme.textTheme.bodySmall?.fontFamilyFallback,
                                  fontSize: 11.5,
                                  color: statusDescriptionColor,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        pillButton,
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 140),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // 抽屉展开区域：采用 140ms + Curves.easeOutCubic，消除 Curves.fastOutSlowIn 尾部拖沓感
                AnimatedSize(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: isExpanded
                      ? Container(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black.withAlpha(25) : Colors.white.withAlpha(120),
                            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                            border: Border(
                              top: BorderSide(
                                color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: _buildDrawerContent(
                            context: context,
                            src: src,
                            state: state,
                            isSelected: isSelected,
                            isDark: isDark,
                            primaryColor: primaryColor,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDrawerContent({
    required BuildContext context,
    required VideoSourceItem src,
    required AggregatedSourceState state,
    required bool isSelected,
    required bool isDark,
    required Color primaryColor,
  }) {
    final theme = Theme.of(context);
    final isShowManual = _showAdvancedSearch.contains(src.id) ||
        state.status == SourceProbeStatus.empty ||
        state.status == SourceProbeStatus.error;

    final uniqueKeywords = widget.keywordOptions
        .map((k) => k.replaceAll(RegExp(r'[\s　 ]+'), ' ').trim())
        .where((k) => k.isNotEmpty)
        .toSet()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 正在检索中
        if (state.status == SourceProbeStatus.probing) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                CupertinoActivityIndicator(radius: 6, color: primaryColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '正在检索 ${src.name}...',
                    style: TextStyle(
                      fontFamily: theme.textTheme.bodySmall?.fontFamily,
                      fontFamilyFallback: theme.textTheme.bodySmall?.fontFamilyFallback,
                      fontSize: 12,
                      color: primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],

        // 2. 候选版本列表 (针对 needsPick 或多条候选)
        if (state.items.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(
                  Icons.video_library_rounded,
                  size: 13,
                  color: state.status == SourceProbeStatus.needsPick
                      ? _kOrangeColor
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  state.status == SourceProbeStatus.needsPick
                      ? '请挑选匹配的番剧版本：'
                      : '可用播放版本 (${state.items.length})：',
                  style: TextStyle(
                    fontFamily: theme.textTheme.titleSmall?.fontFamily,
                    fontFamilyFallback: theme.textTheme.titleSmall?.fontFamilyFallback,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: state.status == SourceProbeStatus.needsPick
                        ? _kOrangeColor
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          // 纯轻量紧凑卡片 (无嵌套 ListView)，展开极速 60fps
          ...state.items.take(4).map((hit) {
            final isHitActive = isSelected && state.matchedHit?.url == hit.url;
            return Container(
              margin: const EdgeInsets.only(bottom: 5),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: isHitActive
                    ? primaryColor.withValues(alpha: isDark ? 0.2 : 0.1)
                    : (isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(4)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isHitActive
                      ? primaryColor.withValues(alpha: 0.5)
                      : Colors.transparent,
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isHitActive ? Icons.play_circle_fill_rounded : Icons.movie_outlined,
                    size: 15,
                    color: isHitActive ? primaryColor : theme.textTheme.bodySmall?.color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      hit.name,
                      style: TextStyle(
                        fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                        fontFamilyFallback: theme.textTheme.bodyMedium?.fontFamilyFallback,
                        fontSize: 12,
                        fontWeight: isHitActive ? FontWeight.w700 : FontWeight.w500,
                        color: isHitActive ? primaryColor : theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  BouncingScaleCard(
                    scaleDown: 0.94,
                    onTap: () {
                      widget.onUserAction?.call();
                      widget.onSelectHit != null
                          ? widget.onSelectHit!(src, hit, isHitActive ? state.roads : const [])
                          : widget.onSourceSelected(src);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: isHitActive
                            ? primaryColor
                            : (state.status == SourceProbeStatus.needsPick
                                ? _kOrangeColor
                                : primaryColor.withValues(alpha: 0.14)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isHitActive ? '在播' : '选用',
                        style: TextStyle(
                          fontFamily: theme.textTheme.labelSmall?.fontFamily,
                          fontFamilyFallback: theme.textTheme.labelSmall?.fontFamilyFallback,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isHitActive || state.status == SourceProbeStatus.needsPick
                              ? Colors.white
                              : primaryColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 6),
        ],

        // 3. 针对就绪/点选状态的“换词检索”折叠开关 (默认收敛，不干扰看剧)
        if (state.status != SourceProbeStatus.empty && state.status != SourceProbeStatus.error) ...[
          Builder(
            builder: (context) {
              final isExpanded = _showAdvancedSearch.contains(src.id);
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    // 即刻触发展开/收起，杜绝人工延时
                    setState(() {
                      if (isExpanded) {
                        _showAdvancedSearch.remove(src.id);
                      } else {
                        _showAdvancedSearch.add(src.id);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isExpanded
                          ? (isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8))
                          : primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isExpanded
                            ? (isDark ? Colors.white.withAlpha(18) : Colors.black.withAlpha(12))
                            : primaryColor.withValues(alpha: 0.28),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_rounded,
                          size: 13,
                          color: isExpanded
                              ? theme.textTheme.bodySmall?.color?.withValues(alpha: 0.85)
                              : primaryColor,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          isExpanded ? '收起自定义换词' : '未找到想要的版本？换词重搜',
                          style: TextStyle(
                            fontFamily: theme.textTheme.bodySmall?.fontFamily,
                            fontFamilyFallback: theme.textTheme.bodySmall?.fontFamilyFallback,
                            fontSize: 11,
                            fontWeight: isExpanded ? FontWeight.w500 : FontWeight.w600,
                            color: isExpanded
                                ? theme.textTheme.bodySmall?.color?.withValues(alpha: 0.85)
                                : primaryColor,
                          ),
                        ),
                        const SizedBox(width: 3),
                        AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 160),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 13,
                            color: isExpanded
                                ? theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7)
                                : primaryColor.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],

        // 4. 手动换词与自定义搜索面板 (带抽屉平滑高度补间动画)
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: isShowManual
              ? Padding(
                  padding: EdgeInsets.only(
                    top: (state.status != SourceProbeStatus.empty &&
                            state.status != SourceProbeStatus.error)
                        ? 10.0
                        : 0.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (uniqueKeywords.isNotEmpty) ...[
                        Text(
                          '推荐片名别名：',
                          style: TextStyle(
                            fontFamily: theme.textTheme.bodySmall?.fontFamily,
                            fontFamilyFallback: theme.textTheme.bodySmall?.fontFamilyFallback,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: uniqueKeywords.take(6).map((kw) {
                            final isCurrentKw = state.keyword == kw;
                            return InkWell(
                              onTap: () {
                                widget.onUserAction?.call();
                                _getController(src.id).text = kw;
                                widget.aggregator?.reProbeSource(src.id, kw);
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: isCurrentKw
                                      ? primaryColor.withValues(alpha: 0.16)
                                      : (isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(5)),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isCurrentKw
                                        ? primaryColor.withValues(alpha: 0.6)
                                        : (isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8)),
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        kw,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: theme.textTheme.bodySmall?.fontFamily,
                                          fontFamilyFallback: theme.textTheme.bodySmall?.fontFamilyFallback,
                                          fontSize: 11,
                                          color: isCurrentKw ? primaryColor : theme.colorScheme.onSurface,
                                          fontWeight: isCurrentKw ? FontWeight.w600 : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.search_rounded,
                                      size: 11,
                                      color: isCurrentKw ? primaryColor : theme.disabledColor,
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 10),
                      ],

                      // 单层胶囊搜索框 (整体外层为输入框，消除双层嵌套)
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 34,
                              child: TextField(
                                controller: _getController(src.id),
                                maxLines: 1,
                                textInputAction: TextInputAction.search,
                                textAlignVertical: TextAlignVertical.center,
                                // 特殊处理说明：显式约束 cursorHeight 与 cursorWidth，防止 Windows DirectWrite 下中文字体度量异常导致光标向上/向下溢出输入框
                                cursorHeight: 14,
                                cursorWidth: 1.5,
                                cursorRadius: const Radius.circular(1),
                                cursorColor: primaryColor,
                                style: TextStyle(
                                  fontFamily: theme.textTheme.bodyMedium?.fontFamily,
                                  fontFamilyFallback: theme.textTheme.bodyMedium?.fontFamilyFallback,
                                  fontSize: 12,
                                  height: 1.2,
                                ),
                                decoration: InputDecoration(
                                  isDense: true,
                                  filled: true,
                                  fillColor: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(6),
                                  prefixIcon: Icon(Icons.search_rounded, size: 15, color: theme.disabledColor),
                                  prefixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 34),
                                  hintText: '输入在 ${src.name} 检索的片名...',
                                  hintStyle: TextStyle(
                                    fontFamily: theme.textTheme.bodySmall?.fontFamily,
                                    fontFamilyFallback: theme.textTheme.bodySmall?.fontFamilyFallback,
                                    fontSize: 11,
                                    height: 1.2,
                                    color: theme.disabledColor,
                                  ),
                                  contentPadding: const EdgeInsets.only(right: 10),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    borderSide: BorderSide(color: primaryColor, width: 1.2),
                                  ),
                                ),
                                onSubmitted: (val) {
                                  if (val.trim().isNotEmpty) {
                                    widget.onUserAction?.call();
                                    widget.aggregator?.reProbeSource(src.id, val.trim());
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          BouncingScaleCard(
                            scaleDown: 0.94,
                            onTap: () {
                              final val = _getController(src.id).text.trim();
                              if (val.isNotEmpty) {
                                widget.onUserAction?.call();
                                widget.aggregator?.reProbeSource(src.id, val);
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7.5),
                              decoration: BoxDecoration(
                                color: primaryColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '重搜',
                                style: TextStyle(
                                  fontFamily: theme.textTheme.labelSmall?.fontFamily,
                                  fontFamilyFallback: theme.textTheme.labelSmall?.fontFamilyFallback,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildPill({
    required BuildContext context,
    required String label,
    required Color color,
    bool isFilled = false,
    bool isLoading = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: isFilled ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: isFilled ? 1.0 : 0.35),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading) ...[
              SizedBox(
                width: 8,
                height: 8,
                child: CupertinoActivityIndicator(radius: 4, color: color),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontFamily: theme.textTheme.labelSmall?.fontFamily,
                fontFamilyFallback: theme.textTheme.labelSmall?.fontFamilyFallback,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isFilled ? Colors.white : color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
