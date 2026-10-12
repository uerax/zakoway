import 'package:flutter/material.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/bouncing_scale_card.dart';

/// 播放页视频推荐区占位组件 (精美仿真卡片流，预留真实数据接入)
class WatchRecommendSection extends StatelessWidget {
  const WatchRecommendSection({
    super.key,
    this.onTapItem,
  });

  final ValueChanged<String>? onTapItem;

  // 占位推荐数据项
  static const List<Map<String, String>> _placeholderAnimes = [
    {
      'title': '葬送的芙莉莲',
      'score': '8.8',
      'tags': '奇幻 · 冒险 · 治愈',
      'eps': '全 28 话',
      'desc': '打倒魔王之后的勇者一行人，精灵魔法使的漫长旅途...',
    },
    {
      'title': '迷宫饭',
      'score': '8.5',
      'tags': '美食 · 奇幻 · 搞笑',
      'eps': '全 24 话',
      'desc': '在深邃的地下迷宫中，品尝魔物料理的独特冒险。',
    },
    {
      'title': '药屋少女的呢喃',
      'score': '8.4',
      'tags': '宫廷 · 推理 · 悬疑',
      'eps': '全 24 话',
      'desc': '毒物研究狂热少女，解开后宫层出不穷的神秘疑案。',
    },
    {
      'title': '咒术回战 怀玉·玉折 / 涩谷事变',
      'score': '8.6',
      'tags': '热血 · 战斗 · 奇幻',
      'eps': '全 23 话',
      'desc': '无法回溯的青春时光，与即将到来的宏大决战。',
    },
    {
      'title': '间谍过家家 第二季',
      'score': '8.1',
      'tags': '搞笑 · 日常 · 动作',
      'eps': '全 12 话',
      'desc': '各自心怀秘密的临时家庭，欢乐而温馨的日常任务。',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题与副标
          Row(
            children: [
              Container(
                width: 3.5,
                height: 14,
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '猜你喜欢',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  fontFamily: 'MiSans',
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '· 同类题材与高分精选',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                  fontFamily: 'MiSans',
                  fontFamilyFallback: FontManager.fallbackFontFamilies,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 推荐卡片纵向流
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _placeholderAnimes.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final anime = _placeholderAnimes[index];
              return BouncingScaleCard(
                scaleDown: 0.97,
                immediateTap: true,
                onTap: () {
                  onTapItem?.call(anime['title']!);
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '点击了推荐番剧: 《${anime['title']}》(占位态)',
                        style: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                      ),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      // 封面占位图 (带圆角和渐变)
                      Container(
                        width: 58,
                        height: 78,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isDark
                                ? [
                                    primaryColor.withValues(alpha: 0.25),
                                    const Color(0xFF282830),
                                  ]
                                : [
                                    primaryColor.withValues(alpha: 0.15),
                                    const Color(0xFFE8E8ED),
                                  ],
                          ),
                        ),
                        child: Icon(
                          Icons.play_circle_outline_rounded,
                          size: 26,
                          color: primaryColor.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 推荐信息
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              anime['title']!,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                fontFamily: 'MiSans',
                                fontFamilyFallback: FontManager.fallbackFontFamilies,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.star_rounded,
                                  size: 14,
                                  color: Color(0xFFFFB300),
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  anime['score']!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFFFB300),
                                    fontFamily: 'MiSans',
                                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '· ${anime['eps']}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                                    fontFamily: 'MiSans',
                                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              anime['desc']!,
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.3,
                                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.65),
                                fontFamily: 'MiSans',
                                fontFamilyFallback: FontManager.fallbackFontFamilies,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.3),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
