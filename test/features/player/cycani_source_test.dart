import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/features/player/source/sources/cycani_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.init();
  });

  test('验证次元城 (cycani.org) 鉴权 Token 持久化与失效双清重试', () async {
    final cycani = CycaniSource();

    // 1. 搜索与分集提取
    final searchResults = await cycani.search('芙莉莲');
    expect(searchResults, isNotEmpty);
    final firstHit = searchResults.first;
    expect(firstHit.url, contains('/anime/'));

    final roads = await cycani.chapters(firstHit.url);
    expect(roads, isNotEmpty);
    expect(roads.first.episodes, isNotEmpty);

    // 2. 直链解析与 Token 本地持久化测试
    final ep1Url = roads.first.episodes.first.url;
    final media = await cycani.resolve(ep1Url);
    expect(media.url, startsWith('http'));

    final savedToken = AppPreferences.getCycaniToken();
    final savedExpiresAt = AppPreferences.getCycaniTokenExpiresAt();
    expect(savedToken, isNotNull);
    expect(savedToken, startsWith('Bearer '));
    expect(savedExpiresAt, greaterThan(DateTime.now().millisecondsSinceEpoch));

    // 3. 验证 Token 失效自动双清并重新登录重试
    await AppPreferences.setCycaniToken('Bearer invalid_token_99999', DateTime.now().millisecondsSinceEpoch + 1000000);
    final freshCycani = CycaniSource();
    final retryMedia = await freshCycani.resolve(ep1Url);
    expect(retryMedia.url, startsWith('http'));

    final refreshedToken = AppPreferences.getCycaniToken();
    expect(refreshedToken, isNotNull);
    expect(refreshedToken, isNot(equals('Bearer invalid_token_99999')));
    expect(refreshedToken, startsWith('Bearer '));
  });
}
