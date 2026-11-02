import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/features/player/source/engines/local_source_engine.dart';
import 'package:zakoway/features/player/source/models/source_models.dart';
import 'package:zakoway/features/player/source/services/source_order_service.dart';
import 'package:zakoway/features/player/source/sources/bimi_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SourceOrderService.instance.resetToDefaultOrder();
  });

  group('BimiSource 基础属性与架构集成测试', () {
    test('1. BimiSource 元数据符合规范 (id: bimi, 权重 60 对齐 xifan-next, 直连)', () {
      final source = BimiSource();
      expect(source.id, 'bimi');
      expect(source.name, '哔咪');
      expect(source.weight, 60);
      expect(source.isDirect, true);
    });

    test('2. SourceOrderService 中 bimi 权重与 xifan-next 严格一致 (60)', () {
      final bimiMeta = const SourceMeta(id: 'bimi', name: '哔咪', version: '1.0');
      final xifanMeta = const SourceMeta(id: 'xifan-next', name: '稀饭Next', version: '1.0');

      final bimiWeight = SourceOrderService.instance.getSourceWeight(bimiMeta);
      final xifanWeight = SourceOrderService.instance.getSourceWeight(xifanMeta);

      expect(bimiWeight, 60);
      expect(xifanWeight, 60);
      expect(bimiWeight, equals(xifanWeight));
    });

    test('3. LocalSourceEngine 成功挂载 bimi 源，位居头部优先位序', () {
      final engine = LocalSourceEngine();
      expect(engine.isLocalSource('bimi'), true);

      final source = engine.getSource('bimi');
      expect(source, isNotNull);
      expect(source!.id, 'bimi');
      expect(source.isDirect, true);

      final sources = engine.availableSources;
      final ids = sources.map((s) => s.id).toList();
      expect(ids.contains('bimi'), true);

      // 验证位居前列（仅次于 xifan-next）
      final xifanIdx = ids.indexOf('xifan-next');
      final bimiIdx = ids.indexOf('bimi');
      expect(xifanIdx, isNonNegative);
      expect(bimiIdx, isNonNegative);
      expect(bimiIdx, equals(xifanIdx + 1));
    });
  });
}
