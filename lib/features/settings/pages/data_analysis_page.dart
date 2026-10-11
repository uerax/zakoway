import 'package:flutter/material.dart';
import '../../../core/services/watch_history_service.dart';
import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/font_manager.dart';
import '../../../core/utils/responsive.dart';
import '../models/anime_analytics_report.dart';
import '../services/anime_analytics_service.dart';

/// 追番数据深度算法解析页面：
/// 1. 展示题材属性动态词云标签图（频次越多的标签字体越大、视觉越聚焦）；
/// 2. 统计呈现 3 联核心数据（观看番剧数、累计时长、题材杂食度得分）；
/// 3. 可视化展现题材分布条形百分比与样本溯源；
/// 4. 统计分析用户的追番活跃作息特征。
class DataAnalysisPage extends StatefulWidget {
  const DataAnalysisPage({super.key});

  @override
  State<DataAnalysisPage> createState() => _DataAnalysisPageState();
}

class _DataAnalysisPageState extends State<DataAnalysisPage> {
  late AnimeAnalyticsReport _report;

  @override
  void initState() {
    super.initState();
    _computeReport();
  }

  void _computeReport() {
    final history = WatchHistoryService.instance.items;
    setState(() {
      _report = AnimeAnalyticsService.analyze(history);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fontMgr = FontManager.instance;

    final titleStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
      fontFamily: fontMgr.activeFontFamily,
      fontFamilyFallback: FontManager.fallbackFontFamilies,
      color: theme.colorScheme.onSurface,
    );

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('追番数据分析', style: titleStyle),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: '重新计算画像',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _computeReport,
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppBreakpoints.maxSettingsWidth),
          child: _report.isEmpty
              ? _buildEmptyState(context)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  children: [
                    // 1. 核心二次元人格与称号卡片
                    _buildPersonaHeroCard(context),
                    const SizedBox(height: 16),

                    // 2. 题材偏好分布雷达/条形图卡片
                    _buildGenreDistributionCard(context),
                    const SizedBox(height: 16),

                    // 3. 追番作息与习惯卡片
                    _buildHabitScheduleCard(context),
                    const SizedBox(height: 16),

                    // 4. 题材作品溯源足迹
                    if (_report.genreAnimeSamples.isNotEmpty) ...[
                      _buildFootprintCard(context),
                      const SizedBox(height: 16),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  /// 1. 核心二次元称号与人格 Hero 卡片
  Widget _buildPersonaHeroCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fontMgr = FontManager.instance;

    final containerColor = M3Surface.container(
      context,
      level: M3ContainerLevel.low,
      pageKey: 'settings',
    );
    final border = M3Surface.border(
      context,
      pageKey: 'settings',
      forceBorder: true,
    );

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(24),
        border: border,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部小标签
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: isDark ? 0.25 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.bubble_chart_rounded,
                      size: 13,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      '属性标签词云',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: fontMgr.activeFontFamily,
                        fontFamilyFallback: FontManager.fallbackFontFamilies,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                _report.diversityLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: fontMgr.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // 核心二次元题材属性标签云（标签频次越多，字体越大、字重越粗、色彩越聚焦）
          _buildTagCloud(context),
          const SizedBox(height: 20),

          // 3 联核心数字指示卡片
          Row(
            children: [
              _buildStatChip(
                context,
                title: '观看番剧',
                value: '${_report.totalAnimeCount}',
                unit: '部',
                icon: Icons.movie_filter_rounded,
                color: const Color(0xFF1976D2),
              ),
              const SizedBox(width: 10),
              _buildStatChip(
                context,
                title: '累计时长',
                value: _report.totalWatchHours < 0.1
                    ? '0.1'
                    : _report.totalWatchHours.toStringAsFixed(1),
                unit: '小时',
                icon: Icons.timer_rounded,
                color: const Color(0xFF388E3C),
              ),
              const SizedBox(width: 10),
              _buildStatChip(
                context,
                title: '杂食度',
                value: '${_report.diversityScore}',
                unit: '分',
                icon: Icons.grain_rounded,
                color: const Color(0xFFE65100),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 构建自适应权重标签词云图：频次越高的题材字体越大、字重越粗、色彩越醒目
  Widget _buildTagCloud(BuildContext context) {
    final theme = Theme.of(context);
    final fontMgr = FontManager.instance;
    final isDark = theme.brightness == Brightness.dark;

    final genreCounts = _report.allGenreCounts;
    if (genreCounts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            '暂无标签数据',
            style: TextStyle(
              fontSize: 13,
              fontFamily: fontMgr.activeFontFamily,
              fontFamilyFallback: FontManager.fallbackFontFamilies,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.50),
            ),
          ),
        ),
      );
    }

    // 按频次从大到小排序
    final sortedEntries = genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxCount = sortedEntries.first.value;
    final minCount = sortedEntries.last.value;
    final countDiff = maxCount - minCount;

    // 综合计算每个标签的视觉权重 (0.0 ~ 1.0)：
    // 兼顾实际频次比例与自然排位梯度，彻底避免“全都是同一种巨大尺寸”的死板情况
    final itemsWithWeights = <(MapEntry<String, int>, double)>[];
    for (var i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      double weight;
      if (countDiff > 0) {
        // 当有频次差异时：频次占比占 70%，排位递减占 30%
        final freqRatio = (entry.value - minCount) / countDiff;
        final rankRatio = 1.0 - (i / sortedEntries.length);
        weight = (freqRatio * 0.70 + rankRatio * 0.30).clamp(0.0, 1.0);
      } else {
        // 当频次全部相同时：按排位衰减梯级权重，确保即使频次一样也能错落有致、大小自然
        weight = sortedEntries.length > 1
            ? (1.0 - (i / (sortedEntries.length - 1)) * 0.75).clamp(0.15, 1.0)
            : 0.85;
      }
      itemsWithWeights.add((entry, weight));
    }

    // 采用经典词云“中心扩散穿插”算法：
    // 将最大核心标签排在视觉重心区域，中等与较小标签在周围散落环绕
    final interleaved = <(MapEntry<String, int>, double)>[];
    for (var i = 0; i < itemsWithWeights.length; i++) {
      if (i % 2 == 0) {
        interleaved.add(itemsWithWeights[i]);
      } else {
        interleaved.insert(0, itemsWithWeights[i]);
      }
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 140),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.035)
            : Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.04),
          width: 1,
        ),
      ),
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: interleaved.map((item) {
            final entry = item.$1;
            final weight = item.$2;
            final genre = entry.key;
            final count = entry.value;

            // 字体大小平滑映射：最小 13px，最大 24.5px
            final fontSize = 13.0 + weight * 11.5;

            // 字重映射：高权重字重更粗
            final fontWeight = weight >= 0.70
                ? FontWeight.w900
                : (weight >= 0.35 ? FontWeight.w800 : FontWeight.w600);

            // 获取题材专属二次元色彩
            final tagColor = _getGenreColor(genre, isDark, theme);
            final tagBg = tagColor.withValues(alpha: isDark ? 0.16 : 0.08);

            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: 9 + weight * 4.5,
                vertical: 4 + weight * 2.8,
              ),
              decoration: BoxDecoration(
                color: tagBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: tagColor.withValues(alpha: isDark ? 0.38 : 0.22),
                  width: weight >= 0.70 ? 1.4 : 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '#$genre',
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: fontWeight,
                      letterSpacing: -0.2,
                      fontFamily: fontMgr.activeFontFamily,
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                      color: tagColor,
                    ),
                  ),
                  if (count > 1) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 0.8),
                      decoration: BoxDecoration(
                        color: tagColor.withValues(alpha: isDark ? 0.28 : 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: (fontSize * 0.65).clamp(9.5, 12.0),
                          fontWeight: FontWeight.w700,
                          fontFamily: fontMgr.activeFontFamily,
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                          color: tagColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  /// 获取题材专属色彩（充满二次元活力的特色调色板）
  Color _getGenreColor(String genre, bool isDark, ThemeData theme) {
    switch (genre) {
      case '恋爱':
      case '纯爱':
      case '百合':
      case '轻百合':
      case '恋爱喜剧':
        return isDark ? const Color(0xFFFF80AB) : const Color(0xFFE91E63);
      case '热血':
      case '战斗':
      case '竞技':
      case '运动':
        return isDark ? const Color(0xFFFF7043) : const Color(0xFFE64A19);
      case '日常':
      case '治愈':
      case '生活':
      case '萌系':
      case '萌':
        return isDark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
      case '奇幻':
      case '异世界':
      case '冒险':
      case '魔幻':
        return isDark ? const Color(0xFF4DD0E1) : const Color(0xFF00838F);
      case '科幻':
      case '机战':
      case '机甲':
      case '赛博朋克':
        return isDark ? const Color(0xFF64B5F6) : const Color(0xFF1565C0);
      case '悬疑':
      case '推理':
      case '智斗':
      case '怪谈':
        return isDark ? const Color(0xFFBA68C8) : const Color(0xFF7B1FA2);
      case '美食':
      case '搞笑':
        return isDark ? const Color(0xFFFFB74D) : const Color(0xFFF57C00);
      case '宫廷':
      case '历史':
      case '群像':
        return isDark ? const Color(0xFFD4E157) : const Color(0xFF689F38);
      default:
        final palette = isDark
            ? const [
                Color(0xFFFF80AB),
                Color(0xFF80D8FF),
                Color(0xFFA7FFEB),
                Color(0xFFFFD180),
                Color(0xFFEA80FC),
                Color(0xFFCCFF90),
              ]
            : const [
                Color(0xFFD81B60),
                Color(0xFF0277BD),
                Color(0xFF00796B),
                Color(0xFFEF6C00),
                Color(0xFF8E24AA),
                Color(0xFF558B2F),
              ];
        final hash = genre.hashCode.abs() % palette.length;
        return palette[hash];
    }
  }

  /// 3 联统计小指标构建辅助组件
  Widget _buildStatChip(
    BuildContext context, {
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    final theme = Theme.of(context);
    final fontMgr = FontManager.instance;
    final isDark = theme.brightness == Brightness.dark;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? color.withValues(alpha: 0.12) : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: color.withValues(alpha: isDark ? 0.22 : 0.15),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    fontFamily: fontMgr.activeFontFamily,
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFamily: fontMgr.activeFontFamily,
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                    color: color,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  unit,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    fontFamily: fontMgr.activeFontFamily,
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.60),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 2. 题材偏好条形图分布卡片
  Widget _buildGenreDistributionCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fontMgr = FontManager.instance;

    final containerColor = M3Surface.container(
      context,
      level: M3ContainerLevel.low,
      pageKey: 'settings',
    );
    final border = M3Surface.border(
      context,
      pageKey: 'settings',
      forceBorder: true,
    );

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(22),
        border: border,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pie_chart_rounded, size: 18, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '题材偏好分布',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: fontMgr.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                '共 ${_report.allGenreCounts.length} 种题材',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: fontMgr.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (_report.topGenres.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: Text(
                  '暂无解析到有效题材标签',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: fontMgr.activeFontFamily,
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.50),
                  ),
                ),
              ),
            )
          else
            ..._report.topGenres.map((item) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          item.genre,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            fontFamily: fontMgr.activeFontFamily,
                            fontFamilyFallback: FontManager.fallbackFontFamilies,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${item.count} 部作品',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            fontFamily: fontMgr.activeFontFamily,
                            fontFamilyFallback: FontManager.fallbackFontFamilies,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.50),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          item.percentageText,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            fontFamily: fontMgr.activeFontFamily,
                            fontFamilyFallback: FontManager.fallbackFontFamilies,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: item.percentage.clamp(0.02, 1.0),
                        minHeight: 7,
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.06),
                        valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// 3. 追番作息与习惯画像卡片
  Widget _buildHabitScheduleCard(BuildContext context) {
    final theme = Theme.of(context);
    final fontMgr = FontManager.instance;

    final containerColor = M3Surface.container(
      context,
      level: M3ContainerLevel.low,
      pageKey: 'settings',
    );
    final border = M3Surface.border(
      context,
      pageKey: 'settings',
      forceBorder: true,
    );

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(22),
        border: border,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.schedule_rounded, size: 18, color: const Color(0xFF8E24AA)),
              const SizedBox(width: 8),
              Text(
                '观影作息画像',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: fontMgr.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _report.activeTimeSlotLabel,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              fontFamily: fontMgr.activeFontFamily,
              fontFamilyFallback: FontManager.fallbackFontFamilies,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _report.activeTimeSlotDesc,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
              fontFamily: fontMgr.activeFontFamily,
              fontFamilyFallback: FontManager.fallbackFontFamilies,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.70),
            ),
          ),
        ],
      ),
    );
  }

  /// 4. 题材样本溯源足迹卡片
  Widget _buildFootprintCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fontMgr = FontManager.instance;

    final containerColor = M3Surface.container(
      context,
      level: M3ContainerLevel.low,
      pageKey: 'settings',
    );
    final border = M3Surface.border(
      context,
      pageKey: 'settings',
      forceBorder: true,
    );

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(22),
        border: border,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bookmarks_rounded, size: 18, color: const Color(0xFF00897B)),
              const SizedBox(width: 8),
              Text(
                '题材基因足迹',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: fontMgr.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '算法捕捉到以下代表作构成了你的喜好基底：',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              fontFamily: fontMgr.activeFontFamily,
              fontFamilyFallback: FontManager.fallbackFontFamilies,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 14),

          ..._report.genreAnimeSamples.entries.take(5).map((entry) {
            final genre = entry.key;
            final titles = entry.value;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark
                          ? theme.colorScheme.primary.withValues(alpha: 0.20)
                          : theme.colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '#$genre',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        fontFamily: fontMgr.activeFontFamily,
                        fontFamilyFallback: FontManager.fallbackFontFamilies,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      titles.join('、'),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                        fontFamily: fontMgr.activeFontFamily,
                        fontFamilyFallback: FontManager.fallbackFontFamilies,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 空数据时的萌系引导视图
  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final fontMgr = FontManager.instance;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
              child: Icon(
                Icons.analytics_outlined,
                size: 36,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '尚无播放数据',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFamily: fontMgr.activeFontFamily,
                fontFamilyFallback: FontManager.fallbackFontFamilies,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '在播放器中看几部喜欢的番剧，\n系统会自动提炼你的专属二次元画像与题材分布！',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
                fontFamily: fontMgr.activeFontFamily,
                fontFamilyFallback: FontManager.fallbackFontFamilies,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.60),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
