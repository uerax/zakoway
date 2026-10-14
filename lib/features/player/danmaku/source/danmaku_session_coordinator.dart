import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:zakoway/features/player/source/services/source_binding_service.dart';
import 'package:zakoway/features/player/source/source_keyword_matcher.dart';
import '../core/danmaku_controller.dart';
import '../core/danmaku_pools_manager.dart';
import '../models/danmaku_item.dart';
import '../models/danmaku_pool_models.dart';
import '../utils/danmaku_episode_matcher.dart';
import 'bilibili_danmaku_client.dart';
import 'dandan_client.dart';
import 'local_xml_parser.dart';

/// 缓存的单集多源弹幕载荷
class _CachedCommentsPayload {
  const _CachedCommentsPayload({
    required this.dandan,
    required this.bilibili,
    required this.bilibiliPart,
  });

  final List<DanmakuItem> dandan;
  final List<DanmakuItem> bilibili;
  final String bilibiliPart;
}

/// 缓存的番剧元数据 (番剧 ID 与分集列表)
class _SubjectMeta {
  const _SubjectMeta({
    required this.bangumiId,
    required this.animeId,
    required this.episodes,
  });

  final int bangumiId;
  final int animeId;
  final List<DandanEpisode> episodes;
}

/// 弹幕会话协调器 (1:1 对齐 animaku use-danmaku-session.ts)
/// 负责自动匹配、多源聚合、L1 内存秒开缓存、集数与时间轴偏移持久化记忆
class DanmakuSessionCoordinator extends ChangeNotifier {
  DanmakuSessionCoordinator({
    required this.danmakuController,
    DandanClient? dandanClient,
    BilibiliDanmakuClient? bilibiliClient,
  })  : dandanClient = dandanClient ?? DandanClient.instance,
        bilibiliClient = bilibiliClient ?? BilibiliDanmakuClient.instance,
        poolsManager = DanmakuPoolsManager() {
    _lastPoolVersion = poolsManager.poolVersion;
    poolsManager.addListener(_onPoolsChanged);
  }

  final DanmakuController danmakuController;
  final DandanClient dandanClient;
  final BilibiliDanmakuClient bilibiliClient;
  final DanmakuPoolsManager poolsManager;

  int _lastPoolVersion = 0;
  int _refreshGen = 0;
  Timer? _offsetDebounceTimer;

  // L1 内存缓存池（保证切集 0ms 瞬间秒切）
  final Map<String, _CachedCommentsPayload> _commentsMemoryCache = {};
  _SubjectMeta? _subjectMeta;
  String _currentBangumiKey = '';

  // 状态变量
  String _status = '';
  bool _searchBusy = false;
  bool _bilibiliBusy = false;

  int _bangumiId = 0;
  int _episode = 1;
  String _title = '';
  String _pluginName = '';
  int _danmakuOffset = 0;

  List<DandanAnime> _animes = const [];
  List<DandanEpisode> _episodes = const [];
  int? _selectedAnimeId;
  int? _selectedEpisodeId;

  int _autoMatchGen = 0;
  bool _disposed = false;

  bool get isDisposed => _disposed;
  String get status => _status.isNotEmpty ? _status : _buildPoolsStatusLine();
  bool get searchBusy => _searchBusy;
  bool get bilibiliBusy => _bilibiliBusy;
  int get danmakuOffset => _danmakuOffset;
  String get title => _title;
  List<DandanAnime> get animes => _animes;
  List<DandanEpisode> get episodes => _episodes;
  int? get selectedAnimeId => _selectedAnimeId;
  int? get selectedEpisodeId => _selectedEpisodeId;

  void _onPoolsChanged() {
    if (_disposed) return;
    final curVersion = poolsManager.poolVersion;
    final isOffsetOnly = curVersion == _lastPoolVersion;
    _lastPoolVersion = curVersion;

    if (isOffsetOnly) {
      // 时移调节增加 200ms 防抖，防抖期间界面上的数值立即更新，实际重建在防抖结束后触发一次
      notifyListeners();
      _offsetDebounceTimer?.cancel();
      _offsetDebounceTimer = Timer(const Duration(milliseconds: 200), () {
        _offsetDebounceTimer = null;
        if (_disposed) return;
        _refreshController();
      });
    } else {
      _offsetDebounceTimer?.cancel();
      _offsetDebounceTimer = null;
      _refreshController();
      notifyListeners();
    }
  }

  Future<void> _refreshController() async {
    if (_disposed) return;
    final gen = ++_refreshGen;
    final flattened = await poolsManager.flattenEnabledPoolsAsync();
    if (_disposed || gen != _refreshGen) return;
    danmakuController.loadItems(flattened);
  }

  /// 启动自动匹配并拉取当前番剧弹幕 (1:1 对齐 animaku 自动匹配策略)
  Future<void> autoMatchAndLoad({
    required int bangumiId,
    required int episode,
    required String title,
    String pluginName = '',
    List<String>? titleAliases,
  }) async {
    final gen = ++_autoMatchGen;
    _bangumiId = bangumiId;
    _episode = math.max(0, episode);
    _title = title.trim();
    _pluginName = pluginName.trim();

    // 1. 读取该源的历史绑定记录与 danmakuOffset
    if (_bangumiId > 0 && _pluginName.isNotEmpty) {
      final binding = SourceBindingService.instance.getBinding(_bangumiId, _pluginName);
      _danmakuOffset = binding?.danmakuOffset ?? 0;
    } else {
      _danmakuOffset = 0;
    }

    _status = '匹配弹幕…';
    notifyListeners();

    try {
      final subjectKey = '$_bangumiId:$_title';
      final isSameSubject = _currentBangumiKey == subjectKey && _subjectMeta != null;

      // 2. 如果切换了新番剧，重新拉取番剧分集列表
      if (!isSameSubject || _subjectMeta == null) {
        _currentBangumiKey = subjectKey;
        _subjectMeta = null;
        _commentsMemoryCache.clear();
        _animes = const [];
        _episodes = const [];
        _selectedAnimeId = null;
        _selectedEpisodeId = null;

        List<DandanEpisode> resolvedEpisodes = const [];
        int resolvedAnimeId = 0;
        String? resolvedAnimeTitle;

        // Step 2.1: 优先走 BGM ID 映射 (最快、最准)
        if (_bangumiId > 0) {
          try {
            final details = await dandanClient.getBangumiByBgmId(_bangumiId);
            if (details.episodes.isNotEmpty) {
              resolvedEpisodes = details.episodes;
              resolvedAnimeId = details.bangumiId;
              resolvedAnimeTitle = details.animeTitle;
            }
          } catch (_) {}
        }

        if (gen != _autoMatchGen) return;

        // Step 2.2: BGM ID 未命中时，降级走标题搜索与相似度匹配
        if (resolvedEpisodes.isEmpty && _title.isNotEmpty) {
          try {
            final searchList = await dandanClient.searchAnime(_title);
            if (searchList.isNotEmpty) {
              _animes = searchList;
              var bestId = 0;
              var bestScore = 0.0;
              final refs = titleAliases ?? [_title];

              for (final a in searchList) {
                if (a.animeId < 2) continue;
                final score = SourceKeywordMatcher.bestSimilarity(a.animeTitle, refs);
                if (score > bestScore) {
                  bestScore = score;
                  bestId = a.animeId;
                }
              }

              if (bestId > 0 && bestScore >= 0.3) {
                resolvedAnimeId = bestId;
                final details = await dandanClient.getBangumiDetails(bestId);
                resolvedEpisodes = details.episodes;
                resolvedAnimeTitle = details.animeTitle;
              }
            }
          } catch (_) {}
        }

        if (gen != _autoMatchGen) return;

        if (resolvedEpisodes.isNotEmpty || resolvedAnimeId > 0) {
          _subjectMeta = _SubjectMeta(
            bangumiId: _bangumiId,
            animeId: resolvedAnimeId,
            episodes: resolvedEpisodes,
          );
          _episodes = resolvedEpisodes;
          _selectedAnimeId = resolvedAnimeId > 0 ? resolvedAnimeId : null;

          // 特殊处理说明：当走 BGM ID 精准匹配成功时，_animes 尚未由搜索结果填充；
          // 为确保控制面板中「选择番剧」下拉菜单能正确定位并回显当前匹配到的番剧，
          // 若 _animes 为空且存在匹配的 animeId，主动注入一条当前番剧条目。
          if (_animes.isEmpty && resolvedAnimeId > 0) {
            final effectiveTitle = (resolvedAnimeTitle != null && resolvedAnimeTitle.isNotEmpty)
                ? resolvedAnimeTitle
                : (_title.isNotEmpty ? _title : '番剧 #$resolvedAnimeId');
            _animes = [
              DandanAnime(
                animeId: resolvedAnimeId,
                animeTitle: effectiveTitle,
                bangumiId: _bangumiId > 0 ? _bangumiId.toString() : null,
                episodeCount: resolvedEpisodes.length,
              ),
            ];
          }
        }
      }

      final meta = _subjectMeta;
      if (meta == null || meta.episodes.isEmpty) {
        _status = '未匹配到弹幕，点「设置」手动搜索或导入';
        notifyListeners();
        return;
      }

      // 3. 匹配当前目标集数 (考虑 danmakuOffset 偏移)
      final effectiveTargetEp = math.max(0, _episode + _danmakuOffset);
      final matchedEp = DanmakuEpisodeMatcher.matchEpisode(meta.episodes, effectiveTargetEp);

      if (matchedEp == null || matchedEp.episodeId <= 0) {
        _status = '未匹配到当前集数弹幕，可手动选择章节';
        notifyListeners();
        return;
      }

      // 4. 加载分集弹幕
      await loadCommentsByEpisodeId(
        matchedEp.episodeId,
        targetEpNum: effectiveTargetEp,
        gen: gen,
      );
    } catch (e) {
      if (gen != _autoMatchGen) return;
      _status = '弹幕加载失败: $e';
      notifyListeners();
    }
  }

  /// 加载指定分集弹幕（支持 L1 内存秒开 + 并行拉取 + 增量交叉去重）
  Future<void> loadCommentsByEpisodeId(
    int epId, {
    int? targetEpNum,
    int? gen,
  }) async {
    final effectiveGen = gen ?? ++_autoMatchGen;
    final epNum = targetEpNum ?? math.max(0, _episode + _danmakuOffset);
    final cacheKey = '$_bangumiId:$epId:$epNum';

    _selectedEpisodeId = epId;
    List<DanmakuItem> dandanComments = const [];
    List<DanmakuItem> biliComments = const [];
    String biliPart = '';

    final cached = _commentsMemoryCache[cacheKey];
    if (cached != null) {
      // 0ms 瞬间秒开
      dandanComments = cached.dandan;
      biliComments = cached.bilibili;
      biliPart = cached.bilibiliPart;
    } else {
      _status = '正在加载弹幕…';
      notifyListeners();

      // 并行请求：弹弹分集弹幕 + B 站跨站关联弹幕 (带安全闭包异常吸收，防止未决 Future 逃逸为 Unhandled Exception)
      final dandanTask = () async {
        try {
          return await dandanClient.getComments(epId);
        } catch (e) {
          developer.log('[DanmakuSessionCoordinator] dandan fetch failed: $e');
          return const <DanmakuItem>[];
        }
      }();

      final biliTask = () async {
        if (_bangumiId <= 0) return null;
        try {
          return await bilibiliClient.fetchDanmaku('bgm$_bangumiId', pageOverride: epNum);
        } catch (e) {
          developer.log('[DanmakuSessionCoordinator] bili fetch failed: $e');
          return null;
        }
      }();

      final results = await Future.wait([dandanTask, biliTask]);
      dandanComments = results[0] as List<DanmakuItem>;
      final biliRes = results[1] as BilibiliDanmakuResult?;
      if (biliRes != null) {
        biliComments = biliRes.comments;
        biliPart = biliRes.part ?? 'P$epNum';
      }

      // 写入 L1 内存缓存
      _commentsMemoryCache[cacheKey] = _CachedCommentsPayload(
        dandan: dandanComments,
        bilibili: biliComments,
        bilibiliPart: biliPart,
      );
    }

    if (effectiveGen != _autoMatchGen) return;

    // 增量交叉去重并写入弹幕池
    final dedup = DanmakuPoolsManager.deduplicateDanmakuIncremental(
      dandanComments,
      biliComments,
    );

    poolsManager.writePool(
      DanmakuPoolId.dandan,
      dandanComments,
      replace: true,
      meta: 'ep $epId',
      enabled: true,
    );

    if (biliComments.isNotEmpty) {
      poolsManager.writePool(
        DanmakuPoolId.bilibiliAuto,
        biliComments,
        replace: true,
        meta: biliPart,
        enabled: true,
      );
    } else {
      poolsManager.clearPool(DanmakuPoolId.bilibiliAuto);
    }

    final offsetStr = _danmakuOffset != 0
        ? ' · 偏移 (${_danmakuOffset > 0 ? "+$_danmakuOffset" : _danmakuOffset}集)'
        : '';

    if (biliComments.isNotEmpty && dedup.incremental.isNotEmpty) {
      _status = '弹弹 (${dandanComments.length}) + B站 (+${dedup.incremental.length}) 已启用$offsetStr';
    } else if (biliComments.isNotEmpty) {
      _status = '弹弹 (${dandanComments.length}) + B站 (已去重) 已启用$offsetStr';
    } else {
      _status = '弹弹 · 已加载 ${dandanComments.length} 条$offsetStr';
    }

    notifyListeners();
  }

  /// 手动搜索弹弹番剧
  Future<void> searchDandan(String keyword) async {
    final kw = keyword.trim();
    if (kw.length < 2) {
      _status = '番剧名称不少于 2 个字';
      notifyListeners();
      return;
    }

    _searchBusy = true;
    _status = '正在搜索番剧…';
    notifyListeners();

    try {
      final list = await dandanClient.searchAnime(kw);
      _animes = list;
      _episodes = const [];
      _selectedAnimeId = null;
      _selectedEpisodeId = null;
      if (list.isEmpty) {
        _status = '无搜索结果';
      } else {
        _status = '找到 ${list.length} 部番剧';
        await pickDandanAnime(list.first.animeId);
      }
    } catch (e) {
      _status = '搜索失败: $e';
    } finally {
      _searchBusy = false;
      notifyListeners();
    }
  }

  /// 手动选择番剧
  Future<void> pickDandanAnime(int animeId) async {
    _selectedAnimeId = animeId;
    _status = '正在搜索剧集…';
    notifyListeners();

    try {
      final details = await dandanClient.getBangumiDetails(animeId);
      _episodes = details.episodes;
      _subjectMeta = _SubjectMeta(
        bangumiId: 0,
        animeId: animeId,
        episodes: details.episodes,
      );

      // 特殊处理说明：若当前 _animes 为空（例如外部直接调用 pickDandanAnime），
      // 注入当前选择的番剧项，保证选择番剧下拉框可回显。
      if (_animes.isEmpty) {
        final effectiveTitle = details.animeTitle ?? (_title.isNotEmpty ? _title : '番剧 #$animeId');
        _animes = [
          DandanAnime(
            animeId: animeId,
            animeTitle: effectiveTitle,
            episodeCount: details.episodes.length,
          ),
        ];
      }

      final matched = DanmakuEpisodeMatcher.matchEpisode(details.episodes, _episode + _danmakuOffset) ??
          (details.episodes.isNotEmpty ? details.episodes.first : null);

      if (matched != null) {
        await pickDandanEpisode(matched.episodeId);
      }
    } catch (e) {
      _status = '剧集加载失败: $e';
      notifyListeners();
    }
  }

  /// 手动选择具体分集（自动计算并记忆 danmakuOffset）
  Future<void> pickDandanEpisode(int episodeId) async {
    _selectedEpisodeId = episodeId;
    final targetEp = _episodes.firstWhere(
      (e) => e.episodeId == episodeId,
      orElse: () => DandanEpisode(episodeId: episodeId, episodeTitle: ''),
    );

    final epNum = DanmakuEpisodeMatcher.parseEpisodeNumber(targetEp.episodeTitle);
    if (epNum != null) {
      final newOffset = epNum - _episode;
      _danmakuOffset = newOffset;
      if (_bangumiId > 0 && _pluginName.isNotEmpty) {
        await SourceBindingService.instance.setBinding(
          bangumiId: _bangumiId,
          sourceId: _pluginName,
          sourceUrl: '',
          title: _title,
          danmakuOffset: newOffset,
        );
      }
    }

    await loadCommentsByEpisodeId(episodeId, targetEpNum: epNum);
  }

  /// 一键重置集数偏移为 0
  Future<void> resetDanmakuOffset() async {
    _danmakuOffset = 0;
    if (_bangumiId > 0 && _pluginName.isNotEmpty) {
      await SourceBindingService.instance.setBinding(
        bangumiId: _bangumiId,
        sourceId: _pluginName,
        sourceUrl: '',
        title: _title,
        danmakuOffset: 0,
      );
    }
    _status = '已重置弹幕偏移';

    final meta = _subjectMeta;
    if (meta != null && meta.episodes.isNotEmpty) {
      final matched = DanmakuEpisodeMatcher.matchEpisode(meta.episodes, _episode);
      if (matched != null) {
        await loadCommentsByEpisodeId(matched.episodeId, targetEpNum: _episode);
      }
    }
  }

  /// 手动追加 B 站弹幕 (支持 BV/ep/ss/av/链接/分P)
  Future<void> loadBilibiliManual(String rawInput, {int page = 1}) async {
    final s = rawInput.trim();
    if (s.isEmpty) {
      _status = '请输入有效 B 站链接或 BV 号';
      notifyListeners();
      return;
    }

    _bilibiliBusy = true;
    _status = '拉取 B 站弹幕中…';
    notifyListeners();

    try {
      final res = await bilibiliClient.fetchDanmaku(s, pageOverride: page);
      final meta = '${res.title ?? "bilibili"}${res.part != null ? " · ${res.part}" : ""}';
      poolsManager.writePool(
        DanmakuPoolId.bilibiliManual,
        res.comments,
        replace: false,
        meta: meta,
        enabled: true,
      );
      _status = '已追加 bilibili · $meta · +${res.comments.length} 条';
    } catch (e) {
      _status = 'B 站弹幕拉取失败: $e';
    } finally {
      _bilibiliBusy = false;
      notifyListeners();
    }
  }

  /// 选取并导入本地 XML 弹幕文件
  Future<void> loadLocalXml() async {
    try {
      final res = await LocalXmlDanmakuParser.pickAndParse();
      if (res == null) return;

      poolsManager.writePool(
        DanmakuPoolId.upload,
        res.comments,
        replace: false,
        meta: res.fileName,
        enabled: true,
      );
      _status = '已追加 用户上传 · ${res.fileName} · +${res.comments.length} 条';
      notifyListeners();
    } catch (e) {
      _status = 'XML 解析失败: $e';
      notifyListeners();
    }
  }

  String _buildPoolsStatusLine() {
    final chips = poolsManager.getSourceChips().where((c) => c.loaded).toList();
    if (chips.isEmpty) return '—';
    final parts = chips.map((c) => '${c.label}${c.enabled ? "" : "·关"} ${c.count}').join(' · ');
    return '$parts · 显示 ${danmakuController.items.length} 条';
  }

  @override
  void dispose() {
    _disposed = true;
    _offsetDebounceTimer?.cancel();
    _offsetDebounceTimer = null;
    poolsManager.removeListener(_onPoolsChanged);
    poolsManager.dispose();
    super.dispose();
  }
}
