import 'package:dio/dio.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/server/animaku_server_client.dart';
import 'package:zakoway/features/player/source/sources/anime1_source.dart';
import 'package:zakoway/features/player/source/sources/animoe_source.dart';
import 'package:zakoway/features/player/source/sources/cycani_source.dart';
import 'package:zakoway/features/player/source/sources/girigiri_source.dart';
import 'package:zakoway/features/player/source/sources/gugu_source.dart';
import 'package:zakoway/features/player/source/sources/libvio_source.dart';
import 'package:zakoway/features/player/source/sources/lzizy_source.dart';
import 'package:zakoway/features/player/source/sources/mifun_source.dart';
import 'package:zakoway/features/player/source/sources/moonci_source.dart';
import 'package:zakoway/features/player/source/sources/mxdm_source.dart';
import 'package:zakoway/features/player/source/sources/neosek_source.dart';
import 'package:zakoway/features/player/source/sources/omofun_source.dart';
import 'package:zakoway/features/player/source/sources/sorani_source.dart';
import 'package:zakoway/features/player/source/sources/tvtfun_source.dart';
import 'package:zakoway/features/player/source/sources/video_source.dart';
import 'package:zakoway/features/player/source/sources/xifan_next_source.dart';
import 'package:zakoway/features/player/source/webview/webview_video_sniffer.dart';

/// 本地原生 Dart 视频源执行引擎
/// 100% 独立管理内置的 15 个本地源，负责纯本地爬虫执行与系统 WebView 视频流嗅探
class LocalSourceEngine {
  LocalSourceEngine({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 8),
                sendTimeout: const Duration(seconds: 5),
              ),
            ) {
    _registerDefaultSources();
  }

  final Dio _dio;
  final Map<String, VideoSource> _localSources = {};

  void _registerDefaultSources() {
    // 特殊处理说明：
    // 视频源默认注册位序直接决定了 UI 排序与自动选源的优先级：
    // 1. xifan-next（综合主线首选）
    // 2. cycani（次元城，多线路原画）
    // 3. mifun / sorani（青空次元与 mifun 同级优质主线）
    // 4. girigiri（Cloudflare CDN 原画直连）
    // 5. moonci（月之祠，降权至 girigiri 之后作为备选多线路源）
    // 6. lzizy / animoe / gugu（全品类与备用多线路源）
    registerSource(XifanNextSource(dio: _dio));
    registerSource(CycaniSource(dio: _dio));
    registerSource(MifunSource(dio: _dio));
    registerSource(SoraniSource(dio: _dio));
    registerSource(GirigiriSource(dio: _dio));
    registerSource(MoonciSource(dio: _dio));
    registerSource(LzizySource(dio: _dio));
    registerSource(AnimoeSource(dio: _dio));
    registerSource(GuguSource(dio: _dio));
    registerSource(MxdmSource(dio: _dio));
    registerSource(NeosekSource(dio: _dio));
    registerSource(TvTFunSource(dio: _dio));
    registerSource(Anime1Source(dio: _dio));
    registerSource(OmofunSource(dio: _dio));
    registerSource(LibvioSource(dio: _dio));
  }

  void registerSource(VideoSource source) {
    _localSources[source.id] = source;
  }

  /// 检查特定源是否为本地内置的原生 Dart 源
  bool isLocalSource(String sourceId) {
    final norm = AnimakuServerClient.instance.normalizeSourceId(sourceId);
    return _localSources.containsKey(norm) || (norm == 'xifan-next' && _localSources.containsKey('xifan'));
  }

  /// 获取指定本地视频源实例
  VideoSource? getSource(String sourceId) {
    final norm = AnimakuServerClient.instance.normalizeSourceId(sourceId);
    return _localSources[norm] ?? (norm == 'xifan-next' ? _localSources['xifan'] : null);
  }

  /// 本地所有可用视频源元数据列表
  List<SourceMeta> get availableSources =>
      _localSources.values.map((s) => s.toMeta()).toList();

  /// 适配器清单映射
  Map<String, String> get adapters =>
      {for (final s in _localSources.values) s.id: s.version};

  /// 本地源执行搜索
  Future<List<SourceSearchResult>> search(String sourceId, String keyword) async {
    final s = getSource(sourceId);
    if (s == null) {
      throw Exception('本地未找到视频源: $sourceId');
    }
    return s.search(keyword);
  }

  /// 本地源获取分集线路
  Future<List<SourceChapterRoad>> chapters(String sourceId, String animeUrl) async {
    final s = getSource(sourceId);
    if (s == null) {
      throw Exception('本地未找到视频源: $sourceId');
    }
    return s.chapters(animeUrl);
  }

  /// 本地源解析播放直链（包含 WebView 优先嗅探判定）
  Future<SourceResolveResult> resolve(String sourceId, String episodeUrl) async {
    final s = getSource(sourceId);
    if (s == null) {
      throw Exception('本地未找到视频源: $sourceId');
    }

    final preferWebview = AppPreferences.isPreferWebviewSniffEnabled() || s.preferWebviewSniff;
    if (preferWebview && WebviewVideoSniffer.isPlatformSupported) {
      final sniffed = await WebviewVideoSniffer.instance.sniff(episodeUrl);
      if (sniffed != null && sniffed.url.isNotEmpty) {
        return sniffed;
      }
      throw Exception('WebView 嗅探未命中有效播放地址');
    }
    return s.resolve(episodeUrl);
  }

  /// 清空本地所有源私有缓存
  void clearCache() {
    for (final s in _localSources.values) {
      s.clearCache();
    }
  }
}
