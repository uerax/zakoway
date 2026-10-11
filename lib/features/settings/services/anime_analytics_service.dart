import 'dart:math';
import '../../../core/collection/models/anime_collection_item.dart';
import '../../../core/models/bangumi/bangumi_collection.dart';
import '../../../core/models/history/watch_history_item.dart';
import '../../../core/utils/anime_tag_filter.dart';
import '../models/anime_analytics_report.dart';

/// 追番数据深度算法解析服务：
/// 1. 题材画像提取：综合清洗用户的观看历史与“我的追番”收藏，统计各题材在用户看过的作品中的频次与权重；
/// 2. 杂食度指数 (Diversity Score)：采用信息熵（香农熵 Shannon Entropy）算法量化用户的题材多样性；
/// 3. 二次元属性判定引擎：依据核心题材组合与杂食度，智能推导趣味二次元称号与专属解读；
/// 4. 作息时间分析：分析历史播放时间戳的小时段分布，推导用户的活跃追番时段；
/// 5. 追番完结率与状态透视：结合追番在看/看过/搁置等状态计算完成度与偏好画像。
class AnimeAnalyticsService {
  AnimeAnalyticsService._();

  /// 核心分析入口：传入历史记录与追番收藏列表，计算生成完整分析报告
  static AnimeAnalyticsReport analyze(
    List<WatchHistoryItem> history, {
    List<AnimeCollectionItem> collections = const [],
  }) {
    if (history.isEmpty && collections.isEmpty) {
      return AnimeAnalyticsReport.empty();
    }

    // 1. 按番剧去重聚合（以番剧为单位分析题材与时长）
    final animeMap = <int, WatchHistoryItem>{};
    var totalSeconds = 0.0;
    for (final item in history) {
      if (item.bangumiId > 0 && !animeMap.containsKey(item.bangumiId)) {
        animeMap[item.bangumiId] = item;
      }
      if (item.position > 0 && item.position.isFinite) {
        totalSeconds += item.position;
      }
    }

    // 过滤出实际观看/正在观看的追番条目（排除「想看」待看囤积、「搁置」及「抛弃」）
    final watchedOrWatchingCollections = collections
        .where((c) =>
            c.type == CollectType.watched || c.type == CollectType.watching)
        .toList();

    // 真正看过的番剧 ID 集合：播放历史 + 标记为「在看」/「看过」
    final watchedSubjectIds = <int>{
      ...animeMap.keys,
      ...watchedOrWatchingCollections
          .map((e) => e.subjectId)
          .where((id) => id > 0),
    };
    final totalAnimeCount = watchedSubjectIds.length;
    final totalEpisodesCount = history.length;
    final totalWatchHours = totalSeconds / 3600.0;

    // 2. 统计题材词频并记录代表作样本（结合观看历史与真正看过的收藏数据）
    final genreCounts = <String, int>{};
    final genreSamples = <String, List<String>>{};

    // (1) 观看历史中的题材
    for (final entry in animeMap.values) {
      final cleanGenres = entry.genres
          .map((g) => g.trim())
          .where((g) => AnimeTagFilter.isAllowedGenre(g))
          .toSet();

      for (final g in cleanGenres) {
        genreCounts[g] = (genreCounts[g] ?? 0) + 1;
        final list = genreSamples.putIfAbsent(g, () => <String>[]);
        if (list.length < 3 && !list.contains(entry.title) && entry.title.isNotEmpty) {
          list.add(entry.title);
        }
      }
    }

    // (2) 追番收藏列表中的题材与画像融合（仅统计「在看」和「看过」的作品，不被「想看」待看列表带偏）
    for (final col in watchedOrWatchingCollections) {
      if (col.tags.isEmpty) continue;
      final cleanGenres = col.tags
          .map((g) => g.trim())
          .where((g) => AnimeTagFilter.isAllowedGenre(g))
          .toSet();

      for (final g in cleanGenres) {
        // 如果观看历史中未统计过该番剧，累加进题材偏好池
        if (!animeMap.containsKey(col.subjectId)) {
          genreCounts[g] = (genreCounts[g] ?? 0) + 1;
        }
        final list = genreSamples.putIfAbsent(g, () => <String>[]);
        if (list.length < 3 && !list.contains(col.title) && col.title.isNotEmpty) {
          list.add(col.title);
        }
      }
    }

    // 3. 计算题材百分比与 Top 6 题材
    final totalGenreOccurrences = genreCounts.values.fold<int>(0, (a, b) => a + b);
    final sortedGenreEntries = genreCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topGenres = sortedGenreEntries.take(6).map((e) {
      final pct = totalGenreOccurrences > 0 ? (e.value / totalGenreOccurrences) : 0.0;
      return GenreStatItem(
        genre: e.key,
        count: e.value,
        percentage: pct,
      );
    }).toList();

    // 4. 计算香农多样性指数（杂食度）
    // H = -sum(p * ln(p))，以 8 种均匀题材作为满分 100 分标准
    var entropy = 0.0;
    if (totalGenreOccurrences > 0) {
      for (final count in genreCounts.values) {
        final p = count / totalGenreOccurrences;
        if (p > 0) {
          entropy -= p * log(p);
        }
      }
    }
    // ln(8) 约等于 2.079
    final rawScore = ((entropy / 2.079) * 100).round();
    final diversityScore = rawScore.clamp(5, 100);

    final diversityLabel = _resolveDiversityLabel(diversityScore);

    // 5. 计算追番时段作息
    final (activeSlotLabel, activeSlotDesc) = _resolveActiveTimeSlot(history);

    // 6. 判定二次元属性称号与个性解读
    final (personaTitle, personaDesc) = _resolvePersona(
      topGenres: topGenres,
      diversityScore: diversityScore,
      totalAnimeCount: totalAnimeCount,
    );

    // 7. 计算追番状态透视指标与完成率
    final colStats = <CollectType, int>{
      CollectType.watching: 0,
      CollectType.planToWatch: 0,
      CollectType.watched: 0,
      CollectType.onHold: 0,
      CollectType.abandoned: 0,
    };
    for (final col in collections) {
      if (colStats.containsKey(col.type)) {
        colStats[col.type] = (colStats[col.type] ?? 0) + 1;
      }
    }
    final watched = colStats[CollectType.watched] ?? 0;
    final watching = colStats[CollectType.watching] ?? 0;
    final abandoned = colStats[CollectType.abandoned] ?? 0;
    final nonDropTotal = watched + watching + abandoned;
    final completionRate = nonDropTotal > 0 ? (watched / nonDropTotal) : 0.0;

    return AnimeAnalyticsReport(
      totalAnimeCount: totalAnimeCount,
      totalEpisodesCount: totalEpisodesCount,
      totalWatchHours: totalWatchHours,
      topGenres: topGenres,
      allGenreCounts: genreCounts,
      personaTitle: personaTitle,
      personaDescription: personaDesc,
      diversityScore: diversityScore,
      diversityLabel: diversityLabel,
      activeTimeSlotLabel: activeSlotLabel,
      activeTimeSlotDesc: activeSlotDesc,
      genreAnimeSamples: genreSamples,
      totalCollectionCount: collections.length,
      collectionCounts: colStats,
      completionRate: completionRate,
    );
  }

  /// 依据杂食度分值评定等级标签
  static String _resolveDiversityLabel(int score) {
    if (score < 35) return '🔥 专一专精党';
    if (score < 65) return '✨ 偏好鲜明派';
    if (score < 85) return '🌟 广泛博览家';
    return '👑 究极杂食大饕';
  }

  /// 时段偏好分析算法
  static (String label, String desc) _resolveActiveTimeSlot(List<WatchHistoryItem> history) {
    if (history.isEmpty) {
      return ('暂无数据', '尚无播放记录');
    }

    // 时段计数：深夜(0-5)、早间(6-10)、午间(11-13)、下午(14-17)、晚间黄金档(18-23)
    var midnightCount = 0;
    var morningCount = 0;
    var lunchCount = 0;
    var afternoonCount = 0;
    var nightCount = 0;

    for (final item in history) {
      final hour = DateTime.fromMillisecondsSinceEpoch(item.updatedAt).hour;
      if (hour >= 0 && hour <= 5) {
        midnightCount++;
      } else if (hour >= 6 && hour <= 10) {
        morningCount++;
      } else if (hour >= 11 && hour <= 13) {
        lunchCount++;
      } else if (hour >= 14 && hour <= 17) {
        afternoonCount++;
      } else {
        nightCount++;
      }
    }

    final counts = [
      (count: midnightCount, label: '🌙 深夜修仙党 (00:00 - 06:00)', desc: '被窝里的一方净土，静谧深夜才是属于你的追番结界'),
      (count: morningCount, label: '☀️ 晨间元气派 (06:00 - 11:00)', desc: '迎着晨光开启新番，清晨的第一缕动力来自于此'),
      (count: lunchCount, label: '🍱 下饭番特派员 (11:00 - 14:00)', desc: '剧情越下饭，饭菜越喷香！追番与午餐的最佳组合'),
      (count: afternoonCount, label: '☕ 午后休闲派 (14:00 - 18:00)', desc: '午后惬意时光，伴随着茶点与悠闲番剧享受慢节奏'),
      (count: nightCount, label: '✨ 黄金档追番人 (18:00 - 24:00)', desc: '晚间黄金追番时刻，卸下一天的疲惫尽情沉浸二次元'),
    ];

    counts.sort((a, b) => b.count.compareTo(a.count));
    final best = counts.first;
    return (best.label, best.desc);
  }

  /// 二次元称号与文案推导引擎
  static (String title, String desc) _resolvePersona({
    required List<GenreStatItem> topGenres,
    required int diversityScore,
    required int totalAnimeCount,
  }) {
    if (topGenres.isEmpty) {
      return (
        '初涉次元的漫步者',
        '你留下的观影足迹还比较少，多看几部不同风格的作品，算法就能捕捉到你的灵魂共鸣！',
      );
    }

    // 若杂食度非常高且作品数 >= 4，优先授予全能称号
    if (diversityScore >= 80 && totalAnimeCount >= 4) {
      return (
        '全能杂食追番大饕',
        '从日常废萌到硬核烧脑全来者不拒，涉猎极广！二次元博览群书，你心中的动漫世界包罗万象。',
      );
    }

    final primary = topGenres.first.genre;
    final secondary = topGenres.length > 1 ? topGenres[1].genre : '';

    switch (primary) {
      case '恋爱':
      case '纯爱':
      case '恋爱喜剧':
        return (
          '纯爱战神本神',
          '问世间情为何物，直教人在屏幕前合不拢嘴！你在别人的青春与爱恋里笑得比谁都甜。',
        );

      case '日常':
      case '治愈':
      case '萌系':
      case '萌':
        if (secondary == '美食') {
          return (
            '顶级下饭品鉴官',
            '番剧配饭，越看越香！剧情越治愈下饭，生活中的疲倦就被抚慰得越彻底。',
          );
        }
        return (
          '治愈系养老仙人',
          '喝茶吃点心、岁月静好才是追番的最高真理。现实的喧嚣纷扰，都在番剧的温柔中烟消云散。',
        );

      case '战斗':
      case '热血':
      case '打斗':
      case '格斗':
        return (
          '燃魂热血硬汉',
          '热血沸腾、拳拳到肉！唯有永不放弃的执着与激燃的打斗分镜，才能瞬间点燃你的灵魂。',
        );

      case '奇幻':
      case '异世界':
      case '冒险':
      case '魔法':
        return (
          '异界特级冒险者',
          '剑与魔法的壮丽大陆、未知的地下城密道，你时刻准备着接受异世界的召唤，踏上全新征途。',
        );

      case '悬疑':
      case '推理':
      case '智斗':
        return (
          '硬核智斗宗师',
          '神级反转、伏笔回收与高智商博弈是你的最爱，任何迷局与谎言都逃不过你的逻辑推演。',
        );

      case '科幻':
      case '机战':
      case '机甲':
      case '赛博朋克':
        return (
          '机魂不灭漫游者',
          '男人的浪漫是钢铁与星辰大海！未来科技的冷峻、机甲轰鸣的震撼是你心中永恒的史诗。',
        );

      case '搞笑':
        return (
          '颜艺爆笑解压大师',
          '看番图的就是一个纯粹快乐！在天马行空的吐槽与无厘头爆笑中，把所有烦恼统统甩掉。',
        );

      case '运动':
      case '竞技':
        return (
          '竞技挥汗应援官',
          '球场上的每一滴汗水与青春呐喊，都让你热泪盈眶。永不言败的竞技精神正是你的信条。',
        );

      case '校园':
      case '青春':
        return (
          '夏日青春物语记录者',
          '那些操场上掠过的微风、蓝天白云下的少年心事，构成了你追番中最向往的白月光。',
        );

      case '美食':
        return (
          '深夜食客品鉴家',
          '香气四溢的料理、烹饪升腾的热气，深夜追番看美食，既满足心灵又慰藉味蕾。',
        );

      default:
        return (
          '【$primary】题材发烧友',
          '对【$primary】题材有着敏锐而坚定的独到品味，在专属的喜好领域里挖掘最闪耀的宝藏作品。',
        );
    }
  }
}
