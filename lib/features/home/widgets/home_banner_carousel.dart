import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/models/bangumi/bangumi_item.dart';
import '../../../core/models/home/recommend_item.dart';
import '../../common/widgets/anime_card.dart';
import '../../common/widgets/bouncing_scale_card.dart';
import '../../common/widgets/cached_anime_image.dart';
import '../../common/widgets/directional_horizontal_scroll.dart';
import '../../common/widgets/shimmer_loading.dart';

/// 首页精选顶部横幅轮播图组件：
/// 1. 响应式布局：手机端几乎吃满屏幕宽度（极窄边距），平板/PC 桌面端限制最大宽度并水平居中；
/// 2. 海报高清偏上裁切：采用 800px 高分辨率大图，锚点偏向上方 Alignment(0, -0.4) 聚焦人物面部；
/// 3. 原生流畅体验：基于 PageView.builder 惰性加载，支持手势触摸感知与平滑自动轮播；
/// 4. 视觉信息沉浸：覆盖微渐变暗色遮罩、金星评分、热播勋章与动态胶囊指示器；
/// 5. 智能算法赋能：支持注入 RecommendItem 渲染算法契合度胶囊与推荐理由气泡。
class HomeBannerCarousel extends StatefulWidget {
  final List<BangumiItem>? items;
  final List<RecommendItem>? recommendations;
  final int maxCount;
  final Duration autoPlayInterval;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;

  const HomeBannerCarousel({
    super.key,
    this.items,
    this.recommendations,
    this.maxCount = 5,
    this.autoPlayInterval = const Duration(seconds: 4),
    this.height,
    this.padding,
    this.borderRadius,
  });

  @override
  State<HomeBannerCarousel> createState() => _HomeBannerCarouselState();
}

class _HomeBannerCarouselState extends State<HomeBannerCarousel> {
  late PageController _pageController;
  Timer? _autoPlayTimer;
  int _currentIndex = 0;
  bool _isInteracting = false;

  // 特殊处理说明：循环基准倍数。在多数据项时，initialPage 设为 count * 1000，
  // 结合 PageView(itemCount: null) 的视口惰性加载机制，既提供向前向后数千页的平滑无阻尼循环空间，
  // 又完全不涉及任何 jumpTo 物理坐标篡改，彻底免疫状态机重入死循环与手势打断
  static const int _kLoopMultiplier = 1000;

  List<BangumiItem> get _carouselItems {
    if (widget.recommendations != null && widget.recommendations!.isNotEmpty) {
      return widget.recommendations!.take(widget.maxCount).map((r) => r.item).toList();
    }
    return (widget.items ?? const []).take(widget.maxCount).toList();
  }

  int _getInitialPage(int count) => count > 1 ? count * _kLoopMultiplier : 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _getInitialPage(_carouselItems.length));
    _startAutoPlay();
  }

  @override
  void didUpdateWidget(covariant HomeBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items?.length != widget.items?.length ||
        oldWidget.recommendations?.length != widget.recommendations?.length) {
      final newCount = _carouselItems.length;
      if (_currentIndex >= newCount && newCount > 0) {
        _currentIndex = 0;
      }
      final targetPage = _getInitialPage(newCount) + _currentIndex;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(targetPage);
      } else if (_pageController.initialPage != targetPage) {
        _pageController.dispose();
        _pageController = PageController(initialPage: targetPage);
      }
      _restartAutoPlay();
    }
  }

  void _startAutoPlay() {
    _autoPlayTimer?.cancel();
    final count = _carouselItems.length;
    if (count <= 1) return;

    _autoPlayTimer = Timer.periodic(widget.autoPlayInterval, (timer) {
      if (!mounted || _isInteracting || !_pageController.hasClients) return;
      final currentItemCount = _carouselItems.length;
      if (currentItemCount <= 1) return;

      final currentPage = _pageController.page?.round() ?? _pageController.initialPage;
      _pageController.animateToPage(
        currentPage + 1,
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _restartAutoPlay() {
    _autoPlayTimer?.cancel();
    _startAutoPlay();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _carouselItems;
    if (items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isNarrow = screenWidth < 600;

        // 手机端几乎吃满宽度（左右微边距 10px），平板及电脑宽屏居中并限宽 840px
        final double horizontalPadding = widget.padding != null ? 0.0 : (isNarrow ? 10.0 : 20.0);
        final double bannerHeight = widget.height ?? (isNarrow ? 195.0 : 250.0);
        final double borderRadiusValue = widget.borderRadius ?? (isNarrow ? 14.0 : 18.0);

        Widget content = Padding(
          padding: widget.padding ?? EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: SizedBox(
            height: bannerHeight,
            child: Listener(
              // 手势交互探测：按下或滑动时暂时暂停定时器，松开后恢复，防止与用户操作打架
              onPointerDown: (_) {
                _isInteracting = true;
                _autoPlayTimer?.cancel();
              },
              onPointerUp: (_) {
                _isInteracting = false;
                _startAutoPlay();
              },
              onPointerCancel: (_) {
                _isInteracting = false;
                _startAutoPlay();
              },
              // 关键：外层强制进行抗锯齿圆角裁剪，防止 PageView 在横向滑动切换过程中卡片两端露出直角矩形硬切边
              child: ClipRRect(
                borderRadius: BorderRadius.circular(borderRadiusValue),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    // 1. 轮播视图核心（无界懒加载 + 取模映射，原生级零闪烁无限循环，加入纵向优先防误触保护）
                    DirectionalHorizontalScroll(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: items.length > 1 ? null : items.length,
                        onPageChanged: (index) {
                          final count = items.length;
                          final realIndex = count > 1 ? index % count : index;
                          setState(() {
                            _currentIndex = realIndex;
                          });
                        },
                        itemBuilder: (context, index) {
                          final count = items.length;
                          final realIndex = count > 1 ? index % count : index;
                          final item = items[realIndex];
                          final recList = widget.recommendations;
                          final currentRec = (recList != null && realIndex < recList.length)
                              ? recList[realIndex]
                              : null;
                          return _buildBannerCard(
                            context: context,
                            item: item,
                            recommendItem: currentRec,
                          );
                        },
                      ),
                    ),

                    // 2. 右下角动态平滑胶囊指示器
                    if (items.length > 1)
                      Positioned(
                        right: 14,
                        bottom: 12,
                        child: _buildPageIndicator(items.length),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );

        if (!isNarrow && widget.height == null) {
          content = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: content,
            ),
          );
        }

        return content;
      },
    );
  }

  /// 单张横幅轮播卡片（无缝平铺，由外层容器统一切割视口圆角）
  Widget _buildBannerCard({
    required BuildContext context,
    required BangumiItem item,
    RecommendItem? recommendItem,
  }) {
    final hasRec = recommendItem != null;

    return BouncingScaleCard(
      immediateTap: true,
      onTap: () => navigateToVideoPlayer(context, item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 背景高清封面图：对准焦点偏上方 Alignment(0, -0.4) 优先保留人物头部与五官
          CachedAnimeImage(
            imageUrl: item.coverUrl,
            fit: BoxFit.cover,
            alignment: const Alignment(0, -0.4),
          ),

            // 全局微暗底色，增强层次感
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withAlpha(20),
              ),
            ),

            // 底部深色渐变遮罩，衬托白色文字
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: hasRec ? 116 : 80,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withAlpha(150),
                      Colors.black.withAlpha(235),
                    ],
                    stops: const [0.0, 0.45, 1.0],
                  ),
                ),
              ),
            ),

            // 底部标题与算法理由
            Positioned(
              left: 14,
              right: 76, // 右侧预留指示器避让空间
              bottom: 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasRec) ...[
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: Colors.amber.withAlpha(225),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.stars_rounded, size: 11, color: Colors.black),
                              const SizedBox(width: 3),
                              Text(
                                '${recommendItem.matchRate}% 契合 · ${recommendItem.tag}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Text(
                    item.preferredName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16.5,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                      shadows: [
                        Shadow(
                          color: Colors.black87,
                          blurRadius: 4,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  if (hasRec) ...[
                    const SizedBox(height: 2),
                    Text(
                      '💡 ${recommendItem.reason}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withAlpha(210),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        shadows: const [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 3,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
  }

  /// 动态平滑胶囊指示器
  Widget _buildPageIndicator(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(120),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(count, (index) {
          final isSelected = index == _currentIndex;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 2.5),
            width: isSelected ? 14 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: isSelected ? Colors.white : Colors.white.withAlpha(100),
              borderRadius: BorderRadius.circular(3),
            ),
          );
        }),
      ),
    );
  }
}

/// 1:1 轮播图流光骨架屏
class ShimmerBannerCarousel extends StatelessWidget {
  final double? height;
  final EdgeInsetsGeometry? padding;
  final double? borderRadius;

  const ShimmerBannerCarousel({
    super.key,
    this.height,
    this.padding,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isNarrow = screenWidth < 600;

        final double horizontalPadding = padding != null ? 0.0 : (isNarrow ? 10.0 : 20.0);
        final double bannerHeight = height ?? (isNarrow ? 195.0 : 250.0);
        final double borderRadiusValue = borderRadius ?? (isNarrow ? 14.0 : 18.0);

        Widget skeleton = Padding(
          padding: padding ?? EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: ShimmerLoading(
            child: Container(
              height: bannerHeight,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(borderRadiusValue),
              ),
            ),
          ),
        );

        if (!isNarrow && height == null) {
          skeleton = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: skeleton,
            ),
          );
        }

        return skeleton;
      },
    );
  }
}
