import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/models/history/watch_history_item.dart';
import '../../../core/services/watch_history_service.dart';
import '../../../core/theme/m3_surface.dart';
import '../../common/widgets/anime_card.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import '../../common/widgets/cached_anime_image.dart';

/// 播放历史记录页面（参考 animaku HistoryPage.tsx 视觉与时间轴交互）：
/// 1. 顶部统计指示栏：展示在追番剧部数、今日观看以及累计观看时长；
/// 2. 业界四段式时间轴分组：按「今天」、「昨天」、「近 7 天」、「更早以前」清晰归类；
/// 3. 单动漫聚合机制：同一番剧最新集数置顶，卡片清晰展示作品名、集数、视频源、时长进度与相对时间；
/// 4. 交互：支持单条轻扫删除 (Dismissible) 或点击垃圾桶单独删除，支持右上角全量清空二次确认；
/// 5. 点击卡片直达番剧详情弹窗，后续播放器完成后支持直接无缝续播。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    await WatchHistoryService.instance.getHistory();
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteItem(WatchHistoryItem item) async {
    HapticFeedback.lightImpact();
    await WatchHistoryService.instance.remove(item.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已移除《${item.title}》播放记录'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空播放历史'),
        content: const Text('确定要清空全部播放历史记录吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确认清空'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      HapticFeedback.mediumImpact();
      await WatchHistoryService.instance.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('播放历史已清空')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ListenableBuilder(
      listenable: WatchHistoryService.instance,
      builder: (context, _) {
        final items = WatchHistoryService.instance.items;
        final groups = groupWatchHistory(items);
        final stats = computeHistoryStats(items);

        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            title: const Text(
              '播放历史',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            centerTitle: true,
            actions: [
              if (items.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.delete_sweep_rounded),
                  tooltip: '清空历史',
                  onPressed: _confirmClearAll,
                ),
            ],
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? _buildEmptyState(context, theme)
                  : CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                    // 1. 顶部数据指标胶囊统计栏
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: _buildStatsBar(context, theme, isDark, stats),
                      ),
                    ),

                    // 2. 四段式时间轴分组列表
                    for (final group in groups) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                          child: Row(
                            children: [
                              Container(
                                width: 3.5,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                group.label,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: theme.textTheme.titleMedium?.color,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '(${group.items.length})',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final item = group.items[index];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _buildHistoryCard(context, theme, isDark, item),
                              );
                            },
                            childCount: group.items.length,
                          ),
                        ),
                      ),
                    ],

                    const SliverToBoxAdapter(
                      child: SizedBox(height: 32),
                    ),
                  ],
                ),
        );
      },
    );
  }

  /// 顶部统计栏（追番部数、今日观看、累计时长）
  Widget _buildStatsBar(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    WatchHistoryStats stats,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: M3Surface.container(context, level: M3ContainerLevel.low),
        borderRadius: BorderRadius.circular(20),
        border: M3Surface.border(context),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            theme: theme,
            title: '在追番剧',
            value: '${stats.totalCount} 部',
            icon: Icons.movie_filter_outlined,
          ),
          Container(
            width: 1,
            height: 28,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          _buildStatItem(
            theme: theme,
            title: '今日观看',
            value: '${stats.todayCount} 部',
            icon: Icons.today_rounded,
          ),
          Container(
            width: 1,
            height: 28,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          _buildStatItem(
            theme: theme,
            title: '累计观看',
            value: stats.totalWatchHoursText,
            icon: Icons.access_time_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem({
    required ThemeData theme,
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: theme.colorScheme.primary),
            const SizedBox(width: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: theme.textTheme.titleMedium?.color,
          ),
        ),
      ],
    );
  }

  /// 单条历史记录卡片（支持侧滑删除）
  Widget _buildHistoryCard(
    BuildContext context,
    ThemeData theme,
    bool isDark,
    WatchHistoryItem item,
  ) {
    return Dismissible(
      key: Key('history_${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withAlpha(210),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: theme.colorScheme.onErrorContainer,
          size: 24,
        ),
      ),
      onDismissed: (_) => _deleteItem(item),
      child: BouncingScaleCard(
        onTap: () => navigateToVideoPlayer(
          context,
          item.toBangumiItem(),
          initialPosition: Duration(seconds: item.position.toInt()),
          currentEpisode: item.episode,
        ),
        child: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: M3Surface.container(context, level: M3ContainerLevel.low),
            borderRadius: BorderRadius.circular(16),
            border: M3Surface.border(context),
          ),
          child: Row(
            children: [
              // 1. 左侧海报缩略图（带已看完/进度微标）
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 72,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedAnimeImage(
                        imageUrl: item.cover ?? '',
                        fit: BoxFit.cover,
                      ),
                      // 底部暗色微渐变与完播/进度标签
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withAlpha(180),
                              ],
                            ),
                          ),
                          child: Text(
                            item.isFinished ? '已看完' : '${(item.progress * 100).toInt()}%',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: item.isFinished ? Colors.greenAccent : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // 2. 中间信息流：片名、集数、视频源、时间轴与进度条
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: theme.textTheme.titleMedium?.color,
                      ),
                    ),
                    const SizedBox(height: 5),

                    // 集数 · 视频源 · 相对时间
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '第 ${item.episode} 话',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                        if (item.pluginName.isNotEmpty && item.pluginName != '默认源') ...[
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              item.pluginName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 6),
                        // 特殊处理说明：相对时间文本使用 Expanded + Align 弹性右对齐并限制单行截断，防止窄屏下与集数/片源文本挤压溢出
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              item.formatRelativeWatchTime(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),

                    // M3 圆润进度条 + 具体秒数
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              value: item.progress.clamp(0.0, 1.0),
                              minHeight: 3.5,
                              backgroundColor: theme.colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                item.isFinished ? Colors.green : theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // 特殊处理说明：时间轴文本限制最大宽度并通过 FittedBox 自动缩放，防止长时码或窄屏下挤爆进度条
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 80),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              item.positionText,
                              style: TextStyle(
                                fontSize: 10,
                                fontFamily: 'monospace',
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 3. 右侧删除小图标
              IconButton(
                icon: Icon(
                  Icons.close_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                ),
                tooltip: '移除记录',
                onPressed: () => _deleteItem(item),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 空状态占位
  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history_toggle_off_rounded,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withAlpha(120),
          ),
          const SizedBox(height: 14),
          Text(
            '暂无播放历史',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: theme.textTheme.titleMedium?.color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '快去挑选喜欢的动画开始追番吧',
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
