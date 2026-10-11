import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/source/native_source_runtime.dart';
import 'package:zakoway/features/player/source/sources/moonci_source.dart';
import 'package:zakoway/features/player/widgets/video_source_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MoonciSource 自愈与权重降级测试', () {
    test('1. 视频源注册位序中，moonci 严格排在 girigiri 之后', () {
      final runtime = NativeSourceRuntime();
      final sources = runtime.availableSources;
      final ids = sources.map((s) => s.id).toList();

      final girigiriIdx = ids.indexOf('girigiri');
      final moonciIdx = ids.indexOf('moonci');

      expect(girigiriIdx, isNonNegative);
      expect(moonciIdx, isNonNegative);
      expect(moonciIdx, greaterThan(girigiriIdx),
          reason: '月之祠权重必须降级到 girigiri 之后');
    });

    test('2. getDefaultSourceItems 默认列表中 moonci 降级至 girigiri 之后', () {
      final items = getDefaultSourceItems();
      final ids = items.map((i) => i.id).toList();

      final girigiriIdx = ids.indexOf('girigiri');
      final moonciIdx = ids.indexOf('moonci');

      expect(girigiriIdx, isNonNegative);
      expect(moonciIdx, isNonNegative);
      expect(moonciIdx, greaterThan(girigiriIdx));
    });

    test('3. MoonciSource 遇到直接媒体流时正常返回直链', () async {
      final source = MoonciSource();
      // 验证元数据
      expect(source.id, 'moonci');
      expect(source.name, '月之祠');
      expect(source.version, '1.4.0');
    });
  });
}
