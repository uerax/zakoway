import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/utils/appearance_manager.dart';
import '../../common/widgets/app_refresh_indicator.dart';
import '../controllers/search_controller.dart';
import '../controllers/search_history_notifier.dart';
import '../widgets/search_bottom_bar.dart';
import '../widgets/search_filter_bar.dart';
import '../widgets/search_history_view.dart';
import '../widgets/search_result_view.dart';

/// 搜索页面（集成 0ms 内存缓存、物理熔断、持久化历史记录、多维筛选排序与壁纸穿透）
class SearchPage extends ConsumerStatefulWidget {
  final String? initialQuery;

  const SearchPage({
    super.key,
    this.initialQuery,
  });

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    final existingKeyword = ref.read(searchControllerProvider).keyword;
    final initialText = widget.initialQuery ?? (existingKeyword.isNotEmpty ? existingKeyword : '');
    _textController = TextEditingController(text: initialText);
    _focusNode = FocusNode();
    _scrollController = ScrollController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
        ref.read(searchControllerProvider.notifier).executeSearch(widget.initialQuery!);
      } else if (existingKeyword.isEmpty) {
        // 无初始搜索词且无既有搜索词时自动聚焦唤起键盘，提升操作效率
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSearch(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;
    _focusNode.unfocus();
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    ref.read(searchControllerProvider.notifier).executeSearch(trimmed);
  }

  void _handleClear() {
    _textController.clear();
    ref.read(searchControllerProvider.notifier).clear();
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final searchState = ref.watch(searchControllerProvider);
    final searchController = ref.read(searchControllerProvider.notifier);
    final history = ref.watch(searchHistoryProvider);

    return ListenableBuilder(
      listenable: AppearanceManager.instance,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            fit: StackFit.expand,
            children: [
              // 0. 底衬背景色
              Positioned.fill(
                child: ColoredBox(color: theme.scaffoldBackgroundColor),
              ),

              // 1. 个性化壁纸透射层（归属个人模块体系，支持单独覆盖或继承全局）
              AppearanceManager.instance.buildWallpaperLayer(pageKey: 'profile'),

              // 2. 顶部微弱动态环境光晕，营造高通透质感
              Positioned(
                top: -120,
                left: -60,
                right: -60,
                height: 380,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.2),
                        radius: 0.85,
                        colors: [
                          theme.colorScheme.primary.withAlpha(isDark ? 36 : 22),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // 3. 页面内容流：顶部内容流与底部 iOS Safari 风格搜索栏结合
              Column(
                children: [
                  // 顶部留出状态栏高度与微弱呼吸边距
                  SizedBox(height: MediaQuery.paddingOf(context).top + 6),

                  // 内容主体：有搜索词时呈现结果流；无搜索词时展示历史记录与空状态
                  Expanded(
                    child: searchState.keyword.isEmpty
                        ? SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            child: SearchHistoryView(
                              history: history,
                              onSelect: (item) {
                                _textController.text = item;
                                _handleSearch(item);
                              },
                              onRemove: (item) => ref
                                  .read(searchHistoryProvider.notifier)
                                  .removeSearch(item),
                              onClearAll: () => ref
                                  .read(searchHistoryProvider.notifier)
                                  .clearAll(),
                            ),
                          )
                        : AppRefreshIndicator(
                            onRefresh: () => searchController.executeSearch(
                              searchState.keyword,
                              forceRefresh: true,
                            ),
                            displacement: 32,
                            child: CustomScrollView(
                              controller: _scrollController,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              physics: const AlwaysScrollableScrollPhysics(
                                parent: BouncingScrollPhysics(),
                              ),
                              slivers: [
                                // 1. 分类标签与排序控制栏
                                SliverToBoxAdapter(
                                  child: SearchFilterBar(
                                    currentFilter: searchState.filter,
                                    allCount: searchState.allCount,
                                    animeCount: searchState.animeCount,
                                    nonAnimeCount: searchState.nonAnimeCount,
                                    onFilterChanged: (filter) =>
                                        searchController.setFilter(filter),
                                    currentSort: searchState.sort,
                                    onSortChanged: (sort) =>
                                        searchController.setSort(sort),
                                  ),
                                ),

                                // 2. 搜索结果网格 / 骨架屏 / 空状态
                                SearchResultView(
                                  isLoading: searchState.isLoading,
                                  errorMessage: searchState.errorMessage,
                                  items: searchState.filteredAndSortedItems,
                                  keyword: searchState.keyword,
                                  currentFilter: searchState.filter,
                                  allCount: searchState.allCount,
                                  nonAnimeCount: searchState.nonAnimeCount,
                                  onRetry: () => searchController.executeSearch(
                                    searchState.keyword,
                                    forceRefresh: true,
                                  ),
                                  onSwitchFilter: (filter) =>
                                      searchController.setFilter(filter),
                                ),

                                const SliverToBoxAdapter(
                                  child: SizedBox(height: 16),
                                ),
                              ],
                            ),
                          ),
                  ),

                  // 底部 iOS Safari 风格悬浮毛玻璃搜索栏
                  SearchBottomBar(
                    controller: _textController,
                    focusNode: _focusNode,
                    onSearch: () => _handleSearch(_textController.text),
                    onClear: _handleClear,
                    onBack: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
