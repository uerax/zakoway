library;

/// 评论区内容过滤与局部遮掩分词引擎 (1:1 复刻 animaku comment-censor 规范)
///
/// 采用规则词法扫描与贪心仲裁算法，将纯文本解析为结构化 AST Token 列表，
/// 供 UI 呈现黑幕遮掩（Heimu）与点击解密显示。

enum CommentTokenType {
  text,
  link,
  socialLead,
  number,
}

class CommentTextToken {
  final CommentTokenType type;
  final String raw;
  final String? label;
  final String? url;
  final bool redacted;

  const CommentTextToken({
    required this.type,
    required this.raw,
    this.label,
    this.url,
    required this.redacted,
  });
}

class _CensorMatch {
  final int start;
  final int end;
  final String raw;
  final CommentTokenType type;
  final String? label;
  final String? url;
  final int priority;

  const _CensorMatch({
    required this.start,
    required this.end,
    required this.raw,
    required this.type,
    this.label,
    this.url,
    required this.priority,
  });
}

class CommentCensorEngine {
  CommentCensorEngine._();

  /// 匹配带协议的 URL 以及主流裸域名/短链 (杜绝中文标点误伤)
  static final RegExp urlPattern = RegExp(
    r'''(?:https?:\/\/)?(?:[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+(?:com|cn|net|org|tv|vg|me|io|cc|top|xyz|vip|site|link|app|fun|moe|dev|ai|gg|co|info|icu|space|la|pw|in)(?::\d{2,5})?(?:\/[^\s一-龥<>"'()（）\[\]]*)?''',
    caseSensitive: false,
  );

  /// 匹配中文社交引流与群号 (QQ群, 企鹅裙, +vx, TG, 等)
  static final RegExp socialLeadPattern = RegExp(
    r'(?:QQ群?|[qQ]群?|企鹅[裙群]?|扣扣[裙群]?|加[裙群]|群号|微信|微信号?|[vV][xX]|TG|tg|电报)[\s:：#号*]*([a-zA-Z0-9_@-]{5,20})',
    caseSensitive: false,
  );

  /// 匹配 6~11 位孤立纯长数字 (通过负向断言自动排除年份、第几集、评分、1080P等自然表达)
  static final RegExp unknownNumberPattern = RegExp(
    r'(?<!\d|\.)([1-9]\d{5,10})(?!\d|\.|年|集|话|分|[pP]|fps)',
  );

  /// 词法分词纯函数：将文本解析为 AST Token 列表
  static List<CommentTextToken> tokenize(String text) {
    if (text.isEmpty) return const [];

    final matches = <_CensorMatch>[];

    // 1. 扫描 URL 规则 (优先级 0)
    for (final m in urlPattern.allMatches(text)) {
      final raw = m.group(0);
      if (raw == null || raw.isEmpty) continue;
      final url = (raw.startsWith('http://') || raw.startsWith('https://'))
          ? raw
          : 'https://$raw';
      matches.add(_CensorMatch(
        start: m.start,
        end: m.end,
        raw: raw,
        type: CommentTokenType.link,
        label: '外部链接',
        url: url,
        priority: 0,
      ));
    }

    // 2. 扫描社交引流规则 (优先级 1)
    for (final m in socialLeadPattern.allMatches(text)) {
      final raw = m.group(0);
      if (raw == null || raw.isEmpty) continue;
      matches.add(_CensorMatch(
        start: m.start,
        end: m.end,
        raw: raw,
        type: CommentTokenType.socialLead,
        label: '疑似引流',
        priority: 1,
      ));
    }

    // 3. 扫描孤立长数字串码 (优先级 2)
    for (final m in unknownNumberPattern.allMatches(text)) {
      final raw = m.group(0);
      if (raw == null || raw.isEmpty) continue;
      matches.add(_CensorMatch(
        start: m.start,
        end: m.end,
        raw: raw,
        type: CommentTokenType.number,
        label: '串码',
        priority: 2,
      ));
    }

    if (matches.isEmpty) {
      return [CommentTextToken(type: CommentTokenType.text, raw: text, redacted: false)];
    }

    // 4. 按起始位置升序排序；若起始位置相同，按优先级升序排序
    matches.sort((a, b) {
      if (a.start != b.start) return a.start.compareTo(b.start);
      return a.priority.compareTo(b.priority);
    });

    // 5. 贪心消除重叠区间
    final nonOverlapping = <_CensorMatch>[];
    var currentEnd = 0;
    for (final m in matches) {
      if (m.start >= currentEnd) {
        nonOverlapping.add(m);
        currentEnd = m.end;
      }
    }

    // 6. 构建 AST Token 列表
    final tokens = <CommentTextToken>[];
    var cursor = 0;

    for (final item in nonOverlapping) {
      if (item.start > cursor) {
        tokens.add(CommentTextToken(
          type: CommentTokenType.text,
          raw: text.substring(cursor, item.start),
          redacted: false,
        ));
      }

      tokens.add(CommentTextToken(
        type: item.type,
        raw: item.raw,
        label: item.label,
        url: item.url,
        redacted: true,
      ));

      cursor = item.end;
    }

    if (cursor < text.length) {
      tokens.add(CommentTextToken(
        type: CommentTokenType.text,
        raw: text.substring(cursor),
        redacted: false,
      ));
    }

    return tokens;
  }
}
