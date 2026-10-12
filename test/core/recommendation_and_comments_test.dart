import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/core/models/bangumi/bangumi_user.dart';
import 'package:zakoway/core/network/bangumi_client.dart';

void main() {
  group('BangumiRecommendationItem model tests', () {
    test('fromJson and toJson mapping', () {
      final json = {
        'id': 364450,
        'name': '葬送のフリーレン',
        'name_cn': '葬送的芙莉莲',
        'cover': 'https://lain.bgm.tv/pic/cover/l/test.jpg',
        'score': 8.8,
        'year': '2023',
        'eps_label': '全28话',
        'relation_badge': '续作',
      };

      final item = BangumiRecommendationItem.fromJson(json);
      expect(item.id, 364450);
      expect(item.name, '葬送のフリーレン');
      expect(item.displayName, '葬送的芙莉莲');
      expect(item.score, 8.8);
      expect(item.year, '2023');
      expect(item.epsLabel, '全28话');
      expect(item.relationBadge, '续作');

      final serialized = item.toJson();
      expect(serialized['id'], 364450);
      expect(serialized['relation_badge'], '续作');
    });
  });

  group('BangumiCommentItem model tests', () {
    test('fromJson, rating, and relativeTime formatting', () {
      final json = {
        'id': 52975924,
        'user': {
          'id': 1247839,
          'username': 'megumin',
          'nickname': '惠惠',
          'avatar': {
            'large': 'https://lain.bgm.tv/pic/user/l/avatar.jpg',
          },
          'sign': 'Explosion!',
        },
        'type': 2,
        'rate': 9,
        'comment': '神作不解释',
        'updated_at': 1788108863,
      };

      final comment = BangumiCommentItem.fromJson(json);
      expect(comment.id, 52975924);
      expect(comment.author.nickname, '惠惠');
      expect(comment.author.avatarUrl, 'https://lain.bgm.tv/pic/user/l/avatar.jpg');
      expect(comment.rate, 9);
      expect(comment.starScore, 4.5);
      expect(comment.collectionType, 2);
      expect(comment.collectionTypeLabel, '看过');
      expect(comment.content, '神作不解释');
      expect(comment.createdAt, isNotNull);
    });

    test('Collection type labels mapping', () {
      expect(
        const BangumiCommentItem(
          id: 1,
          author: BangumiUser(id: 1, username: 'u', nickname: 'n'),
          content: 'c',
          updatedAt: '',
          collectionType: 1,
        ).collectionTypeLabel,
        '想看',
      );
      expect(
        const BangumiCommentItem(
          id: 2,
          author: BangumiUser(id: 1, username: 'u', nickname: 'n'),
          content: 'c',
          updatedAt: '',
          collectionType: 3,
        ).collectionTypeLabel,
        '在看',
      );
    });
  });

  group('BangumiClient recommendation & comment pagination algorithms', () {
    test('comments page safe guard (> 2000 returns empty immediately)', () async {
      final client = BangumiClient();
      final res = await client.getCommentsPage(364450, page: 2001);
      expect(res.items, isEmpty);
      expect(res.total, 0);
    });

    test('comments page safe guard (< 1 or invalid id returns empty immediately)', () async {
      final client = BangumiClient();
      final res1 = await client.getCommentsPage(0, page: 1);
      expect(res1.items, isEmpty);
      final res2 = await client.getCommentsPage(364450, page: 0);
      expect(res2.items, isEmpty);
    });

    test('real getRecommendations call', () async {
      final client = BangumiClient();
      final recs = await client.getRecommendations(364450);
      expect(recs.length, greaterThanOrEqualTo(10));
    });

    test('mirror getRecommendations call', () async {
      final client = BangumiClient(baseUrl: 'https://bgmapi.anibt.net');
      final recs = await client.getRecommendations(364450);
      expect(recs.length, greaterThanOrEqualTo(10));
    });
  });
}
