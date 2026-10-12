import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/bangumi/bangumi_comment_item.dart';
import '../../../core/providers/bangumi_providers.dart';
import '../../../core/utils/comment_censor_engine.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import '../../common/widgets/cached_anime_image.dart';
import '../../common/widgets/instant_dropdown_button.dart';

/// 播放页评论区/吐槽区组件 (1:1 复刻 animaku 块级分页、B 站评分星与黑幕审查引擎)
class WatchCommentsSection extends ConsumerStatefulWidget {
  const WatchCommentsSection({
    super.key,
    this.bangumiId,
    this.shrinkWrap = false,
    this.physics,
  });

  final int? bangumiId;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  ConsumerState<WatchCommentsSection> createState() => _WatchCommentsSectionState();
}

class _WatchCommentsSectionState extends ConsumerState<WatchCommentsSection> {
  int _page = 1;
  int? _selectedType; // null: 全部, 2: 看过, 3: 在看, 1: 想看
  bool _isLoading = false;
  String? _error;
  List<BangumiCommentItem> _comments = const [];
  int _total = 0;

  final ScrollController _scrollController = ScrollController();

  static const List<({String label, int? type})> _typeFilters = [
    (label: '全部', type: null),
    (label: '看过', type: 2),
    (label: '在看', type: 3),
    (label: '想看', type: 1),
    (label: '搁置', type: 4),
    (label: '抛弃', type: 5),
  ];

  @override
  void initState() {
    super.initState();
    _fetchPage(_page);
  }

  @override
  void didUpdateWidget(covariant WatchCommentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bangumiId != widget.bangumiId) {
      _page = 1;
      _fetchPage(1);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchPage(int page, {bool forceRefresh = false}) async {
    final subjectId = widget.bangumiId ?? 0;
    if (subjectId <= 0) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final client = ref.read(bangumiClientProvider);
      final res = await client.getCommentsPage(
        subjectId,
        page: page,
        pageSize: 10,
        type: _selectedType,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;
      setState(() {
        _page = page;
        _comments = res.items;
        _total = res.total;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  void _onPageChanged(int newPage) {
    if (newPage == _page || _isLoading) return;
    _fetchPage(newPage);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final totalPages = max(1, (_total + 9) ~/ 10);

    final contentChildren = <Widget>[
        // 1. 顶部标题、总数与筛选类型胶囊栏
        Row(
          children: [
            const Text(
              '吐槽',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
            ),
            const SizedBox(width: 6),
            if (_total > 0)
              Text(
                '$_total 条',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                  fontFamily: 'MiSans',
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                ),
              ),
            const Spacer(),
            // 筛选类型极速下拉菜单 (支持全部/看过/在看/想看/搁置/抛弃，彻底消除外圈方形阴影，自带微弹性)
            InstantDropdownButton<int?>(
              selectedValue: _selectedType,
              items: _typeFilters.map((f) => f.type).toList(),
              menuWidth: 124,
              maxMenuHeight: 260,
              alignRight: true,
              onSelected: (newType) {
                if (_selectedType == newType) return;
                setState(() {
                  _selectedType = newType;
                  _page = 1;
                });
                _fetchPage(1);
              },
              itemBuilder: (context, typeVal, isSelected) {
                final filter = _typeFilters.firstWhere(
                  (f) => f.type == typeVal,
                  orElse: () => _typeFilters.first,
                );
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: isSelected
                      ? primaryColor.withValues(alpha: isDark ? 0.20 : 0.10)
                      : Colors.transparent,
                  child: Row(
                    children: [
                      Text(
                        filter.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          color: isSelected
                              ? primaryColor
                              : (isDark ? Colors.white.withValues(alpha: 0.85) : Colors.black87),
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                      ),
                      const Spacer(),
                      if (isSelected)
                        Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: primaryColor,
                        ),
                    ],
                  ),
                );
              },
              child: BouncingScaleCard(
                scaleDown: 0.95,
                immediateTap: true,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 28,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: _selectedType != null
                          ? primaryColor.withValues(alpha: isDark ? 0.22 : 0.12)
                          : (isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8)),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _selectedType != null
                            ? primaryColor.withValues(alpha: 0.35)
                            : (isDark ? Colors.white.withAlpha(18) : Colors.black.withAlpha(12)),
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.filter_list_rounded,
                          size: 13,
                          color: _selectedType != null
                              ? primaryColor
                              : theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _typeFilters.firstWhere(
                            (f) => f.type == _selectedType,
                            orElse: () => _typeFilters.first,
                          ).label,
                          style: TextStyle(
                            fontSize: 12.0,
                            fontWeight: _selectedType != null ? FontWeight.w700 : FontWeight.w500,
                            color: _selectedType != null
                                ? primaryColor
                                : theme.textTheme.bodySmall?.color?.withValues(alpha: 0.85),
                            fontFamily: 'MiSans',
                            fontFamilyFallback: FontManager.fallbackFontFamilies,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: _selectedType != null
                              ? primaryColor
                              : theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 2. 评论内容呈现区
        if (_isLoading && _comments.isEmpty)
          _buildLoadingSkeleton(isDark)
        else if (_error != null && _comments.isEmpty)
          _buildErrorView(primaryColor)
        else if (_comments.isEmpty)
          _buildEmptyView(theme)
        else ...[
          // 评论卡片列表
          ..._comments.map((comment) => _CommentCardItem(
                key: ValueKey(comment.id),
                comment: comment,
                isDark: isDark,
                primaryColor: primaryColor,
                theme: theme,
              )),

          // 3. 底部优雅数字分页栏
          if (totalPages > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _buildPaginationBar(totalPages, isDark, primaryColor, theme),
            ),
        ],
    ];

    if (widget.shrinkWrap) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: contentChildren,
        ),
      );
    }

    return ListView(
      controller: _scrollController,
      physics: widget.physics,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: contentChildren,
    );
  }

  Widget _buildLoadingSkeleton(bool isDark) {
    return Column(
      children: List.generate(4, (index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 90,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildEmptyView(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 36,
              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 10),
            Text(
              '暂无相关吐槽评论',
              style: TextStyle(
                fontSize: 13,
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView(Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 36),
      child: Center(
        child: Column(
          children: [
            Text(
              '吐槽列表加载暂不可用',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => _fetchPage(_page, forceRefresh: true),
              child: Text(
                '点击重试',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: primaryColor,
                  fontFamily: 'MiSans',
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaginationBar(int totalPages, bool isDark, Color primaryColor, ThemeData theme) {
    final canPrev = _page > 1;
    final canNext = _page < totalPages;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 上一页
        BouncingScaleCard(
          scaleDown: 0.94,
          onTap: canPrev ? () => _onPageChanged(_page - 1) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: canPrev
                  ? (isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.chevron_left_rounded,
                  size: 16,
                  color: canPrev
                      ? theme.textTheme.bodyMedium?.color
                      : theme.textTheme.bodySmall?.color?.withValues(alpha: 0.25),
                ),
                const SizedBox(width: 2),
                Text(
                  '上一页',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: canPrev
                        ? theme.textTheme.bodyMedium?.color
                        : theme.textTheme.bodySmall?.color?.withValues(alpha: 0.25),
                    fontFamily: 'MiSans',
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(width: 14),

        // 当前页码胶囊
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$_page / $totalPages',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              fontFamily: 'MiSans',
              fontFamilyFallback: FontManager.fallbackFontFamilies,
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
            ),
          ),
        ),

        const SizedBox(width: 14),

        // 下一页
        BouncingScaleCard(
          scaleDown: 0.94,
          onTap: canNext ? () => _onPageChanged(_page + 1) : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: canNext
                  ? (isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(
                  '下一页',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: canNext
                        ? theme.textTheme.bodyMedium?.color
                        : theme.textTheme.bodySmall?.color?.withValues(alpha: 0.25),
                    fontFamily: 'MiSans',
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: canNext
                      ? theme.textTheme.bodyMedium?.color
                      : theme.textTheme.bodySmall?.color?.withValues(alpha: 0.25),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 评论单卡片组件 (带 B 站星星、黑幕遮掩与 2 行截断展开)
class _CommentCardItem extends StatefulWidget {
  const _CommentCardItem({
    super.key,
    required this.comment,
    required this.isDark,
    required this.primaryColor,
    required this.theme,
  });

  final BangumiCommentItem comment;
  final bool isDark;
  final Color primaryColor;
  final ThemeData theme;

  @override
  State<_CommentCardItem> createState() => _CommentCardItemState();
}

class _CommentCardItemState extends State<_CommentCardItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    final theme = widget.theme;
    final isDark = widget.isDark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8),
            width: 0.5,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 用户头像
            _buildAvatar(comment.author.avatarUrl, comment.author.nickname),

            const SizedBox(width: 12),

            // 评论主体
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部作者、B 站星星、收藏状态与发布时间
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          comment.author.nickname.isNotEmpty ? comment.author.nickname : '匿名用户',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.9),
                            fontFamily: 'MiSans',
                            fontFamilyFallback: FontManager.fallbackFontFamilies,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),

                      // B 站 5 星制评分
                      if (comment.starScore != null) ...[
                        _BiliStarRating(starScore: comment.starScore!),
                        const SizedBox(width: 6),
                      ],

                      // 观看状态微胶囊 (看过 / 在看 / 想看)
                      if (comment.collectionTypeLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0.5),
                          decoration: BoxDecoration(
                            color: _resolveStatusBg(comment.collectionType),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            comment.collectionTypeLabel!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _resolveStatusColor(comment.collectionType),
                              fontFamily: 'MiSans',
                              fontFamilyFallback: FontManager.fallbackFontFamilies,
                            ),
                          ),
                        ),

                      const Spacer(),

                      // 相对发布时间
                      Text(
                        comment.relativeTimeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                      ),
                    ],
                  ),

                  // 评论正文 (仅有内容时展示)
                  if (comment.content.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _CommentContentWithCensor(
                      content: comment.content,
                      isExpanded: _expanded,
                      isDark: isDark,
                      theme: theme,
                      onToggleExpand: () => setState(() => _expanded = !_expanded),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String avatarUrl, String nickname) {
    if (avatarUrl.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: 34,
          height: 34,
          child: CachedAnimeImage(
            imageUrl: avatarUrl,
            width: 34,
            height: 34,
            fit: BoxFit.cover,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 17,
      backgroundColor: widget.primaryColor.withValues(alpha: 0.2),
      child: Text(
        nickname.isNotEmpty ? nickname.characters.first : 'U',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: widget.primaryColor,
          fontFamily: 'MiSans',
          fontFamilyFallback: FontManager.fallbackFontFamilies,
        ),
      ),
    );
  }

  Color _resolveStatusBg(int? type) {
    return switch (type) {
      2 => const Color(0xFF10B981).withValues(alpha: 0.15),
      3 => const Color(0xFF0EA5E9).withValues(alpha: 0.15),
      1 => const Color(0xFFF59E0B).withValues(alpha: 0.15),
      4 => const Color(0xFF8B5CF6).withValues(alpha: 0.15),
      5 => const Color(0xFFEF4444).withValues(alpha: 0.15),
      _ => Colors.grey.withValues(alpha: 0.15),
    };
  }

  Color _resolveStatusColor(int? type) {
    return switch (type) {
      2 => const Color(0xFF10B981),
      3 => const Color(0xFF0EA5E9),
      1 => const Color(0xFFF59E0B),
      4 => const Color(0xFF8B5CF6),
      5 => const Color(0xFFEF4444),
      _ => Colors.grey,
    };
  }
}

/// B 站 5 星评分渲染组件 (1:1 复刻 animaku 规范，正金橙色 #FFAA04)
class _BiliStarRating extends StatelessWidget {
  const _BiliStarRating({required this.starScore});

  final double starScore;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final fillAmount = (starScore - i).clamp(0.0, 1.0);
        if (fillAmount >= 0.75) {
          // 全满星
          return const Icon(
            Icons.star_rounded,
            size: 12,
            color: Color(0xFFFFAA04),
          );
        } else if (fillAmount >= 0.25) {
          // 半星
          return const Icon(
            Icons.star_half_rounded,
            size: 12,
            color: Color(0xFFFFAA04),
          );
        } else {
          // 空星
          return Icon(
            Icons.star_rounded,
            size: 12,
            color: Colors.grey.withValues(alpha: 0.3),
          );
        }
      }),
    );
  }
}

/// 评论正文呈现组件 (集成 CommentCensorEngine 黑幕遮掩分词与展开/折叠)
class _CommentContentWithCensor extends StatefulWidget {
  const _CommentContentWithCensor({
    required this.content,
    required this.isExpanded,
    required this.isDark,
    required this.theme,
    required this.onToggleExpand,
  });

  final String content;
  final bool isExpanded;
  final bool isDark;
  final ThemeData theme;
  final VoidCallback onToggleExpand;

  @override
  State<_CommentContentWithCensor> createState() => _CommentContentWithCensorState();
}

class _CommentContentWithCensorState extends State<_CommentContentWithCensor> {
  // 记录已被用户点击解密的 Token 索引集合
  final Set<int> _revealedTokens = {};

  @override
  Widget build(BuildContext context) {
    final tokens = CommentCensorEngine.tokenize(widget.content);
    final theme = widget.theme;
    final isDark = widget.isDark;

    // 若无被遮蔽的 token 且文字较短，直接用常规 Text 提升渲染效率
    final hasRedacted = tokens.any((t) => t.redacted);

    final contentWidget = Wrap(
      spacing: 1.5,
      runSpacing: 2.0,
      children: tokens.asMap().entries.map((entry) {
        final index = entry.key;
        final token = entry.value;

        if (!token.redacted || token.type == CommentTokenType.text) {
          return Text(
            token.raw,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              letterSpacing: -0.1,
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.88),
              fontFamily: 'MiSans',
              fontFamilyFallback: FontManager.fallbackFontFamilies,
            ),
          );
        }

        final isRevealed = _revealedTokens.contains(index);

        return GestureDetector(
          onTap: () {
            setState(() {
              if (isRevealed) {
                _revealedTokens.remove(index);
              } else {
                _revealedTokens.add(index);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: isRevealed
                  ? (isDark ? Colors.white.withAlpha(16) : Colors.black.withAlpha(10))
                  : (isDark ? const Color(0xFF1E1E24) : const Color(0xFF323238)),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isRevealed
                    ? (isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(14))
                    : Colors.transparent,
                width: 0.5,
              ),
            ),
            child: Text(
              isRevealed ? token.raw : '█ ${token.label ?? '黑幕'} 点击查看',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isRevealed ? FontWeight.w500 : FontWeight.w600,
                color: isRevealed
                    ? (isDark ? Colors.white70 : Colors.black87)
                    : (isDark ? Colors.white54 : Colors.white70),
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
            ),
          ),
        );
      }).toList(),
    );

    final isLong = widget.content.length > 70 || widget.content.contains('\n');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.isExpanded && isLong && !hasRedacted)
          Text(
            widget.content,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              letterSpacing: -0.1,
              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.88),
              fontFamily: 'MiSans',
              fontFamilyFallback: FontManager.fallbackFontFamilies,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          )
        else
          contentWidget,

        if (isLong)
          GestureDetector(
            onTap: widget.onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.isExpanded ? '收起' : '展开',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                      fontFamily: 'MiSans',
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    widget.isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                    size: 14,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
