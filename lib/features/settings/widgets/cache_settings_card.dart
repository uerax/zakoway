import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../../../core/network/anime_image_cache_manager.dart';
import '../../../core/network/bangumi_client.dart';
import '../../../core/network/bangumi_data_disk_cache_manager.dart';
import '../../../core/network/player_media_disk_cache_manager.dart';
import '../../../core/services/app_prewarm_coordinator.dart';
import '../../player/danmaku/source/bilibili_danmaku_client.dart';
import '../../player/danmaku/source/dandan_client.dart';
import '../../player/source/source_bundle_manager.dart';
import 'm3_settings_card.dart';
import 'tg_action_sheet.dart';

class CacheSettingsCard extends StatefulWidget {
  final BangumiClient client;

  const CacheSettingsCard({super.key, required this.client});

  @override
  State<CacheSettingsCard> createState() => _CacheSettingsCardState();
}

class _CacheSettingsCardState extends State<CacheSettingsCard> {
  String _imageCacheSizeStr = '0.0 MB';
  String _dataCacheSizeStr = '0.0 MB';

  @override
  void initState() {
    super.initState();
    final cached = AppPrewarmCoordinator.instance.getCachedSizeStrings();
    if (cached != null) {
      _imageCacheSizeStr = cached.image;
      _dataCacheSizeStr = cached.data;
    }
    _updateCacheSizes(forceRefresh: true);
  }

  Future<void> _updateCacheSizes({bool forceRefresh = false}) async {
    final result = await AppPrewarmCoordinator.instance.prewarmSettings(
      widget.client,
      forceRefresh: forceRefresh,
    );

    if (!mounted) return;
    setState(() {
      _imageCacheSizeStr = AppPrewarmCoordinator.formatBytes(result.imgBytes);
      _dataCacheSizeStr = AppPrewarmCoordinator.formatBytes(result.dataBytes);
    });
  }

  Future<void> _performClearImageCache() async {
    try {
      await DefaultCacheManager().emptyCache();
      try {
        await AnimeImageCacheManager.instance.emptyCache();
      } catch (_) {}
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      AppPrewarmCoordinator.instance.invalidateCacheSizes();
      await _updateCacheSizes(forceRefresh: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已清空图片缓存'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('清理图片缓存失败: $e'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _performClearDataCache() async {
    try {
      widget.client.clearCache();
      try {
        await BangumiDataDiskCacheManager.instance?.clearAll();
      } catch (_) {}
      await PlayerMediaDiskCacheManager.instance?.clearAll();
      SourceBundleManager.instance.runtime.clearMemoryCache();
      DandanClient.instance.clearMemoryCache();
      BilibiliDanmakuClient.instance.clearMemoryCache();
      AppPrewarmCoordinator.instance.invalidateCacheSizes();
      await _updateCacheSizes(forceRefresh: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已清空数据与媒体缓存'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('清理数据缓存失败: $e'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmClearImageCache() async {
    final confirmed = await TgActionSheet.showDestructive(
      context,
      title: '当前图片缓存占用 $_imageCacheSizeStr，确认清空？',
      destructiveLabel: '清空图片缓存',
    );
    if (confirmed) {
      _performClearImageCache();
    }
  }

  Future<void> _confirmClearDataCache() async {
    final confirmed = await TgActionSheet.showDestructive(
      context,
      title: '当前数据缓存占用 $_dataCacheSizeStr，确认清空？',
      destructiveLabel: '清空数据缓存',
    );
    if (confirmed) {
      _performClearDataCache();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const M3SettingsSectionHeader(title: '数据与缓存'),
        M3SettingsCard(
          footerText: '清空缓存释放存储空间，不会影响历史记录与收藏状态。',
          children: [
            M3SettingsTile(
              leading: const M3SettingsIconBox(
                icon: Icons.image_outlined,
                bg: Color(0xFFFF9500),
              ),
              title: '图片缓存',
              showDivider: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _imageCacheSizeStr,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    size: 18,
                  ),
                ],
              ),
              onTap: _confirmClearImageCache,
            ),
            M3SettingsTile(
              leading: const M3SettingsIconBox(
                icon: Icons.storage_rounded,
                bg: Color(0xFFFF9F0A),
              ),
              title: '数据缓存',
              showDivider: false,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _dataCacheSizeStr,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 14,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    size: 18,
                  ),
                ],
              ),
              onTap: _confirmClearDataCache,
            ),
          ],
        ),
      ],
    );
  }
}
