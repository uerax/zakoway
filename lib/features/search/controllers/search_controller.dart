import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/bangumi_providers.dart';
import '../models/search_types.dart';
import 'search_history_notifier.dart';
import 'search_state.dart';

/// 搜索控制器提供者：
/// 特殊处理说明：不采用 autoDispose。
/// 保持最近一次的搜索结果、筛选排序与搜索关键词在内存中常驻，
/// 确保用户从番剧详情页返回、或短暂切换至其他标签页再重新进入搜索页时，0ms 瞬间恢复既有搜索成果，
/// 杜绝反复销毁重建导致的重复打字与重复网络开销。
final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(
  SearchController.new,
);

/// 搜索页面交互控制器（包含 0ms 内存缓存快读、物理 CancelToken 熔断、结果分类与排序）
class SearchController extends Notifier<SearchState> {
  static const int searchLimit = 30;

  int _requestSeq = 0;
  CancelToken? _cancelToken;
  bool _isDisposed = false;

  @override
  SearchState build() {
    _isDisposed = false;
    ref.onDispose(() {
      _isDisposed = true;
      _cancelToken?.cancel('search_controller_disposed');
    });

    return const SearchState();
  }

  /// 执行番剧关键词搜索
  Future<void> executeSearch(
    String query, {
    bool forceRefresh = false,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _cancelToken?.cancel('search_cleared');
      state = const SearchState();
      return;
    }

    final seq = ++_requestSeq;
    final client = ref.read(bangumiClientProvider);

    // 1. 核心工程优化：优先同步探测内存缓存，若命中且非强制刷新，则 0ms 瞬间上屏，彻底消除白屏与骨架屏闪烁
    // 特殊处理说明：限定 types 为 [2, 6]（2=动画, 6=三次元/特摄/真人影视），源头排除书籍(漫画)、音乐与游戏条目
    if (!forceRefresh) {
      final cached = client.peekSearchCache(
        trimmed,
        limit: searchLimit,
        offset: 0,
        type: null,
        types: const [2, 6],
      );
      if (cached != null) {
        _cancelToken?.cancel('cache_hit');
        state = state.copyWith(
          keyword: trimmed,
          allItems: cached.items,
          filter: SearchFilterType.anime,
          sort: SearchSortType.dateDesc,
          isLoading: false,
          clearError: true,
        );
        ref.read(searchHistoryProvider.notifier).addSearch(trimmed);
        return;
      }
    }

    // 2. 未命中缓存：对正在飞行中的前序请求实施物理级取消，释放客户端带宽
    _cancelToken?.cancel('search_term_changed');
    final cancelToken = CancelToken();
    _cancelToken = cancelToken;

    state = state.copyWith(
      keyword: trimmed,
      allItems: const [],
      filter: SearchFilterType.anime,
      sort: SearchSortType.dateDesc,
      isLoading: true,
      clearError: true,
    );

    try {
      final result = await client.searchWithTotal(
        trimmed,
        limit: searchLimit,
        offset: 0,
        type: null,
        types: const [2, 6],
        forceRefresh: forceRefresh,
        cancelToken: cancelToken,
      );

      if (_isDisposed || cancelToken.isCancelled || seq != _requestSeq) return;

      state = state.copyWith(
        allItems: result.items,
        isLoading: false,
        clearError: true,
      );
      // 成功检索后自动将关键词追加至搜索历史
      ref.read(searchHistoryProvider.notifier).addSearch(trimmed);
    } catch (e) {
      if (_isDisposed || cancelToken.isCancelled || seq != _requestSeq) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// 切换分类标签（全部 / 动漫 / 非动漫）
  void setFilter(SearchFilterType filter) {
    if (state.filter == filter) return;
    state = state.copyWith(filter: filter);
  }

  /// 切换排序方式（最新放送 / 默认匹配 / 最早放送）
  void setSort(SearchSortType sort) {
    if (state.sort == sort) return;
    state = state.copyWith(sort: sort);
  }

  /// 清空当前搜索输入与结果，回到初始态
  void clear() {
    _cancelToken?.cancel('search_reset');
    state = const SearchState();
  }
}
