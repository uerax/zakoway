import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/bangumi_client.dart';
import '../../common/widgets/app_refresh_indicator.dart';
import '../controllers/category_controller.dart';
import '../controllers/category_state.dart';
import '../widgets/category_content_view.dart';
import '../widgets/category_filter_bar.dart';
import '../widgets/category_genre_chips.dart';

class CategoryPage extends ConsumerStatefulWidget {
  final BangumiClient? client;
  final String? initialCategory;
  final int? initialYear;
  final int? initialMonth;
  final bool isVisible;

  const CategoryPage({
    super.key,
    this.client,
    this.initialCategory,
    this.initialYear,
    this.initialMonth,
    this.isVisible = false,
  });

  @override
  ConsumerState<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends ConsumerState<CategoryPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  CategoryInitialArgs get _initialArgs => CategoryInitialArgs(
        category: widget.initialCategory,
        year: widget.initialYear,
        month: widget.initialMonth,
      );

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    if (widget.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(categoryControllerProvider(_initialArgs).notifier).ensureLoaded();
        }
      });
    }
  }

  @override
  void didUpdateWidget(CategoryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ref.read(categoryControllerProvider(_initialArgs).notifier).ensureLoaded();
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final offset = _scrollController.offset;
    final shouldShowTop = offset > 450;
    if (shouldShowTop != _showBackToTop) {
      setState(() {
        _showBackToTop = shouldShowTop;
      });
    }

    // 触底预加载：距离底部不足 350px 时提前静默拉取下一页
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 350) {
      ref.read(categoryControllerProvider(_initialArgs).notifier).loadMore();
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final state = ref.watch(categoryControllerProvider(_initialArgs));
    final controller = ref.read(categoryControllerProvider(_initialArgs).notifier);

    // 筛选切换时轻量回滚至列表顶部，保障视觉连贯
    ref.listen(
      categoryControllerProvider(_initialArgs).select((s) => s.filter),
      (prev, next) {
        if (prev != null && prev != next && _scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
          );
        }
      },
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 顶部动态微弱环境光晕，营造轻奢通透质感
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

          SafeArea(
            bottom: false,
            child: AppRefreshIndicator(
              onRefresh: () => controller.fetchFirstPage(forceRefresh: true),
              displacement: 32,
              child: CustomScrollView(
                controller: _scrollController,
                scrollCacheExtent: const ScrollCacheExtent.pixels(180),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  // 1. 顶部呼吸留白
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 10),
                  ),

                  // 2. 形式分类（单选）与题材分类（多选）
                  SliverToBoxAdapter(
                    child: CategoryGenreChips(initialArgs: _initialArgs),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 8)),

                  // 3. 年份、季度与排序下拉菜单栏（左侧年份季度，右侧排序）
                  SliverToBoxAdapter(
                    child: CategoryFilterBar(initialArgs: _initialArgs),
                  ),

                  // 4. 动态状态与数量摘要副标题
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              state.buildFilterSummary(),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant.withAlpha(200),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (state.isLoading && state.items.isNotEmpty)
                            SizedBox(
                              width: 13,
                              height: 13,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // 6. 内容主体区域
                  CategoryContentView(initialArgs: _initialArgs),

                  // 7. 底部加载更多或触底提示
                  if (state.isLoadingMore)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          ),
                        ),
                      ),
                    )
                  else if (!state.hasMore && state.items.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            state.total < 1000
                                ? '已经翻到底啦 · 共 ${state.total} 部'
                                : '已经翻到底啦',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant.withAlpha(160),
                            ),
                          ),
                        ),
                      ),
                    ),

                  // 底部预留 96px 避让主导航栏悬浮毛玻璃胶囊 Dock
                  const SliverToBoxAdapter(child: SizedBox(height: 96)),
                ],
              ),
            ),
          ),

          // 浮动返回顶部按钮
          if (_showBackToTop)
            Positioned(
              right: 18,
              bottom: 110,
              child: FloatingActionButton.small(
                onPressed: _scrollToTop,
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                elevation: 3,
                child: const Icon(Icons.arrow_upward_rounded, size: 20),
              ),
            ),
        ],
      ),
    );
  }
}
