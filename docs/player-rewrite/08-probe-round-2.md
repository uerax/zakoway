# 播放控制层重写：第二轮底层探针事实记录表（v1）

> 本文档为阶段 0 第二轮原生探针实测事实记录表，测试运行于 Windows 11 原生环境真实 `media_kit 1.2.6` (mpv v0.36.0-403 + FFmpeg n6.0 + mbedTLS 3.5.0)。
> 严格遵循事实记录原则：**只记录测量到的客观事实与时序数据，不给出架构改造或代码实现建议**。
> 原始日志夹具存放于 `test/fixtures/player_logs/`，敏感鉴权参数已遵循脱敏规则统一替换为 `...`。

---

## 零、测试运行环境与 media_kit 1.2.6 日志路由事实

### 1. 运行环境配置
* **操作系统**：Windows 11 Pro 23H2 x64 (Build 26200)
* **播放内核**：`media_kit 1.2.6` / `media_kit_libs_windows_video 1.0.11`
* **底层库版本**：libmpv v0.36.0-403-g0b16260905、FFmpeg n6.0、TLS 后端为 mbedTLS 3.5.0
* **应用配置**：采用 `playback_controller.dart` 中实际生效的原生 mpv 属性配置（含 `stream-lavf-o: reconnect=1,reconnect_on_network_error=1,reconnect_delay_max=2`、`cache=yes`、`cache-pause=yes`、`cache-pause-wait=0.2`、`network-timeout=10`、`demuxer-max-bytes=33554432` 等）。

### 2. media_kit 1.2.6 底层日志出口分发机制（已通过源码与实测双向核验）
在 `media_kit 1.2.6`（`real.dart` 第 2085~2130 行）中，原生 C 线程的 `mpv_event_log_message` 向 Dart 流的分发逻辑存在严格的硬编码过滤门禁：
1. **`player.stream.log` 出口**：
   受 `PlayerConfiguration(logLevel)` 控制。当 `logLevel = MPVLogLevel.error`（生产默认）时，仅接收 `level == 'error'` 的日志；当 `logLevel = MPVLogLevel.debug` 时，接收 `debug`、`v`、`info`、`warn`、`error` 全部日志。
2. **`player.stream.error` 出口**：
   **只有同时满足 `level == 'error'` 且匹配以下特定前缀规则的日志，才会注入 `stream.error`**：
   * `prefix == 'file'`（本地文件未找到）
   * `prefix == 'ffmpeg' && text.startsWith('tcp:')`（**仅限以 `tcp:` 开头的 FFmpeg 错误！**）
   * `prefix == 'vd'`（视频解码错误）
   * `prefix == 'ad'`（音频解码错误）
   * `prefix == 'cplayer'`（播放器核心错误）
   * `prefix == 'stream'`（流读取错误，如 `Failed to open <url>.`）
3. **关键分流推论**：
   * `tls: mbedtls_ssl_handshake returned -0x4e`（prefix 为 `ffmpeg` 但以 `tls:` 开头）：**绝不进入 `stream.error`**，仅在 `stream.log` 暴露；
   * `[ffmpeg] (warn) https: HTTP error 404 NOT FOUND`（level 为 `warn`）：**绝不进入 `stream.error`**；且在 `logLevel=error` 时在 `stream.log` 亦被静默丢弃，仅在 `warn/debug` 级别可见；
   * `[ffmpeg] (warn) http: Will reconnect at ...`（重连尝试）：同为 `warn` 级别，**绝不进入 `stream.error`**；
   * `[ffmpeg/demuxer] moov atom not found` 与 `[lavf] avformat_open_input() failed`：prefix 不属于上述列表，**绝不进入 `stream.error`**。

---

## 一、场景 1：TLS 握手对端关闭与线路形态实测

### 1.1 夹具文件清单
* `scenario_1_handshake_closed_al_prod.txt`：AL 线路（域名形态），生产配置，`logLevel=error`
* `scenario_1_handshake_closed_al_verbose.txt`：AL 线路（域名形态），生产配置，`logLevel=debug`
* `scenario_1_handshake_closed_al_default_cfg_prod.txt`：AL 线路（域名形态），默认配置对照组，`logLevel=error`
* `scenario_1_handshake_closed_al_default_cfg_verbose.txt`：AL 线路（域名形态），默认配置对照组，`logLevel=debug`
* `scenario_1_xfxf1_domain_prod.txt`：xfxf1 沃云线路（原始域名形态），生产配置，`logLevel=error`
* `scenario_1_xfxf1_domain_verbose.txt`：xfxf1 沃云线路（原始域名形态），生产配置，`logLevel=debug`
* `scenario_1_xfxf1_ip_host_prod.txt`：xfxf1 沃云线路（IP 改写 + Host 头形态），生产配置，`logLevel=error`
* `scenario_1_xfxf1_ip_host_verbose.txt`：xfxf1 沃云线路（IP 改写 + Host 头形态），生产配置，`logLevel=debug`

### 1.2 观测事实与时间戳时序
以 `scenario_1_handshake_closed_al_prod.txt`（现场实测真实数据）为例：
* `T+0ms`：`player.open()` 被调用；
* `T+7ms`：各流重置初始值派发（`position: 0, duration: 0, buffering: false` 等）；
* `T+15ms`：`player.open()` Future 完成，`stream.buffering: true`，`stream.playing: true`；
* `T+278ms`（第 1 次连接失败）：
  * `stream.log`: `[ffmpeg] (error) tcp: ffurl_read returned 0xdfb9b0bb`
  * `stream.error`: `tcp: ffurl_read returned 0xdfb9b0bb`
  * `stream.log`: `[ffmpeg] (error) tls: mbedtls_ssl_handshake returned -0x4e`
* `T+1461ms`（约 1.2s 后，FFmpeg 内部第 2 次重试失败）：
  * `stream.log`: `[ffmpeg] (error) tcp: ffurl_read returned 0xdfb9b0bb`
  * `stream.error`: `tcp: ffurl_read returned 0xdfb9b0bb`
  * `stream.log`: `[ffmpeg] (error) tls: mbedtls_ssl_handshake returned -0x4e`
* `T+2681ms`（约 1.2s 后，FFmpeg 内部第 3 次重试失败，耗尽 `reconnect_delay_max=2`）：
  * `stream.log`: `[ffmpeg] (error) tcp: ffurl_read returned 0xdfb9b0bb`
  * `stream.error`: `tcp: ffurl_read returned 0xdfb9b0bb`
  * `stream.log`: `[ffmpeg] (error) tls: mbedtls_ssl_handshake returned -0x4e`
  * `stream.log`: `[stream] (error) Failed to open https://play.xfvod.pro:8088/...`
  * `stream.error`: `Failed to open https://play.xfvod.pro:8088/...`

### 1.3 对照组与形态差异对比
1. **默认配置对照组（无 `stream-lavf-o` 重试配置）**：
   在 `scenario_1_handshake_closed_al_default_cfg_prod.txt` 中，由于未启用 `reconnect=1`，底层在 `T+203ms` 收到第一次 `-0x4e` 之后**立即终止并直接抛出 `Failed to open`**，全过程仅 203ms，无任何内部重试。
2. **生产配置重试行为**：
   在启用生产配置后，FFmpeg 内部自动执行了 3 次退避重试（退避 0s、1s、1s），总耗时由 200ms 延长至约 2.6 秒，最终才在 `stream.error` 冒出 `Failed to open`。
3. **xfxf1 线路原始域名 vs IP 改写形态**：
   在当前 Windows 环境下对 `apn.moedot.net` 发起请求，无论采用原始域名形态（`scenario_1_xfxf1_domain_prod.txt`，耗时 1747ms）还是直接锁定 IPv4 节点并加 `Host: apn.moedot.net` 头（`scenario_1_xfxf1_ip_host_prod.txt`，耗时 1643ms），底层均抓到了完全一致的 `0xdfb9b0bb` 与 `-0x4e` 握手对端中断。

### 1.4 与设计文档 v2 假设的差异
* **v2 假设**：v2 将此类错误命名为 `handshakeReset`，并在文档中推测可能是 "TCP RST" 或 "并发握手冲突"。
* **实测事实**：日志原文仅有 `tcp: ffurl_read returned 0xdfb9b0bb`（`AVERROR_EOF`）和 `tls: mbedtls_ssl_handshake returned -0x4e`。FFmpeg 源码中 `-0x4e` 对应 `MBEDTLS_ERR_NET_CONN_RESET` 或 EOF，证据仅能证明“远端在握手阶段主动断开连接（EOF）”，不能证明是 TCP RST（RST 在 mbedTLS 中通常另有明确代码 `-0x50`），亦无多并发冲突证据。

---

## 二、场景 2：HTTP 403 与 HTTP 404 状态码暴露实测

### 2.1 夹具文件清单
* `scenario_2_http_403_prod.txt`：HTTP 403，生产配置，`logLevel=error`
* `scenario_2_http_403_verbose.txt`：HTTP 403，生产配置，`logLevel=debug`
* `scenario_2_http_404_prod.txt`：HTTP 404，生产配置，`logLevel=error`
* `scenario_2_http_404_verbose.txt`：HTTP 404，生产配置，`logLevel=debug`

### 2.2 观测事实与时间戳时序
1. **HTTP 403（`https://httpbin.org/status/403`）**：
   * `prod` 级别（`scenario_2_http_403_prod.txt`）：
     * `T+1140ms` 处到达 `stream.error`：`Failed to open https://httpbin.org/status/403.`
     * 全程未出现任何包含 `403`、`Forbidden` 或 `Server returned` 的文本。
   * `verbose` 级别（`scenario_2_http_403_verbose.txt`）：
     * 在 `stream.log` 中同样仅有 `[ffmpeg] (v) Opening https://...` 与 `[stream] (error) Failed to open ...`，FFmpeg 未记录任何状态码数字。
2. **HTTP 404（`https://httpbin.org/status/404`）**：
   * `prod` 级别（`scenario_2_http_404_prod.txt`）：
     * `T+1071ms` 处到达 `stream.error`：`Failed to open https://httpbin.org/status/404.`
     * 文本中不含 `404` 或 `Not Found`。
   * `verbose` 级别（`scenario_2_http_404_verbose.txt`）：
     * `T+1078ms` 处在 `stream.log` 出现：`[ffmpeg] (warn) https: HTTP error 404 NOT FOUND`；
     * 紧随其后 `T+1079ms` 处在 `stream.error` 出现：`Failed to open https://httpbin.org/status/404.`。

### 2.3 与设计文档 v2 假设的差异
* **v2 假设**：v2 在第二节样本 3 中假设 media_kit 抛出的日志为：
  `[media_kit] Failed to open ...: Server returned 403 Forbidden`，并假设能从 rawMessage 正则提取状态码 `403`。
* **实测事实**：
  1. `stream.error` 抛出的文本一律只有 `Failed to open <URL>.`，**末尾无任何冒号或 HTTP 状态码说明，完全无法从 `stream.error` 提取 HTTP 状态码**。
  2. HTTP 404 的状态码文本 `HTTP error 404 NOT FOUND` 仅在 `logLevel >= warn` 时作为 `stream.log` 的 warn 消息打印；在生产默认的 `error` 级别下**根本不向 Dart 暴露**。
  3. HTTP 403 在底层直接返回 open failed，甚至在 `debug` 级别的 `stream.log` 中也未打印状态码行。

---

## 三、场景 3：DNS 失败与连接超时时序实测

### 3.1 夹具文件清单
* `scenario_3_dns_fail_prod.txt`：DNS 失败，生产配置，`logLevel=error`
* `scenario_3_dns_fail_verbose.txt`：DNS 失败，生产配置，`logLevel=debug`
* `scenario_3_connect_timeout_prod.txt`：连接超时（10.255.255.1:12345），生产配置，`logLevel=error`
* `scenario_3_connect_timeout_verbose.txt`：连接超时（10.255.255.1:12345），生产配置，`logLevel=debug`

### 3.2 观测事实与时间戳时序
1. **DNS 失败（`probe-dns-nxdomain.invalid`）**：
   * 在 Windows 平台下，系统 DNS 客户端解析一个不存在的域名耗时约 11 秒。
   * `T+11089ms` 时派发第 1 次错误：
     * `stream.log`: `[ffmpeg] (error) tcp: Failed to resolve hostname probe-dns-nxdomain.invalid: The name does not resolve for the supplied parameters`
     * `stream.error`: `tcp: Failed to resolve hostname probe-dns-nxdomain.invalid: The name does not resolve for the supplied parameters`
   * 由于以 `tcp:` 开头，该错误**成功穿透进入了 `stream.error`**。
   * 因 `reconnect=1`，FFmpeg 继续发起第 2 次尝试，于 `T+22155ms` 再次上报相同错误。
2. **连接超时（不可路由地址 `10.255.255.1:12345`）**：
   * 在 `scenario_3_connect_timeout_verbose.txt` 中：
     * `T+5191ms`: `[ffmpeg] (warn) http: Will reconnect at 0 in 0 second(s).`
     * `T+10367ms`: `[ffmpeg] (warn) http: Will reconnect at 0 in 1 second(s).`
     * `T+11371ms`: 再次尝试连接；
     * `T+16532ms`: 底层耗尽尝试，在 `stream.error` 抛出 `Failed to open http://10.255.255.1:12345/video.mp4.`。
3. **跨会话迟到日志穿透现象**：
   * 在 `scenario_3_connect_timeout_prod.txt` 的 `T+7275ms` 处，捕获到了前一个 DNS 探针测试实例在后台线程中遗留未完成的迟到日志：
     `[stream.error] tcp: Failed to resolve hostname probe-dns-nxdomain.invalid...`
   * 这证明底层 libmpv 的异步网络解析线程若未随 open 销毁，其延迟日志会在后续全新 open 甚至全新 Player 实例运行期间突发冒出。

### 3.3 与设计文档 v2 假设的差异
* **v2 假设**：v2 预算表认为网络超时或连接失败在 8 秒硬超时即可被 Dart 捕获处理。
* **实测事实**：若不加 Dart 层主动裁决，单纯等待底层 FFmpeg + mpv 内部重试报错，连接超时需耗时 **16.5 秒**，DNS 两次重试耗时 **22 秒**。充分证明必须在 Dart 控制层设立会话秒表硬上限强行打断。

---

## 四、场景 4：中途异常 EOF 实测（持续拒绝 vs 恢复服务）

### 4.1 夹具文件清单
* `scenario_4_midstream_eof_refuse_prod.txt`：断开后持续拒绝，`logLevel=error`
* `scenario_4_midstream_eof_refuse_verbose.txt`：断开后持续拒绝，`logLevel=debug`
* `scenario_4_midstream_eof_recover_prod.txt`：断开后恢复服务，`logLevel=error`
* `scenario_4_midstream_eof_recover_verbose.txt`：断开后恢复服务，`logLevel=debug`

### 4.2 观测事实
1. **子情形 4a：服务端断开后持续拒绝连接**：
   * 客户端拉取 70KB 后服务端销毁 Socket，后续连接一律拒绝；
   * 底层 demuxer 报错：
     `[ffmpeg] (error) Seek failed (to 220096, size -40)`
     `[ffmpeg/demuxer] (error) mov,mp4,m4a,3gp,3g2,mj2: moov atom not found`
     `[lavf] (error) avformat_open_input() failed`
   * **`completed` 状态**：全程严格保持为 `false`，**未发生“中途断流误报播放完毕（completed: true）”的假完成 bug**；
   * **`stream.error` 出口**：由于上述日志前缀不是 `file/vd/ad/cplayer/stream` 且不以 `tcp:` 开头，**`stream.error` 完全为空**，播放器永久挂起在 `buffering: true` 态。
2. **子情形 4b：服务端断开后恢复服务**：
   * 服务端切断 1 次后，当 FFmpeg 发起 Range 重连时放行；
   * 在 `T+275ms` 发生断流并报错 `moov atom not found` 后，FFmpeg 自动通过 HTTP Range 重连成功拉取后续切片；
   * 播放时钟完全未被破坏，`position` 毫秒级连续递增（从 191ms 平滑演进至 8121ms）；
   * `completed` 保持为 `false`，实现了底层无缝自愈。

### 4.3 与设计文档 v2 假设的差异
* **v2 假设**：v2 担心断流可能导致 mpv 提前派发 `completed: true`。
* **实测事实**：在 MP4 点播流中，断流并不会触发 `completed: true`。但在断流且无法恢复时，`stream.error` 没有任何事件抛出，导致上层无法依赖 `stream.error` 感知崩溃，必须依靠“播放中卡顿超时监测（rebuffering watchdog）”兜底。

---

## 五、场景 5：正常网络 MP4 物理时序全记录

### 5.1 夹具文件清单
* `scenario_5_normal_mp4_prod.txt`：生产配置，`logLevel=error`
* `scenario_5_normal_mp4_verbose.txt`：生产配置，`logLevel=debug`

### 5.2 绝对毫秒级事件发生顺序
基准媒体：本地 HTTP 托管的 `sample_15s.mp4`（H.264 + AAC，15.02 秒）：
1. `[T0: +4ms]`：`action.open.call`（调用 `player.open()`）；
2. `[T1: +10ms]`：各流派发初始重置值：
   `playing: false, completed: false, position: 0ms, duration: 0ms, buffering: false, buffer: 0ms, videoParams: null, tracks: video=2, audio=2, width: null, height: null`；
3. `[T2: +18ms]`：原生异步指令就绪：
   `stream.playing: true`；
   `action.open.future_completed (耗时 14ms)`；
   `stream.buffering: true`（解复用启动）；
4. `[T3: +34ms]`：解复用完成，媒体轨道解析出：
   `stream.tracks: videoCount=3, audioCount=3, subtitleCount=2`；
5. `[T4: +35ms]`：时长元数据解析出：
   `stream.duration: 15023ms`；
6. `[T5: +36ms]`：首批缓冲就绪，初始缓冲结束：
   `stream.buffering: false`；
7. `[T6: +60ms]`：播放时钟首次出帧：
   `stream.position: 0ms (0:00:00.000012)`；
8. `[T7: +115ms]`：时钟开始前进：
   `stream.position: 41ms` -> `100ms (+175ms)` -> `161ms (+236ms)`...；
9. `[T8: +284ms]`：已缓冲水线范围更新：
   `stream.buffer: 14976ms`。

### 5.3 关键现象：无视频渲染驱动时 videoParams 的表现
* 在测试环境无原生 DirectX/HWND 窗口依附（`vo=null` 纯解码运行）时，mpv 的 `video-params` 属性不更新，`width/height/videoParams` 全程保持为 `null`；
* 这证明上层控制层在设计首帧出画条件时，**不能把 `videoParams != null` 或 `width > 0` 作为唯一的首帧判定前提**，必须兼容纯音频或渲染驱动延迟绑定的场景（以 `duration > 0 && !buffering` 或时钟启动作为充分证据）。

---

## 六、场景 6：连续两次 open() 竞态与重置标记实测

### 6.1 夹具文件清单
* `scenario_6_double_open_20ms_prod.txt` / `_verbose.txt`：间隔 20ms
* `scenario_6_double_open_300ms_prod.txt` / `_verbose.txt`：间隔 300ms
* `scenario_6_double_open_after_first_frame_prod.txt` / `_verbose.txt`：首帧出画后立即 open B
* `scenario_6_open_while_playing_prod.txt` / `_verbose.txt`：A 正在播放（1.5s）时 open B

### 6.2 观测事实
1. **重置标记发射时刻的同步性**：
   * 无论上一次 open 处于何种状态（初建联 20ms、缓冲中 300ms 还是播放中 1.5s），一旦发起第二次 `open(uriB)`：
   * **在发起调用的 6~7ms 内，media_kit 必然会同步发出全套重置值**：
     `playing: false, position: 0ms, duration: 0ms, buffer: 0ms, buffering: false, videoParams: null`。
2. **旧流迟到错误的实测捕捉（20ms 变体）**：
   * 在 `scenario_6_double_open_20ms_prod.txt` 中：
     * `T+30ms` 发起 open B；
     * `T+31ms` 各流重置标记发射；
     * **`T+34ms` 出现旧流 A 的 demuxer 报错**：
       `[ffmpeg/demuxer] (error) mov,mp4,m4a,3gp,3g2,mj2: moov atom not found`
       `[lavf] (error) avformat_open_input() failed`；
     * 该报错物理上完全发生在 open B 之后，且发生在 B 的重置标记之后；
     * `T+40ms` B 的 open Future 完成并启动，随后 B 正常播放。
3. **播放中切流的时钟隔离（正在播放 1.5s 变体）**：
   * 在 `scenario_6_open_while_playing_prod.txt` 中，A 播放至 1548ms 时发起 open B：
   * `T+1597ms` 重置标记发射后，**A 的旧 position 立即戛然而止，未出现任何 >0 的 A 残留 position 泄露**；
   * B 于 `T+1697ms` 开始从 38ms、88ms、146ms 重新起播。

### 6.3 与设计文档 v2 假设的差异
* **v2 假设**：v2 的 openToken 方案在各 stream 回调中通过闭包对比 `currentToken == _openTokenCounter`，但由于监听器在初始化时全局绑定，回调内部无法捕获到每次 open 的局部 token。
* **实测事实**：
  1. media_kit 在每次 open 时必然按序发射全套 0 标记，可作为天然的物理代际划分依据；
  2. 但**迟到的流错误日志（如 A 的 demuxer 异常）依然会在重置标记之后冒出**，单凭重置标记无法防范日志层面的误伤，**错误日志必须结合当前 Session 请求的 URL 进行归因比对（URL 校验过滤）**。

---

## 七、场景 7：慢起播时序（延迟响应头 vs 缓慢滴入）实测

### 7.1 夹具文件清单
* `scenario_7_slow_headers_prod.txt` / `_verbose.txt`：响应头延迟 9 秒
* `scenario_7_slow_drip_prod.txt` / `_verbose.txt`：数据以 22KB/s 缓慢滴入

### 7.2 观测事实
1. **变体 7a（响应头延迟 9 秒）**：
   * `T+18ms` 至 `T+9044ms`（长达 9.02 秒）：
     * `position = 0ms`，`duration = 0ms`，`buffer = 0ms`，`buffering = true`；
     * 期间无任何事件更新，各指标保持静默；
   * `T+9045ms`（响应头到达）：
     * `stream.tracks` 与 `stream.duration = 15023ms` 瞬间解析就绪；
     * `stream.buffering` 翻转为 `false`；
   * `T+9091ms`：首帧时钟启动（`position: 0ms -> 48ms`），`buffer: 14976ms` 就绪。
2. **变体 7b（数据以 22KB/s 缓慢滴入）**：
   * `T+1041ms`：响应头与首个 MOOV 块到位，`duration = 15023ms` 即被解析出，`buffering = false`；
   * 随后的 12 秒内，由于数据持续流入：
     * `buffer` 呈现高度规律的台阶式递增：
       `T+1290ms: 278ms` -> `T+1540ms: 626ms` -> `T+1790ms: 928ms` -> `T+2040ms: 1277ms` -> `T+2290ms: 1904ms` ... 直至 14976ms；
     * 伴随 buffer 的增长，`position` 持续顺畅推进（16ms -> 70ms -> 120ms...）。

### 7.3 与设计文档 v2 假设的差异
* **v2 假设**：v2 设定了首帧黑屏超时 8 秒，若超时直接报错。
* **实测事实**：
  * 在 7b 这种慢速流中，`duration` 在 1 秒左右即已知，且 `buffer` 每隔数百毫秒都在线性增长；这种情况下视频流高度健康，仅是传输速率较慢，若因死守固定超时强行弹错将严重误伤弱网用户；
  * 在 7a 这种上游 CDN 响应慢场景下，若无存活信号，等待超过 `network-timeout`（10s）则会被 mpv 底层主动丢弃连接。

---

## 八、场景 8：同一链接连续 open 重复成功率实测

### 8.1 夹具文件清单
* `scenario_8_repeat_open_0_5s.txt`：间隔 500ms，连续 open 10 次
* `scenario_8_repeat_open_1_0s.txt`：间隔 1000ms，连续 open 10 次
* `scenario_8_repeat_open_2_0s.txt`：间隔 2000ms，连续 open 10 次

### 8.2 实测汇总数据表

| 轮次 | 设定请求间隔 | 总执行次数 | 成功次数 | 失败次数 | 成功率 | 最小单次耗时 | 最大单次耗时 | 平均耗时 | 失败时报错特征 |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **轮次 1** | 500ms | 10 | 0 | 10 | **0.0%** | 1564ms | 2639ms | 1894ms | 100% 出现 `0xdfb9b0bb` 与 `-0x4e` |
| **轮次 2** | 1000ms | 10 | 0 | 10 | **0.0%** | 1543ms | 2586ms | 1783ms | 100% 出现 `0xdfb9b0bb` 与 `-0x4e` |
| **轮次 3** | 2000ms | 10 | 0 | 10 | **0.0%** | 1531ms | 3631ms | 2089ms | 100% 出现 `0xdfb9b0bb` 与 `-0x4e` |
| **合计** | - | 30 | 0 | 30 | **0.0%** | 1531ms | 3631ms | 1922ms | 均在第 2~3 次重试后彻底抛出 `Failed to open` |

### 8.3 观测事实
1. **成功率为绝对零**：对受影响的 CDN 节点（`play.xfvod.pro:8088`），在 0.5s、1.0s、2.0s 任意退避间隔下连续发起 30 次 open，成功率均为 0.0%，无一例偶然成功；
2. **每次失败的报错高度一致**：
   * `stream.log`:
     `[ffmpeg] (error) tcp: ffurl_read returned 0xdfb9b0bb`
     `[ffmpeg] (error) tls: mbedtls_ssl_handshake returned -0x4e`
     `[stream] (error) Failed to open ...`
   * `stream.error`:
     `tcp: ffurl_read returned 0xdfb9b0bb`
     `Failed to open ...`
3. **单次重试耗时规律**：
   平均耗时约 1.8~2.0 秒，证明当前应用配置的 `reconnect_delay_max=2` 每次 open 内部均忠实执行了 2~3 次退避重试，耗时在 1.5s 至 3.6s 之间。
