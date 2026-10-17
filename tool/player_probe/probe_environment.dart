import 'dart:io';
import 'package:media_kit/media_kit.dart';

const String kProbeUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

class ProbeEnvironment {
  static bool _initialized = false;

  static void ensureInitialized() {
    if (_initialized) return;

    final candidatePaths = [
      '${Directory.current.path}/build/windows/x64/libmpv/libmpv-2.dll',
      '${Directory.current.path}/build/windows/x64/runner/Debug/libmpv-2.dll',
      '${Directory.current.path}/build/windows/x64/runner/Profile/libmpv-2.dll',
    ];

    String? dllPath;
    for (final p in candidatePaths) {
      if (File(p).existsSync()) {
        dllPath = p;
        break;
      }
    }

    MediaKit.ensureInitialized(libmpv: dllPath);
    _initialized = true;
  }

  /// 注入应用生产实际使用的完整 mpv 原生属性配置
  /// 来源：lib/features/player/controller/playback_controller.dart 中的 _configureNativeMpvProperties
  static Future<void> applyAppMpvProperties(Player player) async {
    final platform = player.platform;
    if (platform is! NativePlayer) return;

    // 1. scaletempo2
    await platform.setProperty('af', 'scaletempo2=max-speed=8');

    // 2. stream-lavf-o
    await platform.setProperty(
      'stream-lavf-o',
      'reconnect=1,reconnect_on_network_error=1,reconnect_delay_max=2',
    );

    // 3. 禁用磁盘缓存，采用内存缓冲
    await platform.setProperty('cache-on-disk', 'no');

    // 4. demuxer-seekable-cache
    await platform.setProperty('demuxer-seekable-cache', 'yes');

    // 5. force-seekable & hr-seek
    await platform.setProperty('force-seekable', 'yes');
    await platform.setProperty('hr-seek', 'default');
    await platform.setProperty('hr-seek-framedrop', 'yes');

    // 6. cache & pause 配置 (Wi-Fi 默认)
    await platform.setProperty('cache', 'yes');
    await platform.setProperty('cache-pause', 'yes');
    await platform.setProperty('cache-pause-initial', 'no');
    await platform.setProperty('cache-pause-wait', '0.2');
    await platform.setProperty('demuxer-readahead-secs', '15');
    await platform.setProperty('cache-secs', '30');

    // 32MB Wi-Fi 缓存水线
    const int wifiMaxBytes = 32 * 1024 * 1024;
    const int wifiMaxBackBytes = 16 * 1024 * 1024;
    await platform.setProperty('demuxer-max-bytes', wifiMaxBytes.toString());
    await platform.setProperty('demuxer-max-back-bytes', wifiMaxBackBytes.toString());

    await platform.setProperty('network-timeout', '10');
    await platform.setProperty('volume-max', '100');
    await platform.setProperty('user-agent', kProbeUserAgent);

    // 7. 放行自签名与非受信任证书
    await platform.setProperty('tls-verify', 'no');

    // 8. 硬解
    await platform.setProperty('hwdec-codecs', 'all');
    await platform.setProperty('hwdec', 'auto');

    // 9. Windows 动漫插值渲染配置
    if (Platform.isWindows) {
      await platform.setProperty('scale', 'spline36');
      await platform.setProperty('cscale', 'spline36');
      await platform.setProperty('sigmoid-upscaling', 'yes');
      await platform.setProperty('correct-downscaling', 'yes');
    }
  }
}
