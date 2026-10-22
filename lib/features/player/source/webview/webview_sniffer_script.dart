/// 深度视频流嗅探注入脚本 (At Document Start)
///
/// 遵循行业通用 WebExtension / 猫抓成熟嗅探规范：
/// 1. 劫持 window.fetch 与 XMLHttpRequest，直接读取响应头 Content-Type 及响应体 #EXTM3U 特征；
/// 2. 劫持 HTMLMediaElement (video/audio) 的 src 属性赋值；
/// 3. 过滤常见广告、统计追踪与垃圾请求；
/// 4. 识别并捕获视频流真实直链，通过 flutter_inappwebview JavaScriptHandler 抛回 Dart 层。
const String kWebviewSnifferScript = r'''
(function() {
  if (window.__zakoway_sniffer_installed__) return;
  window.__zakoway_sniffer_installed__ = true;

  const AD_DOMAINS = [
    'googleads', 'googlesyndication', 'doubleclick', 'analytics',
    'prestrain', 'adtrafficquality', 'hm.baidu.com', 'cnzz.com',
    'statcounter', 'clarity.ms'
  ];

  function isAdOrTracker(url) {
    if (!url) return true;
    const lower = url.toLowerCase();
    for (let i = 0; i < AD_DOMAINS.length; i++) {
      if (lower.indexOf(AD_DOMAINS[i]) !== -1) return true;
    }
    return false;
  }

  function reportStream(url, format, referer) {
    if (!url || typeof url !== 'string') return;
    if (isAdOrTracker(url)) return;
    if (url.startsWith('blob:')) return; // blob 之前必有 fetch/xhr 请求了实际 m3u8

    const payload = {
      url: url,
      format: format || (url.toLowerCase().indexOf('.m3u8') !== -1 ? 'hls' : 'mp4'),
      referer: referer || window.location.href,
      userAgent: navigator.userAgent
    };

    if (window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
      window.flutter_inappwebview.callHandler('onStreamCaptured', payload);
    }
  }

  // 1. 劫持 window.fetch
  if (window.fetch) {
    const originalFetch = window.fetch;
    window.fetch = async function(...args) {
      const response = await originalFetch.apply(this, args);
      try {
        const reqUrl = (args[0] && typeof args[0] === 'string') ? args[0] : (args[0] && args[0].url ? args[0].url : '');
        // 关键特性：优先采用跟随 302 重定向后的最终落地直链 (response.url)
        const targetUrl = (response && response.url) ? response.url : reqUrl;
        if (targetUrl && !isAdOrTracker(targetUrl)) {
          const lowerUrl = targetUrl.toLowerCase();
          const lowerReq = (reqUrl || '').toLowerCase();
          if (lowerUrl.indexOf('.m3u8') !== -1 || lowerReq.indexOf('.m3u8') !== -1) {
            reportStream(targetUrl, 'hls');
          } else if (lowerUrl.indexOf('.mp4') !== -1 || lowerReq.indexOf('.mp4') !== -1 ||
                     lowerUrl.indexOf('.mp3') !== -1 || lowerReq.indexOf('.mp3') !== -1 ||
                     lowerUrl.indexOf('.m4a') !== -1 || lowerReq.indexOf('.m4a') !== -1) {
            reportStream(targetUrl, 'mp4');
          } else {
            // 无后缀流嗅探：克隆响应并探测 Content-Type 与 #EXTM3U (兼容 video/ 与 audio/ 伪装流)
            const clone = response.clone();
            const ct = (clone.headers.get('content-type') || '').toLowerCase();
            if (ct.indexOf('mpegurl') !== -1 || ct.indexOf('application/x-mpegurl') !== -1) {
              reportStream(targetUrl, 'hls');
            } else if (ct.indexOf('video/') !== -1 || ct.indexOf('audio/') !== -1) {
              reportStream(targetUrl, 'mp4');
            } else {
              clone.text().then(text => {
                if (text && text.trim().startsWith('#EXTM3U')) {
                  reportStream(targetUrl, 'hls');
                }
              }).catch(() => {});
            }
          }
        }
      } catch (e) {}
      return response;
    };
  }

  // 2. 劫持 XMLHttpRequest
  if (window.XMLHttpRequest) {
    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function(method, url, ...rest) {
      this.__reqUrl = url;
      return originalOpen.apply(this, [method, url, ...rest]);
    };

    XMLHttpRequest.prototype.send = function(...args) {
      this.addEventListener('load', function() {
        try {
          const reqUrl = this.__reqUrl;
          // 关键特性：优先采用跟随 302 重定向后的最终落地直链 (this.responseURL)
          const targetUrl = this.responseURL || reqUrl;
          if (targetUrl && !isAdOrTracker(targetUrl)) {
            const lowerUrl = targetUrl.toLowerCase();
            const lowerReq = (reqUrl || '').toLowerCase();
            if (lowerUrl.indexOf('.m3u8') !== -1 || lowerReq.indexOf('.m3u8') !== -1) {
              reportStream(targetUrl, 'hls');
            } else if (lowerUrl.indexOf('.mp4') !== -1 || lowerReq.indexOf('.mp4') !== -1 ||
                       lowerUrl.indexOf('.mp3') !== -1 || lowerReq.indexOf('.mp3') !== -1 ||
                       lowerUrl.indexOf('.m4a') !== -1 || lowerReq.indexOf('.m4a') !== -1) {
              reportStream(targetUrl, 'mp4');
            } else {
              const ct = (this.getResponseHeader('content-type') || '').toLowerCase();
              if (ct.indexOf('mpegurl') !== -1 || ct.indexOf('application/x-mpegurl') !== -1) {
                reportStream(targetUrl, 'hls');
              } else if (ct.indexOf('video/') !== -1 || ct.indexOf('audio/') !== -1) {
                reportStream(targetUrl, 'mp4');
              } else if (this.responseText && this.responseText.trim().startsWith('#EXTM3U')) {
                reportStream(targetUrl, 'hls');
              }
            }
          }
        } catch (e) {}
      });
      return originalSend.apply(this, args);
    };
  }

  // 3. 劫持 HTMLMediaElement.prototype.src 属性定义
  try {
    const videoProto = HTMLMediaElement.prototype;
    const srcDescriptor = Object.getOwnPropertyDescriptor(videoProto, 'src');
    if (srcDescriptor && srcDescriptor.set) {
      const originalSet = srcDescriptor.set;
      Object.defineProperty(videoProto, 'src', {
        set: function(val) {
          if (val && typeof val === 'string') {
            let resolvedUrl = val;
            try {
              resolvedUrl = new URL(val, window.location.href).href;
            } catch (e) {}
            const lower = resolvedUrl.toLowerCase();
            if (lower.indexOf('.m3u8') !== -1) {
              reportStream(resolvedUrl, 'hls');
            } else if (lower.indexOf('.mp4') !== -1 ||
                       lower.indexOf('.mp3') !== -1 ||
                       lower.indexOf('.m4a') !== -1 ||
                       lower.startsWith('http')) {
              reportStream(resolvedUrl, 'mp4');
            }
          }
          return originalSet.call(this, val);
        },
        get: srcDescriptor.get,
        configurable: true
      });
    }
  } catch (e) {}
})();
''';
