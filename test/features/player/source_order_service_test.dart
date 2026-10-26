import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/services/source_order_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SourceOrderService.instance.resetToDefaultOrder();
  });

  group('SourceOrderService 排序与偏好中枢测试', () {
    test('1. 默认状态下按出厂推荐顺序排序', () {
      final raw = [
        const SourceMeta(id: 'lzizy', name: '量子资源', version: '1.0'),
        const SourceMeta(id: 'xifan-next', name: '稀饭Next', version: '1.0'),
        const SourceMeta(id: 'cycani', name: '次元城', version: '1.0'),
      ];

      final ordered = SourceOrderService.instance.getOrderedSources(raw);
      expect(ordered.map((s) => s.id).toList(), ['xifan-next', 'cycani', 'lzizy']);
    });

    test('2. 未知新源平滑追加在队尾，不丢失', () {
      final raw = [
        const SourceMeta(id: 'unknown-remote-source', name: '远程扩展源', version: '1.0'),
        const SourceMeta(id: 'xifan-next', name: '稀饭Next', version: '1.0'),
      ];

      final ordered = SourceOrderService.instance.getOrderedSources(raw);
      expect(ordered.first.id, 'xifan-next');
      expect(ordered.last.id, 'unknown-remote-source');
    });

    test('3. 用户自定义排序持久化与生效', () async {
      await SourceOrderService.instance.updateCustomOrder(['cycani', 'mifun', 'xifan-next']);

      final raw = [
        const SourceMeta(id: 'xifan-next', name: '稀饭Next', version: '1.0'),
        const SourceMeta(id: 'mifun', name: 'MiFun', version: '1.0'),
        const SourceMeta(id: 'cycani', name: '次元城', version: '1.0'),
      ];

      final ordered = SourceOrderService.instance.getOrderedSources(raw);
      expect(ordered.map((s) => s.id).toList(), ['cycani', 'mifun', 'xifan-next']);
    });

    test('4. 禁用源黑名单过滤', () async {
      await SourceOrderService.instance.setSourceEnabled('cycani', false);

      final raw = [
        const SourceMeta(id: 'xifan-next', name: '稀饭Next', version: '1.0'),
        const SourceMeta(id: 'cycani', name: '次元城', version: '1.0'),
      ];

      final ordered = SourceOrderService.instance.getOrderedSources(raw);
      expect(ordered.map((s) => s.id).toList(), ['xifan-next']);
    });

    test('5. getTopSources 严密防越界保护：当可用源数量少于 5 个时安全截取', () {
      // 场景 A: 仅有 2 个源，请求 5 个，安全返回 2 个，不越界
      final raw2 = [
        const SourceMeta(id: 'xifan-next', name: '稀饭Next', version: '1.0'),
        const SourceMeta(id: 'cycani', name: '次元城', version: '1.0'),
      ];
      final top2 = SourceOrderService.instance.getTopSources(raw2, maxCount: 5);
      expect(top2.length, 2);
      expect(top2.map((s) => s.id).toList(), ['xifan-next', 'cycani']);

      // 场景 B: 0 个源，安全返回空列表
      final top0 = SourceOrderService.instance.getTopSources([], maxCount: 5);
      expect(top0, isEmpty);

      // 场景 C: 8 个源，安全截取前 5 个
      final raw8 = List.generate(
        8,
        (i) => SourceMeta(id: 'source_$i', name: 'Source $i', version: '1.0'),
      );
      final top5 = SourceOrderService.instance.getTopSources(raw8, maxCount: 5);
      expect(top5.length, 5);
    });

    test('6. preferredSourceId 追番指定源安全置顶', () {
      final raw = [
        const SourceMeta(id: 'xifan-next', name: '稀饭Next', version: '1.0'),
        const SourceMeta(id: 'cycani', name: '次元城', version: '1.0'),
        const SourceMeta(id: 'girigiri', name: 'girigiri', version: '1.0'),
      ];

      // 指定第 3 顺位的 girigiri 置顶
      final top = SourceOrderService.instance.getTopSources(
        raw,
        maxCount: 5,
        preferredSourceId: 'girigiri',
      );

      expect(top.first.id, 'girigiri');
      expect(top.length, 3);
    });

    test('7. 权重降序 (60 > 59 > 58 > 50) 且同权按名称字母升序排序', () {
      final raw = [
        const SourceMeta(id: 'mifun', name: 'MiFun', version: '1.0'), // 58
        const SourceMeta(id: 'gugu', name: 'gugu', version: '1.0'), // 59
        const SourceMeta(id: 'cycani', name: 'cycani', version: '1.0'), // 59
        const SourceMeta(id: 'neosekai', name: 'neosek', version: '1.0'), // 60
        const SourceMeta(id: 'xifan-next', name: 'xifan', version: '1.0'), // 60
        const SourceMeta(id: 'tvtfun', name: 'TvTFun', version: '1.0'), // 58
        const SourceMeta(id: 'libvio', name: 'libvio', version: '1.0'), // 50
        const SourceMeta(id: 'anime1', name: 'anime1', version: '1.0'), // 50
      ];

      final ordered = SourceOrderService.instance.getOrderedSources(raw);
      final ids = ordered.map((s) => s.id).toList();

      // 60 梯队: neosek, xifan -> 按字母: neosekai, xifan-next
      expect(ids[0], 'neosekai');
      expect(ids[1], 'xifan-next');

      // 59 梯队: cycani, gugu -> 按字母: cycani, gugu
      expect(ids[2], 'cycani');
      expect(ids[3], 'gugu');

      // 58 梯队: MiFun, TvTFun -> 按字母: MiFun, TvTFun
      expect(ids[4], 'mifun');
      expect(ids[5], 'tvtfun');

      // 50 梯队: anime1, libvio -> 按字母: anime1, libvio
      expect(ids[6], 'anime1');
      expect(ids[7], 'libvio');
    });
  });
}
