import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/danmaku/core/danmaku_perf_stats.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DanmakuPerfStats 性能埋点统计测试', () {
    test('单秒指标累加与日志格式化输出', () {
      final logs = <String>[];
      final stats = DanmakuPerfStats(onLog: logs.add, enabled: true);

      stats.recordLayoutCreated(3);
      stats.recordMerge(2);
      stats.recordDropped(1);
      stats.updateActiveCount(42);

      // 构造模拟 120Hz (~8.3ms) FrameTiming 数据
      final timings = [
        FrameTiming(
          vsyncStart: 1000000,
          buildStart: 1001000,
          buildFinish: 1003000, // build: 2ms
          rasterStart: 1003500,
          rasterFinish: 1006500, // raster: 3ms
          rasterFinishWallTime: 1006500,
        ),
        FrameTiming(
          vsyncStart: 1008333, // 间隔 8.33ms (120Hz)
          buildStart: 1009000,
          buildFinish: 1010000, // build: 1ms
          rasterStart: 1010500,
          rasterFinish: 1015500, // raster: 5ms
          rasterFinishWallTime: 1015500,
        ),
      ];

      stats.handleTimings(timings);
      stats.flush();

      expect(logs.length, equals(1));
      final log = logs.first;
      expect(log, contains('[DanmakuPerf]'));
      expect(log, contains('帧间隔: 8.3ms (~120Hz)'));
      expect(log, contains('build: 1.5ms (max 2.0ms)'));
      expect(log, contains('raster: 4.0ms (max 5.0ms)'));
      expect(log, contains('新建 layout: 3'));
      expect(log, contains('合流: 2'));
      expect(log, contains('在场: 42'));
      expect(log, contains('丢弃: 1'));
    });

    test('60Hz 帧间隔识别与计算', () {
      final logs = <String>[];
      final stats = DanmakuPerfStats(onLog: logs.add, enabled: true);

      // 构造模拟 60Hz (~16.7ms) FrameTiming 数据
      final timings = [
        FrameTiming(
          vsyncStart: 1000000,
          buildStart: 1001000,
          buildFinish: 1002000,
          rasterStart: 1002500,
          rasterFinish: 1004500,
          rasterFinishWallTime: 1004500,
        ),
        FrameTiming(
          vsyncStart: 1016666, // 间隔 16.67ms (60Hz)
          buildStart: 1017000,
          buildFinish: 1018000,
          rasterStart: 1018500,
          rasterFinish: 1020500,
          rasterFinishWallTime: 1020500,
        ),
      ];

      stats.handleTimings(timings);
      stats.flush();

      expect(logs.length, equals(1));
      expect(logs.first, contains('帧间隔: 16.7ms (~60Hz)'));
    });

    test('生命周期 start 与 stop 安全调用', () {
      final stats = DanmakuPerfStats();
      expect(() => stats.start(), returnsNormally);
      expect(() => stats.start(), returnsNormally); // 重复调用不崩溃
      expect(() => stats.stop(), returnsNormally);
      expect(() => stats.stop(), returnsNormally); // 重复调用不崩溃
    });

    test('统计重置与零状态格式', () {
      final logs = <String>[];
      final stats = DanmakuPerfStats(onLog: logs.add, enabled: true);

      // 没有帧时不输出日志
      stats.flush();
      expect(logs.isEmpty, isTrue);
    });

    test('默认关闭状态下彻底静默不输出日志且不监听', () {
      final logs = <String>[];
      final stats = DanmakuPerfStats(onLog: logs.add, enabled: false);

      expect(stats.isEnabled, isFalse);
      stats.recordLayoutCreated(10);
      stats.recordMerge(5);
      stats.recordDropped(2);
      stats.updateActiveCount(50);
      stats.start();

      stats.handleTimings([
        FrameTiming(
          vsyncStart: 1000000,
          buildStart: 1001000,
          buildFinish: 1002000,
          rasterStart: 1002500,
          rasterFinish: 1004500,
          rasterFinishWallTime: 1004500,
        ),
      ]);
      stats.flush();
      expect(logs.isEmpty, isTrue);

      // 卡顿记录在关闭状态下也必须静默
      stats.recordTickStutter(
        dtMs: 50.0,
        layoutsCreated: 5,
        merges: 2,
        emitted: 3,
        rebuildReason: 'Seek',
        onTickMs: 2.0,
        paintMs: 3.0,
        activeCount: 10,
      );
      expect(logs.isEmpty, isTrue);
      stats.stop();
    });

    test('帧卡顿归因日志：dt > 1.5倍中位数时输出归因日志，正常帧静默', () {
      final logs = <String>[];
      final stats = DanmakuPerfStats(onLog: logs.add, enabled: true);

      // 准备最新的 frame timing 数据 (build: 1.5ms, raster: 2.5ms)
      stats.handleTimings([
        FrameTiming(
          vsyncStart: 1000000,
          buildStart: 1000000,
          buildFinish: 1001500,
          rasterStart: 1001500,
          rasterFinish: 1004000,
          rasterFinishWallTime: 1004000,
        ),
      ]);

      // 喂入 10 帧正常的 16.6ms 帧以建立基准中位数
      for (var i = 0; i < 10; i++) {
        stats.recordTickStutter(
          dtMs: 16.6,
          layoutsCreated: 0,
          merges: 0,
          emitted: 1,
          rebuildReason: null,
          onTickMs: 0.2,
          paintMs: 0.5,
          activeCount: 15,
        );
      }
      expect(logs.isEmpty, isTrue); // 正常帧不输出任何日志

      // 注入一个普通波动帧（例如 20ms <= 1.5 * 16.6 = 24.9ms）
      stats.recordTickStutter(
        dtMs: 20.0,
        layoutsCreated: 1,
        merges: 0,
        emitted: 1,
        rebuildReason: null,
        onTickMs: 0.3,
        paintMs: 0.6,
        activeCount: 16,
      );
      expect(logs.isEmpty, isTrue);

      // 注入一个卡顿帧（例如 32.0ms > 24.9ms）
      stats.recordTickStutter(
        dtMs: 32.0,
        layoutsCreated: 3,
        merges: 2,
        emitted: 5,
        rebuildReason: 'Seek',
        onTickMs: 1.45,
        paintMs: 2.80,
        activeCount: 28,
      );

      expect(logs.length, equals(1));
      final line = logs.first;
      expect(line, contains('[DanmakuStutter]'));
      expect(line, anyOf(contains('[Skia]'), contains('[Impeller]')));
      expect(line, contains('dt: 32.0ms'));
      expect(line, contains('中位数: 16.6ms'));
      expect(line, contains('排版: 3'));
      expect(line, contains('合流: 2'));
      expect(line, contains('发射: 5'));
      expect(line, contains('重建: Seek'));
      expect(line, contains('在屏: 28'));
      expect(line, contains('onTick=1.45ms'));
      expect(line, contains('paint=2.80ms'));
      expect(line, contains('build=1.50ms'));
      expect(line, contains('raster=2.50ms'));
    });
  });
}
