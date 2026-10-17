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

  test('Scenario 5: Normal Network MP4 Timing Sequence', () async {
    ProbeEnvironment.ensureInitialized();

    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';
    final sampleFile = File('tool/player_probe/sample_15s.mp4');

    Future<void> runNormalProbe({
      required String filename,
      required String scenarioTitle,
      required MPVLogLevel logLevel,
    }) async {
      print('Running probe: $filename (logLevel: $logLevel)...');
      final server = MockMediaServer(
        mediaFile: sampleFile,
        mode: MockServerMode.normal,
      );
      await server.start();

      final player = Player(
        configuration: PlayerConfiguration(
          logLevel: logLevel,
        ),
      );

      await ProbeEnvironment.applyAppMpvProperties(player);

      final recorder = ProbeRecorder(player);
      recorder.logCustom('probe.config', 'logLevel=$logLevel, mode=normal');

      await recorder.recordOpen(server.url, headers: const {}, play: true);

      // 观察正常出画与时钟推进，等待 4 秒
      await Future<void>.delayed(const Duration(seconds: 4));

      recorder.cancel();
      await player.dispose();
      await server.stop();

      final outContent = recorder.buildFixtureOutput(
        scenarioTitle: scenarioTitle,
        command: 'flutter test tool/player_probe/run_scenario_5.dart',
        urlPatternDescription: '本地 Mock HTTP 标准网络媒体流 (127.0.0.1:${server.port}/media.mp4)',
        requestHeaders: const {},
        environmentInfo: envInfo,
        additionalNotes: '应用实际生产 mpv 配置，精确记录 width, height, videoParams, duration 与 position 的物理先后顺序',
      );

      final targetFile = File('test/fixtures/player_logs/$filename');
      await targetFile.writeAsString(outContent);
      print('Saved fixture: ${targetFile.path}');
    }

    await runNormalProbe(
      filename: 'scenario_5_normal_mp4_prod.txt',
      scenarioTitle: '场景 5: 正常网络 MP4 物理时序 (生产 error 级别)',
      logLevel: MPVLogLevel.error,
    );

    await runNormalProbe(
      filename: 'scenario_5_normal_mp4_verbose.txt',
      scenarioTitle: '场景 5: 正常网络 MP4 物理时序 (详细 debug 级别)',
      logLevel: MPVLogLevel.debug,
    );

    print('All Scenario 5 probes completed successfully!');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
