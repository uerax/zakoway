import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'mock_media_server.dart';
import 'probe_environment.dart';
import 'probe_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('Scenario 7: Slow Startup (Delayed Headers vs Drip Body)', () async {
    ProbeEnvironment.ensureInitialized();

    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';
    final sampleFile = File('tool/player_probe/sample_15s.mp4');

    Future<void> runSlowProbe({
      required String filename,
      required String scenarioTitle,
      required MockServerMode serverMode,
      required MPVLogLevel logLevel,
      required Duration headerDelay,
      required int dripSpeed,
      required Duration totalWait,
      required String additionalNotes,
    }) async {
      print('Running probe: $filename (logLevel: $logLevel, mode: $serverMode)...');
      final server = MockMediaServer(
        mediaFile: sampleFile,
        mode: serverMode,
        headerDelay: headerDelay,
        dripBytesPerSecond: dripSpeed,
      );
      await server.start();

      final player = Player(
        configuration: PlayerConfiguration(
          logLevel: logLevel,
        ),
      );

      await ProbeEnvironment.applyAppMpvProperties(player);

      final recorder = ProbeRecorder(player);
      recorder.logCustom('probe.config', 'logLevel=$logLevel, mode=$serverMode');

      await recorder.recordOpen(server.url, headers: const {}, play: true);

      await Future<void>.delayed(totalWait);

      recorder.cancel();
      await player.dispose();
      await server.stop();

      final outContent = recorder.buildFixtureOutput(
        scenarioTitle: scenarioTitle,
        command: 'flutter test tool/player_probe/run_scenario_7.dart',
        urlPatternDescription: '本地 Mock HTTP 慢速起播流 (127.0.0.1:${server.port})',
        requestHeaders: const {},
        environmentInfo: envInfo,
        additionalNotes: additionalNotes,
      );

      final targetFile = File('test/fixtures/player_logs/$filename');
      await targetFile.writeAsString(outContent);
      print('Saved fixture: ${targetFile.path}');
    }

    // 7a. 响应头 9~12 秒才返回 (生产 error 级别)
    await runSlowProbe(
      filename: 'scenario_7_slow_headers_prod.txt',
      scenarioTitle: '场景 7a: 慢起播 (响应头延迟 9 秒返回, 生产 error 级别)',
      serverMode: MockServerMode.delayHeaders,
      logLevel: MPVLogLevel.error,
      headerDelay: const Duration(milliseconds: 9000),
      dripSpeed: 0,
      totalWait: const Duration(seconds: 14),
      additionalNotes: 'HTTP 响应头延迟 9 秒返回。记录 0~9s 静默等待期间 duration, buffer, buffering, position 的状态，以及 9s 后出帧过程',
    );

    // 7a. 响应头 9~12 秒才返回 (详细 debug 级别)
    await runSlowProbe(
      filename: 'scenario_7_slow_headers_verbose.txt',
      scenarioTitle: '场景 7a: 慢起播 (响应头延迟 9 秒返回, 详细 debug 级别)',
      serverMode: MockServerMode.delayHeaders,
      logLevel: MPVLogLevel.debug,
      headerDelay: const Duration(milliseconds: 9000),
      dripSpeed: 0,
      totalWait: const Duration(seconds: 14),
      additionalNotes: 'HTTP 响应头延迟 9 秒返回。记录 0~9s 静默等待期间 duration, buffer, buffering, position 的状态，以及 9s 后出帧过程',
    );

    // 7b. 响应头立即返回但数据缓慢滴入 (生产 error 级别)
    await runSlowProbe(
      filename: 'scenario_7_slow_drip_prod.txt',
      scenarioTitle: '场景 7b: 慢起播 (响应头立即返回, 数据按 ~22KB/s 缓慢滴入, 生产 error 级别)',
      serverMode: MockServerMode.dripBody,
      logLevel: MPVLogLevel.error,
      headerDelay: Duration.zero,
      dripSpeed: 22 * 1024, // 233KB / 22KB/s = ~10.5 秒完成
      totalWait: const Duration(seconds: 14),
      additionalNotes: '响应头立即返回，但数据以 22KB/s 缓慢滴入，首帧在 9~12 秒出画。记录 duration、buffer、buffering、position 动态渐变',
    );

    // 7b. 响应头立即返回但数据缓慢滴入 (详细 debug 级别)
    await runSlowProbe(
      filename: 'scenario_7_slow_drip_verbose.txt',
      scenarioTitle: '场景 7b: 慢起播 (响应头立即返回, 数据按 ~22KB/s 缓慢滴入, 详细 debug 级别)',
      serverMode: MockServerMode.dripBody,
      logLevel: MPVLogLevel.debug,
      headerDelay: Duration.zero,
      dripSpeed: 22 * 1024,
      totalWait: const Duration(seconds: 14),
      additionalNotes: '响应头立即返回，但数据以 22KB/s 缓慢滴入，首帧在 9~12 秒出画。记录 duration、buffer、buffering、position 动态渐变',
    );

    print('All Scenario 7 probes completed successfully!');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
