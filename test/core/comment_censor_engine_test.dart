import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/core/utils/comment_censor_engine.dart';

void main() {
  group('CommentCensorEngine tokenize tests', () {
    test('Empty and plain text without matches', () {
      expect(CommentCensorEngine.tokenize(''), isEmpty);

      final tokens = CommentCensorEngine.tokenize('这部动画太好看了，音乐也很神！');
      expect(tokens.length, 1);
      expect(tokens.first.type, CommentTokenType.text);
      expect(tokens.first.raw, '这部动画太好看了，音乐也很神！');
      expect(tokens.first.redacted, false);
    });

    test('URL patterns detection and redaction', () {
      const text = '大家去 https://bgm.tv 看看，或者访问 b23.tv/anime 查看详情';
      final tokens = CommentCensorEngine.tokenize(text);

      expect(tokens.length, greaterThan(1));
      final urlTokens = tokens.where((t) => t.type == CommentTokenType.link).toList();
      expect(urlTokens.length, 2);
      expect(urlTokens[0].raw, 'https://bgm.tv');
      expect(urlTokens[0].redacted, true);
      expect(urlTokens[0].url, 'https://bgm.tv');
      expect(urlTokens[1].raw, 'b23.tv/anime');
      expect(urlTokens[1].url, 'https://b23.tv/anime');
    });

    test('Social lead patterns detection', () {
      const text = '欢迎加入QQ群: 98765432 交流，或者加微信号 wx_test99';
      final tokens = CommentCensorEngine.tokenize(text);

      final socialTokens = tokens.where((t) => t.type == CommentTokenType.socialLead).toList();
      expect(socialTokens.length, 2);
      expect(socialTokens[0].redacted, true);
      expect(socialTokens[0].label, '疑似引流');
      expect(socialTokens[1].redacted, true);
    });

    test('Unknown numbers vs natural numbers (negative lookahead/behind)', () {
      // 83749281 应被识别为串码；2024年、第12集、8.5分、1080P 不应被误判为串码
      const text = '2024年播出的第12集得到了8.5分的高评价，高清1080P。但这个人发了83749281串码';
      final tokens = CommentCensorEngine.tokenize(text);

      final numberTokens = tokens.where((t) => t.type == CommentTokenType.number).toList();
      expect(numberTokens.length, 1);
      expect(numberTokens.first.raw, '83749281');
      expect(numberTokens.first.redacted, true);

      // 验证自然数字依然完好保留在 text token 中
      final normalText = tokens.where((t) => !t.redacted).map((t) => t.raw).join();
      expect(normalText.contains('2024年'), isTrue);
      expect(normalText.contains('第12集'), isTrue);
      expect(normalText.contains('8.5分'), isTrue);
      expect(normalText.contains('1080P'), isTrue);
    });
  });
}
