# 播放控制层重写：阶段 0 设计文档（6/7）—— 验收场景清单与测试矩阵（v2）

## 本版相对 v1 的变更
1. **修正 TC-05（首帧超时兜底）时序**：严格区分“有推进/有音频证据”放行出画 vs “无推进证据”判定为假死进入 `recovering` 并尝试重连。
2. **修正 TC-10（中途非正常 EOF）时序**：细化从拦截假 EOF、记录中断进度 `pos`、进入 `recovering` 到重新带 `start: pos` 续接起播的自愈全链路。
3. **修正 TC-11（HTTP 403 鉴权过期）时序**：明确仅驱逐 L1 直链缓存，保留 `SourceBinding` 番剧持久绑定，验证无感刷新直链并恢复播放。
4. **新增 7 大关键边界验收场景**：
   * **TC-15**：初次连接失败后重试成功（`prebuffering` -> `recovering` -> `playing`）；
   * **TC-16**：初次连接失败后重试耗尽（`recovering (2次)` -> `error` 报错呈现）；
   * **TC-17**：中途 EOF 断点恢复（记录精准秒数断点重连）；
   * **TC-18**：`resolving` 阶段快速返回（异步 Future 取消与防泄露）；
   * **TC-19**：恢复重试期间 dispose（退避定时器取消与资源销毁）；
   * **TC-20**：合法慢起播不被误判（弱网 4~6 秒前置拉流正常出画）；
   * **TC-21**：迟到原生事件隔离（`openToken` 物理阻断跨集串扰）。

---

## 一、验收场景总览矩阵（v2）

| 场景编号 | 场景名称 | 期望的状态流转序列 | 现有测试覆盖状态 | 需新增/补齐的测试用例 |
| :---: | :--- | :--- | :--- | :--- |
| **TC-01** | 正常单集冷启动起播 | `idle` -> `resolving` -> `preparing` -> `prebuffering` -> `playing` | 部分覆盖：`playback_controller_test` 校验了初始字段 | **需新增**：完整状态机迁移端到端序列测试 |
| **TC-02** | 历史断点续播 (中段有效位置) | `idle` -> `resolving` -> `preparing` -> `prebuffering` -> `seeking` -> `playing` | 部分覆盖：`playback_controller_test` 校验了 `open(start: ...)` | **需新增**：续播时间戳对齐与 `_pendingStart` 瞬态防抖校验 |
| **TC-03** | 接近片尾历史断点重置为从头起播 | `idle` -> `resolving` -> `preparing` -> `prebuffering` -> `playing` (位置归零) | 现有逻辑代码已覆盖；未见独立单元测试 | **需新增**：`_resolveInitialResumePosition` 针对 `>= 95%` 的重置测试 |
| **TC-04** | 首帧物理出画与防闪遮罩撤除 | `prebuffering(遮罩开)` -> `FIRST_FRAME_SIGNAL` -> `playing(遮罩撤除)` | 已覆盖：`playback_controller_test: 首帧渲染状态流转测试` | **需补齐**：模拟原生 video-params 尺寸到达与遮罩 0 延迟移除断言 |
| **TC-05** | 首帧超时判定（区分证据放行与重连）| **有证据**：`prebuffering` -> `playing`；<br>**无证据**：`prebuffering` -> `recovering` -> 重连 | 未覆盖 | **需新增**：`FakeAsync` 下模拟有/无推进证据的 8000ms 超时分支测试 |
| **TC-06** | 进度条实时拖拽预览与松手 Seek | `playing` -> `previewPosition 更新` -> `seeking` -> `playing` | 已覆盖：`playback_controller_test: 拖拽 Seek 预览状态流转测试` | 现有测试绿灯保持 |
| **TC-07** | Seek 接近视频末尾 500ms 截断保护 | `playing` -> `seek(dur)` -> 截断为 `dur - 500ms` -> `seeking` -> `playing` | 已覆盖：`playback_controller_test: Seek 越界边界保护截断测试` | 现有测试绿灯保持 |
| **TC-08** | 播放中途网络断流缓冲与自愈 | `playing` -> `rebuffering(画面保留，居中转圈)` -> `playing` | 部分覆盖：覆盖了 `buffering` 字段拷贝 | **需新增**：中途卡顿不重新激活纯黑遮罩的断言 |
| **TC-09** | 自然完播与自动下一集连播 | `playing` -> `NATURAL_COMPLETION` -> `completed` -> HUD Toast -> `LOAD_REQUEST(ep+1)` | 部分覆盖：`player_controls_overflow_and_autoplay_test` | **需新增**：完播到下一集起播的完整状态流转与 Attempt ID 自增测试 |
| **TC-10** | 中途非正常 EOF 信号拦截与断点恢复 | `playing` -> 异常 EOF 拦截 -> 记录 pos -> `recovering` -> `preparing(start: pos)` -> `playing` | 未覆盖 | **需新增**：模拟 `currentPos < dur - 2s` 拦截假 EOF 并断点自愈测试 |
| **TC-11** | HTTP 403 鉴权过期刷新重试（保留绑定）| `prebuffering` -> 403 -> 驱逐 L1 -> `bypassCache` 重新 resolve -> `preparing` -> `playing` | 部分覆盖：`resolve_cache_policy_test` 覆盖了 `bypassCache` | **需新增**：403 自动刷新重试且断言 `SourceBinding` 未被删除 |
| **TC-12** | 连续快速切集（Attempt ID 竞态隔离）| `LOAD(ep1)` -> 瞬即 `LOAD(ep2)` -> ep1 迟到响应被丢弃 -> ep2 正常起播 | 未覆盖 | **需新增**：异步延迟回包乱序注入测试，断言旧集不污染新集 |
| **TC-13** | 网络类型动态切换热更新缓冲 | `playing` -> `onMeteredChanged(true)` -> 热更新 mpv 属性 -> `playing` | 已覆盖：`playback_controller_test: 自适应分级网络状态字段测试` | **需补齐**：原生属性 `demuxer-max-bytes` 动态更新调用断言 |
| **TC-14** | 退出页面前退场静音与后台脱钩销毁 | `playing` -> `muteForExit()` -> `dispose()` -> 非阻塞退出 -> 后台异步释放 | 已覆盖：`playback_controller_test: 控制器 dispose 后资源安全销毁` | **需补齐**：验证退场静音不修改用户音量偏好持久化 |
| **TC-15** | **初次连接失败后重试成功** | `prebuffering` -> 握手失败 -> `recovering(第1次)` -> 500ms 退避 -> `preparing` -> `playing` | 未覆盖 | **需新增**：`recovering` 状态初次自愈单测 |
| **TC-16** | **初次连接失败后重试耗尽** | `prebuffering` -> 失败 -> `recovering(第1次)` -> 失败 -> `recovering(第2次)` -> `error` | 未覆盖 | **需新增**：重试达上限后平滑转入 `error` 状态机单测 |
| **TC-17** | **中途 EOF 断点恢复** | `playing(480s)` -> 假 EOF -> `recovering` -> `start(480s)` -> `playing(480s)` | 未覆盖 | **需新增**：中途断网自愈断点精确对齐测试 |
| **TC-18** | **resolving 阶段快速返回** | `resolving` -> 用户点返回 -> `DISPOSE_REQUEST` -> 取消 Future -> `disposed` | 未覆盖 | **需新增**：测试在网络 resolve 中途退出无未捕获异步异常 |
| **TC-19** | **恢复重试期间 dispose** | `recovering(退避中)` -> 用户退出 -> 取消退避定时器 -> `disposed` | 未覆盖 | **需新增**：验证退避定时器被立即销毁，不发生悬挂执行 |
| **TC-20** | **合法慢起播不被误判** | 弱网前置缓冲 5.2s（未超 8s） -> 遮罩持续覆盖 -> 5.2s 物理出画 -> `playing` | 未覆盖 | **需新增**：模拟 5 秒慢拉流正常出画且不触发超时的边界单测 |
| **TC-21** | **迟到原生事件隔离** | `openToken: 1` 派发延迟错误 -> 当前已是 `openToken: 2` -> 错误被丢弃 | 未覆盖 | **需新增**：`openToken` 跨集原生事件过滤单测 |

---

## 二、关键重构场景详细时序与断言定义

### 场景 TC-05：首帧超时判定（区分证据放行与重连）
* **分支 A（有证据：纯音频媒体正常放行）**：
  1. `[T0]` 起播广播剧音频流，进入 `prebuffering`，启动 8000ms 定时器；
  2. `[T300ms]` 底层确认 `hasVideoTrack == false`，且音频时钟 `position` 稳步前进；
  3. `[T8000ms]` 首帧定时器超时触发；
  4. **断言**：检测到存在音频推进证据，状态机判定为合法纯音频出画，触发 `FIRST_FRAME_TIMEOUT(有证据)`，撤除纯黑遮罩，状态迁移至 `playing`。
* **分支 B（无证据：连接假死触发重连）**：
  1. `[T0]` 起播视频流，进入 `prebuffering`，启动 8000ms 定时器；
  2. `[T8000ms]` 超时触发时，`width == 0 && height == 0`，且 `position` 依然卡在 0 秒不动；
  3. **断言**：检测到毫无推进证据，**绝对不解除遮罩**！状态机判定为连接假死，触发失败迁移至 `recovering`（`reason = firstFrameStall`），销毁僵死连接并安排退避重试。

---

### 场景 TC-10：中途非正常 EOF 信号拦截与断点恢复
* **时序与断言**：
  1. `[T0]` 24分钟视频正常播放至第 8 分钟（480s），处于 `playing`；
  2. `[T1]` 底层 FFmpeg 因网络中断抛出 EOF，`onCompletedChanged` 变为 `true`；
  3. `[T2]` 状态机卫语句判定：`duration (1440s) > 5s && currentPos (480s) < duration - 2s`；
  4. **断言**：判定该信号为假 EOF，强行拦截忽略；
  5. `[T3]` 状态机记录当前中断点 `pos = 480s`，迁移至 `recovering`（`reason = abnormalEofInterruption`）；
  6. `[T4]` 退避 500ms 后重新发起 `backend.open(url, start: Duration(seconds: 480))`；
  7. `[T5]` 恢复起播后出画，状态机顺利回到 `playing`，断点无缝续接。

---

### 场景 TC-11：HTTP 403 鉴权过期刷新重试（保留绑定）
* **时序与断言**：
  1. `[T0]` 底层拉流返回 `Server returned 403 Forbidden`；
  2. `[T1]` 适配层将其转换为 `BackendError(kind: authForbidden403)`；
  3. `[T2]` 状态机响应：
     * **断言 1**：立即调用 `SourceResolver.invalidate(url)` 驱逐 L1 直链缓存；
     * **断言 2**：`SourceBindingService` 中的番剧绑定**严格保留，不被删除**；
  4. `[T3]` 状态机进入 `recovering`，以 `bypassCache = true` 重新调用 `SourceResolver.resolve()` 获取全新带有效签名的媒体直链；
  5. `[T4]` 获取到新鲜直链后重新调用 `backend.open()`，顺利完成首帧渲染进入 `playing`。

---

### 场景 TC-21：迟到原生事件隔离（`openToken` 分界）
* **时序与断言**：
  1. `[T0]` 用户起播第 1 话，底层分配 `openToken = 1`；
  2. `[T100ms]` 用户迅速切换至第 2 话，底层分配 `openToken = 2`；
  3. `[T300ms]` 底层针对第 1 话的旧网络连接终于抛出了错误 `[media_kit] Failed to open ep1.m3u8: Connection reset`；
  4. **断言**：适配层捕获该错误并比对 `error.openToken (1) != currentOpenToken (2)`，该错误在适配层出口处被**瞬间物理拦截并丢弃**；
  5. **断言**：正在 `preparing` 第 2 话的 UI 与状态机完全不感知该错误，界面零报错闪烁。
