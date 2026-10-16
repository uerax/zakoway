import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/providers/auth_providers.dart';
import '../../../core/collection/models/anime_collection_item.dart';
import '../../../core/collection/providers/collection_providers.dart';
import '../../../core/models/bangumi/bangumi_collection.dart';
import '../../../core/theme/m3_surface.dart';
import '../../../core/utils/appearance_manager.dart';
import '../../../core/utils/font_manager.dart';
import '../../../core/utils/responsive.dart';
import '../../auth/widgets/auth_login_sheet.dart';
import '../../common/widgets/anime_card.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import '../../settings/widgets/tg_action_sheet.dart';

/// “我的追番”主页面：
/// 1. 5 个分类分段管理（在看、想看、看过、搁置、抛弃），带动态数量徽章；
/// 2. 支持下拉刷新及与 Bangumi 远端双向同步；
/// 3. 支持长按呼出快捷修改状态与取消追番；
/// 4. 适配全平台断点网格布局，严格遵循 Windows 安全字体保护规范。
class MyCollectionPage extends ConsumerStatefulWidget {
  final CollectType initialType;

  const MyCollectionPage({
    super.key,
    this.initialType = CollectType.watching,
  });

  @override
  ConsumerState<MyCollectionPage> createState() => _MyCollectionPageState();
}

class _MyCollectionPageState extends ConsumerState<MyCollectionPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const List<CollectType> _tabs = [
    CollectType.watching,
    CollectType.planToWatch,
    CollectType.watched,
    CollectType.onHold,
    CollectType.abandoned,
  ];

  @override
  void initState() {
    super.initState();
    final initialIndex = _tabs.indexOf(widget.initialType);
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: initialIndex != -1 ? initialIndex : 0,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  TextStyle _safeStyle({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: FontManager.instance.activeFontFamily,
      fontFamilyFallback: FontManager.fallbackFontFamilies,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: _safeStyle(fontSize: 13, color: Colors.white),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleSync() async {
    final isLoggedIn = ref.read(isLoggedInProvider);
    if (!isLoggedIn) {
      HapticFeedback.lightImpact();
      final login = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            '连接 Bangumi 同步追番',
            style: _safeStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          content: Text(
            '当前为本地游客模式。连接 Bangumi 账号后，即可将本地收藏与官方账号双向实时同步。',
            style: _safeStyle(fontSize: 13.5, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('稍后', style: _safeStyle(color: Colors.grey)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('立即连接', style: _safeStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (login == true && mounted) {
        AuthLoginSheet.show(context);
      }
      return;
    }

    HapticFeedback.mediumImpact();
    final notifier = ref.read(collectionControllerProvider.notifier);
    final count = await notifier.syncWithRemote();
    if (!mounted) return;
    _showToast('追番同步完成，更新了 $count 部番剧数据');
  }

  void _showItemActionSheet(AnimeCollectionItem item) {
    HapticFeedback.selectionClick();
    final actions = <TgActionItem>[];

    for (final t in _tabs) {
      if (t != item.type) {
        actions.add(
          TgActionItem(
            label: '移至【${t.label}】',
            onTap: () {
              Navigator.of(context).pop();
              ref.read(collectionControllerProvider.notifier).updateStatus(
                    bangumiItem: item.toBangumiItem(),
                    type: t,
                  );
              _showToast('已移至【${t.label}】');
            },
          ),
        );
      }
    }

    actions.add(
      TgActionItem(
        label: '取消追番',
        isDestructive: true,
        onTap: () {
          Navigator.of(context).pop();
          ref.read(collectionControllerProvider.notifier).removeStatus(item.subjectId);
          _showToast('已取消追番');
        },
      ),
    );

    TgActionSheet.show<void>(
      context,
      header: item.title,
      title: '当前状态: ${item.type.label}',
      actions: actions,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final stats = ref.watch(collectionCountStatsProvider);
    final allItems = ref.watch(allCollectionsProvider);
    final collectionState = ref.watch(collectionControllerProvider);
    final isSyncing = collectionState.isSyncing;
    final isLoggedIn = ref.watch(isLoggedInProvider);

    return ListenableBuilder(
      listenable: AppearanceManager.instance,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: theme.scaffoldBackgroundColor,
          appBar: AppBar(
            titleSpacing: 0,
            backgroundColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '我的追番',
                  style: _safeStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  '共收藏 ${allItems.length} 部番剧 · ${isLoggedIn ? "Bangumi 已连接" : "本地游客模式"}',
                  style: _safeStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
            actions: [
              // 追番云端同步按钮
              BouncingScaleCard(
                scaleDown: 0.90,
                immediateTap: true,
                onTap: isSyncing ? null : _handleSync,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? primaryColor.withValues(alpha: 0.18)
                          : primaryColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isSyncing)
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: primaryColor,
                            ),
                          )
                        else
                          Icon(
                            Icons.sync_rounded,
                            size: 15,
                            color: primaryColor,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          isSyncing ? '同步中' : '同步数据',
                          style: _safeStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(44),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(3.0),
                height: 40,
                decoration: BoxDecoration(
                  color: M3Surface.container(context,
                      level: M3ContainerLevel.low, pageKey: 'profile'),
                  borderRadius: BorderRadius.circular(16),
                  border: M3Surface.cardBorder(context),
                  boxShadow: M3Surface.cardShadow(context, elevation: 0.6),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: TabBar(
                  controller: _tabController,
                  splashFactory: NoSplash.splashFactory,
                  overlayColor: WidgetStateProperty.all(Colors.transparent),
                  isScrollable: false,
                  dividerColor: Colors.transparent,
                  padding: EdgeInsets.zero,
                  labelPadding: EdgeInsets.zero,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: isDark
                        ? primaryColor.withValues(alpha: 0.26)
                        : primaryColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.4),
                      width: 1.0,
                    ),
                  ),
                  labelColor: isDark ? Colors.white : primaryColor,
                  unselectedLabelColor:
                      theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  labelStyle: _safeStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w700,
                  ),
                  unselectedLabelStyle: _safeStyle(
                    fontSize: 12.0,
                    fontWeight: FontWeight.w500,
                  ),
                  tabs: _tabs.map((type) {
                    final count = stats[type] ?? 0;
                    return Tab(
                      height: 33,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5.0,
                          vertical: 2.0,
                        ),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                type.label,
                                style: TextStyle(
                                  fontSize: 12.0,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: FontManager.instance.activeFontFamily,
                                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                                ),
                                maxLines: 1,
                                softWrap: false,
                              ),
                              if (count > 0) ...[
                                const SizedBox(width: 3.0),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4.0,
                                    vertical: 0.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.18)
                                        : primaryColor.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$count',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      fontFamily: FontManager.instance.activeFontFamily,
                                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.95)
                                          : primaryColor,
                                    ),
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                ),
              ),
            ),
          ),
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 0. 壁纸透射层（深浅色自适应，归属个人模块）
              AppearanceManager.instance.buildWallpaperLayer(pageKey: 'profile'),

              // 1. 5 分类内容视图
              TabBarView(
                controller: _tabController,
                children: _tabs.map((type) {
                  return _CollectionCategoryView(
                    type: type,
                    onLongPressItem: _showItemActionSheet,
                    onRefresh: _handleSync,
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 单个状态分类下的番剧瀑布流网格展示
class _CollectionCategoryView extends ConsumerWidget {
  final CollectType type;
  final void Function(AnimeCollectionItem item) onLongPressItem;
  final Future<void> Function() onRefresh;

  const _CollectionCategoryView({
    required this.type,
    required this.onLongPressItem,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items = ref.watch(collectionsByTypeProvider(type));
    final screenWidth = context.screenWidth;
    final columns = AppBreakpoints.gridColumns(screenWidth);

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.bookmark_border_rounded,
                size: 56,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 12),
              Text(
                '暂无【${type.label}】分类的番剧',
                style: TextStyle(
                  fontFamily: FontManager.instance.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '在播放页面轻点分类按钮，即可将番剧归档至此',
                style: TextStyle(
                  fontFamily: FontManager.instance.activeFontFamily,
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                  fontSize: 12.5,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          childAspectRatio: 0.68,
          crossAxisSpacing: 10,
          mainAxisSpacing: 14,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final collectionItem = items[index];
          final bangumiItem = collectionItem.toBangumiItem();

          return GestureDetector(
            onLongPress: () => onLongPressItem(collectionItem),
            child: AnimeCard(
              item: bangumiItem,
            ),
          );
        },
      ),
    );
  }
}
