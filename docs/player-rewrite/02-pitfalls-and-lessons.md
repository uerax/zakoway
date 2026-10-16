# 播放控制层重写：阶段 0 设计文档（2/7）—— 暗坑清单（v2）

## 本版相对 v1 的变更
1. **修正 TLS 底层库描述**：明确 media_kit 全平台编译依赖的 FFmpeg n6.0 底座中，TLS 传输层实现为 **mbedTLS 3.5.0**（而非 OpenSSL），典型握手错误代码形如 `mbedtls_ssl_handshake returned -0x4e`。
2. **标明暗坑 1 因果推导为“待验证”**：将“`reconnect_at_eof=1` 在 Seek 时导致向对端发起并发连接并遭遇 TCP RST (-0x4e)”的因果链标明为**待验证**，区分出已确认为真的“现象：配置该参数确实导致 Seek 卡死”与待抓包验证的“机理：是否为底层并发新建连接被源站防火墙 RST”。
3. **补充新增底层暗坑**：
   * **暗坑 19**：首帧之前与首帧之后的网络断流日志歧义（`0xdfb9b0bb` 在首帧前为致命建联失败，首帧后才为良性重连）；
   * **暗坑 20**：握手阶段对端 TCP RST / 异常关闭连接（`mbedtls -0x4e` 假死）；
   * **暗坑 21**：原生 `player.open()` Future 提前完成导致异步错误延迟到达。

---

## 汇总索引表

| 序号 | 暗坑主题 | 涉及底层组件 | 风险等级 | 对应文件位置 |
| :---: | :--- | :--- | :---: | :--- |
| 1 | 点播网络流配置直播重连导致 TCP RST 卡死（**因果待验证**） | FFmpeg `libavformat` | 致命 | `playback_controller.dart:150-159` |
| 2 | media_kit 默认磁盘缓存导致缓存子系统损坏 | media_kit / libmpv | 高危 | `playback_controller.dart:160-164` |
| 3 | force-seekable / hr-seek 缺失导致 8~10 秒关键帧对齐误差 | mpv demuxer / decoder | 高危 | `playback_controller.dart:169-177` |
| 4 | `cache-pause-initial=yes` 导致每次 Seek 强行转圈 1~2 秒 | mpv cache | 体验严重受损 | `playback_controller.dart:178-185` |
| 5 | 第三方源自签名或过期 TLS 证书被拦截 | FFmpeg n6.0 / **mbedTLS 3.5.0** | 致命 | `playback_controller.dart:199-203` |
| 6 | Android 低端芯片激进硬解导致 MediaCodec/Surface 崩溃 | Android MediaCodec / mpv | 致命 | `playback_controller.dart:204-213` |
| 7 | 起播瞬间时间戳提前赋值引发「04:26 / 00:00」时间倒挂 | media_kit timeline / mpv | 逻辑混乱 | `playback_controller.dart:271-276, 630-640` |
| 8 | 切集时 GPU 纹理残留前一集最后一帧画面（残影闪烁）| mpv vo / Flutter Texture | 视觉割裂 | `playback_controller.dart:290-300`<br>`video_surface.dart:63-92` |
| 9 | Seek 目标时间戳接近视频总时长被误判为自然完播 | libmpv `eof-reached` | 逻辑缺陷 | `playback_controller.dart:370-379` |
| 10 | 外层反复 pause/play 破坏解复用线程同步引发 Packet corrupt | FFmpeg / libmpv demuxer | 高危 | `playback_controller.dart:398-402` |
| 11 | 并发频繁注入 Anime4K 着色器导致 mpv 渲染线程死锁与挂起 | Direct3D 11 / ANGLE / libmpv | 致命 | `playback_controller.dart:491-536` |
| 12 | 视频媒体未出首帧前盲目注入 GLSL 导致渲染上下文假死 | mpv vo / Direct3D | 高危 | `playback_controller.dart:680-702` |
| 13 | 中途网络断流/解码异常 EOF 误触发完播并在 EOF 态重播 | libmpv / media_kit stream | 逻辑破坏 | `playback_controller.dart:578-592` |
| 14 | 底层网络断开/Seek 重连良性日志被误报为播放致命错误 | FFmpeg protocol / media_kit | 假性报错 | `playback_controller.dart:609-617` |
| 15 | 页面返回销毁时同步 stop/dispose 阻塞主线程与平台通道 | media_kit PlatformChannel / mpv | 界面假死 | `playback_controller.dart:757-771` |
| 16 | Windows 平台 GLSL 路径反斜杠被转义损坏与分隔符差异 | mpv options parser | 功能失效 | `shader_asset_service.dart:30-44` |
| 17 | 纯音频或无视频轨媒体中死等视频尺寸导致遮罩永久卡死 | UI 首帧门禁状态机 | 假死黑屏 | `playback_controller.dart:34, 282-288, 681-692` |
| 18 | 非标私有加密流（如 Animoe 异或混淆）导致原生解复用器失败 | FFmpeg libavformat | 致命 | `animoe_source.dart:11-15, 165` |
| **19** | **新增：首帧之前与首帧之后的网络断流日志歧义** | 状态机阶段判断 / media_kit | 假死误判 | `04-error-policy.md` |
| **20** | **新增：握手阶段对端 TCP RST / 异常关闭连接 (`-0x4e`)** | mbedTLS 3.5.0 / FFmpeg | 严重卡顿 | `04-error-policy.md` |
| **21** | **新增：原生 `player.open()` Future 提前返回与异步错误延迟** | media_kit Native API | 时序竞态 | `03-state-machine.md` |

---

## 详细条目分析

### 坑 1：点播网络流配置直播重连参数导致 TCP RST 卡死
* **触发条件**：对普通点播网络流 (MP4/HLS)，在底层 FFmpeg 协议参数中配置了 `reconnect_at_eof=1` 或 `reconnect_streamed=1`，且用户在播放期间进行了进度条拖拽（Seek）。
* **确认为真的现象**：配置该参数后，网络点播流在 Seek 时频繁抛出 TCP RST 错误卡死。
* **因果机理（待验证）**：
  * *推测机理*：点播视频 Seek 时，前序发起的 HTTP Range 请求随之结束，FFmpeg 因上述参数将 Range 正常 EOF 误判为流异常中断，向对端 CDN 并发建立重连。对端服务器识别到同一个 Session 的旧连接未彻底释放即收到冲突请求，直接回送 `TCP RST` (错误码 `-0x4e`)。
  * *待验证项*：需要通过 Wireshark 抓包或 libavformat 调试日志验证对端发 RST 的真实触发原因（是旧连接未断并发新连接导致，还是 HTTP 请求头携带了冲突的 Range / Keep-Alive）。
* **现有对策所在位置**：
  * `lib/features/player/controller/playback_controller.dart:150-159`
  * 仅配置基础协议参数：`'stream-lavf-o', 'reconnect=1,reconnect_on_network_error=1,reconnect_delay_max=2'`。严禁注入 `reconnect_at_eof=1` 或 `reconnect_streamed=1`。

---

### 坑 5：第三方源自签名或过期 TLS 证书被拦截
* **触发条件**：第三方动漫聚合源或小型边缘 CDN 节点的 SSL/TLS 证书过期、颁发机构不被系统受信任库收录，或者为自签名证书。
* **底层组件事实说明**：
  media_kit 采用官方预编译的 `media_kit_libs_video` 原生库，其内置的 **FFmpeg n6.0** 链接的 TLS 实现库是 **mbedTLS 3.5.0**（而非 Linux 常用的 OpenSSL）。
* **后果**：mbedTLS 在 TLS Client Hello 握手协商与证书链校验失败时抛出错误，导致底层音视频拉流中断。
* **现有对策所在位置**：
  * `lib/features/player/controller/playback_controller.dart:199-203`
  * 底层播放器显式设置 `'tls-verify', 'no'`。该配置仅局限于 mpv 音视频媒体拉流通道，大幅提升第三方源播放成功率。

---

### 坑 19（新增）：首帧之前与首帧之后的网络断流日志歧义
* **触发条件**：底层 FFmpeg 输出 `tcp: ffurl_read returned 0xdfb9b0bb (end of file)`。
* **后果**：
  * **在首帧渲染后（`playing` / `seeking` / `rebuffering`）**：该日志通常只是旧 Range 读取完毕的良性通知，属于正常流切换行为；
  * **在首帧渲染前（`preparing` / `prebuffering`）**：如果在首帧还未出画时就收到了该日志，说明连接刚建立就被服务端直接掐断，媒体数据根本未到达，此时若依然盲目“良性忽略”，将导致播放器无限期卡死在纯黑遮罩中等待首帧！
* **对策所在位置**：
  * 收敛至 `04-error-policy.md`：根据 `phase` 严格分流：首帧前收到按 `initialConnectionFailure` 处理，进入 `recovering` 触发重连；首帧后收到才按 `benignLog` 静默放行。

---

### 坑 20（新增）：握手阶段对端 TCP RST / 异常关闭连接 (`-0x4e`)
* **触发条件**：源站防盗链风控临时拒绝、CDN 节点并发握手冲突或 TLS 协商失败，mbedTLS 输出：
  `tls: mbedtls_ssl_handshake returned -0x4e`
* **后果**：底层媒体拉流在握手初期崩溃，播放器进入死链接状态。
* **对策所在位置**：
  * 收敛至 `04-error-policy.md`：适配层将其结构化为 `BackendErrorKind.handshakeReset`，触发 500ms 延迟退避重试；若 2 次重试均失败，则触发自动故障转移切换视频源。

---

### 坑 21（新增）：原生 `player.open()` Future 提前返回与异步错误延迟到达
* **触发条件**：调用 `await player.open(Media(url))`。
* **后果与时序（待验证）**：
  * *观察现象*：`player.open` 的 Future 极大概率是在向 libmpv 发送完 IPC `loadfile` 指令后立即完成，而真正的 HTTP 连接与 demux 是在 C 语言后台线程异步执行的。因此，若直链 403 或网络超时，`await player.open` 本身并不会抛出异常，错误是在数秒后通过 `player.stream.error` 异步冒出；
  * *引发问题*：如果不做状态机阶段与 `openToken` 隔离，旧会话的异步报错会直接砸在后续新会话的头部，引发界面弹窗闪烁。
* **对策所在位置**：
  * 收敛至 `03-state-machine.md` 与 `05-interfaces-and-contracts.md`：引入 `openToken` 物理隔离机制，并在阶段 1 前置进行日志探针验证。
