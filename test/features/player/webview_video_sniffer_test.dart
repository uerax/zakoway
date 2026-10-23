import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/sources/video_source.dart';
import 'package:zakoway/features/player/source/webview/webview_sniffer_script.dart';
import 'package:zakoway/features/player/source/webview/webview_video_sniffer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('验证 WebviewVideoSniffer 平台支持与环境判定', () {
    // 单测运行环境 (FLUTTER_TEST) 自动返回 false，防止单测触发原生宿主 Channel
    expect(WebviewVideoSniffer.isPlatformSupported, isFalse);
  });

  test('验证 kWebviewSnifferScript 通用注入脚本包含全套深度拦截特征', () {
    // 1. window.fetch 劫持与无后缀 Content-Type / #EXTM3U 深度探测、302 重定向及 mp3/audio 音频流兼容
    expect(kWebviewSnifferScript, contains('window.fetch'));
    expect(kWebviewSnifferScript, contains('response.url'));
    expect(kWebviewSnifferScript, contains('#EXTM3U'));
    expect(kWebviewSnifferScript, contains('application/x-mpegurl'));
    expect(kWebviewSnifferScript, contains('video/'));
    expect(kWebviewSnifferScript, contains('audio/'));
    expect(kWebviewSnifferScript, contains('.mp3'));

    // 2. XMLHttpRequest 劫持与 302 重定向落地直链及 mp3 兼容
    expect(kWebviewSnifferScript, contains('XMLHttpRequest.prototype.open'));
    expect(kWebviewSnifferScript, contains('XMLHttpRequest.prototype.send'));
    expect(kWebviewSnifferScript, contains('this.responseURL'));
    expect(kWebviewSnifferScript, contains('getResponseHeader'));

    // 3. HTMLMediaElement.prototype.src 劫持与相对路径 URL 规范化
    expect(kWebviewSnifferScript, contains('HTMLMediaElement.prototype'));
    expect(kWebviewSnifferScript, contains('new URL'));
    expect(kWebviewSnifferScript, contains('onStreamCaptured'));

    // 4. 广告、反调试与追踪域名过滤
    expect(kWebviewSnifferScript, contains('googleads'));
    expect(kWebviewSnifferScript, contains('prestrain'));
    expect(kWebviewSnifferScript, contains('doubleclick'));
    expect(kWebviewSnifferScript, contains('devtools-detector'));

    // 5. 关键增强：强制解除 iframe 懒加载、DOM 节点动态感知与套壳 query 参数解码
    expect(kWebviewSnifferScript, contains('removeLazyLoading'));
    expect(kWebviewSnifferScript, contains('loading="lazy"'));
    expect(kWebviewSnifferScript, contains('MutationObserver'));
    expect(kWebviewSnifferScript, contains('decodeQueryVideoUrl'));
  });

  test('验证 VideoSource 基类包含 preferWebviewSniff 属性定义', () {
    final mockSource = _TestMockSource();
    expect(mockSource.preferWebviewSniff, isA<bool>());
  });
}

class _TestMockSource extends VideoSource {
  @override
  String get id => 'mock';
  @override
  String get name => 'Mock';
  @override
  String get version => '1.0';
  @override
  String get description => 'Mock Source';

  @override
  Future<List<SourceSearchResult>> search(String keyword) async => [];
  @override
  Future<List<SourceChapterRoad>> chapters(String animeUrl) async => [];
  @override
  Future<SourceResolveResult> resolve(String episodeUrl) async =>
      const SourceResolveResult(url: 'https://test.com/video.mp4');
}
