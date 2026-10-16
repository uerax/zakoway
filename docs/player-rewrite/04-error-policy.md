# 播放控制层重写：阶段 0 设计文档（4/7）—— 错误分类与恢复策略表（v2）

## 本版相对 v1 的变更
1. **结构化错误模型（`BackendError`）**：废除依赖粗暴 `contains('403')` 的字符串匹配，建立“生命周期阶段 + 结构化枚举 + HTTP状态码 + 剥离后纯净消息”的严谨模型。
2. **底层日志单点解析收敛**：规定原始日志解析仅在底层后端适配层（`PlayerBackend`）出口发生一次，必须先正则剥离 URL，防止 URL 含有敏感词造成误判。以三组真实底层日志作为测试契约样本。
3. **收紧“良性日志”作用域**：`0xdfb9b0bb` 等日志仅在“首帧已渲染之后的 seek 或中途断网重连”阶段认定为良性放行；在首帧渲染前（`preparing` / `prebuffering`）出现同一签名，一律视为“初次连接失败”，进入 `recovering`。
4. **新增“握手阶段对端关闭”类别**：专门针对 TLS/TCP 握手时服务器返回 `-0x4e` / `Connection reset by peer` 的场景，定义恢复动作、重试退避与超时时限。
5. **建立全链路总时限与总预算表**：综合计算 FFmpeg 内建重试、Dart 层重试退避与阶段硬超时，锁定用户界面可见的最长等待预算（< 15s），杜绝无休止假死黑屏。
6. **修正缓存驱逐规则**：B 类（403 鉴权失效）与 C 类（404 失效）**仅驱逐 L1 内存直链缓存**，**严禁轻易删除 `SourceBindingService` 持久绑定**（源站可能只是切片直链或某集失效，番剧的页面主 URL 依然有效；若重试且该集直链刷新仍失败，可标记该集异常，但保留番剧绑定）。
7. **重写清洗算法**：基于 `BackendError.kind` 强类型映射，彻底消除针对未脱敏 raw text 的暴力判断。

---

## 一、结构化错误模型（`BackendError`）

底层 C 线程产生的非结构化文本在进入 Dart 领域模型时，必须在适配层统一收敛转化为强类型的 `BackendError`：

```dart
/// 错误所属的生命周期阶段
enum PlaybackPhase {
  resolving,    // 直链解析阶段
  preparing,    // 底层初始化 open 阶段
  prebuffering, // 首帧前初始缓冲拉流阶段
  playing,      // 正常播放阶段
  seeking,      // 寻道出新帧阶段
  rebuffering,  // 播放中途卡顿缓冲阶段
}

/// 错误核心类别
enum BackendErrorKind {
  benignLog,          // 良性底层重连日志（非致命）
  handshakeReset,     // 握手阶段对端强制关闭连接 (-0x4e / RST)
  authForbidden403,   // 鉴权失败 / 防盗链拦截 (HTTP 403)
  notFound404,        // 资源不存在 / 已下架 (HTTP 404)
  serverError5xx,     // 上游服务端崩溃 (HTTP 5xx)
  connectTimeout,     // 网络连接 / 握手超时
  decodeCorrupted,    // 数据解析 / 解复用 / 解码损毁
  formatUnsupported,  // 媒体格式不支持
  unknown,            // 未分类异常
}

/// 结构化播放错误实体
@immutable
class BackendError {
  const BackendError({
    required this.kind,
    required this.phase,
    required this.rawMessage,
    this.cleanUrl,
    this.httpStatus,
    this.nativeErrorCode,
    this.timestamp,
  });

  /// 归一化错误分类
  final BackendErrorKind kind;

  /// 发生该错误时播放器所处的生命周期阶段
  final PlaybackPhase phase;

  /// 已剥离 URL 和堆栈后的纯净原始错误描述
  final String rawMessage;

  /// 涉及的媒体直链 URL（若解析出）
  final String? cleanUrl;

  /// HTTP 状态码（如 403, 404, 502 等）
  final int? httpStatus;

  /// 底层原生错误码（如 FFmpeg 的 -541478725 或 mbedTLS 的 -0x4e）
  final int? nativeErrorCode;

  /// 发生时刻
  final DateTime? timestamp;

  /// 是否为可在后台自愈的可恢复错误
  bool get isRecoverable =>
      kind == BackendErrorKind.authForbidden403 ||
      kind == BackendErrorKind.handshakeReset ||
      kind == BackendErrorKind.connectTimeout ||
      kind == BackendErrorKind.benignLog;
}
```

---

## 二、真实底层日志样本与单点解析契约

底层适配层必须**先正则剥离 URL**，再进行特征码匹配。以下三组真实日志作为适配层解析器的**基准测试样本**：

### 样本 1：点播 Seek 或正常 EOF 良性网络重连
* **原始日志文本**：
  `[ffmpeg] tcp: ffurl_read returned 0xdfb9b0bb (end of file)`
* **阶段上下文**：`phase == PlaybackPhase.seeking` 或 `phase == PlaybackPhase.playing`
* **解析产物**：
  * `kind = BackendErrorKind.benignLog`
  * `nativeErrorCode = 0xdfb9b0bb` (AVERROR_EOF)
  * `rawMessage = "tcp: ffurl_read returned end of file"`

### 样本 2：TLS 握手被对端 RST 强行重置
* **原始日志文本**：
  `[ffmpeg] tls: mbedtls_ssl_handshake returned -0x4e (A close_notify / TCP RST was received)`
* **阶段上下文**：`phase == PlaybackPhase.preparing` 或 `prebuffering`
* **解析产物**：
  * `kind = BackendErrorKind.handshakeReset`
  * `nativeErrorCode = -0x4e`
  * `rawMessage = "tls: mbedtls_ssl_handshake returned -0x4e"`

### 样本 3：直链解析或建联失败抛出完整 URL
* **原始日志文本**：
  `[media_kit] Failed to open https://vip.ffzy-online.com/20240101/40392_8f9a403/index.m3u8: Server returned 403 Forbidden`
* **剥离处理**：
  提取 URL：`https://vip.ffzy-online.com/20240101/40392_8f9a403/index.m3u8`
  剥离后文本：`Failed to open <URL>: Server returned 403 Forbidden`
* **解析产物**：
  * `kind = BackendErrorKind.authForbidden403`
  * `httpStatus = 403`
  * `cleanUrl = "https://vip.ffzy-online.com/20240101/40392_8f9a403/index.m3u8"`
  * `rawMessage = "Server returned 403 Forbidden"`

---

## 三、错误分类全景矩阵（v2）

| 错误分类 (`BackendErrorKind`) | 发生阶段 (`phase`) | 恢复动作（Action） | 最大重试与退避 | 缓存驱逐范围 | 用户端呈现 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **`benignLog` (良性日志)** | 仅限 `playing` / `seeking` / `rebuffering`（首帧之后） | **静默忽略**：不切状态，记入 debug 日志，依赖底层自愈。 | 0 次（底层自行处理）。 | **不驱逐**任何缓存。 | **无提示**，静默自愈。 |
| **`benignLog` 伪良性（初次建联失败）** | 发生在 `preparing` / `prebuffering`（首帧之前） | **判定为初次连接失败**：转入 `recovering`，尝试重新建立连接。 | 最大 2 次；<br>退避：500ms, 1000ms。 | 不驱逐缓存。 | 保持缓冲遮罩，不弹报错。 |
| **`handshakeReset` (握手被对端关闭)** | `preparing` / `prebuffering` | **轻量重连**：对端 CDN 握手并发冲突或假死，延时退避后发起全新 open。 | 最大 2 次；<br>退避：500ms, 1000ms。 | **不驱逐**缓存（保留 URL，重建 TCP 通道）。 | 若耗尽：提示“握手被对端重置，正在尝试切换视频源”。 |
| **`authForbidden403` (鉴权过期/防盗链)** | 任意阶段 | **刷新直链重试**：强制 `bypassCache: true` 向 `SourceResolver` 重新请求新鲜直链。 | **重试 1 次**；<br>退避：立即（0ms）。 | **仅驱逐 L1 内存直链缓存**；<br>**严禁删除** `SourceBinding` 持久绑定。 | 若重试仍 403：展示错误卡片：<br>“视频源请求被拒绝 (HTTP 403)”<br>提供【重试】、【切换视频源】。 |
| **`notFound404` (资源下架/失效)** | 任意阶段 | **自动故障转移**：向仲裁器上报失效，切至下一保底可用源。 | 0 次（404 立即切源）。 | **仅驱逐 L1 内存直链**；<br>保留 `SourceBinding` 番剧绑定。 | 若所有源耗尽：<br>“视频资源已失效或不存在 (HTTP 404)”<br>提供【换源】、【换词重搜】。 |
| **`connectTimeout` (网络拉流超时)** | `resolving` / `preparing` / `prebuffering` | **指数退避重连**：重新发起网络请求。 | 最大 2 次；<br>退避：500ms, 1000ms。 | **不驱逐**缓存。 | 若耗尽：<br>“网络连接超时，请检查网络设置”<br>提供【点击重试】。 |
| **`serverError5xx` (源站服务端崩溃)** | 任意阶段 | **快速熔断并切源**：触发断路器熔断该源 5 分钟，自动切下一源。 | 重试 1 次 (退避 1000ms)。 | 不驱逐缓存。 | HUD Toast：“当前视频源服务不可用，已自动切换备用源”。 |
| **`decodeCorrupted` (流损坏/解码崩溃)** | `prebuffering` / `playing` | **尝试重启播放内核**：若首帧前崩溃尝试重置 demuxer；中途崩溃记录 pos 后重开。 | 重试 1 次 (退避 500ms)。 | 驱逐当前 L1 直链缓存。 | 若仍失败：<br>“媒体数据解析失败，建议切换视频源”。 |

---

## 四、全链路总时限与总预算表（Budget Matrix）

为防止在网络故障时“FFmpeg 重连 2 秒 + Dart 重试 3 次 + 备用源探测”互相叠加导致用户死等黑屏半分钟以上，必须建立**不可逾越的全局时间预算机制**：

```
[用户触发起播]
   │
   ├─ 1. 直链解析阶段预算 (Resolving Budget): 5.0 秒硬上限
   │     ├─ 单次请求超时: 3.5s
   │     └─ 允许重试: 最多 1 次 (延迟 500ms)
   │
   ├─ 2. 底层建联与首帧出画预算 (Preparing & Prebuffering Budget): 8.0 秒硬上限
   │     ├─ 底层 FFmpeg reconnect_delay_max: 2.0s
   │     ├─ 握手对端 Reset 重连退避: 500ms
   │     └─ 首帧兜底定时器硬上限: 8.0s
   │
   └─ 3. 用户感知端到端总预算 (Total User-Perceived Budget): 13.0 秒硬上限
         └─ 任何场景下，从点击到出画或报错，总耗时严禁超过 13 秒！
```

* **预算实施规则**：
  在 `PlaybackSession.start()` 时启动一个与生命周期绑定的全局秒表 `Stopwatch _sessionClock`。
  无论处于哪一层重试或退避，只要 `_sessionClock.elapsed > 13.0s`，**强制熔断退出 `recovering` 态，直接迁移至 `error` 并呈现清晰操作项**，坚决不让用户在无反馈状态下无限等待。

---

## 五、结构化错误信息清洗标准（Sanitization v2）

废除原先容易误伤的 `text.contains('403')` 代码，改用结构化字段判定：

```dart
String sanitizePlaybackError(BackendError error, {String prefix = '播放失败'}) {
  switch (error.kind) {
    case BackendErrorKind.authForbidden403:
      return '$prefix: 视频源请求被拒绝 (HTTP 403)';

    case BackendErrorKind.notFound404:
      return '$prefix: 视频资源已失效或不存在 (HTTP 404)';

    case BackendErrorKind.serverError5xx:
      final code = error.httpStatus != null ? ' (HTTP ${error.httpStatus})' : '';
      return '$prefix: 视频源服务暂时不可用$code';

    case BackendErrorKind.connectTimeout:
      return '$prefix: 视频拉流超时，请检查网络设置';

    case BackendErrorKind.handshakeReset:
      return '$prefix: 连接被远端服务器重置，建议切换视频源';

    case BackendErrorKind.decodeCorrupted:
      return '$prefix: 媒体数据损坏或格式不兼容，建议切换视频源';

    case BackendErrorKind.formatUnsupported:
      return '$prefix: 当前平台暂不支持该视频编码格式';

    case BackendErrorKind.benignLog:
      return ''; // 良性日志不产生用户可见文案

    case BackendErrorKind.unknown:
    default:
      var msg = error.rawMessage.trim();
      if (msg.length > 40) {
        msg = '${msg.substring(0, 40)}...';
      }
      return msg.isNotEmpty ? '$prefix: $msg' : '$prefix: 发生未知播放异常';
  }
}
```
