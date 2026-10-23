# Kazumi 无头 WebView 媒体流嗅探架构与底层实现技术白皮书

> 本文档深入剖析 **Kazumi** 生产级无头 (Headless) WebView 媒体流嗅探系统的全套设计哲学、前端 JS 劫持探针、生命周期治理机制以及针对 Windows 平台深度魔改的 `flutter-webview-windows` 底层 C++ 引擎，并为 **zakoway** 提供演进路线与工程避坑指南。

---

## 1. 概述与核心挑战

在第三方流媒体与动漫聚合播放类应用中，由于大部分视频资源站不提供公开的标准化 REST API，甚至部署了高强度的前端防护手段，视频流地址解析面临以下核心痛点：

1. **前端高强度混淆与反爬**：页面采用动态 Token 签名计算、混淆 JS 混编、甚至 WASM 模块执行流加密；
2. **多层嵌套沙箱化 iframe**：真实播放器嵌套在多层动态生成的 `<iframe>` 内部，流媒体直链通过动态解析接口异步派发；
3. **Blob URL 伪装与内存切片**：现代播放器（如 Hls.js、DPlayer、ArtPlayer）通过 `fetch`/`XHR` 异步下载切片后，在内存中生成 `blob:http://...` 挂载到 `<video>` 标签，外部独立播放器（如 mpv / ExoPlayer）无法直接消费内存指针；
4. **防盗链与鉴权绑定**：部分直链强校验源站网页的 Cookie 链、动态生成的 `Referer` 或一次性临时防盗链签名；
5. **视口懒加载阻断**：站点给播放器 iframe 注入 `loading="lazy"`，在无真实窗口曝光与滚动的无头模式下，浏览器内核默认拒绝发起加载。

传统基于网络正则爬虫或纯 HTML 静态解析的方案极易失效。Kazumi 针对此建立了一整套**系统级无头浏览器主动渲染、多层探针渗透劫持与底层响应流拦截**的高可用嗅探架构。

---

## 2. 嗅探系统顶层架构设计

Kazumi 将嗅探驱动与上层业务调度彻底解耦，结构自顶向下分为三层：

```
                 ┌─────────────────────────────────────────────────────────┐
                 │               WebViewVideoSourceService                 │
                 │   - 串行排队锁 (_resolveTail)    - 代际取消令牌 (_ResolveRequest) │
                 │   - 实例复用与空白中立态管理     - 统一超时异常仲裁 (15s)       │
                 └────────────────────────────┬────────────────────────────┘
                                              │ 统一调度指令
                 ┌────────────────────────────▼────────────────────────────┐
                 │                VideoWebviewController                   │
                 │   - init()                 - loadUrl(url, legacyMode)   │
                 │   - unloadPage()           - dispose()                  │
                 │   - onVideoURLParser 广播流                             │
                 └───────┬──────────────┬──────────────┬───────────┬───────┘
                         │              │              │           │
            ┌────────────▼──┐    ┌──────▼──────┐  ┌────▼─────┐ ┌───▼───────┐
            │ Windows 平台  │    │  Apple 平台 │  │ Android  │ │  Linux    │
            │(魔改 WebView2)│    │(WebKit 注入)│  │ (InApp)  │ │ (WebkitGTK│
            └───────────────┘    └─────────────┘  └──────────┘ └───────────┘
```

### 2.1 调度服务层 (`WebViewVideoSourceService`)
* **单例长驻复用 (Singleton Reuse)**：
  全局复用单个 WebView 实例，绝对禁止在集数切换或嗅探完成时调用底层的 `dispose()`，杜绝 Windows C++ 底层野指针崩溃（Use-After-Free）与反复拉起进程的 CPU/显存激增；
* **串行排队链条 (`_resolveTail`)**：
  单实例同一时间只执行一个页面的加载与嗅探，利用 `Future.then` 级联队列实现并发互斥，将应用内存锁定在单实例物理上限（~150MB~200MB）；
* **代际取消令牌 (`_ResolveRequest`)**：
  当用户快速切集、切换线路时，立即向旧请求发送取消信号，阻断旧会话并使迟到的媒体回调失效，彻底消除集数串流；
* **空白页中立态打断 (`unloadPage`)**：
  每次任务结束或取消时，强制执行重定向至 `about:blank`，由浏览器原生引擎彻底切断在途网络连接、音视频缓冲与 JS 定时器。

### 2.2 嗅探双模分流策略
规则引擎（`Plugin`）提供 `useLegacyParser` 模式开关：
* **Legacy 规则模式（针对传统套壳/解析接口站）**：
  通过 `MutationObserver` 监听 DOM 树的动态插入和 `src` 属性变化（`attributeFilter: ['src']`），捕获所有新增和变更的 `iframe`。从提取到的 `src` 中，通过 `decodeVideoSource()` 深度解码 query 参数，递归提取真实嵌套的 `.m3u8` 或 `.mp4` 地址；
* **现代网络嗅探模式（针对 Fetch/XHR + Blob 播放器）**：
  放弃在 DOM 树中抓取 `<video src="blob:...">`，转而全面监听底层网络请求、重写前端网络 API，并在必要时抓取原生 `<video>` 真实源。

---

## 3. 跨平台前端（JS/DOM）嗅探技术策略

在 iOS、macOS、Android 以及通用 WebKit 平台中，Kazumi 在文档创建早期（`documentStart` / `DOMContentLoaded`）注入了极具针对性的无感知嗅探探针。

### 3.1 解除 iframe 懒加载死穴 (`removeLazyLoading`)
* **原理**：许多站点为了节约服务器带宽，对播放器 iframe 设置了 `loading="lazy"`。由于无头 WebView 不具备真实的物理视口与滚动渲染，WebKit 内核判定该元素处于“不可见状态”，**永远不会加载 iframe 内容**，直接引发 15s 嗅探超时。
* **解法**：在文档就绪前立即执行：
  ```javascript
  function removeLazyLoading() {
    document.querySelectorAll('iframe[loading="lazy"]').forEach(iframe => {
      iframe.removeAttribute('loading'); // 强行剥除 lazy 属性，强制内核无条件立即加载
    });
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', removeLazyLoading);
  } else {
    removeLazyLoading();
  }
  ```

### 3.2 双重网络原型链劫持 (Fetch & XHR Hooks)
针对通过 Hls.js 将分片转为 `blob:` 的现代播放器，Kazumi 直接深入浏览器底层网络 API 原型链：

#### 1. 劫持 `window.Response.prototype.text` (Fetch API)
```javascript
const _r_text = window.Response.prototype.text;
window.Response.prototype.text = function () {
  return new Promise((resolve, reject) => {
    _r_text.call(this).then((text) => {
      resolve(text);
      // 当现代播放器解析 m3u8 文本内容时捕获
      if (text.trim().startsWith("#EXTM3U")) {
        // this.url 为浏览器跟随 302 重定向后的最终落地直链
        window.flutter_inappwebview.callHandler('VideoBridgeDebug', this.url);
      }
    }).catch(reject);
  });
};
```

#### 2. 劫持 `window.XMLHttpRequest.prototype.open` (XHR)
拦截 XHR 的 `load` 事件，在异步回调中检查 `this.responseText` 是否以 `#EXTM3U` 签名开头；一旦命中，提取 `this.responseURL`（包含重定向后的落地地址）向 Native 回传。

### 3.3 DOM 动态感知与同源 iframe 穿透
* 使用 `MutationObserver` 深度监听页面动态插入的 `IFRAME`、`VIDEO` 和 `SOURCE` 标签；
* **同源 iframe 注入穿透**：当检测到同源 iframe 插入时，主动获取 `iframe.contentWindow`，对其内部的 `Response.prototype.text` 与 `XMLHttpRequest.prototype.open` 再次挂载相同的 Hook，确保多层套壳播放器内部发起的流请求不失联。

### 3.4 反反爬与广告阻断 (ContentBlocker)
* **阻断反调试脚本**：针对挂载了 `devtools-detector.js` 等反爬/反自动化检测器的播放页，通过 ContentBlocker 直接将其阻断，防止页面进入死循环 `debugger` 或跳往 403 页面；
* **全面禁图加速**：拦截所有 `IMAGE` 静态资源下载（Android 开启 `blockNetworkImage: true`），省去所有图片纹理传输与光栅化开销，页面嗅探速度提升 60% 以上；
* **广告秒拒**：拦截 `googleads`、`googlesyndication.com`、`adtrafficquality`、`prestrain.html`，杜绝广告视频被误判为正片流。

### 3.5 宽松的 Web 兼容环境配置
* `mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE`：放行 HTTPS 网页中嵌套的第三方 HTTP 视频切片请求；
* `upgradeKnownHostsToHTTPS: false`：严禁 Chromium 内核将仅支持 HTTP 的切片直链强行升级为 HTTPS 导致 TLS 握手失败；
* `mediaPlaybackRequiresUserGesture: true`：禁止无头网页在后台静默自动外放声音；
* `setPopupWindowPolicy(WebviewPopupWindowPolicy.deny)`：禁止网页弹窗开启新标签页。

---

## 4. 魔改 Windows 插件底层剖析 (`Predidit/flutter-webview-windows`)

官方原版的 `webview_windows` 是基于 WebView2 + DirectComposition + Flutter Texture 的纯 UI 显示组件。Kazumi 作者 fork 并进行了深度 C++ 重构（改动 22 个文件，新增 2300+ 行代码），解决了桌面端性能与网络拦截的核心痛点。

### 4.1 纯无头零纹理开销架构 (`HeadlessWebviewBridge`)
* **痛点**：原版插件为了在 Flutter 窗口中绘制网页，必须初始化 Direct3D 交换链并注册到 `TextureRegistrar`，每帧拷贝显存，CPU/显存消耗巨大；
* **魔改实现**：
  * 新增 C++ 桥接类 `HeadlessWebviewBridge`，底层通过 `CreateWindowEx` 创建一个轻量级的 `HWND_MESSAGE`（仅消息响应窗口，不占用桌面实际窗口资源）；
  * **完全不注册 Flutter Texture，不走 Direct3D 纹理交换**，彻底消除了无头状态下的显存占用与画面光栅化开销。

### 4.2 消除 Win10 桌面透明伪影与鼠标穿透（DirectComposition 视觉偏移）
这是 Windows 桌面端无头 WebView 极其精妙的一项底层修复（commit `9b9aabb` / `d9bbeab`）：

* **背景矛盾**：
  1. 若将 WebView2 的视口尺寸（Bounds）设为 0 或不可见，Chromium 内核会挂起渲染管线，导致许多站点的视频初始化逻辑与 GPU 加速探测停止运行；因此视口必须保持标准尺寸（如 1280x720）；
  2. 若将视口直接设为负坐标（如 `Bounds = {-1280, -720}`），在 Windows 10 DWM（桌面窗口管理器）下会出现系统级 Bug：**桌面上残留一个 1280x720 的透明矩形伪影，并且强行拦截/劫持用户的鼠标点击！**
* **魔改底层解法（C++ `webview.cc` 中 `CreateSurface`）**：
  ```cpp
  // 1. 保持 WebView2 控制器的 Bounds 为正常屏幕矩形，使 GPU 渲染管线保持完整激活
  RECT bounds;
  bounds.left = 0; bounds.top = 0;
  bounds.right = 1280; bounds.bottom = 720;
  webview_controller_->put_Bounds(bounds);

  // 2. 核心：在 DirectComposition 合成树层面，通过 IVisual::Offset 将根节点推移至屏幕外 -32000 像素！
  surface_->put_Offset({-32000.0f, -32000.0f, 0.0f});
  ```
  通过把合成根 Visual 平移到屏幕物理极限之外，Windows DWM 绝不会将内容绘制到桌面，彻底消除了 Win10 透明残留与鼠标穿透问题，同时 Chromium 内部依然感知自己在正常桌面视口中渲染。

### 4.3 原生响应阶段网络拦截 (`ICoreWebView2_2::add_WebResourceResponseReceived`)
上游通用 WebView 只能在请求发起前做拦截，无法感知服务器最终下发的 Response 状态。魔改版接入了 WebView2 的底层响应回调，实现了双轨嗅探：

```
                            WebView2 底层响应到达
                                      │
                     ┌────────────────┴────────────────┐
                     ▼                                 ▼
           1. 媒体元数据检测                  2. 内容签名异步探测
        (Content-Type / Disposition)             (Peek 8KB 流)
                     │                                 │
                     ▼                                 ▼
           命中 video/* 或视频文件名           前缀匹配 #EXTM3U 签名
                     │                                 │
                     ▼                                 ▼
            [onVideoSourceLoaded]              [onM3USourceLoaded]
            (0 内存消耗，瞬时返回)               (通杀任何防盗链与伪装流)
```

#### (1) MP4/MKV 零开销元数据探测
* 读取响应头 `Content-Type` 是否包含 `video/`；
* **自制 Content-Disposition 规范解析器 (`content_disposition.cc`)**：
  完整支持 RFC 2616 `filename` 与 RFC 5987 `filename*`（带字符集和 URL 解码），支持转义引号与 Percent-Decode，检测文件名是否以 `.mp4`、`.mkv` 或 `.mknvideo` 结尾；
* **核心优势**：只要命中视频响应头，直接返回直链，**完全不需要读取数百 MB 的视频响应流 Body**，零内存占用。

#### (2) 突破伪装的 M3U8 流签名异步探测
* 针对伪装成 `.png`、`.jpg` 或无后缀 API 的 m3u8，魔改版通过 `IStream` **仅异步读取流的前 8192 字节（8KB）**；
* 只要检测到以 `#EXTM3U` 签名开头，即刻判定为 HLS 视频源并上报给 Dart 层的 `onM3USourceLoaded`；读取完毕立即关闭流，规避了大文件内存泄漏。

### 4.4 引用计数驱动的 Environment 动态重置 (`WebViewInstanceTracker`)
* **痛点**：WebView2 的 `CoreWebView2Environment` 属于进程单例，初始化时若指定了 `--proxy-server` 参数，运行期间无法修改；一旦用户在设置中切换代理，旧 WebView2 无法热更新；
* **魔改实现**：
  * C++ 层新增 `disposeEnvironment` 方法清理全部实例并重置 `webview_host_`；
  * Dart 层设计全局引用计数器 `WebViewInstanceTracker`：创建时 `register()`，销毁时 `unregister()`；
  * 当活跃实例数归零（`_activeInstanceCount == 0`）时，**自动触发 `disposeEnvironment()` 彻底释放底层的 `CoreWebView2Environment`**，下一次嗅探即可挂载最新代理参数。

### 4.5 Cookie 管理器对接 (`GetCookies`)
* 在 C++ 层通过 `ICoreWebView2CookieManager` 实现 `GetCookies(url)`；
* 枚举提取 Cookie 列表并格式化为标准 HTTP 请求头（`name=value; name2=value2`）；
* 嗅探到直链后直接回填给 Dart 层并注入给外部播放器（mpv），解决防盗链 403 难题。

---

## 5. 核心避坑指南与反模式对比

在流媒体嗅探系统的落地演进中，以下反模式需严格杜绝：

| 反模式 (Anti-Pattern) | 机制缺陷与后果 | 工业级正确解法 (Kazumi) |
| :--- | :--- | :--- |
| **在 `shouldInterceptRequest` 抢跑秒杀页面** | 在网络请求发出前（Pre-request）截获并立即导向 `about:blank`，导致浏览器内核的 302 跟随被强行掐断，捕获到的是中间跳板且丢失子 iframe 的 `Referer`。 | `shouldInterceptRequest` 仅用于 0ms 秒拒静态资源；流的捕获交由响应到达后（Response-Phase）的 C++ 回调或 JS Hook 提取。 |
| **全量进行无差别 HTTP `HEAD` 预检** | 嗅探到直链后强制用 HTTP Client 发 HEAD 探测 302。流媒体 CDN/自建 VOD 普遍屏蔽 HEAD，导致死等直至 1.5 秒超时。 | 浏览器内部与 mpv 底层原生支持 302 跟随。绝不无差别发 HEAD；如需预检，采用 `GET + Range: bytes=0-0` 轻量探测，20ms 瞬间放行。 |
| **嗅探未命中时直接抛出异常断流** | 对纯 REST API 源（如次元城）或需要前端手势交互才能起播的页面，无头嗅探必然未命中，直接抛异常导致播放黑屏。 | 架构上遵循**责任链容灾降级模式**：无头嗅探未命中时，自动平滑降级回退执行本地源自身的 `s.resolve()` 原生解析。 |
| **无熔断的串行队列排队** | 选集或切线发生时，旧会话依然在后台跑完整套网络加载才让位，新会话被动等待 3~4 秒。 | 引入 `_activeCancelToken`，新任务到达瞬间主动触发取消信号并导向 `about:blank`，旧会话瞬间退出，新任务零等待插队。 |
| **针对域名与端口进行硬编码特判** | 针对特定源（如带 `:8088` 端口、特定网盘域名）写死 `if-else` 分流逻辑，规则极易失效且污染架构。 | 依托 W3C 标准协议机制：使用标准 `Range: bytes=0-0` 状态码探测或播放器原生多态解决，绝不在通用层沉淀私有特判。 |

---

## 6. Zakoway 落地演进路线图

基于对 Kazumi 方案的完整吸收，zakoway 确立了如下分阶段演进策略：

```
┌────────────────────────────────────────────────────────────────────────┐
│                        阶段一：纯上层能力补强 (已完成)                  │
│  - 强制剥除 iframe[loading="lazy"]，保障无头环境下子播放器必定加载      │
│  - 注入 Fetch/XHR 原型链 Hook 与 MutationObserver DOM 动态感知        │
│  - 自动提取并注入防盗链 Cookie (CookieManager)                         │
│  - 引入 _activeCancelToken 主动快速熔断排队会话                        │
│  - 采用标准 GET Range: bytes=0-0 轻量探测替代高危 HEAD 预检 (400ms)    │
│  - 建立责任链多态容灾回退机制 (未命中自动降级原生 s.resolve)           │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │ 下一步演进 (按需推进)
┌───────────────────────────────────▼────────────────────────────────────┐
│                  阶段二：Windows 专属底层引擎替换                      │
│  - 引入经过验证的 Predidit/flutter-webview-windows 魔改仓库           │
│  - 建立 IVideoSnifferPlatform 跨平台工厂 (移动端 InApp / 桌面端魔改)   │
│  - 启用 DirectComposition -32000px 离屏位移 (规避 Win10 透明残留)     │
│  - 接入 ICoreWebView2_2 底层响应拦截 (RFC 5987 元数据 + 8KB 流签名)    │
│  - 接入 WebViewInstanceTracker 引用计数与动态代理管理                  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 7. 总结

Kazumi 的无头 WebView 嗅探系统之所以能在极其苛刻的第三方动漫网络环境下保持极高的成功率与稳定性，关键在于**全链路技术闭环**：

1. **业务层**通过单例长驻、代际令牌与快速熔断解决生命周期抖动；
2. **探针层**通过原型链 Hook、懒加载剥除与 DOM 深度感知穿透前端混淆；
3. **原生层**在 Windows 平台上跳出 Flutter 既有插件的束缚，通过 DirectComposition 离屏位移规避桌面穿透，并在 Chromium 响应阶段实现零内存开销的视频元数据提取与 8KB 签名探测。

该架构为现代多端聚合流媒体客户端提供了一套高可靠、低开销的标准化解决方案。
