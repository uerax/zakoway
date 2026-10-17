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

  test('Scenario 4: Midstream EOF (Refuse vs Recover)', () async {
    ProbeEnvironment.ensureInitialized();

    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';
    final sampleFile = File('tool/player_probe/sample_15s.mp4');

    Future<void> runEofProbe({
      required String filename,
      required String scenarioTitle,
      required MockServerMode serverMode,
      required MPVLogLevel logLevel,
      required String additionalNotes,
    }) async {
      print('Running probe: $filename (logLevel: $logLevel, mode: $serverMode)...');
      final server = MockMediaServer(
        mediaFile: sampleFile,
        mode: serverMode,
        eofByteThreshold: 70 * 1024, // 传输约 70KB（前数秒音视频关键帧）后立即掐断
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

      // 观察播放进程与断开后的反应，等待 8 秒
      await Future<void>.delayed(const Duration(seconds: 8));

      recorder.cancel();
      await player.dispose();
      await server.stop();

      final outContent = recorder.buildFixtureOutput(
        scenarioTitle: scenarioTitle,
        command: 'flutter test tool/player_probe/run_scenario_4.dart',
        urlPatternDescription: '本地 Mock HTTP 媒体流 (127.0.0.1:${server.port})，模拟中途 EOF',
        requestHeaders: const {},
        environmentInfo: envInfo,
        additionalNotes: additionalNotes,
      );

      final targetFile = File('test/fixtures/player_logs/$filename');
      await targetFile.writeAsString(outContent);
      print('Saved fixture: ${targetFile.path}');
    }

    // 4a. 服务端断开后持续拒绝连接 (生产 error 级别)
    await runEofProbe(
      filename: 'scenario_4_midstream_eof_refuse_prod.txt',
      scenarioTitle: '场景 4a: 中途异常 EOF (断开后持续拒绝连接, 生产 error 级别)',
      serverMode: MockServerMode.eofAndRefuse,
      logLevel: MPVLogLevel.error,
      additionalNotes: '传输 70KB 后断开 Socket，后续重连一律拒绝连接；观察 completed 是否误触发及 stream.error 报错',
    );

    // 4a. 服务端断开后持续拒绝连接 (详细 debug 级别)
    await runEofProbe(
      filename: 'scenario_4_midstream_eof_refuse_verbose.txt',
      scenarioTitle: '场景 4a: 中途异常 EOF (断开后持续拒绝连接, 详细 debug 级别)',
      serverMode: MockServerMode.eofAndRefuse,
      logLevel: MPVLogLevel.debug,
      additionalNotes: '传输 70KB 后断开 Socket，后续重连一律拒绝连接；观察 completed 是否误触发及 stream.error 报错',
    );

    // 4b. 服务端断开后恢复服务 (生产 error 级别)
    await runEofProbe(
      filename: 'scenario_4_midstream_eof_recover_prod.txt',
      scenarioTitle: '场景 4b: 中途异常 EOF (断开后恢复服务, 生产 error 级别)',
      serverMode: MockServerMode.eofAndRecover,
      logLevel: MPVLogLevel.error,
      additionalNotes: '传输 70KB 后断开 Socket 一次，底层重连时恢复提供服务；观察 reconnect 是否无缝自愈',
    );

    // 4b. 服务端断开后恢复服务 (详细 debug 级别)
    await runEofProbe(
      filename: 'scenario_4_midstream_eof_recover_verbose.txt',
      scenarioTitle: '场景 4b: 中途异常 EOF (断开后恢复服务, 详细 debug 级别)',
      serverMode: MockServerMode.eofAndRecover,
      logLevel: MPVLogLevel.debug,
      additionalNotes: '传输 70KB 后断开 Socket 一次，底层重连时恢复提供服务；观察 reconnect 是否无缝自愈',
    );

    print('All Scenario 4 probes completed successfully!');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
