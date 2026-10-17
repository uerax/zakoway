import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zakoway/features/player/source/sources/xifan_next_source.dart';
import 'probe_environment.dart';
import 'probe_recorder.dart';

class IterationResult {
  IterationResult({
    required this.index,
    required this.success,
    required this.elapsedMs,
    required this.errors,
    required this.logs,
  });

  final int index;
  final bool success;
  final int elapsedMs;
  final List<String> errors;
  final List<String> logs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('Scenario 8: Repeat Open Success Rate Test', () async {
    ProbeEnvironment.ensureInitialized();
    final source = XifanNextSource();

    // 解析出最新的 AL 线路签名链接 (play.xfvod.pro:8088)
    print('Resolving AL line for anime 3457 episode 1...');
    final alResolve = await source.resolve(
      'https://next.xifanacg.com/anime/3457/play/206574?source_id=1&source=AL',
    );
    final targetUrl = alResolve.url;
    final targetHeaders = alResolve.headers;
    print('Target AL URL: $targetUrl');

    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';

    Future<void> runRepeatRound({
      required Duration interval,
      required int repeatCount,
      required String filename,
    }) async {
      print('\n==================================================');
      print('Starting Repeat Round: interval = ${interval.inMilliseconds}ms, count = $repeatCount');
      print('==================================================');

      final roundResults = <IterationResult>[];
      final roundRecorderBuf = StringBuffer();

      roundRecorderBuf.writeln('================================================================================');
      roundRecorderBuf.writeln('ZAKOWAY PLAYER PROBE FIXTURE LOG - SCENARIO 8');
      roundRecorderBuf.writeln('================================================================================');
      roundRecorderBuf.writeln('场景名称: 场景 8: 同一链接连续 open 重复成功率 (间隔 ${interval.inMilliseconds}ms, 10 次)');
      roundRecorderBuf.writeln('测试日期: ${DateTime.now().toIso8601String()}');
      roundRecorderBuf.writeln('执行环境: $envInfo');
      roundRecorderBuf.writeln('执行命令: flutter test tool/player_probe/run_scenario_8.dart');
      roundRecorderBuf.writeln('URL形态说明: AL 线路标准域名形态 (play.xfvod.pro:8088)');
      roundRecorderBuf.writeln('脱敏规则说明: 敏感参数 sign、t、token 等替换为 ...，其余保持完全原始输出');
      roundRecorderBuf.writeln('请求头信息: $targetHeaders');
      roundRecorderBuf.writeln('附加说明: 生产 mpv 配置，每次 open 监控出帧成功或报错失败，记录单次用时与日志原文');
      roundRecorderBuf.writeln('================================================================================\n');

      for (var i = 1; i <= repeatCount; i++) {
        print('Iteration $i/$repeatCount (interval: ${interval.inMilliseconds}ms)...');
        final player = Player(
          configuration: const PlayerConfiguration(
            logLevel: MPVLogLevel.error,
          ),
        );
        await ProbeEnvironment.applyAppMpvProperties(player);

        final capturedErrors = <String>[];
        final capturedLogs = <String>[];
        final subError = player.stream.error.listen((e) => capturedErrors.add(e));
        final subLog = player.stream.log.listen((l) => capturedLogs.add('[${l.prefix}] (${l.level}) ${l.text}'));

        final completer = Completer<bool>();
        final sw = Stopwatch()..start();

        final subDur = player.stream.duration.listen((dur) {
          if (dur > Duration.zero && !completer.isCompleted) {
            completer.complete(true);
          }
        });

        final subErrCheck = player.stream.error.listen((err) {
          if (err.contains('Failed to open') && !completer.isCompleted) {
            completer.complete(false);
          }
        });

        try {
          await player.open(
            Media(targetUrl, httpHeaders: targetHeaders),
            play: true,
          );
        } catch (_) {}

        bool success = false;
        try {
          success = await completer.future.timeout(const Duration(seconds: 6));
        } catch (_) {
          success = false;
        }
        sw.stop();

        await subDur.cancel();
        await subErrCheck.cancel();
        await subError.cancel();
        await subLog.cancel();
        await player.dispose();

        final itRes = IterationResult(
          index: i,
          success: success,
          elapsedMs: sw.elapsedMilliseconds,
          errors: capturedErrors,
          logs: capturedLogs,
        );
        roundResults.add(itRes);

        roundRecorderBuf.writeln('--- Iteration #$i ---');
        roundRecorderBuf.writeln('结果: ${success ? "SUCCESS" : "FAILED"} (耗时: ${itRes.elapsedMs}ms)');
        if (capturedErrors.isNotEmpty) {
          roundRecorderBuf.writeln('stream.error:');
          for (final e in capturedErrors) {
            roundRecorderBuf.writeln('  ${ProbeRecorder.maskSensitive(e)}');
          }
        }
        if (capturedLogs.isNotEmpty) {
          roundRecorderBuf.writeln('stream.log:');
          for (final l in capturedLogs) {
            roundRecorderBuf.writeln('  ${ProbeRecorder.maskSensitive(l)}');
          }
        }
        roundRecorderBuf.writeln('');

        print('  Result: ${success ? "SUCCESS" : "FAILED"}, cost: ${itRes.elapsedMs}ms, errCount: ${capturedErrors.length}');

        if (i < repeatCount) {
          await Future<void>.delayed(interval);
        }
      }

      // 统计汇总
      final successCount = roundResults.where((r) => r.success).length;
      final failCount = roundResults.length - successCount;
      final avgCost = (roundResults.map((r) => r.elapsedMs).reduce((a, b) => a + b) / roundResults.length).round();

      roundRecorderBuf.writeln('================================================================================');
      roundRecorderBuf.writeln('ROUND SUMMARY STATS:');
      roundRecorderBuf.writeln('总测试轮次: ${roundResults.length}');
      roundRecorderBuf.writeln('成功次数: $successCount');
      roundRecorderBuf.writeln('失败次数: $failCount');
      roundRecorderBuf.writeln('成功率: ${(successCount / roundResults.length * 100).toStringAsFixed(1)}%');
      roundRecorderBuf.writeln('平均耗时: ${avgCost}ms');
      roundRecorderBuf.writeln('================================================================================');

      final targetFile = File('test/fixtures/player_logs/$filename');
      await targetFile.writeAsString(roundRecorderBuf.toString());
      print('Saved fixture: ${targetFile.path}');
    }

    // 轮次 1: 间隔 0.5s，10 次
    await runRepeatRound(
      interval: const Duration(milliseconds: 500),
      repeatCount: 10,
      filename: 'scenario_8_repeat_open_0_5s.txt',
    );

    // 轮次 2: 间隔 1.0s，10 次
    await runRepeatRound(
      interval: const Duration(milliseconds: 1000),
      repeatCount: 10,
      filename: 'scenario_8_repeat_open_1_0s.txt',
    );

    // 轮次 3: 间隔 2.0s，10 次
    await runRepeatRound(
      interval: const Duration(milliseconds: 2000),
      repeatCount: 10,
      filename: 'scenario_8_repeat_open_2_0s.txt',
    );

    print('All Scenario 8 repeat tests completed successfully!');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
