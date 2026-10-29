import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../../core/network/anime_image_cache_manager.dart';
import '../../../core/utils/image_utils.dart';

/// 高性能动漫封面图片组件：
/// 1. 采用专用的 AnimeImageCacheManager，磁盘容量达 3000 张，支持 60 天长效落盘存储；
/// 2. 使用 memCacheWidth 限制解码位图宽度，杜绝过量采样撑爆显存；
/// 3. 支持基于行梯度的错峰延迟加载 (loadDelayMs)，彻底消除同屏十多张图片同时并发解码导致的 CPU 抢占；
/// 4. 采用超快 100ms 平滑淡入，消除图片反复加载的突兀感。
class CachedAnimeImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final int? resizeWidth;
  final BorderRadius? borderRadius;
  final int loadDelayMs;
  final FilterQuality filterQuality;

  const CachedAnimeImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.resizeWidth,
    this.borderRadius,
    this.loadDelayMs = 0,
    this.filterQuality = FilterQuality.medium,
  });

  @override
  State<CachedAnimeImage> createState() => _CachedAnimeImageState();
}

class _CachedAnimeImageState extends State<CachedAnimeImage> {
  bool _canLoad = false;
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    if (widget.loadDelayMs <= 0) {
      _canLoad = true;
    } else {
      _delayTimer = Timer(Duration(milliseconds: widget.loadDelayMs), () {
        if (mounted) {
          setState(() {
            _canLoad = true;
          });
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant CachedAnimeImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _delayTimer?.cancel();
      if (widget.loadDelayMs <= 0) {
        _canLoad = true;
      } else {
        _canLoad = false;
        _delayTimer = Timer(Duration(milliseconds: widget.loadDelayMs), () {
          if (mounted) {
            setState(() {
              _canLoad = true;
            });
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final targetUrl = bangumiImageUrl(widget.imageUrl);
    final cacheKey = getBangumiImageCacheKey(targetUrl);

    if (targetUrl.isEmpty || !_canLoad) {
      return _buildPlaceholder(
        context,
        theme,
        child: targetUrl.isEmpty
            ? const Icon(Icons.movie_rounded, color: Colors.grey, size: 28)
            : null,
      );
    }

    Widget imageWidget = CachedNetworkImage(
      imageUrl: targetUrl,
      cacheKey: cacheKey.isNotEmpty ? cacheKey : null,
      cacheManager: AnimeImageCacheManager.instance,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      memCacheWidth: widget.resizeWidth,
      filterQuality: widget.filterQuality,
      fadeInDuration: const Duration(milliseconds: 180),
      fadeOutDuration: const Duration(milliseconds: 180),
      useOldImageOnUrlChange: true,
      placeholder: (context, url) => _buildPlaceholder(context, theme),
      errorWidget: (context, url, error) => _buildPlaceholder(
        context,
        theme,
        child: const Icon(Icons.broken_image_rounded, color: Colors.grey, size: 26),
      ),
    );

    if (widget.borderRadius != null) {
      imageWidget = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildPlaceholder(
    BuildContext context,
    ThemeData theme, {
    Widget? child,
  }) {
    return Container(
      width: widget.width,
      height: widget.height,
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
      child: child != null ? Center(child: child) : null,
    );
  }
}
