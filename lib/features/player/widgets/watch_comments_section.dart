import 'package:flutter/material.dart';
import '../../../core/utils/font_manager.dart';
import '../../common/widgets/bouncing_scale_card.dart';

/// 播放页评论区/吐槽区占位组件 (高仿真热评与长流式讨论区，预留真实 Bangumi 评论接入)
class WatchCommentsSection extends StatefulWidget {
  const WatchCommentsSection({super.key});

  @override
  State<WatchCommentsSection> createState() => _WatchCommentsSectionState();
}

class _WatchCommentsSectionState extends State<WatchCommentsSection> {
  int _selectedSortIndex = 0; // 0: 热门, 1: 最新

  static const List<Map<String, dynamic>> _placeholderComments = [
    {
      'name': '辛美尔的迷弟',
      'avatarColor': Color(0xFF6750A4),
      'score': 5,
      'time': '2小时前',
      'content': '「如果是辛美尔的话，他一定会这么做的吧。」分镜和台词真的封神了，那种淡淡的哀伤和释怀让人回味无穷！',
      'likes': 382,
      'replies': 24,
    },
    {
      'name': '魔法使芙莉莲',
      'avatarColor': Color(0xFF006C50),
      'score': 5,
      'time': '5小时前',
      'content': '作画质量完全是剧场版级别的，战斗部分的魔法粒子特效太炸裂了，MADHOUSE 这一次真的拿出了全盛期的水准。',
      'likes': 219,
      'replies': 16,
    },
    {
      'name': '旅人菲伦',
      'avatarColor': Color(0xFF8F4C38),
      'score': 4,
      'time': '昨天',
      'content': '节奏很慢，但这种公路片般的温吞感正是这部作品最大的魅力所在，非常适合下班后静下心来看。',
      'likes': 145,
      'replies': 8,
    },
    {
      'name': '修塔尔克小跟班',
      'avatarColor': Color(0xFF3B5998),
      'score': 5,
      'time': '前天',
      'content': 'OP 和 ED 都好好听！Evan Call 的配乐无敌了，每次小提琴一响浑身起鸡皮疙瘩。年度霸权无悬念！',
      'likes': 96,
      'replies': 5,
    },
    {
      'name': '动漫考古学家',
      'avatarColor': Color(0xFF7A5700),
      'score': 4,
      'time': '3天前',
      'content': '对时间流逝的刻画非常深刻，凡人的几十年在长生种眼里不过是一瞬，但那一瞬却改变了芙莉莲的整个世界。',
      'likes': 64,
      'replies': 2,
    },
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        // 1. 顶部排序与总数统计栏
        Row(
          children: [
            const Text(
              '讨论吐槽',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '892 条',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                fontFamily: 'MiSans',
                fontFamilyFallback: FontManager.fallbackFontFamilies,
              ),
            ),
            const Spacer(),
            // 排序切换 (热门 / 最新)
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  _buildSortTab('按热度', 0, isDark, primaryColor),
                  _buildSortTab('按最新', 1, isDark, primaryColor),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        // 2. 发吐槽快捷占位栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(8),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.edit_note_rounded,
                size: 18,
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '发一条友善的吐槽吧 (支持 Bangumi 同步)...',
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                    fontFamily: 'MiSans',
                    fontFamilyFallback: FontManager.fallbackFontFamilies,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. 评论列表
        ..._placeholderComments.map((comment) {
          final name = comment['name'] as String;
          final avatarColor = comment['avatarColor'] as Color;
          final score = comment['score'] as int;
          final time = comment['time'] as String;
          final content = comment['content'] as String;
          final likes = comment['likes'] as int;
          final replies = comment['replies'] as int;

          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 用户头像圆角徽章
                CircleAvatar(
                  radius: 17,
                  backgroundColor: avatarColor,
                  child: Text(
                    name.isNotEmpty ? name.characters.first : 'U',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      fontFamily: 'MiSans',
                      fontFamilyFallback: FontManager.fallbackFontFamilies,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 评论主体
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 用户名与评分
                      Row(
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.9),
                              fontFamily: 'MiSans',
                              fontFamilyFallback: FontManager.fallbackFontFamilies,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Row(
                            children: List.generate(
                              score,
                              (_) => const Icon(
                                Icons.star_rounded,
                                size: 12,
                                color: Color(0xFFFFB300),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            time,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                              fontFamily: 'MiSans',
                              fontFamilyFallback: FontManager.fallbackFontFamilies,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      // 评论正文
                      Text(
                        content,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          letterSpacing: -0.1,
                          color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.88),
                          fontFamily: 'MiSans',
                          fontFamilyFallback: FontManager.fallbackFontFamilies,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 底部互动行
                      Row(
                        children: [
                          Icon(
                            Icons.thumb_up_alt_outlined,
                            size: 13,
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$likes',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                              fontFamily: 'MiSans',
                              fontFamilyFallback: FontManager.fallbackFontFamilies,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 13,
                            color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$replies 回复',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                              fontFamily: 'MiSans',
                              fontFamilyFallback: FontManager.fallbackFontFamilies,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSortTab(String label, int index, bool isDark, Color primaryColor) {
    final isSelected = _selectedSortIndex == index;
    return BouncingScaleCard(
      scaleDown: 0.94,
      immediateTap: true,
      onTap: () => setState(() => _selectedSortIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3.5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white.withValues(alpha: 0.18) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? (isDark ? Colors.white : primaryColor)
                : Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
            fontFamily: 'MiSans',
            fontFamilyFallback: FontManager.fallbackFontFamilies,
          ),
        ),
      ),
    );
  }
}
