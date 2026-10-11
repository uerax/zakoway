import 'dart:async';
import 'dart:math';
import '../models/bangumi/bangumi_item.dart';
import '../models/home/recommend_item.dart';
import '../network/bangumi_client.dart';
import '../network/bangumi_data_disk_cache_manager.dart';
import '../utils/anime_tag_filter.dart';
import 'app_preferences.dart';

/// 今日推荐调度核心算法服务（广域离散散落采样架构）：
/// 1. 确定性天命种子（Deterministic Daily Seed）：
///    结合设备唯一标识 (DeviceUUID) 与当日日期字符串计算 32 位离散哈希，
///    确保“千人千面、天内绝对幂等（全天刷新结果不变）、次日零点自动平滑轮换”；
/// 2. 受控白名单精准清洗：
///    通过 AnimeTagFilter.genreAllowList 过滤用户输入，彻底免疫时间、载体、恶搞短句等一切 UGC 噪音；
/// 3. 广域离散散落采样（Scattered Sampling，坚决杜绝连号与扎堆）：
///    - 5 个槽位题材严格互斥（绝不推荐同一题材）；
///    - 每个槽位基于独立质数步进与基底计算 offset，翻页深度彼此相距甚远，杜绝在同一局部区间抓取连号邻近条目；
///    - 排序维度交替采用 heat（热度/流行新番）与 score（口碑经典），热度与品质错落交替；
///    - 评分不过滤：放宽生硬的评分限制，让 6~8 分各类精品与宝藏自然涌现；
/// 4. 槽位调度与降级保护：
///    - 无数据时（冷启动）：从题材库中离散打乱抽样 5 个互斥题材独立检索；
///    - 有数据时（个性化）：前几个槽位绑定用户 Top 偏好题材，其余槽位取长尾与探索互斥题材；
/// 5. 跨槽位与播放历史全局去重，输出稳固散落的 5 部今日推荐番剧。
class DailyRecommendService {
  DailyRecommendService._();

  /// 缓存当天的推荐计算结果，避免同一会话内重复计算
  static List<RecommendItem>? _memoryCachedItems;
  static String? _cachedDateKey;

  /// 清空今日推荐的内存与时间戳缓存（在用户手动清理数据缓存或切换线路时调用）
  static void clearCache() {
    _memoryCachedItems = null;
    _cachedDateKey = null;
  }

  /// 计算当天的 32 位确定性正整数天命种子
  static int computeSeed(String deviceId, DateTime date) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final raw = '$deviceId#$dateStr';

    // 采用 32-bit FNV-1a 高离散度哈希算法
    var hash = 0x811c9dc5;
    for (var i = 0; i < raw.length; i++) {
      hash ^= raw.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  /// 获取今日推荐番剧核心入口
  static Future<List<RecommendItem>> getDailyRecommendations({
    required BangumiClient client,
    Map<String, int> rawUserTagFreq = const {},
    Set<int> watchedSubjectIds = const {},
    DateTime? customDate,
    String? customDeviceId,
    bool forceRefresh = false,
  }) async {
    final now = customDate ?? DateTime.now();
    final dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final diskCacheKey = 'daily_roam_bundle_$dateKey';

    // 1. L1 内存缓存拦截（当前会话内绝对幂等）
    if (!forceRefresh && _cachedDateKey == dateKey && _memoryCachedItems != null) {
      return _memoryCachedItems!;
    }

    // 2. L2 本地硬盘持久化缓存拦截（用户杀进程重新打开时 0ms 命中，0 次网络请求）
    if (!forceRefresh) {
      try {
        final diskJson = await BangumiDataDiskCacheManager.instance?.getJson(diskCacheKey);
        if (diskJson is List) {
          final cachedList = diskJson
              .whereType<Map<String, dynamic>>()
              .map((j) => RecommendItem.fromJson(j))
              .toList();
          if (cachedList.isNotEmpty) {
            _cachedDateKey = dateKey;
            _memoryCachedItems = cachedList;
            return cachedList;
          }
        }
      } catch (_) {}
    }

    final deviceId = customDeviceId ?? AppPreferences.getOrCreateDeviceInstallId();
    final seed = computeSeed(deviceId, now);
    final rng = Random(seed);

    // 3. 白名单清洗用户词频画像
    final cleanProfile = AnimeTagFilter.filterByGenreAllowList(rawUserTagFreq);

    List<RecommendItem> finalRecommendations;

    if (cleanProfile.isEmpty) {
      // 4. 情况 A：冷启动（无用户数据）
      finalRecommendations = await _fetchColdStartRecommendations(
        client: client,
        seed: seed,
        rng: rng,
        watchedSubjectIds: watchedSubjectIds,
      );
    } else {
      // 5. 情况 B：有用户数据（Top 3 主力 + 2 长尾探索）
      finalRecommendations = await _fetchPersonalizedRecommendations(
        client: client,
        cleanProfile: cleanProfile,
        seed: seed,
        rng: rng,
        watchedSubjectIds: watchedSubjectIds,
      );
    }

    // 6. 回填 L1 内存缓存
    _cachedDateKey = dateKey;
    _memoryCachedItems = finalRecommendations;

    // 7. 异步安全落盘至 L2 硬盘：有效期严格锁定至今日 23:59:59 (次日零点自动过期)
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final remainingTtl = endOfDay.difference(now);
    final validDuration = remainingTtl.isNegative || remainingTtl.inMinutes < 15
        ? const Duration(hours: 4)
        : remainingTtl;

    unawaited(
      BangumiDataDiskCacheManager.instance?.putJson(
        diskCacheKey,
        finalRecommendations.map((r) => r.toJson()).toList(),
        maxAge: validDuration,
      ) ?? Future.value(),
    );

    return finalRecommendations;
  }

  /// 冷启动抓取：广域离散散落抽样（从白名单题材库中抽选 5 个互斥题材独立检索，绝不连号扎堆）
  static Future<List<RecommendItem>> _fetchColdStartRecommendations({
    required BangumiClient client,
    required int seed,
    required Random rng,
    required Set<int> watchedSubjectIds,
  }) async {
    // 从题材白名单中基于种子打乱选取 5 个截然不同的题材，确保 5 个槽位题材完全互斥
    final availableGenres = AnimeTagFilter.genreAllowList.toList()..shuffle(rng);
    final slotTags = availableGenres.take(5).toList();

    return _fetchScatteredRecommendations(
      client: client,
      slotTags: slotTags,
      seed: seed,
      rng: rng,
      watchedSubjectIds: watchedSubjectIds,
      isColdStart: true,
    );
  }

  /// 个性化抓取：前几个槽位绑定用户 Top 偏好题材，其余槽位取长尾与探索互斥题材
  static Future<List<RecommendItem>> _fetchPersonalizedRecommendations({
    required BangumiClient client,
    required Map<String, int> cleanProfile,
    required int seed,
    required Random rng,
    required Set<int> watchedSubjectIds,
  }) async {
    // 1. 标签按频次降序排序
    final sortedTags = cleanProfile.keys.toList()
      ..sort((a, b) => (cleanProfile[b] ?? 0).compareTo(cleanProfile[a] ?? 0));

    // 2. 提取 Top 3 核心偏好标签
    final top3Tags = sortedTags.take(3).toList();

    // 3. 提取长尾候选标签（排除 Top 3）
    final remainingTags = sortedTags.length > 3 ? sortedTags.sublist(3) : <String>[];
    final selectedLongTailTags = <String>[];
    if (remainingTags.isNotEmpty) {
      final shuffled = [...remainingTags]..shuffle(rng);
      selectedLongTailTags.addAll(shuffled.take(2));
    }

    // 4. 构建 5 个互斥的槽位标签；若用户题材不足 5 个，从白名单题材中补充互斥题材
    final pickedTagSet = <String>{...top3Tags, ...selectedLongTailTags};
    final candidateGenres = AnimeTagFilter.genreAllowList
        .where((g) => !pickedTagSet.contains(g))
        .toList()
      ..shuffle(rng);

    final slotTags = <String>[...top3Tags, ...selectedLongTailTags];
    for (final genre in candidateGenres) {
      if (slotTags.length >= 5) break;
      slotTags.add(genre);
    }

    return _fetchScatteredRecommendations(
      client: client,
      slotTags: slotTags,
      seed: seed,
      rng: rng,
      watchedSubjectIds: watchedSubjectIds,
      isColdStart: false,
    );
  }

  /// 核心离散散落推荐调度引擎：
  /// 1. 题材散落：5 个槽位题材严格互斥，各探索不同风格；
  /// 2. 深度散落：每个槽位使用独立的大质数散列步进计算 offset，翻页深度彼此相距甚远，杜绝在同一局部区间抓取连号邻近条目；
  /// 3. 排序错落：交替使用 heat（热度）与 score（口碑经典），热度与口碑自然交融；
  /// 4. 评分不过滤：放宽生硬的评分限制，只校验海报有效性与已看去重，让 6~8 分各类精品与宝藏自然涌现；
  /// 5. 跨槽位全局去重与已看过滤，平滑兜底。
  static Future<List<RecommendItem>> _fetchScatteredRecommendations({
    required BangumiClient client,
    required List<String> slotTags,
    required int seed,
    required Random rng,
    required Set<int> watchedSubjectIds,
    required bool isColdStart,
  }) async {
    // 质数散列步进常数：保证各槽位翻页深度相隔拉远，杜绝在同一局部区间抓取连号邻近条目
    const primes = [17, 37, 53, 71, 89];
    const bases = [0, 19, 31, 47, 63];
    const sortModes = ['heat', 'score', 'heat', 'score', 'heat'];

    final futures = <Future<List<BangumiItem>>>[];
    for (var i = 0; i < 5; i++) {
      final targetTag = i < slotTags.length ? slotTags[i] : null;
      final prime = primes[i % primes.length];
      final base = bases[i % bases.length];
      // 深度大跨度散落：每个槽位 offset 在 0 ~ 45 不同的质数区间分布，绝不挨着
      final slotOffset = ((seed * prime + base) & 0x7FFFFFFF) % 45;
      final sortMode = sortModes[i % sortModes.length];

      if (targetTag != null) {
        futures.add(
          client
              .searchWithTotal(
                '',
                tags: [targetTag, '日本'],
                sort: sortMode,
                limit: 8,
                offset: slotOffset,
              )
              .then((res) => res.items)
              .catchError((_) => <BangumiItem>[]),
        );
      } else {
        futures.add(
          client
              .searchWithTotal(
                '',
                tags: const ['日本'],
                sort: sortMode,
                limit: 8,
                offset: slotOffset,
              )
              .then((res) => res.items)
              .catchError((_) => <BangumiItem>[]),
        );
      }
    }

    final slotResults = await Future.wait(futures);

    // 跨槽位去重与已看过滤（取消死板评分限制，重点保证条目散落不扎堆）
    final seenIds = <int>{...watchedSubjectIds};
    final chosenItems = <BangumiItem>[];
    final chosenTags = <String>[];

    for (var i = 0; i < 5; i++) {
      final candidates = slotResults[i];
      BangumiItem? picked;
      for (final item in candidates) {
        if (!seenIds.contains(item.id) && item.coverUrl.isNotEmpty) {
          picked = item;
          break;
        }
      }

      if (picked != null) {
        seenIds.add(picked.id);
        chosenItems.add(picked);
        chosenTags.add(i < slotTags.length ? slotTags[i] : '精选');
      }
    }

    // 兜底补偿：若因去重或偏门标签未凑满 5 部，通过离散 offset 全量池平滑补充
    if (chosenItems.length < 5) {
      try {
        final fallbackOffset = ((seed * 73 + chosenItems.length * 29) & 0x7FFFFFFF) % 100;
        final fallbackRes = await client.searchWithTotal(
          '',
          tags: const ['日本'],
          sort: 'heat',
          limit: 12,
          offset: fallbackOffset,
        );
        for (final item in fallbackRes.items) {
          if (!seenIds.contains(item.id) && item.coverUrl.isNotEmpty) {
            seenIds.add(item.id);
            chosenItems.add(item);
            chosenTags.add('精选');
            if (chosenItems.length >= 5) break;
          }
        }
      } catch (_) {}
    }

    // 终极网络失败兜底（当 Bangumi searchWithTotal 完全不可用时）：从热门列表中补充
    if (chosenItems.isEmpty) {
      try {
        final hotFallback = await client.getTrending(limit: 10);
        for (final item in hotFallback) {
          if (!seenIds.contains(item.id) && item.coverUrl.isNotEmpty) {
            seenIds.add(item.id);
            chosenItems.add(item);
            chosenTags.add('精选');
            if (chosenItems.length >= 5) break;
          }
        }
      } catch (_) {}
    }

    // 装箱为推荐实体
    final result = <RecommendItem>[];
    for (var i = 0; i < chosenItems.length; i++) {
      final item = chosenItems[i];
      final tag = chosenTags[i];
      final isDegraded = tag == '精选';
      final displayTag = resolveDisplayTag(isDegraded ? null : tag, item, rng);
      final reason = buildRecommendReason(i, isDegraded ? null : tag, item, isColdStart);

      result.add(
        RecommendItem(
          item: item,
          tag: displayTag,
          reason: reason,
          matchRate: 98 - (i * 2),
        ),
      );
    }

    return result;
  }

  /// 依据主题材与作品自身次级标签，合成地道二次元特色标签
  static String resolveDisplayTag(String? mainTag, BangumiItem item, [Random? rng]) {
    final subTags = item.tags
        .map((t) => t.name.trim())
        .where((t) => t != mainTag)
        .toSet();

    switch (mainTag) {
      case '恋爱':
        if (subTags.contains('治愈') || subTags.contains('纯爱')) return '#纯爱治愈';
        if (subTags.contains('搞笑') || subTags.contains('校园')) return '#恋爱喜剧';
        return '#恋爱喜剧';

      case '悬疑':
        if (subTags.contains('智斗') || subTags.contains('推理')) return '#硬核烧脑';
        return '#硬核烧脑';

      case '打斗':
      case '战斗':
        if (subTags.contains('超能力') || subTags.contains('热血')) return '#战斗爽';
        return '#战斗爽';

      case '日常':
        if (subTags.contains('美食')) return '#下饭神作';
        if (subTags.contains('治愈')) return '#日常治愈';
        return '#日常治愈';

      case '奇幻':
        if (subTags.contains('异世界')) return '#异界冒险';
        if (subTags.contains('冒险')) return '#奇幻冒险';
        return '#奇幻冒险';

      case '宫廷':
        if (subTags.contains('悬疑') || subTags.contains('剧情')) return '#宫廷权谋';
        return '#宫廷权谋';

      default:
        // 其他题材：从番剧自身高频有效标签里挑选一个
        final validTags = AnimeTagFilter.cleanItemTags(item.tags.map((t) => t.name));
        if (validTags.isNotEmpty) {
          final pickIndex = rng != null ? rng.nextInt(validTags.length) : 0;
          return '#${validTags[pickIndex]}';
        }
        if (mainTag != null && mainTag.isNotEmpty) {
          return '#$mainTag';
        }
        return '#今日推荐';
    }
  }

  /// 四维槽位推荐理由文案动态引擎
  /// 特殊处理说明：文案返回纯语义文本，不包含 💡 等装饰 Emoji，避免与 UI 层的图标控件叠加显示重复。
  static String buildRecommendReason(
    int slotIndex,
    String? mainTag,
    BangumiItem item, [
    bool isColdStart = false,
  ]) {
    final scoreStr = item.ratingScore > 0 ? '${item.ratingScore.toStringAsFixed(1)}分' : '高人气';

    if (isColdStart && mainTag != null && mainTag.isNotEmpty) {
      return '今日散落精选：【$mainTag】题材，Bangumi $scoreStr';
    }

    // 槽位 0 (Top 1 主力)
    if (slotIndex == 0 && mainTag != null) {
      return '命中你偏好最高的【$mainTag】题材，Bangumi $scoreStr';
    }

    // 槽位 1~2 (Top 2~3 次级主力)
    if ((slotIndex == 1 || slotIndex == 2) && mainTag != null) {
      return '兼顾你关注的【$mainTag】风向，Bangumi $scoreStr';
    }

    // 槽位 3~4 (长尾探索)
    if ((slotIndex == 3 || slotIndex == 4) && mainTag != null) {
      return '偶尔换换口味：捕捉到你兴趣库中的【$mainTag】基因，翻出的宝藏作品';
    }

    // 无标签 / 兜底
    return '今日番剧推荐：Bangumi $scoreStr';
  }
}
