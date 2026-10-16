# 播放控制层重写：阶段 0 设计文档（7/7）—— 迁移计划与回退方案（v2）

## 本版相对 v1 的变更
1. **架构职责解耦（阶段 3 调整）**：明确将“15秒有效时长防刷（Anti-Bounce）、85% 完播标记、10秒周期历史落盘”拆解为**独立的领域服务类 `WatchProgressTracker`**，严禁塞入 `PlaybackSession` 中。使 `PlaybackSession` 纯粹聚焦于单次播放流的状态机运转，提升两者的单元测试独立性。
2. **新增阶段 1 前置任务（原生探针验证）**：在阶段 1 编写任何生产代码前，明确通过运行临时日志探针，在真实应用环境中验证 3 个关键原生行为，锁定底层时序事实。

---

## 一、三大底层行为探针实测结果（已全部验证通过）

在进入阶段 1 编写 `PlayerBackend` 之前，已在真实本地 libmpv 运行环境下执行时序探针，彻底锁定了以下 3 项关键事实：

### 探针 1 实测：`player.open()` Future 的确切完成时机（已证实为极速完成）
* **实测结果**：`await player.open(Media(url))` 仅耗时 **11ms ~ 36ms** 即完成 Future。
* **物理事实**：它仅代表向底层 libmpv 成功发送 IPC `loadfile` 指令，网络连接尚未建立。建联拉流过程完全处于 `prebuffering` 阶段。

### 探针 2 实测：`Failed to open <url>` 到底经由哪条流到达（已证实仅走 `stream.error`）
* **实测结果**：`player.open()` 的 Future 从不抛出 403 异常（`catchError` 不触发），所有拉流建网错误 100% 异步经由 `player.stream.error` 冒出。

### 探针 3 实测：`open` 期间各流事件的绝对到达先后顺序（已实测锁定）
* **实测物理顺序**：
  `open Future完成 (11~14ms)` -> `buffering: true` -> `duration: 3023 (21ms)` -> `buffering: false (22ms)` -> `position: 50, 100... (时钟启动)`。

---

## 二、分阶段实施路线图（v2）

```
┌────────────────────────────────────────────────────────────────────────┐
│ 阶段 0：设计规范评审与技术契约冻结（当前阶段）                         │
│ 产出：docs/player-rewrite/ 全套 v2 规范文档；代码库 0 改动             │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 阶段 1：探针时序验证 + 内核状态机落地（无侵入新建）                     │
│ 步骤 1.1：日志探针验证三大待验证项（锁定底层时序）                     │
│ 步骤 1.2：新建 PlayerBackend, PlaybackSession, PlaybackFsm (含 recovering)│
│ 步骤 1.3：跑通新增的 TC-01 ~ TC-21 单元测试集                           │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 阶段 2：ZakowayPlaybackController 门面适配与双轨验证                   │
│ 产出：原控制器转为 Facade，内部连接新 Session；提供 kUseRewrittenPlayerCore│
│ 准出：现有 playback_controller_test 等全部原有单测 100% 保持绿灯      │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 阶段 3：WatchProgressTracker 独立提炼与 VideoPlayPage 精简             │
│ 产出：新建 WatchProgressTracker 承接 15s/完播/历史落盘                  │
│ 收益：VideoPlayPage 仅监听 Tracker 与 Session，不再手写定时统计逻辑     │
└──────────────────────────────────┬─────────────────────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────────┐
│ 阶段 4：多端真机冒烟与废弃旧逻辑清理                                   │
│ 验证：弱网多源并发、快速连续切集、Anime4K 串行切换；清理降级开关       │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 三、各阶段详细交付、准出与回退方案

### 阶段 0：设计规范评审与技术契约冻结
* **交付物**：`docs/player-rewrite/` 目录下全部修订后的 v2 文档。
* **代码修改**：**0 行**。严禁改动任何 `.dart` 文件。
* **准出标准**：文档修订经评审通过。
* **回退办法**：直接 `git revert` 本次文档提交即可。

---

### 阶段 1：探针时序验证 + 内核状态机落地
* **交付物**：
  * 在 `lib/features/player/core/` 下新建独立文件：
    1. `backend/player_backend.dart`
    2. `backend/media_kit_player_backend.dart`
    3. `session/playback_session.dart`
    4. `session/playback_fsm.dart` (含 `recovering` 状态与 Attempt ID / openToken)
    5. `resolver/source_resolver.dart`
  * 对应新增单元测试文件：`test/features/player/core/` 覆盖 TC-01 ~ TC-21。
* **准出标准**：
  1. 3 个探针的实际输出记录在案并固化为单元测试用例；
  2. 新增的独立状态机单测 100% 通过；
  3. 不引入或修改任何现有的 Controller/Page 代码，主干代码 0 侵入。
* **回退办法**：
  * 直接删除新建的 `lib/features/player/core/` 目录，主干业务完全不受影响。

---

### 阶段 2：`ZakowayPlaybackController` 门面适配与双轨验证
* **交付物**：
  * 将 `lib/features/player/controller/playback_controller.dart` 重构为外观门面（Facade），内部直接创建并驱动 `PlaybackSession` 与 `MediaKitPlayerBackend`；
  * 保留安全特性开关：
    ```dart
    /// 播放控制层重构特性开关 (默认为 true，若遇未知异常可秒级切为 false)
    const bool kUseRewrittenPlayerCore = true;
    ```
    旧版实现作为 `_LegacyZakowayPlaybackControllerImpl` 保留。若 `kUseRewrittenPlayerCore == false`，直接透明降级回旧实现。
* **准出标准**：
  * 现有 8 个核心单测（`test/features/player/playback_controller_test.dart`）在门面类上**无需修改一行测试代码**即 100% 绿灯通过；
  * `player_resume_and_error_card_test.dart`、`player_controls_overflow_and_autoplay_test.dart` 全部通过。
* **回退办法**：
  * 紧急回退：将 `kUseRewrittenPlayerCore` 置为 `false`；
  * 物理回退：`git revert` 对应 commit，恢复旧文件。

---

### 阶段 3：`WatchProgressTracker` 独立提炼与 `VideoPlayPage` 精简
* **交付物**：
  * 新建独立领域服务 `lib/features/player/services/watch_progress_tracker.dart`：
    * 封装 `_playSecAccumulated` 15秒自然播放累加逻辑（Anti-Bounce）；
    * 封装 `0 < tickDelta <= 2.5s` 自然步进检查；
    * 封装 85% 完播兜底标记与 10秒周期节流落盘逻辑；
    * 封装 `resolveInitialResumePosition`（>= 95% 或剩余 < 15s 强制归零重播逻辑）；
    * 配套单元测试 `test/features/player/services/watch_progress_tracker_test.dart`。
  * `VideoPlayPage` 移除内嵌的高频时间线统计和历史写入逻辑，完全委托给 `WatchProgressTracker`。
* **准出标准**：
  * `test/features/player/video_play_page_test.dart` 12 个集成测试全部绿灯；
  * 视频起播、进度保存、历史记录恢复功能体验完全无缝对齐。
* **回退办法**：
  * `git revert` 阶段 3 提交，`VideoPlayPage` 回退至原有自管逻辑，门面类完全兼容。

---

### 阶段 4：多端真机冒烟与废弃旧逻辑清理
* **交付物**：
  * 在 Windows、Android、iOS 真机上完成弱网多源切换、快速选集连击、Anime4K 连续切档冒烟；
  * 删除阶段 2 中的 `_LegacyZakowayPlaybackControllerImpl` 兜底代码与 `kUseRewrittenPlayerCore` 开关。
* **回退办法**：
  * 定点修复边缘平台兼容 bug。
