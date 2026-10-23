import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/source/sources/girigiri_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('GirigiriSource 2026 API 重构适配测试', () {
    test('1. 验证元数据定义', () {
      final source = GirigiriSource();
      expect(source.id, 'girigiri');
      expect(source.name, 'girigiri');
      expect(source.version, '1.4.0');
      expect(source.isDirect, isFalse);
    });

    test('2. 真实搜索 API 连通性测试 (葬送的芙莉莲)', () async {
      final source = GirigiriSource();
      final results = await source.search('葬送的芙莉莲');
      expect(results, isNotEmpty);
      expect(results.first.name, contains('芙莉莲'));
      expect(results.first.url, contains('/detail/'));

      // 3. 选集与多线路解析测试
      final roads = await source.chapters(results.first.url);
      expect(roads, isNotEmpty);
      expect(roads.first.episodes, isNotEmpty);
      expect(roads.first.episodes.first.url, anyOf(contains('.m3u8'), contains('.mp4')));

      // 4. 直链解析测试 (零网络往返直接透传)
      final directMedia = await source.resolve(roads.first.episodes.first.url);
      expect(directMedia.url, roads.first.episodes.first.url);
      expect(directMedia.format, anyOf('hls', 'mp4'));
      expect(directMedia.headers['Referer'], 'https://ani.girigirilove.com/');
    });
  });
}
