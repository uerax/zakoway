import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/features/player/source/sources/gugu_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.init();
  });

  test('验证咕咕番新架构 (gugu.fan) 双线路顺位锁定与解析（无后台换源容灾）', () async {
    final gugu = GuguSource();

    // 1. 验证 anime/19 (学生会也有洞) 双线路划分与分集命名规范
    final roads19 = await gugu.chapters('https://gugu.fan/anime/19');
    expect(roads19, isNotEmpty);
    expect(roads19.length, equals(2));
    expect(roads19.first.name, equals('国内线路'));
    expect(roads19.last.name, equals('海外线路'));

    for (final r in roads19) {
      // 验证第 1 集名称包含 "第 1 话" 且包含副标题
      expect(r.episodes.first.name, startsWith('第 1 话'));
      expect(r.episodes.first.name, contains('雄小鬼也有洞'));
    }

    // 2. 验证 anime/19 第 1 集国内线路: 无国内2线时，顺位锁定 vod_1080 (国内1线)，起播成功
    final domesticRoad = roads19.firstWhere((r) => r.name == '国内线路');
    final ep1Url = domesticRoad.episodes.first.url;
    final ep1Media = await gugu.resolve(ep1Url);
    expect(ep1Media.url, startsWith('http'));

    // 3. 验证 anime/19 第 1 集海外线路: 顺位锁定 zy1080_02 (海外1线)，起播成功
    final overseasRoad = roads19.firstWhere((r) => r.name == '海外线路');
    final ep1OverseasUrl = overseasRoad.episodes.first.url;
    final ep1OverseasMedia = await gugu.resolve(ep1OverseasUrl);
    expect(ep1OverseasMedia.url, contains('zy1080_02'));

    // 4. 验证 FX战士久留美 第 4 集 (episode 67633) 国内线路: 顺位优先锁定国内2线 (zy1080_01)，秒播成功且避开 503
    final fx4Url = 'https://gugu.fan/watch/1?episode=67633&preferred_source=domestic';
    final fx4Media = await gugu.resolve(fx4Url);
    expect(fx4Media.url, contains('kqgfbs.com')); // zy1080_01 国内直链

    // 5. 验证 Session Cookie 成功持久化保存
    final savedCookie = AppPreferences.getGuguSessionCookie();
    expect(savedCookie, isNotNull);
    expect(savedCookie, contains('ggf_viewer_session='));

    // 6. 验证 Cookie 失效（401）时自动双清并重新登录重试成功
    await AppPreferences.setGuguSessionCookie('invalid_expired_session_99999');
    final freshGugu = GuguSource();
    final retryMedia = await freshGugu.resolve(fx4Url);
    expect(retryMedia.url, contains('kqgfbs.com'));
    final refreshedCookie = AppPreferences.getGuguSessionCookie();
    expect(refreshedCookie, isNotNull);
    expect(refreshedCookie, isNot(equals('invalid_expired_session_99999')));
    expect(refreshedCookie, contains('ggf_viewer_session='));
  });
}
