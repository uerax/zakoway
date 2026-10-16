# 播放控制层重写：阶段 0 设计文档（3/7）—— 状态机与生命周期设计（v2）

## 本版相对 v1 的变更
1. **新增 `recovering` 状态**：包含触发原因（`RecoveryReason`）、重试计数（`retryCount`）及退避定时器（`backoffTimer`）；补全全阶段失败迁移至 `recovering` 并安全自愈或超预算转 `error` 的流转逻辑。
2. **细化缓冲状态**：将原本笼统的 `buffering` 严格拆分为 `prebuffering`（首帧渲染前的初始建联缓冲）与 `rebuffering`（正常播放中途遭遇弱网卡顿的缓冲）。
3. **收紧首帧超时兜底条件**：`FIRST_FRAME_TIMEOUT` (8s) 绝不无条件盲目放行，必须以“位置有推进（`pos > startPos`）或音频时钟在播”为有效证据才放行；无证据判定为连接假死，触发失败迁移至 `recovering`。明确定义纯音频媒体识别条件。
4. **重构首帧契约**：彻底删除恒真的 `position >= Duration.zero`，换为可被单测与运行时证伪的硬核物理条件。
5. **澄清 Attempt ID 适用边界**：明确其作用范围仅限 Dart 侧异步控制流续接；原生层媒体事件通过新增的“`openToken`（原生 open 分界与 URL 归因）”机制进行硬件级事件隔离。
6. **标明待验证项**：将 `BACKEND_MEDIA_OPENED` 的真实来源（`player.open()` Future 的完成时机与语义）明确标为“待验证”，并给出确定的日志探针验证方案。
7. **统一 Session 生命周期模型**：确立“每次 `open()` 创建全新的 `PlaybackSession` 独立实例”模型，与 05 接口文档保持完全一致。

---

## 一、状态机全貌设计（FSM v2）

```
                     ┌────────────────────────────────────────────────────────┐
                     │                                                        │
                     ▼                                                        │
                ┌─────────┐   LOAD_REQUEST (实例化新 Session + 生成 AttemptId) │
                │  idle   ├───────────────────────────────────┐               │
                └────┬────┘                                   │               │
                     ▲                                        ▼               │
                     │                                 ┌─────────────┐        │
                     │                                 │  resolving  │        │
                     │                                 └──────┬──────┘        │
                     │                      RESOLVE_SUCCESS   │               │
                     │                                        ▼               │
                     │                                 ┌─────────────┐        │
                     │               BACKEND_DISPATCHED│  preparing  │        │
                     │               (open Future 完成)└──────┬──────┘        │
                     │                                        ▼               │
                     │                                 ┌──────────────┐       │
                     │          FIRST_FRAME_SIGNAL     │ prebuffering │       │
                     │         (或有证据的超时兜底)      └──────┬───────┘       │
                     │                                        │               │
                     │                                        ▼               │
                     │       PAUSE_REQUEST             ┌──────────────┐       │
                     ├─────────────────────────────────┤   playing    │       │
                     │                                 └──┬───┬───┬───┘       │
                     │                   PLAY_REQUEST     │   │   │           │
                     │             ┌──────────────────────┘   │   │           │
                     │             ▼                          │   │           │
                     │       ┌───────────┐                    │   │           │
                     │       │  paused   │                    │   │           │
                     │       └─────┬─────┘                    │   │           │
                     │             │                          │   │           │
                     │             │             SEEK_REQUEST │   │           │
                     │             │         ┌────────────────┘   │           │
                     │             ▼         ▼                    │           │
                     │       ┌───────────┐ ┌───────────┐          │           │
                     │       │  seeking  │ │rebuffering│◄─────────┘           │
                     │       └─────┬─────┘ └─────┬─────┘ 卡顿触发             │
                     │             │             │                            │
                     │             └──────┬──────┘                            │
                     │                    │                                   │
                     │                    ▼ NATURAL_COMPLETION                │
                     │             ┌───────────┐                              │
                     │             │ completed │                              │
                     │             └─────┬─────┘                              │
                     │                   │                                    │
                     │   可恢复错误       ▼ 致命错误 / 重试预算耗尽             │
                     │ ┌───────────┐   ┌───────────┐                          │
                     │ │recovering │──►│   error   │                          │
                     │ └─────┬─────┘   └─────┬─────┘                          │
                     │       │               │                                │
                     │       └───────────────┴────────────────────────────────┤
                     │                                                        │
                     └────────────────────────────────────────────────────────┘
                                          DISPOSE_REQUEST
                                                 │
                                                 ▼
                                          ┌─────────────┐
                                          │  disposed   │
                                          └─────────────┘
```

---

## 二、状态集合（PlaybackState）

状态机在任意瞬时**必须且只能**处于以下 11 个互斥状态之一：

| 状态枚举（`PlaybackState`） | 语义描述 | 核心标志映射 (`loading` / `playing` / `buffering` / `completed`) |
| :--- | :--- | :--- |
| `idle` | 初始空闲态；无活跃媒体会话。 | `loading: false, playing: false, buffering: false, completed: false, firstFrameRendered: false` |
| `resolving` | 正在通过 `SourceResolver` 解析分集直链与鉴权头。 | `loading: true, playing: false, buffering: false, completed: false, firstFrameRendered: false` |
| `preparing` | 直链就绪，已向底层 Player 发送 open 指令，等待底层完成资源分配与解复用启动。 | `loading: true, playing: false, buffering: false, completed: false, firstFrameRendered: false` |
| `prebuffering` | **首帧前初始缓冲态**：底层已开始建立流连接，正在拉取首批切片，黑屏遮罩保持覆盖，等待首帧信号。 | `loading: false, playing: false, buffering: true, completed: false, firstFrameRendered: false` |
| `playing` | **正常播放中**：首帧画面已渲染出画，时钟推进正常。 | `loading: false, playing: true, buffering: false, completed: false, firstFrameRendered: true` |
| `paused` | 暂停态：画面定格在当前帧。 | `loading: false, playing: false, buffering: false, completed: false, firstFrameRendered: true` |
| `seeking` | 寻道态：已向底层发起 seek，等待底层重定位出新帧。 | `loading: false, playing: (保持前态), buffering: true, completed: false, firstFrameRendered: true` |
| `rebuffering` | **中途卡顿缓冲态**：首帧已出画，播放中途因网络波动导致解复用缓冲区水位过低。画面保留，仅中央转圈。 | `loading: false, playing: false, buffering: true, completed: false, firstFrameRendered: true` |
| `recovering` | **自动恢复态**：发生可恢复异常（403 鉴权过期、TCP 瞬断、中途假 EOF），正在退避等待重试或重新解析直链。 | `loading: true, playing: false, buffering: false, completed: false, firstFrameRendered: (视原阶段保持)` |
| `completed` | 自然播放完毕：播放进度接近总时长且收到自然 EOF。 | `loading: false, playing: false, buffering: false, completed: true, firstFrameRendered: true` |
| `error` | 致命错误态：错误不可自动恢复，或重试总预算耗尽，等待用户交互干预。 | `loading: false, playing: false, buffering: false, completed: false, hasError: true` |
| `disposed` | 终态：会话彻底销毁，拒绝响应除状态查询外的任何事件。 | 全部标志归零，资源解绑。 |

---

## 三、`recovering` 状态的内部结构与运转机制

当播放器在 `preparing`、`prebuffering`、`playing` 或 `rebuffering` 阶段遭遇可恢复的异常时，状态机**绝不直接向用户展示红色报错**，而是立即切入 `recovering` 状态：

```dart
class RecoveryContext {
  RecoveryContext({
    required this.reason,
    required this.targetPhase,
    required this.attemptCount,
    required this.maxAttempts,
    required this.backoffDelay,
    this.resumePosition,
  });

  final RecoveryReason reason;        // 触发恢复的原因
  final PlaybackState targetPhase;     // 恢复成功后期望回到的阶段
  final int attemptCount;              // 当前已是第 n 次重试 (1-based)
  final int maxAttempts;               // 最大允许重试次数
  final Duration backoffDelay;         // 本次退避延迟时长
  final Duration? resumePosition;      // 恢复时需要对齐的进度断点
}

enum RecoveryReason {
  tokenExpired403,         // 直链防盗链过期 (HTTP 403)
  handshakeReset,          // TLS/TCP 握手阶段被对端强制 Reset (-0x4e)
  networkTimeout,          // 网络拉流超时
  abnormalEofInterruption, // 播放中途因断流抛出的假 EOF
  firstFrameStall,         // 8秒超时且无推进证据的建联假死
}
```

### 3.1 退出条件
1. **成功自愈**：退避定时器触发后重新发起操作成功，无缝回到 `targetPhase`；
2. **预算耗尽**：`attemptCount >= maxAttempts` 或耗时超过全局阶段预算，迁移至 `error`；
3. **用户中止**：在退避等待中用户发起切集（`LOAD_REQUEST`）或退出页面（`DISPOSE_REQUEST`）。

---

## 四、确定性状态迁移表（Transition Table v2）

> 门禁准则：所有带 `attemptId` 或 `openToken` 的底层事件，若与当前会话不一致，**一律静默丢弃**。

| 当前状态 | 触发事件 / 条件 | 目标状态 | 伴随动作 / 副作用（Actions） |
| :--- | :--- | :--- | :--- |
| **任意状态** | `LOAD_REQUEST(ep, src, start, autoplay)` | `resolving` | 创建全新 `PlaybackSession` 实例，分配新 `attemptId`；取消旧定时器；清空错误；覆盖黑屏遮罩；启动直链解析。 |
| `resolving` | `RESOLVE_SUCCESS(url, headers)` | `preparing` | 生成新 `openToken`；向后端派发 `backend.open(url, headers, start)`；启动 preparing 阶段超时防护。 |
| `resolving` | `RESOLVE_FAILURE(err)` (可恢复) | `recovering` | 启动退避定时器，记录 `reason=networkTimeout`，重试直链解析。 |
| `resolving` | `RESOLVE_FAILURE(err)` (不可恢复/预算尽) | `error` | 清洗错误文本，呈现错误卡片。 |
| `preparing` | `BACKEND_DISPATCHED` (open Future 完成) | `prebuffering` | 开启 8000ms 首帧兜底定时器；保持黑屏防闪遮罩；等待底层数据出画。 |
| `preparing` | `BACKEND_FATAL_ERROR` (如握手失败/403) | `recovering` | 驱逐 L1 缓存，`bypassCache=true` 准备重新获取直链重试；若超预算则转 `error`。 |
| `prebuffering`| `FIRST_FRAME_SIGNAL` (物理出画) | `playing` (若 autoplay) / `paused` | 撤去黑屏遮罩与 loading；取消首帧定时器；安全注入 Anime4K 着色器；通知时间线。 |
| `prebuffering`| `FIRST_FRAME_TIMEOUT` (有推进证据) | `playing` (若 autoplay) / `paused` | 判定为纯音频或尺寸事件缺失，记录降级日志，强制撤去遮罩归还控制权。 |
| `prebuffering`| `FIRST_FRAME_TIMEOUT` (无推进证据) | `recovering` | 判定为连接僵死，记录 `reason=firstFrameStall`，销毁当前底层连接并退避重连。 |
| `prebuffering`| `BACKEND_FATAL_ERROR` (网络中断) | `recovering` | 进入退避恢复，记录重试计数。 |
| `playing` | `PAUSE_REQUEST` | `paused` | 调用 `backend.pause()`；触发当前播放进度同步落盘。 |
| `playing` | `BUFFERING_STATE_CHANGED(true)` | `rebuffering` | 仅激活画面中央缓冲转圈（**严禁重新遮蔽画面**）；记录卡顿起始时刻。 |
| `playing` | `SEEK_REQUEST(pos)` | `seeking` | 检查 500ms 终点截断保护；调用原生 `backend.seek(pos)`。 |
| `playing` | `NATURAL_COMPLETION_SIGNAL` | `completed` | 校验 `pos >= dur - 2s`；进度标记 100%；触发已看落盘；若开启连播启动定时连播调度。 |
| `playing` | `ABNORMAL_EOF_SIGNAL` (中途假 EOF) | `recovering` | 拦截错误；记录当前已播进度 `pos`；进入 `recovering` 准备从 `pos` 断点续接。 |
| `paused` | `PLAY_REQUEST` | `playing` | 幂等恢复：调用 `backend.play()`。 |
| `paused` | `SEEK_REQUEST(pos)` | `seeking` | 检查 500ms 截断保护；调用 `backend.seek(pos)`。 |
| `seeking` | `SEEK_ACKNOWLEDGED` / `POSITION_ADVANCED` | `playing` / `paused` (恢复前态) | 寻道完成出新帧，清除 seeking 标志，恢复对应基态。 |
| `seeking` | `SEEK_TIMEOUT (5s)` | `playing` / `paused` | 寻道防死锁熔断：解除 seeking 标志，尝试重新定位或恢复播放。 |
| `rebuffering` | `BUFFERING_STATE_CHANGED(false)` | `playing` | 缓冲水线恢复，隐藏转圈，恢复正常播放。 |
| `rebuffering` | `REBUFFERING_TIMEOUT (15s)` | `recovering` | 判定当前 CDN 节点卡死，触发重连或降级换源。 |
| `recovering` | `RECOVERY_TIMER_TICK` (准备重试) | `resolving` / `preparing` | 根据 `reason` 重新执行刷新直链或重新建联 open。 |
| `recovering` | `RECOVERY_BUDGET_EXHAUSTED` | `error` | 重试次数达上限或总时限耗尽，彻底转入 `error` 提示用户。 |
| `completed` | `PLAY_REQUEST` / `SEEK_REQUEST(0)` | `seeking` -> `playing` | 从 `00:00` 重新起播当前视频。 |
| `error` | `RETRY_REQUEST` | `resolving` | 用户手动点击【重试】，清空错误状态，全新尝试起播。 |
| **任意状态** | `DISPOSE_REQUEST` | `disposed` | 立即静音；取消所有定时器（含退避定时器）；在后台微任务异步 dispose 底层 player。 |

---

## 五、首帧信号的唯一定义与可证伪条件

### 5.1 契约原则
彻底剔除 v1 中无意义的 `position >= Duration.zero`（在无符号或归零初始态下恒为 true，无法证明底层真正渲染出帧）。

### 5.2 唯一定义公式
首帧信号确立必须**满足且仅满足以下两个互斥途径之一**：

#### 途径一：主途径【物理出画信号 (Physical Frame Rendered)】
必须同时满足以下 **3 个可证伪物理条件**：
1. **尺寸条件**：`width != null && width > 0 && height != null && height > 0`（mpv 报出有效 `video-params`）；
2. **位置条件（可证伪位移）**：
   * 若为 0 秒起播：底层上报的 `position > Duration.zero`，或收到首次 `frame-rendered` 原生回调；
   * 若为断点续播（`startPos > 0`）：底层上报的 `position >= startPos - 1s` 且 `duration > Duration.zero`；
3. **分界归因**：事件携带的 `openToken == currentOpenToken`。

#### 途径二：兜底途径【有证据的超时降级 (Timeout with Liveness Proof)】
自底层 `open` 指令派发并完成起播建联起，若等待达到 `kFirstFrameCoverMaxWait` (8000ms)：
* **放行硬性证据门禁**：
  必须检测到底层具备下列**有效生存证据之一**：
  1. **时间戳在真实推进**：`currentPosition > initialPosition` 且持续递增；
  2. **确认为纯音频媒体**：底层已明确识别无视频流轨（`hasVideoTrack == false` 或 `track.type == audio` 且 `duration > Duration.zero`）；
  3. **音频时钟在走**：收到音频硬件缓冲正常消耗信号。
* **无证据处理**：
  若满 8000ms 时底层既无画面尺寸，时间戳又纹丝不动（`position == 0` 且无音频时钟），**绝对禁止盲目解除遮罩**！这代表网络连接已死锁或 CDN 握手假死，必须立即判定首帧建立失败，触发 `FIRST_FRAME_TIMEOUT (无证据)` 事件迁移至 `recovering` 实施重连。

---

## 六、Attempt ID 作用范围与原生 `openToken` 分界机制

### 6.1 澄清：Attempt ID 的真实作用范围
必须诚实面对系统现实：
* **Attempt ID 仅在 Dart 异步调度流中有效**：它完美管理 `Future`、`Timer`、`async/await` 微任务与 Stream 闭包的异步续接；
* **原生 C 语言线程并不感知 Dart Attempt ID**：底层 libmpv 的 C 线程是单例或长生命周期对象，其产生的原生事件（`mpv_event`）通过 PlatformChannel 或 FFI 持续向 Dart 管道喷吐，本身不带业务 Attempt ID。

### 6.2 方案：原生事件的 `openToken` 分界与 URL 归因
为解决“切集后上一集的底层尺寸/错误事件串扰下一集”问题，在 Dart 适配层（`PlayerBackend`）建立物理分界：

1. **单调自增的 `openToken`**：
   适配层内部维护 `int _openTokenCounter = 0`。每次调用 `backend.open(url)`，计数递增：
   ```dart
   final currentToken = ++_openTokenCounter;
   ```
2. **底层事件出口清洗**：
   适配层对 media_kit 原始流进行包装，将每个底层事件打上当时的 `openToken`：
   ```dart
   // 伪代码示范
   _rawPlayer.stream.width.listen((w) {
     if (currentToken == _openTokenCounter) {
       _dimensionsStreamController.add(VideoDimensions(w, _rawHeight, currentToken));
     }
   });
   ```
3. **URL 归因校验**：
   对于原生上报的错误日志（如 `Failed to open https://...`），先剥离提取其中的 URL；若报错中的 URL 不等于当前 Session 正在请求的媒体 URL，直接判定为旧连接的迟到垃圾日志，坚决丢弃。

---

## 七、待验证技术项与验证方案

### 待验证项：`player.open()` Future 的确切完成时机
* **问题描述**：在 media_kit 中，`await player.open(Media(url))` 返回的 Future 究竟是在向底层 libmpv 派发 `loadfile` 指令后立即完成，还是在底层 HTTP 握手建立并解析出流信息后才完成？
* **潜在风险**：若 `open()` 是立即完成，则 `preparing` 状态几乎瞬态闪过，网络建连期实际上处于 `prebuffering`；若 `open()` 是握手完才完成，则网络超时可能直接由 `open()` 的 Future 抛出而非来自 `stream.error`。
* **验证方案（阶段 1 前置执行）**：
  在应用临时接入探针代码，观察日志时间戳与事件先后顺序：
  ```dart
  debugPrint('[Probe] 1. 调用 player.open 前: ${DateTime.now()}');
  final future = player.open(Media(testUrl));
  future.then((_) => debugPrint('[Probe] 2. player.open Future 完成: ${DateTime.now()}'));
  player.stream.buffering.listen((b) => debugPrint('[Probe] 缓冲流变动: $b at ${DateTime.now()}'));
  player.stream.width.listen((w) => debugPrint('[Probe] 尺寸流变动: $w at ${DateTime.now()}'));
  player.stream.error.listen((e) => debugPrint('[Probe] 错误流捕获: $e at ${DateTime.now()}'));
  ```
  通过分析上述输出，即可在阶段 1 编码时彻底锁定 `preparing` 与 `prebuffering` 的精准边界。
