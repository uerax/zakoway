import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../core/collection/services/anime_collection_service.dart';
import '../../../core/models/bangumi/bangumi_collection.dart';
import '../../../core/services/watch_history_service.dart';
import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/appearance_manager.dart';
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
    final collections = AnimeCollectionService.instance.allItems;
    setState(() {
      _report = AnimeAnalyticsService.analyze(history, collections: collections);
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

    return ListenableBuilder(
      listenable: AppearanceManager.instance,
      builder: (context, _) {
        final content = Center(
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

                      // 1.5 追番状态与完成率透视卡片 (由我的追番驱动)
                      if (_report.totalCollectionCount > 0) ...[
                        _buildCollectionInsightCard(context),
                        const SizedBox(height: 16),
                      ],

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
        );

        // 特殊处理说明：
        // 1. 最外层包裹 100% 不透明的 ColoredBox(color: theme.scaffoldBackgroundColor)，
        //    从物理层面杜绝移动端路由推入（0.5s 转场动画）期间或 AppBar 背后漏出底层页面内容与黑底；
        // 2. 第二层铺满专属个人壁纸层，使壁纸从屏幕最顶端自然延伸至 AppBar 背后；
        // 3. 内部 Scaffold 保持 transparent，AppBar 背景透明且 elevation: 0、scrolledUnderElevation: 0，
        //    使标题栏与全屏壁纸柔和相融，同时 body 内容天然在 AppBar 下方正常流淌，零溢出与遮挡风险。
        return ColoredBox(
          color: theme.scaffoldBackgroundColor,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 0. 个人专属背景壁纸层 (全景铺满，涵盖 AppBar 背后)
              AppearanceManager.instance.buildWallpaperLayer(pageKey: 'profile'),
              // 1. 数据分析主脚手架
              Scaffold(
                backgroundColor: Colors.transparent,
                appBar: AppBar(
                  title: Text('追番数据分析', style: titleStyle),
                  centerTitle: true,
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  actions: [
                    IconButton(
                      tooltip: '重新计算画像',
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: _computeReport,
                    ),
                  ],
                ),
                body: content,
              ),
            ],
          ),
        );
      },
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
    final border = M3Surface.cardBorder(context);
    final shadow = M3Surface.cardShadow(context);

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(24),
        border: border,
        boxShadow: shadow,
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
              const SizedBox(width: 8),
              // 特殊处理说明：称号文案包裹 Expanded + Align 弹性右对齐并限制单行省略，防止极窄窗口下两端挤压溢出
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _report.diversityLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: fontMgr.activeFontFamily,
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
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
                title: '观看',
                value: '${_report.totalAnimeCount}',
                unit: '部',
                icon: Icons.movie_filter_rounded,
                color: const Color(0xFF1976D2),
              ),
              const SizedBox(width: 10),
              _buildStatChip(
                context,
                title: '时长',
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

  /// 构建自适应经典文字词云图（2D 螺旋紧凑无重叠排布、横竖穿插、保留二次元专属色彩）：
  /// 特殊处理说明：
  /// 1. 采用阿基米德螺旋线碰撞放置算法（Archimedean Spiral），让高频大字聚焦于视觉中心，中小字横竖紧密咬合填补缝隙，完全消除外框气泡，呈现纯净的经典文字词云质感；
  /// 2. 中文方块字天然支持垂直排版（按字符换行堆叠），高频词按 25%~30% 比例交替进行纵横混排，高度还原自然生动的视觉构图；
  /// 3. 支持 Tooltip 交互（悬浮或点击提示具体观看番剧数），兼顾视觉极简与量化数据可读性；
  /// 4. 严守字体回退链，注入 activeFontFamily 与 fallbackFontFamilies，防止 Windows 平台退回中易宋体。
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

    return Container(
      width: double.infinity,
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
      clipBehavior: Clip.antiAlias,
      child: _WordCloudView(
        genreCounts: genreCounts,
        isDark: isDark,
        theme: theme,
        colorGetter: _getGenreColor,
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
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
            // 特殊处理说明：标题行采用 Flexible + 省略号，避免极窄视口下小指标卡片内图标与文本横向溢出
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: fontMgr.activeFontFamily,
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 特殊处理说明：数值与单位行使用 FittedBox 自适应等比微缩，保证数值在极窄视口或较大数字时完整可见且不溢出
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
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
            ),
          ],
        ),
      ),
    );
  }

  /// 1.5 追番状态与完成率透视卡片 (由我的追番驱动)
  Widget _buildCollectionInsightCard(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fontMgr = FontManager.instance;

    final containerColor = M3Surface.container(
      context,
      level: M3ContainerLevel.low,
      pageKey: 'settings',
    );
    final border = M3Surface.cardBorder(context);
    final shadow = M3Surface.cardShadow(context);

    final stats = _report.collectionCounts;
    final watching = stats[CollectType.watching] ?? 0;
    final plan = stats[CollectType.planToWatch] ?? 0;
    final watched = stats[CollectType.watched] ?? 0;
    final onHold = stats[CollectType.onHold] ?? 0;
    final abandoned = stats[CollectType.abandoned] ?? 0;

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(24),
        border: border,
        boxShadow: shadow,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.favorite_rounded, size: 18, color: Color(0xFFE91E63)),
              const SizedBox(width: 8),
              Text(
                '追番透视',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: fontMgr.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              // 特殊处理说明：完结率胶囊采用 Expanded + Align 弹性右对齐并限制单行省略，防止极窄视口下两端挤压溢出
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE91E63).withValues(alpha: isDark ? 0.22 : 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '完结率 ${_report.completionRateText}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        fontFamily: fontMgr.activeFontFamily,
                        fontFamilyFallback: FontManager.fallbackFontFamilies,
                        color: const Color(0xFFE91E63),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildCollectionStatCell(context, '在看', '$watching', const Color(0xFF1976D2)),
              const SizedBox(width: 8),
              _buildCollectionStatCell(context, '想看', '$plan', const Color(0xFF7B1FA2)),
              const SizedBox(width: 8),
              _buildCollectionStatCell(context, '看过', '$watched', const Color(0xFF388E3C)),
              const SizedBox(width: 8),
              _buildCollectionStatCell(context, '抛弃', '${onHold + abandoned}', const Color(0xFFE65100)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionStatCell(
    BuildContext context,
    String label,
    String count,
    Color accentColor,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fontMgr = FontManager.instance;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? accentColor.withValues(alpha: 0.14)
              : accentColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.25),
            width: 0.8,
          ),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                count,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: fontMgr.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  color: accentColor,
                ),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: fontMgr.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                ),
              ),
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
    final border = M3Surface.cardBorder(context);
    final shadow = M3Surface.cardShadow(context);

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(22),
        border: border,
        boxShadow: shadow,
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
                '题材偏好',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  fontFamily: fontMgr.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              // 特殊处理说明：题材数文案采用 Expanded + Align 弹性右对齐并限制单行省略，防止极窄窗口下两端挤压溢出
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '共 ${_report.allGenreCounts.length} 种题材',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: fontMgr.activeFontFamily,
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
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
                        Flexible(
                          child: Text(
                            '${item.count} 部作品',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              fontFamily: fontMgr.activeFontFamily,
                              fontFamilyFallback: FontManager.fallbackFontFamilies,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.50),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            item.percentageText,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              fontFamily: fontMgr.activeFontFamily,
                              fontFamilyFallback: FontManager.fallbackFontFamilies,
                              color: theme.colorScheme.primary,
                            ),
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
    final border = M3Surface.cardBorder(context);
    final shadow = M3Surface.cardShadow(context);

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(22),
        border: border,
        boxShadow: shadow,
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
    final border = M3Surface.cardBorder(context);
    final shadow = M3Surface.cardShadow(context);

    return Container(
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(22),
        border: border,
        boxShadow: shadow,
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

/// 经典文字词云展示视图组件
class _WordCloudView extends StatelessWidget {
  final Map<String, int> genreCounts;
  final bool isDark;
  final ThemeData theme;
  final Color Function(String, bool, ThemeData) colorGetter;

  const _WordCloudView({
    required this.genreCounts,
    required this.isDark,
    required this.theme,
    required this.colorGetter,
  });

  @override
  Widget build(BuildContext context) {
    final fontMgr = FontManager.instance;
    final fontFamily = fontMgr.activeFontFamily;
    final fontFallback = FontManager.fallbackFontFamilies;

    return LayoutBuilder(
      builder: (context, constraints) {
        final canvasWidth = constraints.maxWidth;
        // 动态高度自适应：窄屏长宽比约 1.6:1 ~ 1.7:1，宽屏锁定在 245dp 以内，兼顾密集紧凑度与开阔感
        final canvasHeight = (canvasWidth * 0.58).clamp(210.0, 245.0);

        final placedItems = _WordCloudLayoutEngine.compute(
          genreCounts: genreCounts,
          canvasWidth: canvasWidth,
          canvasHeight: canvasHeight,
          isDark: isDark,
          theme: theme,
          colorGetter: colorGetter,
          fontFamily: fontFamily,
          fontFallback: fontFallback,
        );

        return SizedBox(
          width: canvasWidth,
          height: canvasHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: placedItems.map((item) {
              return Positioned(
                left: item.x,
                top: item.y,
                child: Tooltip(
                  message: '${item.genre} · ${item.count} 部番剧',
                  child: Text(
                    item.displayText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: item.fontSize,
                      fontWeight: item.fontWeight,
                      height: item.isVertical ? 1.05 : 1.15,
                      letterSpacing: item.isVertical ? 0 : -0.2,
                      fontFamily: fontFamily,
                      fontFamilyFallback: fontFallback,
                      color: item.color.withValues(alpha: item.opacity),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}

/// 词云渲染实体模型
class _WordCloudItem {
  final String genre;
  final int count;
  final String displayText;
  final double x;
  final double y;
  final double fontSize;
  final FontWeight fontWeight;
  final bool isVertical;
  final Color color;
  final double opacity;

  const _WordCloudItem({
    required this.genre,
    required this.count,
    required this.displayText,
    required this.x,
    required this.y,
    required this.fontSize,
    required this.fontWeight,
    required this.isVertical,
    required this.color,
    required this.opacity,
  });
}

/// 2D 阿基米德螺旋线碰撞紧密排版引擎：
/// 1. 将最高频词汇定位在画布重心，其余词汇沿椭圆螺旋线向外紧凑填补空白；
/// 2. 支持中文题材横竖穿插（字间换行），打破单调的横向排列；
/// 3. 多级字号降级重试机制，确保各类题材均能找到合适的无重叠空隙。
class _WordCloudLayoutEngine {
  static List<_WordCloudItem> compute({
    required Map<String, int> genreCounts,
    required double canvasWidth,
    required double canvasHeight,
    required bool isDark,
    required ThemeData theme,
    required Color Function(String, bool, ThemeData) colorGetter,
    required String? fontFamily,
    required List<String> fontFallback,
  }) {
    if (genreCounts.isEmpty || canvasWidth < 60 || canvasHeight < 60) {
      return const [];
    }

    final sorted = genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final maxCount = sorted.first.value;
    final minCount = sorted.last.value;
    final countDiff = maxCount - minCount;

    final placedItems = <_WordCloudItem>[];
    final placedRects = <Rect>[];

    final cx = canvasWidth / 2;
    final cy = canvasHeight / 2;
    // 椭圆长宽比系数，使螺旋线走向贴合长方形画布
    final aspectFactor = (canvasWidth / canvasHeight).clamp(1.15, 2.3);
    // 基于画布宽度微调缩放基准
    final scale = (canvasWidth / 360.0).clamp(0.85, 1.25);

    for (var i = 0; i < sorted.length; i++) {
      final entry = sorted[i];
      final genre = entry.key;
      final count = entry.value;

      double weight;
      if (countDiff > 0) {
        final freqRatio = (count - minCount) / countDiff;
        final rankRatio = 1.0 - (i / sorted.length);
        weight = (freqRatio * 0.70 + rankRatio * 0.30).clamp(0.0, 1.0);
      } else {
        weight = sorted.length > 1
            ? (1.0 - (i / (sorted.length - 1)) * 0.75).clamp(0.15, 1.0)
            : 0.90;
      }

      // 字体大小平滑映射：高频最大约 33px，低频约 11.5px
      var fontSize = (11.5 + math.pow(weight, 0.72) * 21.5) * scale;
      final fontWeight = weight >= 0.72
          ? FontWeight.w900
          : (weight >= 0.38 ? FontWeight.w800 : FontWeight.w600);

      final baseColor = colorGetter(genre, isDark, theme);
      final opacity = (0.72 + weight * 0.28).clamp(0.60, 1.0);

      // 决定排版方向：纯汉字题材（2~4字）在特定位序尝试竖排（约25%~30%），英文/数字强制横排
      final canVertical = genre.length >= 2 &&
          genre.length <= 4 &&
          RegExp(r'^[一-龥]+$').hasMatch(genre);

      final preferVertical = canVertical && (i % 3 == 1 || (i > 3 && (i * 7) % 5 == 0));

      final success = _tryPlace(
        genre: genre,
        count: count,
        baseFontSize: fontSize,
        fontWeight: fontWeight,
        preferVertical: preferVertical,
        canVertical: canVertical,
        baseColor: baseColor,
        opacity: opacity,
        cx: cx,
        cy: cy,
        canvasWidth: canvasWidth,
        canvasHeight: canvasHeight,
        aspectFactor: aspectFactor,
        fontFamily: fontFamily,
        fontFallback: fontFallback,
        placedItems: placedItems,
        placedRects: placedRects,
      );

      // 若区域过于拥挤未放下，以 75% 较小尺寸重试横排
      if (!success) {
        _tryPlace(
          genre: genre,
          count: count,
          baseFontSize: fontSize * 0.75,
          fontWeight: FontWeight.w600,
          preferVertical: false,
          canVertical: canVertical,
          baseColor: baseColor,
          opacity: opacity * 0.88,
          cx: cx,
          cy: cy,
          canvasWidth: canvasWidth,
          canvasHeight: canvasHeight,
          aspectFactor: aspectFactor,
          fontFamily: fontFamily,
          fontFallback: fontFallback,
          placedItems: placedItems,
          placedRects: placedRects,
        );
      }
    }

    return placedItems;
  }

  static bool _tryPlace({
    required String genre,
    required int count,
    required double baseFontSize,
    required FontWeight fontWeight,
    required bool preferVertical,
    required bool canVertical,
    required Color baseColor,
    required double opacity,
    required double cx,
    required double cy,
    required double canvasWidth,
    required double canvasHeight,
    required double aspectFactor,
    required String? fontFamily,
    required List<String> fontFallback,
    required List<_WordCloudItem> placedItems,
    required List<Rect> placedRects,
  }) {
    final orientationAttempts = preferVertical
        ? [true, false]
        : (canVertical ? [false, true] : [false]);

    for (final isVertical in orientationAttempts) {
      final text = isVertical ? genre.split('').join('\n') : genre;
      final textStyle = TextStyle(
        fontSize: baseFontSize,
        fontWeight: fontWeight,
        height: isVertical ? 1.05 : 1.15,
        letterSpacing: isVertical ? 0 : -0.2,
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallback,
      );

      final tp = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      final w = tp.width;
      final h = tp.height;
      const margin = 2.5;
      final boxW = w + margin * 2;
      final boxH = h + margin * 2;

      if (boxW > canvasWidth - 8 || boxH > canvasHeight - 8) {
        continue;
      }

      const stepAngle = 0.18;
      const radiusStep = 0.65;
      final maxRadius = math.max(canvasWidth, canvasHeight) * 0.65;
      var theta = 0.0;
      var found = false;
      double bestX = 0;
      double bestY = 0;

      while (true) {
        final r = radiusStep * theta;
        if (r > maxRadius) break;

        final candX = cx + r * math.cos(theta) * aspectFactor - boxW / 2;
        final candY = cy + r * math.sin(theta) - boxH / 2;

        if (candX >= 4 &&
            candX + boxW <= canvasWidth - 4 &&
            candY >= 4 &&
            candY + boxH <= canvasHeight - 4) {
          final candRect = Rect.fromLTWH(candX, candY, boxW, boxH);
          var overlaps = false;
          for (var k = 0; k < placedRects.length; k++) {
            if (candRect.overlaps(placedRects[k])) {
              overlaps = true;
              break;
            }
          }

          if (!overlaps) {
            found = true;
            bestX = candX + margin;
            bestY = candY + margin;
            placedRects.add(candRect);
            placedItems.add(_WordCloudItem(
              genre: genre,
              count: count,
              displayText: text,
              x: bestX,
              y: bestY,
              fontSize: baseFontSize,
              fontWeight: fontWeight,
              isVertical: isVertical,
              color: baseColor,
              opacity: opacity,
            ));
            break;
          }
        }

        theta += stepAngle;
      }

      if (found) return true;
    }

    return false;
  }
}
