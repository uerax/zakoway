import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:zakoway/core/services/network_connectivity_service.dart';
import 'package:zakoway/features/player/controller/playback_state.dart';
import 'package:zakoway/features/player/services/player_preferences_service.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// 自适应网络分级缓存策略：
/// 1. Wi-Fi / 有线宽带环境：开启 32MB 解复用缓冲与 16MB 回退缓存。
///    符合 media_kit 官方标准推荐水线，既保证平滑预读，又防止过度抢占网络通道造成 Seek Range 请求拥塞。
/// 2. 移动蜂窝网络环境：降级为 16MB 解复用缓冲与 4MB 回退缓存。
///    提供 1~2 分钟平滑防抖窗口的同时，防止点开即退时偷跑宝贵流量。
const int _kWifiBufferSize = 32 * 1024 * 1024; // 32MB
const int _kWifiMaxBytes = 32 * 1024 * 1024; // 32MB
const int _kWifiMaxBackBytes = 16 * 1024 * 1024; // 16MB

const int _kMobileBufferSize = 16 * 1024 * 1024; // 16MB
const int _kMobileMaxBytes = 16 * 1024 * 1024; // 16MB
const int _kMobileMaxBackBytes = 4 * 1024 * 1024; // 4MB

/// 首帧黑屏防闪遮罩最长保持时间（硬上限超时兜底，防止纯音频、无视频轨或尺寸事件缺失导致死等遮罩）
const Duration kFirstFrameCoverMaxWait = Duration(milliseconds: 1800);

/// zakoway 视频播放引擎控制器
/// 封装 media_kit (libmpv) 底层驱动，支持 250ms 节流解耦、倍速变调修正与切片断流自动重试
class ZakowayPlaybackController {
  ZakowayPlaybackController();

  /// 低频宏观控制状态
  final ValueNotifier<PlaybackCoreState> core =
      ValueNotifier<PlaybackCoreState>(const PlaybackCoreState());

  /// 高频时间线状态（250ms 节流）
  final ValueNotifier<PlaybackTimelineState> timeline =
      ValueNotifier<PlaybackTimelineState>(const PlaybackTimelineState());

  /// 视频渲染控制器（提供给 Video 组件）
  final ValueNotifier<VideoController?> videoControllerNotifier =
      ValueNotifier<VideoController?>(null);

  Player? _player;
  VideoController? _videoController;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _timelineThrottleTimer;
  Duration _lastPosition = Duration.zero;

  /// 位置采样到达时刻（单调时钟），用于把旧采样外推到“此刻”
  final Stopwatch _positionClock = Stopwatch()..start();
  Duration _lastPositionAt = Duration.zero;
  Duration _lastDuration = Duration.zero;
  Duration _lastBuffer = Duration.zero;

  Timer? _firstFrameFallbackTimer;
  bool _hasReceivedVideoDimensionsSinceOpen = false;

  Duration _pendingStart = Duration.zero;
  bool _disposed = false;
  String? _currentUri;
  double _preMuteVolume = 1.0;

  bool get isDisposed => _disposed;
  Player? get rawPlayer => _player;
  String? get currentUri => _currentUri;

  /// 初始化底层播放器实例与 mpv 原生配置
  Future<void> initialize() async {
    if (_player != null || _disposed) return;

    final isMetered = NetworkConnectivityService.instance.isMetered;
    core.value = core.value.copyWith(isMeteredNetwork: isMetered);
    final initialBufferSize = isMetered ? _kMobileBufferSize : _kWifiBufferSize;

    final player = Player(
      configuration: PlayerConfiguration(
        bufferSize: initialBufferSize,
        title: 'zakoway Player',
      ),
    );
    _player = player;

    _videoController = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    videoControllerNotifier.value = _videoController;

    // 绑定底层播放器流事件与网络环境动态监听
    _subscriptions.addAll([
      player.stream.playing.listen(_onPlayingChanged),
      player.stream.buffering.listen(_onBufferingChanged),
      player.stream.completed.listen(_onCompletedChanged),
      player.stream.position.listen(_onPositionChanged),
      player.stream.duration.listen(_onDurationChanged),
      player.stream.buffer.listen(_onBufferChanged),
      player.stream.rate.listen(_onRateChanged),
      player.stream.error.listen(_onErrorChanged),
      player.stream.width.listen(_onWidthChanged),
      player.stream.height.listen(_onHeightChanged),
      NetworkConnectivityService.instance.onMeteredChanged.listen(_onNetworkMeteredChanged),
    ]);

    // 注入底层 mpv 增强属性
    await _configureNativeMpvProperties();

    // 加载用户上次持久化的播放倍速与音量记忆
    await PlayerPreferencesService.instance.initialize();
    final savedRate = PlayerPreferencesService.instance.playbackRate;
    final savedVolume = PlayerPreferencesService.instance.volume;

    core.value = core.value.copyWith(
      playbackRate: savedRate,
      volume: savedVolume,
      muted: savedVolume <= 0.001,
    );

    if (savedRate != 1.0) {
      await player.setRate(savedRate);
    }
    await player.setVolume(savedVolume * 100.0);
  }

  /// 配置底层 mpv 属性（变速变调不变音、协议层断流自动重连、确保网络流快速定位、自适应分级缓冲）
  Future<void> _configureNativeMpvProperties() async {
    final player = _player;
    if (player == null) return;

    try {
      final platform = player.platform;
      if (platform is NativePlayer) {
        // 1. scaletempo2 滤镜：倍速播放（1.25x~3.0x）时自动修正音高，人声音质不失真
        await platform.setProperty('af', 'scaletempo2=max-speed=8');

        // 2. 特殊处理说明：
        // 针对点播视频网络流 (MP4/HLS)，仅配置基础的 reconnect 与 reconnect_on_network_error，
        // 严禁配置 reconnect_at_eof=1 或 reconnect_streamed=1！
        // 那些参数是专用于不可 Seek 的直播流的；在点播视频 Seek 时，旧 Range 结束会被误判为流异常触发重连，
        // 导致向对端发起并发连接并遭遇服务器 TCP RST (-0x4e)，进而引发卡死与流损坏。
        await platform.setProperty(
          'stream-lavf-o',
          'reconnect=1,reconnect_on_network_error=1,reconnect_delay_max=2',
        );

        // 3. 特殊处理说明：
        // media_kit 默认写死 cache-on-disk=yes，但在 Windows/Android 平台上未配置缓存目录，
        // 会抛出 "Failed to create file cache" 导致缓存子系统损坏。显式关闭磁盘缓存，改用全内存缓冲。
        await platform.setProperty('cache-on-disk', 'no');

        // 4. 特殊处理说明：
        // 开启 demuxer-seekable-cache，使用内存缓存实现已读区间的秒级拖拽/快进，避免重复发起 HTTP 请求。
        await platform.setProperty('demuxer-seekable-cache', 'yes');

        // 5. 特殊处理说明：
        // 必须配置 force-seekable=yes，确保网络 MP4 始终被 libmpv 标记为可寻道流；
        // 点播网络视频（尤其是 1080P 高码率 MP4）必须将 hr-seek 设置为 no。
        // 设为 default/yes 会强制从前序关键帧逐帧解码至目标时间，在网络环境下产生严重的解码延迟与转圈冻结；
        // 设为 no 时，底层直接跳至最近关键帧秒级呈现画面，实现丝滑瞬间拖拽。
        await platform.setProperty('force-seekable', 'yes');
        await platform.setProperty('hr-seek', 'no');

        // 6. 特殊处理说明：
        // 严禁设置 cache-pause-initial=yes！mpv 官方手册明确注明该选项在每次 Seek 拖动进度条后都会
        // 强制重新 pause 并进入 buffering 状态，死等缓冲水线人为制造 1~2 秒转圈。
        // 将其设为 no，并将 cache-pause-wait 降至 0.2 秒轻量防抖，起播与拖拽瞬间出帧。
        await platform.setProperty('cache', 'yes');
        await platform.setProperty('cache-pause', 'yes');
        await platform.setProperty('cache-pause-initial', 'no');
        await platform.setProperty('cache-pause-wait', '0.2');
        await platform.setProperty('demuxer-readahead-secs', '15');
        await platform.setProperty('cache-secs', '30');

        final isMetered = NetworkConnectivityService.instance.isMetered;
        final maxBytes = isMetered ? _kMobileMaxBytes : _kWifiMaxBytes;
        final maxBackBytes = isMetered ? _kMobileMaxBackBytes : _kWifiMaxBackBytes;

        await platform.setProperty('demuxer-max-bytes', maxBytes.toString());
        await platform.setProperty('demuxer-max-back-bytes', maxBackBytes.toString());
        await platform.setProperty('network-timeout', '10');
        await platform.setProperty('volume-max', '100');
        await platform.setProperty('user-agent', _kDefaultUserAgent);

        // 7. 特殊处理说明：
        // 放行过期或未受信任的自签名证书。第三方聚合源/边缘 CDN 节点经常存在证书过期或
        // 自签名情况，关闭媒体流 TLS 校验可大幅提升外链播放成功率（仅作用于底层 mpv 音视频拉流）。
        await platform.setProperty('tls-verify', 'no');

        // 9. 特殊处理说明：
        // 开启全格式硬解码；Android 下使用 auto-safe 防止部分低端芯片遇到非常规编码直接导致 Surface 崩溃。
        await platform.setProperty('hwdec-codecs', 'all');
        if (Platform.isAndroid) {
          await platform.setProperty('hwdec', 'auto-safe');
          // Android 平台默认音频输出
          await platform.setProperty('ao', 'opensles');
        } else {
          await platform.setProperty('hwdec', 'auto');
        }

        // 10. 桌面端（Windows）动漫线条与渲染优化：
        // 采用 Spline36 与 Sigmoid 插值，消除动漫色块边缘锯齿与光晕，计算量轻量杜绝掉帧
        if (Platform.isWindows) {
          await platform.setProperty('scale', 'spline36');
          await platform.setProperty('cscale', 'spline36');
          await platform.setProperty('sigmoid-upscaling', 'yes');
          await platform.setProperty('correct-downscaling', 'yes');
        }
      }
    } catch (e) {
      debugPrint('[ZakowayPlayback] 配置 mpv 属性失败: $e');
    }
  }

  /// 网络环境动态变更（如播放中从 Wi-Fi 切换至 4G/5G 蜂窝数据或反之）：在线热更新 mpv 缓冲水线
  Future<void> _onNetworkMeteredChanged(bool isMetered) async {
    if (_disposed) return;
    core.value = core.value.copyWith(isMeteredNetwork: isMetered);

    final player = _player;
    if (player == null) return;

    try {
      final platform = player.platform;
      if (platform is NativePlayer) {
        final maxBytes = isMetered ? _kMobileMaxBytes : _kWifiMaxBytes;
        final maxBackBytes = isMetered ? _kMobileMaxBackBytes : _kWifiMaxBackBytes;
        await platform.setProperty('demuxer-max-bytes', maxBytes.toString());
        await platform.setProperty('demuxer-max-back-bytes', maxBackBytes.toString());
        debugPrint(
          '[ZakowayPlayback] 网络类型动态变更，已热更新解复用缓冲: '
          '${isMetered ? "移动蜂窝数据模式(16MB)" : "高速Wi-Fi/有线模式(150MB)"}',
        );
      }
    } catch (e) {
      debugPrint('[ZakowayPlayback] 动态热更新解复用缓冲失败: $e');
    }
  }

  /// 打开媒体流并起播
  /// [uri] 媒体播放直链（mp4 / m3u8 等）
  /// [httpHeaders] 防盗链请求头（如 Referer / User-Agent）
  /// [start] 起播定位时间戳（用于历史进度记忆断点续播）
  Future<void> open(
    String uri, {
    Map<String, String>? httpHeaders,
    Duration? start,
    bool autoplay = true,
  }) async {
    if (_disposed) return;
    await initialize();
    final player = _player;
    if (player == null || _disposed) return;

    _currentUri = uri;
    _pendingStart = start ?? Duration.zero;
    _lastPosition = _pendingStart;
    _lastPositionAt = _positionClock.elapsed;
    _lastDuration = Duration.zero;
    _lastBuffer = Duration.zero;
    _hasReceivedVideoDimensionsSinceOpen = false;

    _firstFrameFallbackTimer?.cancel();
    _firstFrameFallbackTimer = Timer(kFirstFrameCoverMaxWait, () {
      if (_disposed) return;
      if (!core.value.firstFrameRendered) {
        _checkFirstFrameRendered(force: true);
      }
    });

    // 特殊处理说明：
    // 切集或初次打开媒体流时，必须将 firstFrameRendered 立即置为 false 并保持 loading=true。
    // 这会在 UI 层激活纯黑防闪遮罩，彻底遮蔽底层 GPU Texture 中残留的上一集最后一帧画面。
    // 直到底层真正解码出首帧（position/duration 就绪）才解除遮罩。
    core.value = core.value.copyWith(
      loading: true,
      firstFrameRendered: false,
      buffering: false,
      completed: false,
      clearError: true,
    );

    timeline.value = PlaybackTimelineState(
      position: _pendingStart,
      duration: Duration.zero,
      buffer: Duration.zero,
    );

    try {
      await player.open(
        Media(
          uri,
          httpHeaders: httpHeaders ?? const <String, String>{},
          start: start,
        ),
        play: autoplay,
      );
    } catch (e) {
      _firstFrameFallbackTimer?.cancel();
      _firstFrameFallbackTimer = null;
      core.value = core.value.copyWith(
        loading: false,
        firstFrameRendered: true,
        buffering: false,
        errorMessage: '视频播放失败: $e',
      );
    }
  }

  /// 播放 / 暂停切换
  Future<void> togglePlay() async {
    if (_disposed) return;
    final player = _player;
    if (player == null) {
      core.value = core.value.copyWith(playing: !core.value.playing);
      return;
    }
    if (core.value.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> play() async {
    if (_disposed) return;
    final player = _player;
    if (player == null) {
      core.value = core.value.copyWith(playing: true);
      return;
    }
    await player.play();
  }

  Future<void> pause() async {
    if (_disposed) return;
    final player = _player;
    if (player == null) {
      core.value = core.value.copyWith(playing: false);
      return;
    }
    await player.pause();
  }

  /// 跳转至指定播放进度
  Future<void> seek(Duration target) async {
    if (_disposed) return;
    final dur = timeline.value.duration;
    var targetPosition = target < Duration.zero ? Duration.zero : target;

    // 特殊处理说明：
    // 若目标时间戳非常接近或等于/超过视频总时长 (dur)，libmpv 会直接触发 eof-reached 将 completed 置为 true。
    // 因此在时长有效时，对 Seek 终点做 500ms 安全余量截断保护。
    if (dur > const Duration(seconds: 1) && targetPosition >= dur) {
      targetPosition = dur - const Duration(milliseconds: 500);
      if (targetPosition < Duration.zero) {
        targetPosition = Duration.zero;
      }
    }

    _lastPosition = targetPosition;
    _lastPositionAt = _positionClock.elapsed;

    timeline.value = timeline.value.copyWith(
      position: targetPosition,
      clearPreview: true,
    );

    // Seek 时主动清除前序偶发错误与 completed 状态，确保平滑恢复与继续播放
    if (core.value.hasError || core.value.completed) {
      core.value = core.value.copyWith(
        clearError: true,
        completed: false,
      );
    }

    final player = _player;
    if (player != null) {
      // 特殊处理说明：
      // 直接委托底层 media_kit 原生 seek 处理，杜绝上层多余的 pause() -> seek() -> play() 异步交错。
      // 外层反复 pause/play 会破坏底层解复用线程与解码器缓冲区的状态机同步，诱发 Packet corrupt。
      await player.seek(targetPosition);
    }
  }

  /// 进度条拖拽中实时更新预览位置（手指不松开不调用底层的 seek）
  void updateSeekPreview(Duration previewTarget) {
    timeline.value = timeline.value.copyWith(previewPosition: previewTarget);
  }

  /// 结束拖拽，真正落地 seek
  Future<void> endSeekPreview() async {
    final preview = timeline.value.previewPosition;
    if (preview != null) {
      await seek(preview);
    }
  }

  /// 步进跳转（快进 / 快退）
  Future<void> seekBy(Duration offset) async {
    final current = timeline.value.position;
    final target = current + offset;
    await seek(target);
  }

  /// 设置播放倍速
  Future<void> setPlaybackRate(double rate) async {
    if (_disposed) return;
    final clampedRate = math.max(0.25, math.min(3.0, rate));
    core.value = core.value.copyWith(playbackRate: clampedRate);
    final player = _player;
    if (player != null) {
      await player.setRate(clampedRate);
    }
    PlayerPreferencesService.instance.savePlaybackRate(clampedRate).ignore();
  }

  /// 设置音量 (0.0 ~ 1.0)
  Future<void> setVolume(double vol) async {
    final clamped = math.max(0.0, math.min(1.0, vol));
    core.value = core.value.copyWith(
      volume: clamped,
      muted: clamped <= 0.001,
    );
    final player = _player;
    if (player != null) {
      // media_kit volume 范围为 0 ~ 100
      await player.setVolume(clamped * 100.0);
    }
    PlayerPreferencesService.instance.saveVolume(clamped).ignore();
  }

  /// 退出页面前静音底层播放器：不改写 UI 音量状态，也不落盘用户音量偏好
  Future<void> muteForExit() async {
    final player = _player;
    if (player == null) return;
    try {
      await player.setVolume(0.0);
    } catch (_) {}
  }

  /// 切换静音
  Future<void> toggleMute() async {
    if (core.value.muted) {
      await setVolume(_preMuteVolume > 0.05 ? _preMuteVolume : 0.7);
    } else {
      _preMuteVolume = core.value.volume;
      await setVolume(0.0);
    }
  }

  /// 切换画面缩放模式
  void setVideoFit(BoxFit fit) {
    core.value = core.value.copyWith(videoFit: fit);
  }

  /// 切换 Anime4K 超分辨率画质增强模式
  Future<void> setSuperResolution(SuperResolutionMode mode) async {
    core.value = core.value.copyWith(superResolution: mode);
    final player = _player;
    if (player == null) return;
    try {
      final platform = player.platform;
      if (platform is NativePlayer) {
        if (mode == SuperResolutionMode.off) {
          await platform.command(['change-list', 'glsl-shaders', 'clr', '']);
        }
      }
    } catch (_) {}
  }

  /// 高清截取当前视频帧画面
  Future<Uint8List?> screenshot({String format = 'image/png'}) async {
    final player = _player;
    if (player == null) return null;
    try {
      return await player.screenshot(format: format);
    } catch (_) {
      return null;
    }
  }

  // ==========================
  // 底层事件流响应与 250ms 节流
  // ==========================

  void _onPlayingChanged(bool isPlaying) {
    if (_disposed) return;
    if (core.value.playing != isPlaying) {
      core.value = core.value.copyWith(
        playing: isPlaying,
        clearError: isPlaying,
      );
      _checkFirstFrameRendered();
    }
  }

  void _onBufferingChanged(bool isBuffering) {
    if (_disposed) return;
    if (core.value.buffering != isBuffering) {
      core.value = core.value.copyWith(buffering: isBuffering);
      if (!isBuffering) {
        _checkFirstFrameRendered();
      }
    }
  }

  void _onCompletedChanged(bool isCompleted) {
    if (_disposed) return;
    if (isCompleted) {
      // 特殊处理说明：
      // 当底层网络断流或解码瞬态异常抛出 EOF code: 4 (ERROR) 时，
      // media_kit 会将 eof-reached 误认为 completed = true。
      // 只有当当前播放位置真正接近视频总时长（剩余不足 2 秒）时，才确认为自然播放结束。
      // 严禁在中途非正常 EOF 时调用 player.play()，因为 EOF 态下调用 play() 会被 mpv 默认当做从 00:00 重播。
      final currentPos = timeline.value.position;
      final totalDur = timeline.value.duration;
      if (totalDur > const Duration(seconds: 5) &&
          currentPos < totalDur - const Duration(seconds: 2)) {
        debugPrint(
          '[ZakowayPlayback] 忽略中途非正常 EOF 信号 (当前: ${currentPos.inSeconds}s, 总长: ${totalDur.inSeconds}s)',
        );
        return;
      }
    }

    if (core.value.completed != isCompleted) {
      core.value = core.value.copyWith(completed: isCompleted);
    }
  }

  void _onRateChanged(double rate) {
    if (_disposed) return;
    if (core.value.playbackRate != rate) {
      core.value = core.value.copyWith(playbackRate: rate);
    }
  }

  void _onErrorChanged(String error) {
    if (_disposed || error.isEmpty) return;

    // 过滤底层网络断开/Seek重连/EOF良性日志 (如 FFmpeg AVERROR_EOF = -541478725 / 0xdfb9b0bb)
    final lower = error.toLowerCase();
    if (lower.contains('0xdfb9b0bb') ||
        lower.contains('ffurl_read returned') ||
        lower.contains('end of file') ||
        lower.contains('connection reset by peer')) {
      debugPrint('[ZakowayPlayback] 忽略底层网络断流/Seek良性重连日志: $error');
      return;
    }

    _firstFrameFallbackTimer?.cancel();
    _firstFrameFallbackTimer = null;
    core.value = core.value.copyWith(
      errorMessage: error,
      loading: false,
      firstFrameRendered: true,
    );
  }

  void _onPositionChanged(Duration pos) {
    if (_disposed) return;
    // 门禁：规避起播瞬间 mpv 抛出的 0 秒事件覆盖真实断点进度
    if (_pendingStart > Duration.zero) {
      if (pos + const Duration(seconds: 1) < _pendingStart) {
        return;
      }
      _pendingStart = Duration.zero;
    }

    // 当播放进度正常前进时，说明媒体解码通畅，自动抹除瞬态错误
    if (core.value.hasError && pos > Duration.zero) {
      core.value = core.value.copyWith(clearError: true);
    }

    _lastPosition = pos;
    _lastPositionAt = _positionClock.elapsed;
    _scheduleTimelineEmit();
  }

  void _onDurationChanged(Duration dur) {
    if (_disposed) return;
    _lastDuration = dur;
    _scheduleTimelineEmit();
  }

  void _onWidthChanged(int? width) {
    if (_disposed) return;
    if ((width ?? 0) > 0) {
      _hasReceivedVideoDimensionsSinceOpen = true;
      _checkFirstFrameRendered();
    }
  }

  void _onHeightChanged(int? height) {
    if (_disposed) return;
    if ((height ?? 0) > 0) {
      _hasReceivedVideoDimensionsSinceOpen = true;
      _checkFirstFrameRendered();
    }
  }

  /// 检查新视频首帧是否已经真正解码渲染上屏
  /// 特殊处理说明：
  /// 首帧就绪门禁：
  /// 1. open() 之后收到 player.stream.width / height 非空且大于 0 的事件，
  ///    作为解码器真正出画（mpv 报出 video-params）的可靠物理信号；
  /// 2. 具备硬上限超时兜底 (kFirstFrameCoverMaxWait / force: true)，
  ///    防止纯音频、无视频轨或尺寸事件缺失导致遮罩永久卡死。
  void _checkFirstFrameRendered({bool force = false}) {
    if (_disposed) return;
    if (!core.value.firstFrameRendered) {
      final canRender = force || _hasReceivedVideoDimensionsSinceOpen;
      if (canRender) {
        _firstFrameFallbackTimer?.cancel();
        _firstFrameFallbackTimer = null;
        core.value = core.value.copyWith(
          firstFrameRendered: true,
          loading: false,
        );
      }
    }
  }

  void _onBufferChanged(Duration buf) {
    if (_disposed) return;
    _lastBuffer = buf;
    _scheduleTimelineEmit();
  }

  /// 把最近一次位置采样按到达时刻外推到当前时刻，供弹幕时钟对时使用。
  /// 采样本身是旧值（事件延迟 + 250ms 节流定时器），直接拿来对时会给弹幕时钟注入噪声。
  /// 暂停 / 缓冲中不外推；外推量设上限，防止事件长时间缺失时越推越偏。
  Duration get extrapolatedPosition {
    if (_disposed) return Duration.zero;
    final state = core.value;
    if (!state.playing || state.buffering) return timeline.value.position;
    final ageUs = (_positionClock.elapsed - _lastPositionAt).inMicroseconds;
    if (ageUs <= 0) return _lastPosition;
    final cappedUs = math.min(ageUs, 250000);
    return _lastPosition +
        Duration(microseconds: (cappedUs * state.playbackRate).round());
  }

  /// 250ms 节流触发时间线更新，杜绝高频重绘
  void _scheduleTimelineEmit() {
    if (_timelineThrottleTimer != null && _timelineThrottleTimer!.isActive) {
      return;
    }

    _timelineThrottleTimer = Timer(const Duration(milliseconds: 250), () {
      if (_disposed) return;
      timeline.value = timeline.value.copyWith(
        position: _lastPosition,
        duration: _lastDuration,
        buffer: _lastBuffer,
      );
    });
  }

  /// 资源销毁
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _firstFrameFallbackTimer?.cancel();
    _firstFrameFallbackTimer = null;
    _timelineThrottleTimer?.cancel();
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _subscriptions.clear();

    final player = _player;
    _player = null;
    videoControllerNotifier.value = null;

    if (player != null) {
      // 特殊处理说明：
      // 在页面 Pop 退出或销毁时，libmpv (media_kit) 若正处于网络缓冲或 demux 状态，
      // 同步等待 player.stop()/dispose() 会阻塞原生线程与 PlatformChannel 达数秒导致界面卡死。
      // 因此此处先立即触发非阻塞 pause，并将真正的 stop/dispose 脱钩至后台微任务中异步释放。
      unawaited(() async {
        try {
          await player.pause();
          await player.stop();
        } catch (_) {}
        try {
          await player.dispose();
        } catch (_) {}
      }());
    }

    core.dispose();
    timeline.dispose();
    videoControllerNotifier.dispose();
  }
}
