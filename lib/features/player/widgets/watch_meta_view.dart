import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/cached_anime_image.dart';

/// iOS 现代风格番剧详情 Tab 组件 (Apple Card & Typography Style)
class WatchMetaView extends StatefulWidget {
  const WatchMetaView({
    super.key,
    required this.title,
    this.bangumiItem,
    this.coverUrl,
    this.episodeCount = 12,
    this.isLoadingDetails = false,
  });

  final String title;
  final BangumiItem? bangumiItem;
  final String? coverUrl;
  final int episodeCount;
  final bool isLoadingDetails;

  @override
  State<WatchMetaView> createState() => _WatchMetaViewState();
}

class _WatchMetaViewState extends State<WatchMetaView> {
  bool _isSummaryExpanded = false;
  String? _collectStatus;
  int _lastCollectIndex = 0;

  static const List<String> _collectOptions = ['想看', '在看', '看过', '搁置', '抛弃'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final item = widget.bangumiItem;

    final displayName = item?.preferredName ?? widget.title;
    final subName = (item != null && item.name != item.nameCn && item.name.isNotEmpty)
        ? item.name
        : null;

    final cover = (widget.coverUrl != null && widget.coverUrl!.isNotEmpty)
        ? widget.coverUrl!
        : (item?.coverUrl ?? '');

    final summary = (item?.summary != null && item!.summary.isNotEmpty)
        ? item.summary.trim()
        : '暂无番剧详细剧情简介。';

    final selectedCollectIndex = _collectStatus != null
        ? _collectOptions.indexOf(_collectStatus!)
        : -1;
    final activeCollectSliderIndex = selectedCollectIndex != -1
        ? selectedCollectIndex
        : _lastCollectIndex;
    final collectAlignX = _collectOptions.length > 1
        ? -1.0 + (activeCollectSliderIndex * (2.0 / (_collectOptions.length - 1)))
        : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // 1. 顶部基础信息（iOS Inset Card: 封面 + 标题 + 评分与排名）
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: isDark ? 0.16 : 0.6),
                  width: 0.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: primaryColor.withValues(alpha: isDark ? 0.28 : 0.14),
                    blurRadius: 18,
                    spreadRadius: -1,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.40 : 0.10),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 96,
                  height: 134,
                  child: cover.isNotEmpty
                      ? CachedAnimeImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: isDark ? Colors.white10 : Colors.black12,
                          child: const Icon(Icons.movie_outlined, size: 36),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      height: 1.25,
                      fontFamily: 'MiSans',
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subName != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subName,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color,
                        letterSpacing: -0.1,
                        height: 1.2,
                        fontFamily: 'MiSans',
                        fontFamilyFallback: FontManager.fallbackFontFamilies,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  // 评分与排名胶囊
                  Row(
                    children: [
                      if (item != null && item.ratingScore > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.3),
                              width: 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded,
                                  color: Colors.amber, size: 14),
                              const SizedBox(width: 3),
                              Text(
                                item.ratingScore.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'MiSans',
                                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (item != null && item.rank > 0) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: primaryColor.withValues(alpha: 0.3),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            '#${item.rank}',
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'MiSans',
                              fontFamilyFallback: FontManager.fallbackFontFamilies,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        '共 ${item?.eps != null && item!.eps > 0 ? item.eps : widget.episodeCount} 话',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodySmall?.color,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                      ),
                    ],
                  ),
                  if (item != null && item.airDate.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '放送日期: ${item.airDate}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        const SizedBox(height: 18),

        // 2. iOS 风格追番状态分段控制器 (带 AnimatedAlign 丝滑物理滑动滑块)
        Container(
          height: 40,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: M3Surface.container(context, level: M3ContainerLevel.lowest),
            borderRadius: BorderRadius.circular(16),
            border: M3Surface.border(context) ??
                Border.all(
                  color: isDark ? Colors.white.withAlpha(18) : Colors.black.withAlpha(12),
                  width: 0.5,
                ),
          ),
          child: Stack(
            children: [
              // (1) 丝滑物理平移的选中滑块 (AnimatedAlign + 柔和阴影，消除局部缩放变形)
              AnimatedOpacity(
                opacity: selectedCollectIndex != -1 ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(collectAlignX, 0.0),
                  child: FractionallySizedBox(
                    widthFactor: 1.0 / _collectOptions.length,
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withAlpha(36) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                            blurRadius: 6,
                            offset: const Offset(0, 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // (2) 5 个等分热区按钮项 (平滑颜色渐变，消除跳动闪烁)
              Row(
                children: _collectOptions.map((opt) {
                  final isSelected = _collectStatus == opt;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          if (_collectStatus == opt) {
                            _collectStatus = null;
                          } else {
                            _collectStatus = opt;
                            _lastCollectIndex = _collectOptions.indexOf(opt);
                          }
                        });
                      },
                      child: Container(
                        height: 32,
                        alignment: Alignment.center,
                        child: Text(
                          opt,
                          style: TextStyle(
                            fontFamily: 'MiSans',
                            fontFamilyFallback: FontManager.fallbackFontFamilies,
                            fontSize: 12.5,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected
                                ? (isDark ? Colors.white : primaryColor)
                                : theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        // 3. 标签列表（Tags）
        if (item != null && item.tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: item.tags.take(12).map((t) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: M3Surface.container(context, level: M3ContainerLevel.lowest),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white.withAlpha(16) : Colors.black.withAlpha(10),
                    width: 0.5,
                  ),
                ),
                child: Text(
                  t.name,
                  style: TextStyle(
                    fontFamily: 'MiSans',
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
        ] else if (widget.isLoadingDetails) ...[
          // 骨架屏占位标签
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(4, (index) {
              return Container(
                width: 48.0 + (index * 16),
                height: 24,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
                  borderRadius: BorderRadius.circular(12),
                ),
              );
            }),
          ),
          const SizedBox(height: 18),
        ],

        // 4. 剧情简介（iOS 风格卡片 + 展开/收起）
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: M3Surface.container(context, level: M3ContainerLevel.lowest),
            borderRadius: BorderRadius.circular(16),
            border: M3Surface.border(context) ??
                Border.all(
                  color: isDark ? Colors.white.withAlpha(16) : Colors.black.withAlpha(10),
                  width: 0.5,
                ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '剧情简介',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      fontFamily: 'MiSans',
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => setState(() => _isSummaryExpanded = !_isSummaryExpanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isSummaryExpanded ? '收起' : '展开',
                            style: TextStyle(
                              fontSize: 12,
                              color: primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Icon(
                            _isSummaryExpanded
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (widget.isLoadingDetails && (item?.summary.isEmpty ?? true))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 12,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 140,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                )
              else
                AnimatedCrossFade(
                firstChild: Text(
                  summary,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.88),
                  ),
                ),
                secondChild: Text(
                  summary,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.88),
                  ),
                ),
                crossFadeState: _isSummaryExpanded
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                duration: const Duration(milliseconds: 200),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
