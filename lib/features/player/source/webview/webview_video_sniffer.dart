import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/utils/media_url_resolver.dart';
import 'webview_sniffer_script.dart';

const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

/// 系统级通用无头 (Headless) 视频流嗅探器
///
/// 遵循成熟嗅探器工业级生命周期管理规范 (对齐 Kazumi 生产验证架构)：
/// 1. 【单例长驻复用】：全局懒加载保持单个 HeadlessInAppWebView 实例，彻底消除反复 dispose() 触发的 Windows C++ 野指针崩溃 (Use-After-Free)；
/// 2. 【空白页导航打断】：切集或任务结束时，通过 loadUrl('about:blank') 由浏览器原生中断所有在途网络请求与 JS 脚本执行；
/// 3. 【单线串行排队锁】：通过 _queueTail 异步链条保证多任务严格串行，严禁多页面后台并发打架，内存锁定在单实例物理上限 (~200MB)；
/// 4. 【代际防串令牌】：基于递增的 sessionId 严格校验会话，迟到的旧媒体回调直接丢弃，杜绝集数串流；
/// 5. 【0ms 静态秒拒】：在 shouldInterceptRequest 中秒拒 CSS、图片、字体与广告追踪，极大提升页面加载速度并节省带宽。
class WebviewVideoSniffer {
  WebviewVideoSniffer._();

  static final WebviewVideoSniffer instance = WebviewVideoSniffer._();

  static bool get isPlatformSupported {
    if (kIsWeb) return false;
    // 单测运行环境无底层原生 WebView2 宿主环境，自动跳过
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    // 明确排除 Linux 平台
    if (Platform.isLinux) return false;
    return Platform.isWindows ||
        Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS;
  }

  // ===== 单例复用与会话代际状态 =====
  HeadlessInAppWebView? _headless;
  InAppWebViewController? _controller;
  Completer<void>? _initCompleter;

  // 串行队列尾部，确保切集与嗅探严格按序串行推进
  Future<void> _queueTail = Future<void>.value();

  // 当前活跃会话令牌与回调守卫
  int _sessionCounter = 0;
  int _activeSessionId = 0;
  Completer<SourceResolveResult?>? _activeCompleter;
  String _activePageUrl = '';

  /// 懒加载初始化全局唯一长驻无头 WebView 实例
  Future<void> _ensureInitialized() async {
    if (_headless != null && _controller != null) return;
    if (_initCompleter != null) return _initCompleter!.future;

    _initCompleter = Completer<void>();
    debugPrint('[WebviewSniffer] 初始化全局唯一长驻无头 WebView 实例 (单例长驻模式)...');

    try {
      _headless = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri('about:blank')),
        initialUserScripts: UnmodifiableListView([
          UserScript(
            source: kWebviewSnifferScript,
            injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
            forMainFrameOnly: false,
          ),
        ]),
        initialSettings: InAppWebViewSettings(
          userAgent: _kDefaultUserAgent,
          javaScriptEnabled: true,
          mediaPlaybackRequiresUserGesture: false,
          blockNetworkImage: true, // 核心优化：完全阻断图片加载
          loadsImagesAutomatically: false,
          allowsInlineMediaPlayback: true,
          useShouldInterceptRequest: true,
        ),
        onWebViewCreated: (controller) {
          _controller = controller;
          // 注册通用 JS 深度嗅探回调
          controller.addJavaScriptHandler(
            handlerName: 'onStreamCaptured',
            callback: (args) {
              if (args.isEmpty) return;
              final dynamic payload = args.first;
              if (payload is Map) {
                final streamUrl = payload['url']?.toString() ?? '';
                final format = payload['format']?.toString() ?? 'hls';
                final referer = payload['referer']?.toString() ?? _activePageUrl;
                final ua = payload['userAgent']?.toString() ?? _kDefaultUserAgent;
                _onCaptured(streamUrl, format: format, referer: referer, userAgent: ua, source: 'JS Hook');
              }
            },
          );
        },
        shouldInterceptRequest: (controller, request) async {
          final urlStr = request.url.toString();
          if (urlStr.isEmpty) return null;

          // 1. 0ms 秒拒静态样式、图片、字体、埋点广告
          if (_shouldBlockResource(urlStr)) {
            return WebResourceResponse(
              contentType: 'text/plain',
              statusCode: 200,
              reasonPhrase: 'OK',
              data: Uint8List(0),
            );
          }

          // 2. 深度嗅探：检查是否为视频媒体直链 (网络层捕获)
          // 特殊处理说明：这里捕获后严禁返回 204 No Content，必须返回 null 允许浏览器网络层正常请求与跟随 302 重定向；
          // 嗅探完成后由生命周期回调导向 about:blank 自然中断在途连接，避免切断重定向链路。
          if (_isMediaStreamUrl(urlStr)) {
            final lower = urlStr.toLowerCase();
            final format = lower.contains('.m3u8') ? 'hls' : 'mp4';
            final reqHeaders = request.headers;
            final referer = reqHeaders?['Referer'] ??
                reqHeaders?['referer'] ??
                _activePageUrl;
            final ua = reqHeaders?['User-Agent'] ??
                reqHeaders?['user-agent'] ??
                _kDefaultUserAgent;
            _onCaptured(
              urlStr,
              format: format,
              referer: referer,
              userAgent: ua,
              source: 'shouldInterceptRequest',
            );
          }

          return null;
        },
        onReceivedError: (controller, request, error) {
          // 忽略常见已拦截请求报错
        },
      );

      await _headless!.run();
      _initCompleter!.complete();
    } catch (e) {
      debugPrint('[WebviewSniffer] 初始化无头 WebView 失败: $e');
      _initCompleter!.completeError(e);
      _initCompleter = null;
      rethrow;
    }
  }

  void _onCaptured(
    String streamUrl, {
    required String format,
    required String referer,
    required String userAgent,
    required String source,
  }) {
    if (streamUrl.isEmpty) return;
    final completer = _activeCompleter;
    if (completer != null && !completer.isCompleted) {
      debugPrint('[WebviewSniffer] [$source] 成功捕获直链 (Session: $_activeSessionId): $streamUrl');
      completer.complete(SourceResolveResult(
        url: streamUrl,
        format: format,
        headers: {
          'User-Agent': userAgent,
          if (referer.isNotEmpty) 'Referer': referer,
        },
      ));
    }
  }

  /// 异步嗅探目标播放网页中的视频真实流直链 (排队串行且具备代际防串安全保护)
  Future<SourceResolveResult?> sniff(
    String pageUrl, {
    Duration timeout = const Duration(seconds: 15),
    Map<String, String>? customHeaders,
  }) async {
    if (!isPlatformSupported) {
      debugPrint('[WebviewSniffer] 当前平台不支持系统级 WebView 嗅探');
      return null;
    }

    final trimmedUrl = pageUrl.trim();
    if (trimmedUrl.isEmpty) return null;

    final taskCompleter = Completer<SourceResolveResult?>();

    // 加入串行队列锁：等待前序会话清理中立态后按序推进
    _queueTail = _queueTail.then((_) async {
      try {
        final result = await _executeSniff(
          trimmedUrl,
          timeout: timeout,
          customHeaders: customHeaders,
        );
        if (result != null && result.url.isNotEmpty) {
          final resolved = await MediaUrlResolver.resolveRedirects(result);
          taskCompleter.complete(resolved);
        } else {
          taskCompleter.complete(result);
        }
      } catch (e) {
        taskCompleter.complete(null);
      }
    }, onError: (_) {
      taskCompleter.complete(null);
    });

    return taskCompleter.future;
  }

  /// 内部单次嗅探执行逻辑
  Future<SourceResolveResult?> _executeSniff(
    String targetUrl, {
    required Duration timeout,
    Map<String, String>? customHeaders,
  }) async {
    await _ensureInitialized();
    final controller = _controller;
    if (controller == null) return null;

    // 1. 会话代际自增：使之前所有残留迟到回调彻底失效
    final sessionId = ++_sessionCounter;
    _activeSessionId = sessionId;
    _activePageUrl = targetUrl;
    final completer = Completer<SourceResolveResult?>();
    _activeCompleter = completer;

    debugPrint('[WebviewSniffer] [Session: $sessionId] 开始无头嗅探: $targetUrl');

    try {
      // 2. 先重定向到 about:blank 空白页，由浏览器引擎原生切断所有上级在途连接与 JS 脚本
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));

      // 3. 正式加载目标番剧播放页面
      await controller.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(targetUrl),
          headers: customHeaders,
        ),
      );

      // 4. 等待捕获或超时
      final result = await completer.future.timeout(
        timeout,
        onTimeout: () {
          debugPrint('[WebviewSniffer] [Session: $sessionId] 嗅探超时 (${timeout.inSeconds}s)');
          return null;
        },
      );

      return result;
    } catch (e) {
      debugPrint('[WebviewSniffer] [Session: $sessionId] 嗅探异常: $e');
      return null;
    } finally {
      // 5. 核心生命周期规范：绝对不调用 dispose()！
      // 仅重置当前活跃会话句柄并导向空白中立态，保持单例在后台安全驻留以供下次秒开复用
      if (_activeSessionId == sessionId) {
        _activeCompleter = null;
        try {
          await controller.loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')));
          debugPrint('[WebviewSniffer] [Session: $sessionId] 嗅探结束，已导向空白中立态 (单例安全驻留)');
        } catch (_) {}
      }
    }
  }

  static bool _shouldBlockResource(String urlStr) {
    if (urlStr.isEmpty) return false;
    final lower = urlStr.toLowerCase();

    // 1. 过滤 CSS 样式文件
    if (lower.endsWith('.css') || lower.contains('.css?')) return true;

    // 2. 过滤图像与图标文件
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.ico') ||
        lower.endsWith('.svg') ||
        lower.contains('.png?') ||
        lower.contains('.jpg?') ||
        lower.contains('.jpeg?')) {
      return true;
    }

    // 3. 过滤网页字体文件
    if (lower.endsWith('.woff') ||
        lower.endsWith('.woff2') ||
        lower.endsWith('.ttf') ||
        lower.endsWith('.otf') ||
        lower.endsWith('.eot')) {
      return true;
    }

    // 4. 过滤统计上报、回放录制与广告脚本
    if (lower.contains('googleads') ||
        lower.contains('googlesyndication') ||
        lower.contains('doubleclick') ||
        lower.contains('openpanel') ||
        lower.contains('op1.js') ||
        lower.contains('op1-replay.js') ||
        lower.contains('/api/op/track') ||
        lower.contains('analytics') ||
        lower.contains('clarity.ms') ||
        lower.contains('hm.baidu.com') ||
        lower.contains('cnzz.com')) {
      return true;
    }

    return false;
  }

  static bool _isMediaStreamUrl(String url) {
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    if (_shouldBlockResource(url)) return false;

    // 排除网页自身 HTML
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return false;

    // 常见标准视频与音频流/伪装流扩展名识别
    return lower.contains('.m3u8') ||
        lower.contains('.mp4') ||
        lower.contains('.mp3') ||
        lower.contains('.m4a') ||
        lower.contains('.flv') ||
        lower.contains('.webm');
  }
}
