library;

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';

/// 桌面端与移动端 Native MPV 底层策略强类型配置对象
///
/// 遵循 docs/player-rewrite/09-adapter-plan.md 第四节规范
/// 完整承载 11 组核心底层参数，提供跨平台属性映射与在线热更新能力
class NativeMpvPolicy {
  const NativeMpvPolicy({
    this.audioFilter = 'scaletempo2=max-speed=8',
    this.streamLavfOptions =
        'reconnect=1,reconnect_on_network_error=1,reconnect_delay_max=2',
    this.cacheOnDisk = false,
    this.demuxerSeekableCache = true,
    this.forceSeekable = true,
    this.hrSeek = 'default',
    this.hrSeekFramedrop = true,
    this.cache = true,
    this.cachePause = true,
    this.cachePauseInitial = false,
    this.cachePauseWaitSecs = 0.2,
    this.demuxerReadaheadSecs = 15,
    this.cacheSecs = 30,
    this.wifiMaxBytes = 32 * 1024 * 1024,
    this.wifiMaxBackBytes = 16 * 1024 * 1024,
    this.mobileMaxBytes = 16 * 1024 * 1024,
    this.mobileMaxBackBytes = 4 * 1024 * 1024,
    this.networkTimeoutSecs = 10,
    this.volumeMax = 100,
    this.userAgent =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
    this.tlsVerify = false,
    this.hwdecCodecs = 'all',
    this.enableWindowsScaling = true,
    this.scale = 'spline36',
    this.cscale = 'spline36',
    this.sigmoidUpscaling = true,
    this.correctDownscaling = true,
    this.subFont =
        'Microsoft YaHei UI, PingFang SC, Segoe UI, sans-serif',
    this.subFontSize = 48,
    this.subColor = '#FFFFFFFF',
    this.subBorderColor = '#D0000000',
    this.subBorderSize = 2.2,
    this.subShadowOffset = 1.2,
    this.subShadowColor = '#60000000',
    this.subMarginY = 38,
    this.subAssOverride = 'scale',
    this.subAssForceMargins = true,
  });

  /// 1. 音频滤镜：倍速音高自动修正
  final String audioFilter;

  /// 2. 网络流选项：断流自动重连（严禁 reconnect_at_eof / reconnect_streamed）
  final String streamLavfOptions;

  /// 3. 磁盘缓存开关（Windows/Android 无目录配置时关闭，改用全内存）
  final bool cacheOnDisk;

  /// 4. 内存已读区间瞬时 Seek
  final bool demuxerSeekableCache;

  /// 5. 精准可寻道流标记与丢帧加速
  final bool forceSeekable;
  final String hrSeek;
  final bool hrSeekFramedrop;

  /// 6. 缓存与防转圈配置（严禁 cache-pause-initial=yes）
  final bool cache;
  final bool cachePause;
  final bool cachePauseInitial;
  final double cachePauseWaitSecs;
  final int demuxerReadaheadSecs;
  final int cacheSecs;

  /// 7. 分级内存水线（Wi-Fi vs 移动蜂窝）
  final int wifiMaxBytes;
  final int wifiMaxBackBytes;
  final int mobileMaxBytes;
  final int mobileMaxBackBytes;

  /// 8. 网络超时与 UA
  final int networkTimeoutSecs;
  final int volumeMax;
  final String userAgent;

  /// 9. 放行过期自签名证书
  final bool tlsVerify;

  /// 10. 平台硬解码与音频输出
  final String hwdecCodecs;

  /// 11. 桌面端（Windows）画质插值增强可选项（默认启用，保持现状）
  final bool enableWindowsScaling;
  final String scale;
  final String cscale;
  final bool sigmoidUpscaling;
  final bool correctDownscaling;

  /// 12. 字幕排版与质感增强配置（严防 Windows 跌入宋体，保障高质感柔和描边与合适边距）
  final String subFont;
  final int subFontSize;
  final String subColor;
  final String subBorderColor;
  final double subBorderSize;
  final double subShadowOffset;
  final String subShadowColor;
  final int subMarginY;
  final String subAssOverride;
  final bool subAssForceMargins;

  /// 计算在指定网络与操作系统平台下的完整 MPV 属性字典
  Map<String, String> toMpvProperties({
    required bool isMeteredNetwork,
    String? platformOverride,
  }) {
    final os = (platformOverride ?? Platform.operatingSystem).toLowerCase();
    final isAndroid = os == 'android';
    final isWindows = os == 'windows';

    final maxBytes = isMeteredNetwork ? mobileMaxBytes : wifiMaxBytes;
    final maxBackBytes =
        isMeteredNetwork ? mobileMaxBackBytes : wifiMaxBackBytes;

    final props = <String, String>{
      'af': audioFilter,
      'stream-lavf-o': streamLavfOptions,
      'cache-on-disk': cacheOnDisk ? 'yes' : 'no',
      'demuxer-seekable-cache': demuxerSeekableCache ? 'yes' : 'no',
      'force-seekable': forceSeekable ? 'yes' : 'no',
      'hr-seek': hrSeek,
      'hr-seek-framedrop': hrSeekFramedrop ? 'yes' : 'no',
      'cache': cache ? 'yes' : 'no',
      'cache-pause': cachePause ? 'yes' : 'no',
      'cache-pause-initial': cachePauseInitial ? 'yes' : 'no',
      'cache-pause-wait': cachePauseWaitSecs.toString(),
      'demuxer-readahead-secs': demuxerReadaheadSecs.toString(),
      'cache-secs': cacheSecs.toString(),
      'demuxer-max-bytes': maxBytes.toString(),
      'demuxer-max-back-bytes': maxBackBytes.toString(),
      'network-timeout': networkTimeoutSecs.toString(),
      'volume-max': volumeMax.toString(),
      'user-agent': userAgent,
      'tls-verify': tlsVerify ? 'yes' : 'no',
      'hwdec-codecs': hwdecCodecs,
      'hwdec': isAndroid ? 'auto-safe' : 'auto',
      'sub-font': subFont,
      'sub-font-size': subFontSize.toString(),
      'sub-color': subColor,
      'sub-border-color': subBorderColor,
      'sub-border-size': subBorderSize.toString(),
      'sub-shadow-offset': subShadowOffset.toString(),
      'sub-shadow-color': subShadowColor,
      'sub-margin-y': subMarginY.toString(),
      'sub-ass-override': subAssOverride,
      'sub-ass-force-margins': subAssForceMargins ? 'yes' : 'no',
    };

    if (isAndroid) {
      props['ao'] = 'opensles';
    }

    if (isWindows && enableWindowsScaling) {
      props['scale'] = scale;
      props['cscale'] = cscale;
      props['sigmoid-upscaling'] = sigmoidUpscaling ? 'yes' : 'no';
      props['correct-downscaling'] = correctDownscaling ? 'yes' : 'no';
    }

    return props;
  }

  /// 提取用于运行期动态更新的缓冲水线属性字典
  Map<String, String> getDemuxerWatermarkProperties({
    required bool isMeteredNetwork,
  }) {
    final maxBytes = isMeteredNetwork ? mobileMaxBytes : wifiMaxBytes;
    final maxBackBytes =
        isMeteredNetwork ? mobileMaxBackBytes : wifiMaxBackBytes;
    return {
      'demuxer-max-bytes': maxBytes.toString(),
      'demuxer-max-back-bytes': maxBackBytes.toString(),
    };
  }

  /// 将属性字典一次性下发至 media_kit NativePlayer
  Future<void> apply(
    Player player, {
    required bool isMeteredNetwork,
    String? platformOverride,
  }) async {
    try {
      final platform = player.platform;
      if (platform is NativePlayer) {
        final props = toMpvProperties(
          isMeteredNetwork: isMeteredNetwork,
          platformOverride: platformOverride,
        );
        for (final entry in props.entries) {
          await platform.setProperty(entry.key, entry.value);
        }
      }
    } catch (e) {
      debugPrint('[NativeMpvPolicy] 配置 mpv 属性失败: $e');
    }
  }
}
