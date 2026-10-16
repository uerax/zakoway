# 播放控制层重写：阶段 0 设计文档（1/7）—— 现状盘点（v2）

## 本版相对 v1 的变更
1. **强化未知项登记**：将首帧判定与时间倒挂门禁中“依赖 `position >= Duration.zero` 的无效恒真判定”及“外推采样上限固定 250ms 的经验值”明确列为代码现状分析重点。
2. **区分业务层与内核层边界**：在盘点中明确标注出哪些字段属于业务层（如 15s 有效播放统计、历史落盘、自动连播），为后续将其剥离至 `WatchProgressTracker` 奠定依据。

---

## 一、`playback_controller.dart` 现状盘点

文件路径：`lib/features/player/controller/playback_controller.dart`  
总代码行数：778 行

### 1.1 状态相关字段清单

| 字段名 | 类型 | 初始值 / 默认值 | 作用描述 | 解决的问题（以注释为准） |
| :--- | :--- | :--- | :--- | :--- |
| `core` | `ValueNotifier<PlaybackCoreState>` | `PlaybackCoreState()` | 播放器低频宏观控制状态容器 | **解决高低频状态耦合引发的掉帧**：仅在宏观状态（播放/暂停、加载、缓冲、倍速、音量、超分）变化时通知，不包含毫秒级时间戳。 |
| `timeline` | `ValueNotifier<PlaybackTimelineState>` | `PlaybackTimelineState()` | 播放器高频时间线状态容器 | **解决时间戳高频刷新拖垮渲染树**：250ms 节流派发，专供进度条、时间文字与弹幕时间轴监听。 |
| `videoControllerNotifier` | `ValueNotifier<VideoController?>` | `null` | 原生视频渲染控制器容器 | 提供给 `Video` 组件使用；在 `initialize` 完成后装载，销毁时置空。 |
| `_player` | `Player?` | `null` | media_kit (libmpv) 底层驱动实例 | 底层媒体播放核心。 |
| `_videoController` | `VideoController?` | `null` | media_kit_video 渲染控制器 | 开启硬解渲染管道（`enableHardwareAcceleration: true`）。 |
| `_subscriptions` | `List<StreamSubscription>` | `[]` | 底层事件流与网络监听订阅列表 | 集中管理 11 个底层流监听，便于 `dispose` 时安全取消。 |
| `_timelineThrottleTimer` | `Timer?` | `null` | 250ms 时间线节流定时器 | **解决高频重绘**：250ms 节流触发时间线更新，杜绝底层每几十毫秒上报导致的高频 UI 重建。 |
| `_lastPosition` | `Duration` | `Duration.zero` | 最近一次底层采样的播放进度 | **解决时间倒挂**：起播时初始化为 `Duration.zero`，严禁提前预设为 `_pendingStart`，杜绝断点起播时在时长解析前显示「04:26 / 00:00」的时间倒挂荒谬界面。 |
| `_positionClock` | `Stopwatch` | `Stopwatch()..start()` | 单调时钟 | **解决弹幕时钟对时噪声**：记录采样到达时刻（单调时钟），用于把旧采样外推到“此刻”。 |
| `_lastPositionAt` | `Duration` | `Duration.zero` | 最近一次位置采样到达时的单调时钟偏移 | 记录采样到达时刻，供 `extrapolatedPosition` 计算经过的微秒数。 |
| `_lastDuration` | `Duration` | `Duration.zero` | 最近一次底层采样的视频总时长 | 用于防倒挂门禁判断，并节流合并进 `timeline`。 |
| `_lastBuffer` | `Duration` | `Duration.zero` | 最近一次底层采样的缓冲位置 | 用于节流合并进 `timeline` 供缓冲进度条渲染。 |
| `_firstFrameFallbackTimer`| `Timer?` | `null` | 首帧防闪遮罩硬上限超时定时器 | **解决死等遮罩**：硬上限超时兜底（8000ms），防止纯音频、无视频轨或尺寸事件缺失导致死等遮罩。 |
| `_hasReceivedVideoDimensionsSinceOpen` | `bool` | `false` | 本次 open 后是否已收到视频宽高尺寸事件 | **解决出画物理信号判定**：作为解码器真正出画（mpv 报出 video-params）的可靠物理信号。 |
| `_pendingStart` | `Duration` | `Duration.zero` | 目标断点续播时间戳 | 断点续播进度；底层 mpv 在媒体解析前若抛出 0 秒瞬态事件，依赖该字段做防抖拦截。 |
| `_disposed` | `bool` | `false` | 控制器生命周期销毁标记 | 防止异步微任务和底层流在组件销毁后继续改写已释放的 Notifier。 |
| `_currentUri` | `String?` | `null` | 当前正在播放的媒体直链 | 记录当前媒体资源标识。 |
| `_preMuteVolume` | `double` | `1.0` | 静音前的音量备份 | 取消静音时恢复原有音量，默认下限保证不低于 0.7（若原值极小）。 |
| `_isApplyingShader` | `bool` | `false` | 着色器注入执行中互斥锁 | **解决 mpv 渲染线程死锁**：串行互斥队列保护，避免连续点击触发多重并发指令导致 mpv 在 D3D/ANGLE 编译期死锁。 |
| `_pendingShaderMode` | `SuperResolutionMode?` | `null` | 队列中等待执行的最新着色器模式 | **解决请求竞争与过时**：执行期间到达的新请求自动合并为最新档位，串行处理最新请求。 |

---

### 1.2 定时器清单

| 定时器 | 时长 | 触发动作 | 退出 / 取消条件 | 解决的问题（以注释为准） |
| :--- | :--- | :--- | :--- | :--- |
| `_timelineThrottleTimer` | 250ms | 将 `_lastPosition`、`_lastDuration`、`_lastBuffer` 写入 `timeline.value` | 定时器自触发后自然结束；`dispose` 时手动 `.cancel()` | 节流更新时间线，杜绝高频刷新与动画卡顿。 |
| `_firstFrameFallbackTimer` | 8000ms (`kFirstFrameCoverMaxWait`) | 触发 `_checkFirstFrameRendered(force: true)`，强制解除遮罩与 loading | 1. 收到 `width > 0` 或 `height > 0` 正常出帧；<br>2. 底层上报致命错误 `_onErrorChanged`；<br>3. `open` 异常；<br>4. 控制器 `dispose` | 第三方外链与 CDN 在网络波动下拉流与解复用首片往往需要 2~5 秒，放宽至 8 秒兼顾纯音频等特殊流兜底与弱网首帧等待体验，防止死等遮罩假死。 |

---

### 1.3 过滤条件与特殊判断清单

| 所在方法 / 代码行 | 条件 / 判断语句 | 解决的问题（以注释为准） |
| :--- | :--- | :--- |
| `_configureNativeMpvProperties` (L148) | `setProperty('af', 'scaletempo2=max-speed=8')` | **倍速变调失真**：倍速播放（1.25x~3.0x）时自动修正音高，人声音质不失真。 |
| `_configureNativeMpvProperties` (L155-158) | `setProperty('stream-lavf-o', 'reconnect=1,reconnect_on_network_error=1,reconnect_delay_max=2')`，严禁 `reconnect_at_eof=1` 或 `reconnect_streamed=1` | **Seek 并发重连 TCP RST 卡死**：那些参数是专用于不可 Seek 的直播流的；在点播视频 Seek 时，旧 Range 结束会被误判为流异常触发重连，导致向对端发起并发连接并遭遇服务器 TCP RST (-0x4e)，进而引发卡死与流损坏。 |
| `_configureNativeMpvProperties` (L163) | `setProperty('cache-on-disk', 'no')` | **缓存子系统崩溃**：media_kit 默认写死 `cache-on-disk=yes`，但在 Windows/Android 平台上未配置缓存目录，会抛出 "Failed to create file cache" 导致缓存子系统损坏。显式关闭磁盘缓存，改用全内存缓冲。 |
| `_configureNativeMpvProperties` (L167) | `setProperty('demuxer-seekable-cache', 'yes')` | **已读区间重复请求**：开启 demuxer-seekable-cache，使用内存缓存实现已读区间的秒级拖拽/快进，避免重复发起 HTTP 请求。 |
| `_configureNativeMpvProperties` (L174-176) | `setProperty('force-seekable', 'yes')`<br>`setProperty('hr-seek', 'default')`<br>`setProperty('hr-seek-framedrop', 'yes')` | **关键帧对齐 8~10 秒误差**：若设为 no，底层 Seek 会强行对齐到前序关键帧（造成 8~10 秒误差，使自动跳过 OP/ED、断点续播严重偏离）；设为 default 配合 framedrop=yes 既能保证时间戳秒级精确命中，又能快速丢弃中间帧加速出图防卡死。 |
| `_configureNativeMpvProperties` (L182-185) | `setProperty('cache-pause-initial', 'no')`<br>`setProperty('cache-pause-wait', '0.2')` | **Seek 人为转圈 1~2 秒**：严禁设置 `cache-pause-initial=yes`！mpv 官方手册注明该选项在每次 Seek 拖动进度条后都会强制重新 pause 并进入 buffering 状态，死等缓冲水线人为制造 1~2 秒转圈。将其设为 no 配合 0.2 秒轻量防抖，起播与拖拽瞬间出帧。 |
| `_configureNativeMpvProperties` (L202) | `setProperty('tls-verify', 'no')` | **自签名/证书过期被拦截**：放行过期或未受信任的自签名证书。第三方聚合源/边缘 CDN 节点经常存在证书过期或自签名情况，关闭媒体流 TLS 校验可大幅提升外链播放成功率（仅作用于底层 mpv 音视频拉流）。 |
| `_configureNativeMpvProperties` (L207-213) | `if (Platform.isAndroid) { hwdec='auto-safe'; ao='opensles'; } else { hwdec='auto'; }` | **Android 底层芯片崩溃**：开启全格式硬解码；Android 下使用 `auto-safe` 防止部分低端芯片遇到非常规编码直接导致 Surface 崩溃。 |
| `_configureNativeMpvProperties` (L217-222) | `if (Platform.isWindows) { scale='spline36'; cscale='spline36'; sigmoid-upscaling='yes'; correct-downscaling='yes'; }` | **动漫线条锯齿与掉帧**：采用 Spline36 与 Sigmoid 插值，消除动漫色块边缘锯齿与光晕，计算量轻量杜绝掉帧。 |
| `_onNetworkMeteredChanged` (L230-252) | 动态监听网络计费状态并更新 `demuxer-max-bytes` (16MB vs 32MB) 与 `demuxer-max-back-bytes` (4MB vs 16MB) | **移动蜂窝流量偷跑 vs 宽带预读**：在线热更新 mpv 缓冲水线。Wi-Fi/有线保证平滑预读且不抢占 Seek 通道；蜂窝网络提供 1~2 分钟平滑防抖窗口同时防止点开即退时偷跑宝贵流量。 |
| `open` (L271-276) | `_lastPosition = Duration.zero;`<br>禁止设为 `_pendingStart` | **时间倒挂「04:26 / 00:00」**：目标断点续播进度由底层 mpv 通过 `Media(..., start: start)` 驱动定位；在底层解析出真实时长并上报有效播放位置前，时间轴必须保持 `Duration.zero`，杜绝在网络慢或直链失效时出现时间倒挂荒谬界面。 |
| `open` (L290-300) | `core.value = core.value.copyWith(loading: true, firstFrameRendered: false, ...)` | **切集残影闪烁**：切集或初次打开媒体流时，必须将 `firstFrameRendered` 立即置为 false 并保持 `loading: true`。在 UI 层激活纯黑防闪遮罩，彻底遮蔽底层 GPU Texture 中残留的上一集最后一帧画面。直到底层真正解码出首帧才解除遮罩。 |
| `seek` (L370-379) | `if (dur > const Duration(seconds: 1) && targetPosition >= dur) { targetPosition = dur - const Duration(milliseconds: 500); }` | **Seek 终点误判 EOF**：若目标时间戳非常接近或等于/超过视频总时长 (dur)，libmpv 会直接触发 `eof-reached` 将 `completed` 置为 true。因此在时长有效时，对 Seek 终点做 500ms 安全余量截断保护。 |
| `seek` (L388-394) | `if (core.value.hasError \|\| core.value.completed) { clearError: true, completed: false }` | Seek 时主动清除前序偶发错误与 completed 状态，确保平滑恢复与继续播放。 |
| `seek` (L398-402) | 直接调用 `player.seek(targetPosition)`，严禁 `pause() -> seek() -> play()` | **Packet corrupt 状态机紊乱**：直接委托底层 media_kit 原生 seek 处理，杜绝上层多余的异步交错。外层反复 pause/play 会破坏底层解复用线程与解码器缓冲区的状态机同步，诱发 Packet corrupt。 |
| `_applyShaderToPlayer` (L491-536) | 1. `_isApplyingShader` 串行互斥锁；<br>2. 3s/4s `.timeout()` 熔断保护；<br>3. `_pendingShaderMode` 合并最新请求 | **Direct3D 着色器编译挂起死锁**：避免用户快速连续点击档位时触发多重并发指令导致 mpv 渲染线程在 D3D/ANGLE 编译期死锁；防止 Direct3D 着色器编译挂起永久阻断 Dart 异步流；自动合并最新请求。 |
| `_onCompletedChanged` (L578-592) | `if (totalDur > 5s && currentPos < totalDur - 2s) { return; }` | **中途异常 EOF 误当播完并从头重播**：当底层网络断流或解码瞬态异常抛出 EOF code: 4 (ERROR) 时，media_kit 会将 eof-reached 误认为 completed = true。只有当当前播放位置真正接近视频总时长（剩余不足 2 秒）时，才确认为自然播放结束。严禁在中途非正常 EOF 时调用 player.play()，因为 EOF 态下调用 play() 会被 mpv 默认当做从 00:00 重播。 |
| `_onErrorChanged` (L609-617) | 包含 `0xdfb9b0bb` (AVERROR_EOF)、`ffurl_read returned`、`end of file`、`connection reset by peer` 时静默忽略 | **底层良性重连日志被误报为崩溃**：过滤底层网络断开/Seek重连/EOF良性日志，防止将正常的底层网络恢复行为误当成播放致命失败展示给用户。 |
| `_onPositionChanged` (L630-640) | `if (_pendingStart > Duration.zero) { if (pos + 1s < _pendingStart && _lastDuration == Duration.zero) return; _pendingStart = Duration.zero; }` | **起播 0 秒瞬态冲掉续播位置**：门禁规避起播瞬间 mpv 抛出的 0 秒瞬态事件提前冲掉 `_pendingStart`；仅当底层进度尚未接近断点目标且尚未获得有效时长（媒体还在解复用）时才过滤防抖；一旦获得有效时长或底层 Seek 完成，立即放行真实进度。 |
| `_onPositionChanged` (L642-645) | `if (core.value.hasError && pos > Duration.zero) { clearError: true }` | 当播放进度正常前进时，说明媒体解码通畅，自动抹除瞬态错误。 |
| `_onWidthChanged` / `_onHeightChanged` (L658-672) | `(width ?? 0) > 0 \|\| (height ?? 0) > 0` 置 `_hasReceivedVideoDimensionsSinceOpen = true` | 解码器真正出画（mpv 报出 video-params）的可靠物理信号。 |
| `_checkFirstFrameRendered` (L680-702) | 首帧出画后才注入 `_applyShaderToPlayer` | **无纹理盲目注入导致上下文假死**：首帧画面与纹理就绪后，再安全应用用户偏好配置的超分辨率滤镜；彻底规避在播放器未加载视频媒体时盲目注入着色器导致的 Direct3D/ANGLE 渲染上下文假死。 |
| `extrapolatedPosition` (L713-722) | `if (!state.playing \|\| state.buffering) return position; min(ageUs, 250000);` | **弹幕时钟对时抖动与越推越偏**：采样本身是旧值（事件延迟 + 250ms 节流定时器），直接拿来对时会给弹幕时钟注入噪声。暂停/缓冲中不外推；外推量设上限（250ms），防止事件长时间缺失时越推越偏。 |
| `dispose` (L757-771) | 先 `player.pause()`，再在 `unawaited` 后台异步微任务中执行 `stop()` 和 `dispose()` | **Pop 退出阻塞原生主线程卡死**：在页面 Pop 退出或销毁时，libmpv (media_kit) 若正处于网络缓冲或 demux 状态，同步等待 `player.stop()/dispose()` 会阻塞原生线程与 PlatformChannel 达数秒导致界面卡死。先立即触发非阻塞 pause，并将真正的 stop/dispose 脱钩至后台微任务中异步释放。 |

---

## 二、`video_play_page.dart` 现状盘点

文件路径：`lib/features/player/pages/video_play_page.dart`  
总代码行数：1900 行

### 2.1 状态相关字段清单

| 字段名 | 类型 | 初始值 / 默认值 | 作用描述 | 解决的问题（以注释为准） |
| :--- | :--- | :--- | :--- | :--- |
| `_playerSubtreeKey` | `GlobalKey` | `GlobalKey()` | 跨布局复用 Key | **全屏切换播放器卸载重建**：跨布局保活 Key，确保在全屏/桌面/移动端布局切换时复用同一 Element 节点，防止播放器和弹幕被卸载重建。 |
| `_isAppFullscreen` | `bool` | `false` | 应用内窗口全屏状态 | 控制宽屏/桌面端在应用窗口内铺满全屏。 |
| `_isTrueFullscreen` | `bool` | `false` | 系统原生真全屏状态 | 隐藏系统状态栏/进入沉浸式模式（Android）或原生全屏（桌面）。 |
| `_isSidePanelOpen` | `bool` | `false` | 全屏悬浮侧边栏展开状态 | 全屏看剧时，选集与换源无需打断播放或退出全屏。 |
| `_sidePanelInitialTab` | `PlayerSidePanelTab` | `.episodes` | 全屏侧边栏初始 Tab | 控制侧边栏呼出时默认展示选集还是视频源。 |
| `_activeEpisode` | `int?` | `widget.currentEpisode` | 当前选中的集数编号 (1-based) | 为 null 时表示页面处于未起播占位引导态。 |
| `_hasStartedPlayback` | `bool` | `false` | 是否已真正启动过播放 | **未起播态按键劫持与占位**：控制是渲染海报占位骨架还是渲染视频组件；未起播态下不劫持播放控制快捷键。 |
| `_playingRoadIndex` | `int?` | `null` | 实际处于在播态的线路索引 | **多线路在播态隔离**：线路 1 正在播放第 1 集时，用户切换查看线路 2 不会把线路 2 的第 1 集误标为正在播放。 |
| `_playingSourceId` | `String?` | `null` | 实际处于在播态的视频源 ID | 配合 `_playingRoadIndex` 实现跨源与跨线路播放高亮隔离。 |
| `_isLoadingAuthorityDetails`| `bool` | `true` | Bangumi 官方权威详情加载态 | 控制番剧名、封面、标签骨架屏显隐。 |
| `_selectedSourceId` | `String` | `'xifan-next'` | 当前选中的视频源标识 | 当前选集列表所依赖的源（默认稀饭Next）。 |
| `_sources` | `List<VideoSourceItem>`| `getDefaultSourceItems()` | 可选视频源列表 | 提供视频源看板与换源列表。 |
| `_isLoadingChapters` | `bool` | `false` | 分集列表网络加载态 | **虚假集数防提前暴露**：分集正在加载时展示骨架与提示，绝不提前暴露虚假上千集卡片与分页胶囊。 |
| `_resolveError` | `String?` | `null` | 媒体直链解析或分集错误文本 | 在播放器中央或选集区展示清洗后的错误卡片。 |
| `_sourceNotice` | `String?` | `null` | 视频源调度提示文案 | 提示默认源未收录或自动切换备用源的通知。 |
| `_hudToast` | `String?` | `null` | 播放画面浮动 HUD 提示文本 | 快捷键操作（音量、倍速、切集、全屏）时的即时视觉反馈。 |
| `_hudToastTimer` | `Timer?` | `null` | HUD 提示自动消失定时器 | 默认 2200ms 后自动清空 `_hudToast`。 |
| `_defaultSearchEmpty` | `bool` | `false` | 默认源精准检索是否落空 | 标记默认源未收录，驱动后台静默并发探测保底源。 |
| `_chapterRoads` | `List<SourceChapterRoad>`| `[]` | 当前源解析到的分集线路列表 | 承载多线路与集数列表。 |
| `_selectedRoadIndex` | `int` | `0` | 当前查看的分集线路索引 | 切换线路仅更新查看视图与集数列表，绝不自动切换起播。 |
| `_currentPlayingPageUrl` | `String?` | `null` | 当前在播剧集的网页 URL | 用于历史记录落盘的精确页面回溯定位。 |
| `_playSecAccumulated` | `double` | `0.0` | 自然有效播放累积时长（秒） | **防刷有效播放 (Anti-Bounce)**：对齐 animaku 规范，严格累加自然递增时间，满 15 秒才首次落盘。 |
| `_isValidPlayReported` | `bool` | `false` | 15 秒有效播放是否已上报 | 标记该集已达到有效观看门槛，后续转入 10 秒周期节流同步。 |
| `_lastPlayTick` | `double` | `0.0` | 上一次时间线 tick 的播放时间戳 | 用于计算相邻 tick 的增量 delta。 |
| `_lastSaveTimeMs` | `int` | `0` | 上一次历史落盘的系统时间戳 (ms) | 达到 15 秒有效播放后，每 10 秒周期性节流同步最新进度。 |
| `_fullBangumiItem` | `BangumiItem?` | `null` | Bangumi API 返回的权威详情 | 补充番剧中文名、标签、演职员信息。 |
| `_officialEpisodes` | `List<BangumiEpisode>?`| `null` | Bangumi 官方分集列表 | 用于 `PlayableSlotEngine` 双层对齐，过滤 PV/SP/特典。 |
| `_opedData` | `Map<int, EpisodeOpedSegment>`| `{}` | 本剧各集 OP/ED 时间段映射表 | 驱动进度条彩色标记与自动跳过片头片尾。 |
| `_autoPlayNextNotifier` | `ValueNotifier<bool>` | 读本地配置 | 是否自动播放下一集设置项 | 监听与更新用户连播偏好。 |
| `_lastPlaybackCompleted` | `bool` | `false` | 上一次监听到的 completed 状态 | 边沿触发检测，防止单次完播重复触发连播。 |

---

### 2.2 定时器清单

| 定时器 | 时长 | 触发动作 | 退出 / 取消条件 | 解决的问题（以注释为准） |
| :--- | :--- | :--- | :--- | :--- |
| `_hudToastTimer` | 2200ms | 清空 `_hudToast` 隐藏提示浮层 | 再次触发 HUD 时重置；页面 `dispose` 时 `.cancel()` | 保证屏幕快捷提示轻量展现并自动退场，不长期遮挡画面。 |

---

### 2.3 过滤条件与特殊判断清单

| 所在方法 / 代码行 | 条件 / 判断语句 | 解决的问题（以注释为准） |
| :--- | :--- | :--- |
| `initState` (L317-350) | `WidgetsBinding.instance.addPostFrameCallback`<br>配合 `ModalRoute.of(context).animation.isCompleted` | **路由推入动画第一下掉帧卡顿**：等待路由平滑推入动画（约 350ms）定格完成后，再启动重度视频源网络检索与起播，保证跳转全程享有 100% 独立主线程算力，彻底消除页面跳转时的第一下掉帧卡顿。 |
| `_resolveInitialResumePosition` (L398-419) | `if ((d > 30 && (p >= d - 15 \|\| p / d >= 0.95)) \|\| p < 15) return null;` | **片尾死循环连播切走陷阱**：对齐 animaku usePlaybackResume 规范，若目标续播进度已处于视频终点附近（>= 95% 或距离末尾不足 15s），判定为该集已完整看毕，强制重置为 0 从头开播，彻底杜绝“重新点开已看剧集立刻触发片尾/被连播切走”的死循环陷阱；若记录进度不足 15s 同样从 0 开播，避免 1~2 秒偶发抖动。 |
| `_saveProgressOnExit` (L472-479) | `if (t > 0 && (_isValidPlayReported \|\| (d > 30 && t / d >= 0.85)))` | **秒退产生 0 秒垃圾历史记录**：严禁任何起播秒退都无脑写入历史记录！仅当达到 15 秒有效播放门槛或进度已达到 85% 完播兜底门槛时才执行保存，杜绝用户仅进入页面挑源 1~2 秒就退出时在历史列表中产生大量 0 秒垃圾记录。 |
| `_onPlaybackTimelineChanged` (L489-510) | `isPlaying = core.playing && !core.buffering && !core.loading && core.firstFrameRendered;`<br>`if (tickDelta > 0 && tickDelta <= 2.5)` 累加 | **拖拽/快进误算有效播放**：严禁在拖拽或非正常时间跳变时累加；仅自然递增 0 < tickDelta <= 2.5s 时累加；满 15 秒正式标记已看并首次落盘。 |
| `_onPlaybackTimelineChanged` (L514-517) | `if (_effectiveBangumiId > 0 && d > 30 && t / d >= 0.85)` | **完播兜底标记**：单集播放接近末尾（d > 30 且 t / d >= 0.85）自动记录已看（纯客户端标记）。 |
| `_onPlaybackTimelineChanged` (L520-523) | `if (_isValidPlayReported && now - _lastSaveTimeMs >= 10000)` | **高频 IO 阻塞**：达到有效播放门槛（满 15s）后，每 10s 节流同步一次最新进度至本地存储。 |
| `_startDefaultSourceSearch` (L637-661) | Step 1 检查 `SourceBindingService.getBinding`<br>捕获异常则 `removeBinding` | **0ms 历史直开与失效降级**：优先命中该源历史绑定，直接取 sourceUrl 提取分集跳过搜索；若源站下架/URL变更抛出异常，自动清除失效绑定并平滑降级至关键词搜索。 |
| `_startDefaultSourceSearch` (L666-700) | Step 2 单关键词精准检索匹配度 `score >= 0.55` | **剧名不一致误绑**：打分 >= 0.55 且无季数冲突才自动采用，低于门槛则不乱绑定。 |
| `_startDefaultSourceSearch` (L733-751) | Step 3 默认源未收录触发后台保底探测 | **主源失效时播放阻断**：前 6 个源，3 并发，5s 超时熔断，由 `AutoSourcePickCoordinator` 仲裁 1200ms 宽限切换。 |
| `_handleSourceSelected` (L767) | `_autoPicker.onUserAction();` | **用户手动选择与自动选源打架**：用户一旦手动点击源或集数，即时互斥锁死自动仲裁器，防止仲裁器事后切走用户选好的源。 |
| `_handleSourceSelected` (L770-804) | `if (cachedRoads != null && cachedRoads.isNotEmpty)` 直接采纳 | **切源重复检索并报错**：0ms 秒级直开，若探测器中已预先验活并缓存了分集线路，直接采纳，彻底杜绝“切过去又开始检索然后报错”。 |
| `_handleSourceSelected` (L1736-1739, L1785-1788) | `onRoadSelected: (idx) { setState(() => _selectedRoadIndex = idx); }` | **切线路打断当前播放**：切换线路仅更新查看视图与集数列表，绝不自动切换起播，保持当前正在播放的线路和集数不被打断。 |
| `_selectSlot` / `_selectEpisode` (L988-992, L1073-1076) | `runtime.resolve(_selectedSourceId, nextSlot.pageUrl).ignore();` | **下一集起播加载迟滞**：当前集起播成功后，后台静默预热下一集播放直链。 |
| `_onPlaybackCoreStateChanged` (L1089-1096) | `if (!core.playing && _isValidPlayReported) { _saveCurrentProgress(t, d); }` | 用户暂停播放时，若已满足 15 秒有效播放，即时同步保存进度。 |
| `_onPlaybackCoreStateChanged` (L1098-1120) | `if (isCompleted != _lastPlaybackCompleted)` 且为 true | **完播重复连播**：边沿检测，仅在由 false 变 true 的瞬间标记已看、保存进度为 100%、并在开启连播时自动无缝起播下一集。 |
| `_handleBackPressed` (L1256-1262) | 1. 进度统一由 dispose 落盘，返回键不重复写；<br>2. 仅调用 `muteForExit()` 禁音底层，禁止 `setVolume(0.0)` | **退场动画残音与音量偏好被覆盖**：不能用 setVolume(0.0)，它会把 0 写进用户音量偏好导致下次起播被静音；返回键不重复写历史避免点击返回瞬间多触发一次落盘导致首页在退场动画中重建。 |
| `build` Focus onKeyEvent (L1287-1302) | 1. `event is KeyDownEvent \|\| KeyRepeatEvent`<br>2. `primaryWidget is! EditableText`<br>3. `_hasStartedPlayback == true` 门禁 | **桌面端快捷键焦点冒泡失灵**：Flutter 的 KeyEvent 是从当前焦点节点沿父链单向冒泡。用户点击右侧选集网格或空白处时，主焦点离开播放器导致所有媒体快捷键失灵。只要用户未在输入框打字且已起播，一律全局兜底路由至控制器。 |

---

### 2.4 注释不清楚或未记录原因的字段与逻辑（如实登记为“未知”）

依据项目规范，未在注释中详细记录“为什么必须这样处理”的项如下：
1. `video_play_page.dart` 中 `_selectedSourceId` 为何写死默认初始值为 `'xifan-next'`：代码注释说明其为“官方推荐主线”，但若用户本地安装有自选主源时为何没有读取用户偏好作为初始默认值？—— **原因未知**（待重构时评估是否支持偏好持久化）。
2. `video_play_page.dart` 中 `_sources` 的初始化直接调用 `getDefaultSourceItems()`，后续未见动态更新插件源列表的侦听 —— **原因未知**。
3. `playback_controller.dart` 中 `_positionClock` 上限为何固定截断在 `250000` 微秒（250ms）：注释说明了外推量设上限防止越推越偏，但上限选取 250ms 是否是直接与 `_timelineThrottleTimer` 周期 1:1 对齐？—— **注释未明确数学推导，待验证**。
