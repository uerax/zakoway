import '../../../core/models/bangumi/bangumi_collection.dart';

/// 单个题材的统计指标实体
class GenreStatItem {
  final String genre;
  final int count;
  final double percentage; // 0.0 ~ 1.0

  const GenreStatItem({
    required this.genre,
    required this.count,
    required this.percentage,
  });

  String get percentageText => '${(percentage * 100).toStringAsFixed(1)}%';
}

/// 追番数据分析总报告数据模型
class AnimeAnalyticsReport {
  final int totalAnimeCount; // 观看过的独立番剧数
  final int totalEpisodesCount; // 观看过的分集总数
  final double totalWatchHours; // 累计播放时长（小时）
  final List<GenreStatItem> topGenres; // 频次最高的前 6 个题材
  final Map<String, int> allGenreCounts; // 全量题材频次
  final String personaTitle; // 二次元专属称号
  final String personaDescription; // 人话化个性解读
  final int diversityScore; // 题材杂食度得分 (0 ~ 100)
  final String diversityLabel; // 杂食度评级文字
  final String activeTimeSlotLabel; // 追番活跃时段标签
  final String activeTimeSlotDesc; // 追番活跃时段描述
  final Map<String, List<String>> genreAnimeSamples; // 题材代表作归属溯源
  final int totalCollectionCount; // 收藏总数
  final Map<CollectType, int> collectionCounts; // 各分类数量统计
  final double completionRate; // 追番完结率: watched / (watched + watching + abandoned)

  const AnimeAnalyticsReport({
    required this.totalAnimeCount,
    required this.totalEpisodesCount,
    required this.totalWatchHours,
    required this.topGenres,
    required this.allGenreCounts,
    required this.personaTitle,
    required this.personaDescription,
    required this.diversityScore,
    required this.diversityLabel,
    required this.activeTimeSlotLabel,
    required this.activeTimeSlotDesc,
    required this.genreAnimeSamples,
    this.totalCollectionCount = 0,
    this.collectionCounts = const {},
    this.completionRate = 0.0,
  });

  /// 完结率格式化文本
  String get completionRateText =>
      '${(completionRate * 100).toStringAsFixed(1)}%';

  /// 是否为空数据（未看过任何番剧且无追番）
  bool get isEmpty => totalAnimeCount == 0 && totalCollectionCount == 0;

  /// 空数据时的默认兜底报告
  factory AnimeAnalyticsReport.empty() {
    return const AnimeAnalyticsReport(
      totalAnimeCount: 0,
      totalEpisodesCount: 0,
      totalWatchHours: 0.0,
      topGenres: [],
      allGenreCounts: {},
      personaTitle: '初入次元的萌新',
      personaDescription: '暂无播放与追番记录，去看几部喜欢的番剧或添加追番即可解锁你的专属算法画像 ( ╹▽╹ )',
      diversityScore: 0,
      diversityLabel: '尚待探索',
      activeTimeSlotLabel: '暂无时段',
      activeTimeSlotDesc: '等待首次播放记录...',
      genreAnimeSamples: {},
      totalCollectionCount: 0,
      collectionCounts: {},
      completionRate: 0.0,
    );
  }
}
