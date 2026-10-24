import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/core/backend/playback_engine_pool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PlaybackEnginePool 单元测试', () {
    test('单测环境下 acquire 安全返回 null 避免污染', () {
      final acquired = PlaybackEnginePool.instance.acquire();
      expect(acquired, isNull);
    });

    test('disposeAll 幂等安全执行', () async {
      await PlaybackEnginePool.instance.disposeAll();
    });
  });
}
