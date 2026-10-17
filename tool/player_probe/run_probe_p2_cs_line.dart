// 运行命令: flutter test tool/player_probe/run_probe_p2_cs_line.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zakoway/features/player/source/sources/xifan_next_source.dart';
import 'probe_environment.dart';
import 'probe_recorder.dart';

class CsIterationResult {
  CsIterationResult({
    required this.index,
    required this.success,
    required this.elapsedMs,
    required this.targetUrl,
    required this.failureKind,
    required this.errors,
    required this.logs,
  });

  final int index;
  final bool success;
  final int elapsedMs;
  final String targetUrl;
  final String failureKind;
  final List<String> errors;
  final List<String> logs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('P2: CS Backup Line (dl.playxf.top m3u8) Probe', () async {
    ProbeEnvironment.ensureInitialized();
    final source = XifanNextSource();

    print('Step 1: Finding an episode with CS line using chapters()...');
    const animeUrl = 'https://next.xifanacg.com/anime/3403';
    String? selectedEpUrl;
    String? selectedEpName;
    try {
      final roads = await source.chapters(animeUrl);
      for (final r in roads) {
        for (final ep in r.episodes) {
          if (ep.url.contains('source=CS') || ep.url.contains('source_id=2')) {
            selectedEpUrl = ep.url;
            selectedEpName = '${r.name} - ${ep.name}';
            break;
          }
        }
        if (selectedEpUrl != null) break;
      }
    } catch (e) {
      print('Chapters attempt failed: $e');
    }

    if (selectedEpUrl == null) {
      print('Fallback: using standard CS episode URL for anime 3403...');
      selectedEpUrl = 'https://next.xifanacg.com/anime/3403/play/121397?source_id=2&source=CS';
      selectedEpName = '稀饭备用-1 - 第1集 (Fallback)';
    }
    final finalEpUrl = selectedEpUrl;
    final finalEpName = selectedEpName!;
    print('Selected Episode: $finalEpName -> $finalEpUrl');

    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';
    const successDefinition = 'open 后 15 秒内 position >= 3000ms（3秒）为成功，出现 Failed to open 或 15 秒超时未达标为失败';

    String classifyFailure(List<String> errors, List<String> logs, bool timeout) {
      final combined = [...errors, ...logs].join(' ');
      if (combined.contains('tcp: ffurl_read') ||
          combined.contains('mbedtls_ssl_handshake') ||
          combined.contains('-0x4e') ||
          combined.contains('0xdfb9b0bb')) {
        return 'tls_handshake_closed';
      }
      if (combined.contains('HTTP error') || combined.contains('403') || combined.contains('404')) {
        return 'http_or_signature';
      }
      if (timeout) return 'timeout_no_progress';
      return 'unknown_error';
    }

    Future<void> runCsBatchTest({
      required String filename,
      required String scenarioTitle,
      required int iterations,
      required MPVLogLevel logLevel,
    }) async {
      print('\n==================================================');
      print('Running: $filename ($scenarioTitle, logLevel: $logLevel, count: $iterations)');
      print('==================================================');

      final results = <CsIterationResult>[];
      final fixtureBuf = StringBuffer();

      fixtureBuf.writeln('================================================================================');
      fixtureBuf.writeln('ZAKOWAY PLAYER PROBE FIXTURE LOG - P2');
      fixtureBuf.writeln('================================================================================');
      fixtureBuf.writeln('场景名称: $scenarioTitle');
      fixtureBuf.writeln('测试日期: ${DateTime.now().toIso8601String()}');
      fixtureBuf.writeln('执行环境: $envInfo');
      fixtureBuf.writeln('执行命令: flutter test tool/player_probe/run_probe_p2_cs_line.dart');
      fixtureBuf.writeln('选用番剧与分集: $finalEpName ($finalEpUrl)');
      fixtureBuf.writeln('URL形态说明: 稀饭 CS 备用切片线路 (dl.playxf.top 的 m3u8)，每次迭代重新 resolve()');
      fixtureBuf.writeln('成功定义: $successDefinition');
      fixtureBuf.writeln('脱敏规则说明: 敏感参数 sign、t、token 等替换为 ...，其余保持完全原始输出');
      fixtureBuf.writeln('请求头信息: 遵循源站下发 Headers (含 Referer: https://next.xifanacg.com/)');
      fixtureBuf.writeln('附加说明: 生产 mpv 配置，连续 open 5 次，监控 HLS 切片加载与起播进度');
      fixtureBuf.writeln('================================================================================\n');

      for (var i = 1; i <= iterations; i++) {
        print('Iteration $i/$iterations...');
        final freshResolve = await source.resolve(finalEpUrl);
        final playUrl = freshResolve.url;
        final headers = Map<String, String>.from(freshResolve.headers);

        final player = Player(
          configuration: PlayerConfiguration(
            logLevel: logLevel,
          ),
        );
        await ProbeEnvironment.applyAppMpvProperties(player);

        final capturedErrors = <String>[];
        final capturedLogs = <String>[];
        final subError = player.stream.error.listen((e) => capturedErrors.add(e));
        final subLog = player.stream.log.listen((l) => capturedLogs.add('[${l.prefix}] (${l.level}) ${l.text}'));

        final completer = Completer<bool>();
        final sw = Stopwatch()..start();

        final subPos = player.stream.position.listen((pos) {
          if (pos >= const Duration(seconds: 3) && !completer.isCompleted) {
            completer.complete(true);
          }
        });

        final subErr = player.stream.error.listen((err) {
          if (err.contains('Failed to open') && !completer.isCompleted) {
            completer.complete(false);
          }
        });

        try {
          await player.open(
            Media(playUrl, httpHeaders: headers),
            play: true,
          );
        } catch (_) {}

        bool isSuccess = false;
        bool isTimeout = false;
        try {
          isSuccess = await completer.future.timeout(const Duration(seconds: 15));
        } catch (_) {
          isSuccess = false;
          isTimeout = true;
        }
        sw.stop();

        await subPos.cancel();
        await subErr.cancel();
        await subError.cancel();
        await subLog.cancel();
        await player.dispose();

        final failKind = isSuccess ? 'none' : classifyFailure(capturedErrors, capturedLogs, isTimeout);
        final itRes = CsIterationResult(
          index: i,
          success: isSuccess,
          elapsedMs: sw.elapsedMilliseconds,
          targetUrl: playUrl,
          failureKind: failKind,
          errors: capturedErrors,
          logs: capturedLogs,
        );
        results.add(itRes);

        fixtureBuf.writeln('--- Iteration #$i ---');
        fixtureBuf.writeln('目标 URL: ${ProbeRecorder.maskSensitive(playUrl)}');
        fixtureBuf.writeln('请求头: $headers');
        fixtureBuf.writeln('结果: ${isSuccess ? "SUCCESS" : "FAILED"} (耗时: ${sw.elapsedMilliseconds}ms, 归因: $failKind)');
        if (capturedErrors.isNotEmpty) {
          fixtureBuf.writeln('stream.error:');
          for (final e in capturedErrors) {
            fixtureBuf.writeln('  ${ProbeRecorder.maskSensitive(e)}');
          }
        }
        if (capturedLogs.isNotEmpty) {
          fixtureBuf.writeln('stream.log:');
          for (final l in capturedLogs) {
            fixtureBuf.writeln('  ${ProbeRecorder.maskSensitive(l)}');
          }
        }
        fixtureBuf.writeln('');

        print('  Result: ${isSuccess ? "SUCCESS" : "FAILED"} ($failKind, ${sw.elapsedMilliseconds}ms)');

        if (i < iterations) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }

      // 汇总统计
      final successCount = results.where((r) => r.success).length;
      final failCount = results.length - successCount;
      final tlsFailCount = results.where((r) => r.failureKind == 'tls_handshake_closed').length;
      final httpFailCount = results.where((r) => r.failureKind == 'http_or_signature').length;
      final timeoutCount = results.where((r) => r.failureKind == 'timeout_no_progress').length;

      fixtureBuf.writeln('================================================================================');
      fixtureBuf.writeln('SUMMARY STATS:');
      fixtureBuf.writeln('总测试轮次: ${results.length}');
      fixtureBuf.writeln('成功次数: $successCount');
      fixtureBuf.writeln('失败次数: $failCount');
      fixtureBuf.writeln('  - TLS 握手中断失败: $tlsFailCount');
      fixtureBuf.writeln('  - HTTP/签名层失败: $httpFailCount');
      fixtureBuf.writeln('  - 15秒超时未达标: $timeoutCount');
      fixtureBuf.writeln('成功率: ${(successCount / results.length * 100).toStringAsFixed(1)}%');
      fixtureBuf.writeln('================================================================================');

      final targetFile = File('test/fixtures/player_logs/$filename');
      await targetFile.writeAsString(fixtureBuf.toString());
      print('Saved fixture: ${targetFile.path}');
    }

    // P2 生产 error 级别 (5次)
    await runCsBatchTest(
      filename: 'p2_cs_m3u8_prod.txt',
      scenarioTitle: 'P2: CS 备用线路 m3u8 (生产 mpv 配置, error 级别, 5次)',
      iterations: 5,
      logLevel: MPVLogLevel.error,
    );

    // P2 详细 debug 级别 (5次)
    await runCsBatchTest(
      filename: 'p2_cs_m3u8_verbose.txt',
      scenarioTitle: 'P2: CS 备用线路 m3u8 (生产 mpv 配置, debug 级别, 5次)',
      iterations: 5,
      logLevel: MPVLogLevel.debug,
    );

    print('All P2 probes finished successfully!');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
