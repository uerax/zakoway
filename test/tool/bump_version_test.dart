import 'package:flutter_test/flutter_test.dart';
import '../../tool/bump_version.dart';

void main() {
  group('bump_version calculateNextVersion tests', () {
    test('exact version inputs are sanitized correctly', () {
      expect(calculateNextVersion('0.0.1', '0.0.2'), '0.0.2');
      expect(calculateNextVersion('0.0.1', 'v0.0.2'), '0.0.2');
      expect(calculateNextVersion('0.0.1', '0.0.2-beta'), '0.0.2-beta');
      expect(calculateNextVersion('0.0.1', 'v0.0.2-beta'), '0.0.2-beta');
    });

    test('semantic increments from release version', () {
      expect(calculateNextVersion('0.0.1', 'patch'), '0.0.2');
      expect(calculateNextVersion('0.0.1', 'minor'), '0.1.0');
      expect(calculateNextVersion('0.0.1', 'major'), '1.0.0');
      expect(calculateNextVersion('0.0.1', 'beta'), '0.0.2-beta');
    });

    test('semantic increments from beta version', () {
      // 当前是 0.0.2-beta 时，patch 将其转正为正式版 0.0.2
      expect(calculateNextVersion('0.0.2-beta', 'patch'), '0.0.2');

      // 当前是 0.0.2-beta 时，继续发 beta 变为 0.0.2-beta.2
      expect(calculateNextVersion('0.0.2-beta', 'beta'), '0.0.2-beta.2');

      // 当前是 0.0.2-beta.2 时，继续发 beta 变为 0.0.2-beta.3
      expect(calculateNextVersion('0.0.2-beta.2', 'beta'), '0.0.2-beta.3');

      // minor / major 仍能从测试版跨越升级
      expect(calculateNextVersion('0.0.2-beta', 'minor'), '0.1.0');
      expect(calculateNextVersion('0.0.2-beta', 'major'), '1.0.0');
    });
  });
}
