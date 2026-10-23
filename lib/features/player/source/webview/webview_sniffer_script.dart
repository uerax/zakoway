/// 深度视频流嗅探注入脚本 (At Document Start)
///
/// 遵循行业通用 WebExtension / 猫抓及 Kazumi 生产验证的成熟嗅探规范：
/// 1. 【解除懒加载】：强制移除 iframe[loading="lazy"]，避免无头无渲染模式下视口外 iframe 永远不加载导致超时；
/// 2. 【双重网络劫持】：劫持 window.fetch 与 XMLHttpRequest，识别响应头 Content-Type 及响应体 #EXTM3U 特征；
/// 3. 【套壳 iframe 递归】：递归解析 iframe src 中的 query 视频参数 (如 ?url=...m3u8/.mp4)；
/// 4. 【DOM 动态感知】：MutationObserver 深度监听动态新增的 iframe、video 与 source 节点；
/// 5. 【媒体原型劫持】：劫持 HTMLMediaElement (video/audio) 的 src 属性赋值；
/// 6. 【安全降噪】：过滤反调试脚本 (devtools-detector)、常见广告、统计追踪与垃圾请求。
const String kWebviewSnifferScript = r'''
(function() {
  if (window.__zakoway_sniffer_installed__) return;
  window.__zakoway_sniffer_installed__ = true;

  const AD_DOMAINS = [
    'googleads', 'googlesyndication', 'doubleclick', 'analytics',
    'prestrain', 'adtrafficquality', 'hm.baidu.com', 'cnzz.com',
    'statcounter', 'clarity.ms', 'devtools-detector'
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

  // 0. 关键特性：强制解除 iframe 懒加载 (无头无视口滚动模式下保障播放器 iframe 必定加载)
  function removeLazyLoading() {
    try {
      var lazyIframes = document.querySelectorAll('iframe[loading="lazy"]');
      for (var i = 0; i < lazyIframes.length; i++) {
        lazyIframes[i].removeAttribute('loading');
      }
    } catch (e) {}
  }

  // 从 iframe src 中递归解码被封装在 query 参数中的真实视频直链 (兼容常见套壳播放器与解析接口)
  function decodeQueryVideoUrl(rawUrl) {
    if (!rawUrl || typeof rawUrl !== 'string') return null;
    try {
      var decoded = decodeURIComponent(rawUrl);
      var reg = /(https?:\/\/[^\s"'<>]+\.(?:m3u8|mp4|m4a|mp3)(?:\?[^\s"'<>]*)?)/i;
      var match = decoded.match(reg);
      if (match && match[1]) {
        return match[1];
      }
    } catch (e) {}
    return null;
  }

  function processIframe(iframe) {
    if (!iframe) return;
    try {
      var src = iframe.getAttribute('src');
      if (src) {
        var videoUrl = decodeQueryVideoUrl(src);
        if (videoUrl) {
          reportStream(videoUrl);
        }
      }
    } catch (e) {}
  }

  function processVideoNode(node) {
    if (!node) return;
    try {
      if (node.nodeName === 'VIDEO') {
        try { node.play(); } catch (e) {}
        var src = node.getAttribute('src') || node.currentSrc;
        if (src && !src.startsWith('blob:') && !isAdOrTracker(src)) {
          reportStream(new URL(src, window.location.href).href);
        }
        var sources = node.getElementsByTagName('source');
        for (var i = 0; i < sources.length; i++) {
          var sSrc = sources[i].getAttribute('src');
          if (sSrc && !sSrc.startsWith('blob:') && !isAdOrTracker(sSrc)) {
            reportStream(new URL(sSrc, window.location.href).href);
          }
        }
      }
    } catch (e) {}
  }

  // DOM 变化与节点插入深度监听 (覆盖动态渲染的 iframe 与 video 节点)
  try {
    var domObserver = new MutationObserver(function(mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var m = mutations[i];
        if (m.type === 'attributes') {
          if (m.target.nodeName === 'IFRAME') {
            processIframe(m.target);
          } else if (m.target.nodeName === 'VIDEO' || m.target.nodeName === 'SOURCE') {
            processVideoNode(m.target.nodeName === 'VIDEO' ? m.target : m.target.parentElement);
          }
        } else if (m.addedNodes) {
          for (var j = 0; j < m.addedNodes.length; j++) {
            var n = m.addedNodes[j];
            if (n.nodeName === 'IFRAME') {
              processIframe(n);
            } else if (n.nodeName === 'VIDEO') {
              processVideoNode(n);
            } else if (n.querySelectorAll) {
              var iframes = n.querySelectorAll('iframe');
              for (var k = 0; k < iframes.length; k++) processIframe(iframes[k]);
              var videos = n.querySelectorAll('video');
              for (var v = 0; v < videos.length; v++) processVideoNode(videos[v]);
            }
          }
        }
      }
    });

    function initDomSensors() {
      removeLazyLoading();
      document.querySelectorAll('iframe').forEach(processIframe);
      document.querySelectorAll('video').forEach(processVideoNode);
      if (document.documentElement) {
        domObserver.observe(document.documentElement, {
          childList: true,
          subtree: true,
          attributes: true,
          attributeFilter: ['src', 'loading']
        });
      }
    }

    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', initDomSensors);
    } else {
      initDomSensors();
    }
  } catch (e) {}

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
