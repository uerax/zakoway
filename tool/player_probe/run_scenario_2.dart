import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'probe_environment.dart';
import 'probe_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('Scenario 2: HTTP 403 & 404', () async {
    ProbeEnvironment.ensureInitialized();

    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';

    Future<void> runHttpProbe({
      required String filename,
      required String scenarioTitle,
      required String url,
      required MPVLogLevel logLevel,
      Duration waitDuration = const Duration(seconds: 4),
    }) async {
      print('Running probe: $filename (logLevel: $logLevel)...');
      final player = Player(
        configuration: PlayerConfiguration(
          logLevel: logLevel,
        ),
      );

      await ProbeEnvironment.applyAppMpvProperties(player);

      final recorder = ProbeRecorder(player);
      recorder.logCustom('probe.config', 'logLevel=$logLevel, appProps=true');

      await recorder.recordOpen(url, headers: const {}, play: true);
      await Future<void>.delayed(waitDuration);

      recorder.cancel();
      await player.dispose();

      final outContent = recorder.buildFixtureOutput(
        scenarioTitle: scenarioTitle,
        command: 'flutter test tool/player_probe/run_scenario_2.dart',
        urlPatternDescription: url,
        requestHeaders: const {},
        environmentInfo: envInfo,
        additionalNotes: '应用实际生产 mpv 配置，验证 HTTP 状态码是否暴露及具体出口',
      );

      final targetFile = File('test/fixtures/player_logs/$filename');
      await targetFile.writeAsString(outContent);
      print('Saved fixture: ${targetFile.path}');
    }

    // 2a. HTTP 403
    await runHttpProbe(
      filename: 'scenario_2_http_403_prod.txt',
      scenarioTitle: '场景 2a: HTTP 403 Forbidden (生产 error 级别)',
      url: 'https://httpbin.org/status/403',
      logLevel: MPVLogLevel.error,
    );

    await runHttpProbe(
      filename: 'scenario_2_http_403_verbose.txt',
      scenarioTitle: '场景 2a: HTTP 403 Forbidden (详细 debug 级别)',
      url: 'https://httpbin.org/status/403',
      logLevel: MPVLogLevel.debug,
    );

    // 2b. HTTP 404
    await runHttpProbe(
      filename: 'scenario_2_http_404_prod.txt',
      scenarioTitle: '场景 2b: HTTP 404 Not Found (生产 error 级别)',
      url: 'https://httpbin.org/status/404',
      logLevel: MPVLogLevel.error,
    );

    await runHttpProbe(
      filename: 'scenario_2_http_404_verbose.txt',
      scenarioTitle: '场景 2b: HTTP 404 Not Found (详细 debug 级别)',
      url: 'https://httpbin.org/status/404',
      logLevel: MPVLogLevel.debug,
    );

    print('All Scenario 2 probes completed successfully!');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
