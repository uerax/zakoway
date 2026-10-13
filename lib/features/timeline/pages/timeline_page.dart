import 'package:flutter/material.dart';
import '../../../core/models/bangumi/bangumi_calendar.dart';
import '../../../core/network/bangumi_client.dart';
import '../../../core/utils/responsive.dart';
import '../../common/widgets/anime_card.dart';

class TimelinePage extends StatefulWidget {
  final BangumiClient client;
  final bool showAppBar;

  const TimelinePage({
    super.key,
    required this.client,
    this.showAppBar = true,
  });

  @override
  State<TimelinePage> createState() => _TimelinePageState();
}

class _TimelinePageState extends State<TimelinePage> with AutomaticKeepAliveClientMixin {
  late Future<List<BangumiCalendarDay>> _calendarFuture;
  ScrollController? _chipScrollController;
  ScrollController get _effectiveChipScrollController =>
      _chipScrollController ??= ScrollController();
  int _selectedDayIndex = 0;
  late final Set<int> _loadedDays = {_selectedDayIndex};

  static const _weekLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  static const double _chipWidth = 60.0;
  static const double _chipGap = 8.0;
  static const double _hPadding = 16.0;

  // 保证时间表页面切走后再切回时不重新销毁、不重新触发网络请求
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 默认高亮今天 (1=Mon .. 7=Sun)
    final todayWeekday = DateTime.now().weekday;
    _selectedDayIndex = (todayWeekday - 1).clamp(0, 6);
    _loadedDays.add(_selectedDayIndex);
    _loadCalendar();

    // 页面初次完成渲染后，将当前选中的星期自动滚动至可视区居中
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToSelectedChip(animate: false);
      }
    });
  }

  @override
  void dispose() {
    _chipScrollController?.dispose();
    super.dispose();
  }

  void _scrollToSelectedChip({bool animate = true}) {
    final controller = _effectiveChipScrollController;
    if (!controller.hasClients) return;

    final maxScroll = controller.position.maxScrollExtent;
    final minScroll = controller.position.minScrollExtent;
    final viewportWidth = controller.position.viewportDimension;

    final itemCenter = _hPadding + _selectedDayIndex * (_chipWidth + _chipGap) + (_chipWidth / 2);
    final targetOffset = (itemCenter - viewportWidth / 2).clamp(minScroll, maxScroll);

    if (animate) {
      controller.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    } else {
      controller.jumpTo(targetOffset);
    }
  }

  void _loadCalendar({bool forceRefresh = false}) {
    setState(() {
      _calendarFuture = widget.client.getCalendar(forceRefresh: forceRefresh);
    });
  }

  @override
  void didUpdateWidget(TimelinePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client.baseUrl != widget.client.baseUrl ||
        oldWidget.client.activeRouteId != widget.client.activeRouteId ||
        oldWidget.client.sourcePreset != widget.client.sourcePreset) {
      _loadedDays.clear();
      _loadedDays.add(_selectedDayIndex);
      _loadCalendar(forceRefresh: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final safeTop = MediaQuery.paddingOf(context).top;

    // 当作为首页“连载”子面板嵌入时（showAppBar == false）：
    // 采用沉浸式无边框架构，顶部预留安全区避让悬浮胶囊，底部避让 Dock 栏
    if (!widget.showAppBar) {
      return Column(
        children: [
          SizedBox(height: safeTop + 48),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _buildWeekdayChips(theme, isDark),
          ),
          Expanded(
            child: _buildCalendarBody(theme),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.calendar_month_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            const Text('连载周历', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '刷新连载表',
            onPressed: () => _loadCalendar(forceRefresh: true),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: _buildWeekdayChips(theme, isDark),
          ),
        ),
      ),
      body: _buildCalendarBody(theme),
    );
  }

  Widget _buildWeekdayChips(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      controller: _effectiveChipScrollController,
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: _hPadding),
      child: Row(
        children: List.generate(7, (index) {
          final isSelected = _selectedDayIndex == index;
          final isToday = (DateTime.now().weekday - 1) == index;

          return Padding(
            padding: EdgeInsets.only(right: index == 6 ? 0 : _chipGap),
            child: SizedBox(
              width: _chipWidth,
              child: ChoiceChip(
                label: Center(
                  child: Text(
                    _weekLabels[index],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : (isToday ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ),
                selected: isSelected,
                selectedColor: theme.colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.14),
                backgroundColor: theme.colorScheme.surfaceContainerHigh,
                shape: const StadiumBorder(),
                side: isToday && !isSelected
                    ? BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.6), width: 1.2)
                    : BorderSide.none,
                showCheckmark: false,
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onSelected: (selected) {
                  if (selected) {
                    setState(() {
                      _selectedDayIndex = index;
                      _loadedDays.add(index);
                    });
                    _scrollToSelectedChip(animate: true);
                  }
                },
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildCalendarBody(ThemeData theme) {
    return FutureBuilder<List<BangumiCalendarDay>>(
      future: _calendarFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在同步连载更新...'),
              ],
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    '数据获取失败',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.redAccent),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _loadCalendar(forceRefresh: true),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重试'),
                  ),
                ],
              ),
            ),
          );
        }

        final calendarList = snapshot.data ?? [];
        if (calendarList.isEmpty) {
          return const Center(child: Text('暂无每日连载数据'));
        }

        // 核心优化：使用 IndexedStack 配合按需惰性挂载 (Lazy IndexedStack)
        // 1. 初次打开仅挂载当前选中的星期，其余 6 天暂用轻量占位，杜绝 7 天高清大图同时发起并发网络请求；
        // 2. 用户点击切换至其他星期时按需激活并随后永久常驻内存，二次切换 0ms 瞬间显示，永无白屏。
        return IndexedStack(
          index: _selectedDayIndex,
          children: List.generate(7, (index) {
            if (!_loadedDays.contains(index)) {
              return SizedBox.shrink(
                key: ValueKey('unloaded_day_${index + 1}_${widget.client.sourcePreset.name}'),
              );
            }

            final weekdayId = index + 1; // 1=Mon .. 7=Sun
            final dayData = calendarList.firstWhere(
              (d) => d.weekday.id == weekdayId,
              orElse: () => calendarList.length > index
                  ? calendarList[index]
                  : BangumiCalendarDay(
                      weekday: BangumiWeekday(
                        id: weekdayId,
                        en: '',
                        cn: _weekLabels[index],
                        ja: '',
                      ),
                      items: const [],
                    ),
            );

            return _KeepAliveDayView(
              key: ValueKey('day_${weekdayId}_${widget.client.sourcePreset.name}'),
              dayData: dayData,
              presetName: widget.client.sourcePreset.name,
            );
          }),
        );
      },
    );
  }
}

class _KeepAliveDayView extends StatefulWidget {
  final BangumiCalendarDay dayData;
  final String presetName;

  const _KeepAliveDayView({
    super.key,
    required this.dayData,
    required this.presetName,
  });

  @override
  State<_KeepAliveDayView> createState() => _KeepAliveDayViewState();
}

class _KeepAliveDayViewState extends State<_KeepAliveDayView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.dayData.items.isEmpty) {
      return Center(
        child: Text('【${widget.dayData.weekday.cn}】今日暂无放送'),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final int crossAxisCount = AppBreakpoints.gridColumns(width);

        return GridView.builder(
          key: PageStorageKey<String>(
            'day_${widget.dayData.weekday.id}_${widget.presetName}',
          ),
          // 底部留出 96px，配合底栏 extendBody: true 悬浮毛玻璃穿透
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: crossAxisCount >= 3 ? 0.58 : 0.62,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: widget.dayData.items.length,
          itemBuilder: (context, index) {
            final item = widget.dayData.items[index];
            return AnimeCard(item: item, compact: true);
          },
        );
      },
    );
  }
}
