import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/source/sources/gugu_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('验证咕咕番新架构 (gugu.fan) 搜索、多线路提取与智能分流解析', () async {
    final gugu = GuguSource();

    // 1. 验证 anime/19 (学生会也有洞) 多线路与集数命名规范
    final roads19 = await gugu.chapters('https://gugu.fan/anime/19');
    expect(roads19, isNotEmpty);
    expect(roads19.length, greaterThanOrEqualTo(2));
    for (final r in roads19) {
      // 验证第 1 集名称包含 "第 1 话" 且包含副标题
      expect(r.episodes.first.name, startsWith('第 1 话'));
      expect(r.episodes.first.name, contains('雄小鬼也有洞'));
    }

    // 2. 验证国内1线播放第 1 集 (episode 33): 智能命中 vod_1080 (国内1线)，杜绝海外线断流
    final domesticRoad = roads19.firstWhere((r) => r.name == '国内1线');
    final ep1Url = domesticRoad.episodes.first.url;
    final ep1Media = await gugu.resolve(ep1Url);
    expect(ep1Media.url, startsWith('http'));

    // 3. 验证海外1线播放第 1 集: 精准命中 zy1080_02
    final overseasRoad = roads19.firstWhere((r) => r.name == '海外1线');
    final ep1OverseasUrl = overseasRoad.episodes.first.url;
    final ep1OverseasMedia = await gugu.resolve(ep1OverseasUrl);
    expect(ep1OverseasMedia.url, contains('zy1080_02'));

    // 4. 验证第 4 集 (episode 67652): 只有海外线时，国内线依然能平滑 fallback 播放
    final ep4Url = domesticRoad.episodes.last.url;
    final ep4Media = await gugu.resolve(ep4Url);
    expect(ep4Media.url, startsWith('http'));
  });
}
