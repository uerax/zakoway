# 播放控制层重写：阶段 0 设计文档（5/7）—— 接口定义与兼容层（v2）

## 本版相对 v1 的变更
1. **结构化错误流定义**：`PlayerBackend.onErrorOccurred` 签名由粗糙的 `Stream<String>` 全面重构为结构化的 `Stream<BackendError>`。
2. **事件流增加 `openToken` 原生分界标记**：所有底层状态流（尺寸、位置、时长、缓冲、错误）均携带原生 open 分界标记 `openToken`，使跨集、切源的迟到原生事件在适配层出口处即可被精确识别并拦截。
3. **修正门面（Facade）幂等性与生命周期**：
   * `play()` 与 `pause()` 必须具有严格的**幂等性**（状态已匹配时无副作用立即返回）；
   * `open()` 统一遵循“每次起播均创建全新 `PlaybackSession` 实例”的明确契约，旧 Session 显式清理。
4. **统一 Session 生命周期模型**：选定“每次 open 创建一个独立的 `PlaybackSession` 实例”模型，与 03 状态机保持 100% 严格统一。

---

## 一、`PlayerBackend` 契约（底层播放内核抽象）

`PlayerBackend` 是对具体播放内核（media_kit / libmpv）的统一抽象。所有由底层派发的事件均携带 `openToken`，标识其归属于哪一次原生 `open` 调用。

```dart
import 'dart:typed_data';
import 'package:flutter/widgets.dart';
import '../models/backend_error.dart';

/// 携带 openToken 原生分界标记的事件包装器
@immutable
class BackendEvent<T> {
  const BackendEvent(this.data, {required this.openToken});
  final T data;
  final int openToken;
}

/// 视频画面物理尺寸模型
@immutable
class VideoDimensions {
  const VideoDimensions(this.width, this.height);
  final int width;
  final int height;

  bool get hasValidSize => width > 0 && height > 0;
  double get aspectRatio => height == 0 ? 16 / 9 : width / height;
}

/// 底层音视频播放引擎后端抽象契约
abstract class PlayerBackend {
  /// 初始化播放器底层实例与平台原生配置
  Future<void> initialize({required bool isMeteredNetwork});

  /// 打开媒体流并起播
  /// 返回值为本次底层 open 分配的全局单调自增 `openToken`
  Future<int> open(
    String uri, {
    Map<String, String>? headers,
    Duration? start,
    bool autoplay = true,
  });

  /// 恢复播放（底层必须保证幂等，已处于 playing 时无副作用）
  Future<void> play();

  /// 暂停播放（底层必须保证幂等，已处于 paused 时无副作用）
  Future<void> pause();

  /// 精准寻道（底层需包含 500ms 终点截断保护与丢帧加速配置）
  Future<void> seek(Duration position);

  /// 设置播放速率 (0.25x ~ 3.0x，内置 scaletempo2 音高修正)
  Future<void> setRate(double rate);

  /// 设置音量大小 (0.0 ~ 1.0)
  Future<void> setVolume(double volume);

  /// 页面退场前轻量静音（不改写用户音量偏好，不触发持久化）
  Future<void> muteForExit();

  /// 动态应用或清空 Anime4K GLSL 着色器滤镜链
  Future<void> applyShaders(List<String> shaderPaths);

  /// 截取当前视频帧画面
  Future<Uint8List?> screenshot({String format = 'image/png'});

  /// 在线热更新解复用缓冲水线（适应网络类型变化）
  Future<void> updateDemuxerCacheWatermark({
    required int maxBytes,
    required int maxBackBytes,
  });

  /// 释放播放器底层资源（需支持后台微任务脱钩防阻塞）
  Future<void> dispose();

  // ==========================================
  // 底层带 openToken 分界的广播流事件通道
  // ==========================================
  Stream<BackendEvent<bool>> get onPlayingChanged;
  Stream<BackendEvent<bool>> get onBufferingChanged;
  Stream<BackendEvent<bool>> get onCompletedChanged;
  Stream<BackendEvent<Duration>> get onPositionChanged;
  Stream<BackendEvent<Duration>> get onDurationChanged;
  Stream<BackendEvent<Duration>> get onBufferChanged;
  Stream<BackendEvent<double>> get onRateChanged;
  Stream<BackendEvent<VideoDimensions>> get onDimensionsChanged;

  /// 结构化错误流（由适配层单点解析原始日志生成）
  Stream<BackendError> get onErrorOccurred;

  /// 供 UI 层挂载渲染的原生组件工厂
  Widget buildVideoSurface({
    required BoxFit fit,
    Key? key,
  });
}
```

---

## 二、`SourceResolver` 契约（直链解析与缓存中心）

```dart
/// 直链解析结果数据模型
@immutable
class ResolvedMedia {
  const ResolvedMedia({
    required this.url,
    this.headers = const <String, String>{},
    this.format = 'mp4',
    this.expiresAt,
  });

  /// 媒体直链 URL
  final String url;

  /// 防盗链请求头 (Referer, Cookie, User-Agent)
  final Map<String, String> headers;

  /// 流媒体格式 ('mp4', 'm3u8', etc.)
  final String format;

  /// 临时鉴权/签名预估失效时刻
  final DateTime? expiresAt;

  /// 该直链是否已过期或即将过期（预留 15 秒安全缓冲窗口）
  bool get isExpired {
    if (expiresAt == null) return false;
    return DateTime.now().isAfter(
      expiresAt!.subtract(const Duration(seconds: 15)),
    );
  }
}

/// 视频源直链解析器契约
abstract class SourceResolver {
  /// 根据分集页面 URL 解析可播放直链
  /// [bypassCache]: 是否强制绕过 L1 短时缓存向上游发起新鲜请求
  Future<ResolvedMedia> resolve(
    String sourceId,
    String episodeUrl, {
    bool bypassCache = false,
  });

  /// 显式驱逐某分集的 L1 直链缓存（遭遇 403 拦截或失效时调用）
  void invalidate(String sourceId, String episodeUrl);

  /// 查询指定分集当前缓存的过期时间
  DateTime? expiresAt(String sourceId, String episodeUrl);

  /// 清空当前解析器的全部内存缓存
  void clearCache();
}
```

---

## 三、`PlaybackSession` 生命周期与状态机契约

### 3.1 统一 Session 模型：每次 `open()` 产生一个全新实例
* **架构决策理由**：
  若采用“全局单一 Session 内部重置计数”模型，前一集的定时器、退避重试循环、状态机残余监听极易发生状态泄漏，代码中充斥着复杂的 `reset()` 清理逻辑。
  **统一采用“每次起播实例化一个全新的 `PlaybackSession`”**：
  1. 生命周期完全自然闭环：新 Session 拥有全新的 Attempt ID，状态从 `idle` 干净起步；
  2. 旧 Session 直接调用 `dispose()`，将其所有未完成的 Future、退避定时器与流监听彻底掐断；
  3. 杜绝任何跨集状态污染，保证单元测试可针对单次会话进行纯粹隔离的测试。

```dart
abstract class PlaybackSession {
  /// 本次会话全局自增 Attempt ID (用于 Dart 异步流校验)
  int get attemptId;

  /// 当前会话对应的正片集数
  int get canonicalEpisode;

  /// 目标视频源 ID
  String get sourceId;

  /// 核心状态只读通知器
  ValueListenable<PlaybackCoreState> get coreNotifier;

  /// 高频时间线只读通知器
  ValueListenable<PlaybackTimelineState> get timelineNotifier;

  /// 绑定底层驱动并启动会话
  Future<void> start({
    Duration? initialResumePosition,
    bool autoplay = true,
  });

  /// 寻道（带 500ms 终点截断保护）
  Future<void> seek(Duration position);

  /// 拖拽预览更新（不直接调用底层）
  void updateSeekPreview(Duration position);

  /// 结束拖拽真正 Seek
  Future<void> endSeekPreview();

  /// 幂等播放
  Future<void> play();

  /// 幂等暂停
  Future<void> pause();

  /// 切换倍速
  Future<void> setPlaybackRate(double rate);

  /// 切换音量
  Future<void> setVolume(double volume);

  /// 切换静音
  Future<void> toggleMute();

  /// 切换 Anime4K 超分模式
  Future<void> setSuperResolution(SuperResolutionMode mode);

  /// 手动错误重试
  Future<void> retry();

  /// 销毁并退出会话
  Future<void> dispose();
}
```

---

## 四、`ZakowayPlaybackController` 门面（Facade）规范

门面类对所有上层组件暴露**完全向后兼容**的接口，内部严格管理会话生命周期与调用幂等性：

```dart
class ZakowayPlaybackController {
  ZakowayPlaybackController({
    PlayerBackend? backend,
    SourceResolver? resolver,
  })  : _backend = backend ?? MediaKitPlayerBackend(),
        _resolver = resolver ?? NativeSourceRuntime();

  final PlayerBackend _backend;
  final SourceResolver _resolver;
  PlaybackSession? _activeSession;

  /// 对外 100% 保持兼容的只读状态通知器
  final ValueNotifier<PlaybackCoreState> core =
      ValueNotifier<PlaybackCoreState>(const PlaybackCoreState());

  final ValueNotifier<PlaybackTimelineState> timeline =
      ValueNotifier<PlaybackTimelineState>(const PlaybackTimelineState());

  final ValueNotifier<PlayerBackend?> backendNotifier =
      ValueNotifier<PlayerBackend?>(null);

  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  /// 初始化播放器底座
  Future<void> initialize() async {
    if (_isDisposed) return;
    await _backend.initialize(
      isMeteredNetwork: NetworkConnectivityService.instance.isMetered,
    );
    backendNotifier.value = _backend;
  }

  /// 打开媒体直链并起播：统一创建全新 Session 实例
  Future<void> open(
    String uri, {
    Map<String, String>? httpHeaders,
    Duration? start,
    bool autoplay = true,
    int? canonicalEpisode,
    String? sourceId,
  }) async {
    if (_isDisposed) return;
    await initialize();

    // 1. 显式安全释放旧会话
    if (_activeSession != null) {
      await _activeSession!.dispose();
      _activeSession = null;
    }

    // 2. 实例化新 Session
    final session = PlaybackSessionImpl(
      backend: _backend,
      resolver: _resolver,
      uri: uri,
      httpHeaders: httpHeaders,
      canonicalEpisode: canonicalEpisode ?? 1,
      sourceId: sourceId ?? 'default',
      onCoreChanged: (state) => core.value = state,
      onTimelineChanged: (state) => timeline.value = state,
    );
    _activeSession = session;

    // 3. 启动新会话
    await session.start(
      initialResumePosition: start,
      autoplay: autoplay,
    );
  }

  /// 幂等播放：已处于 playing 状态时直接 return
  Future<void> play() async {
    if (_isDisposed || core.value.playing) return;
    await _activeSession?.play();
  }

  /// 幂等暂停：已处于 paused 状态时直接 return
  Future<void> pause() async {
    if (_isDisposed || !core.value.playing) return;
    await _activeSession?.pause();
  }

  /// 播放 / 暂停切换
  Future<void> togglePlay() async {
    if (core.value.playing) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration target) async {
    if (_isDisposed) return;
    await _activeSession?.seek(target);
  }

  void updateSeekPreview(Duration previewTarget) {
    _activeSession?.updateSeekPreview(previewTarget);
  }

  Future<void> endSeekPreview() async {
    await _activeSession?.endSeekPreview();
  }

  Future<void> seekBy(Duration offset) async {
    final current = timeline.value.position;
    await seek(current + offset);
  }

  Future<void> setPlaybackRate(double rate) async {
    await _activeSession?.setPlaybackRate(rate);
  }

  Future<void> setVolume(double vol) async {
    await _activeSession?.setVolume(vol);
  }

  Future<void> toggleMute() async {
    await _activeSession?.toggleMute();
  }

  Future<void> muteForExit() async {
    await _backend.muteForExit();
  }

  Future<void> setSuperResolution(SuperResolutionMode mode) async {
    await _activeSession?.setSuperResolution(mode);
  }

  Future<Uint8List?> screenshot({String format = 'image/png'}) async {
    return await _backend.screenshot(format: format);
  }

  /// 释放控制器
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;

    await _activeSession?.dispose();
    _activeSession = null;

    // 后台微任务异步释放底层后端
    unawaited(_backend.dispose());

    backendNotifier.dispose();
    core.dispose();
    timeline.dispose();
  }
}
```
通过上述 Facade 规范，`video_play_page.dart` 以及所有子组件对 `controller.core`、`controller.timeline`、`controller.play()`、`controller.seek()` 的调用**保持 100% 源码兼容**，平滑对接底层状态机。
