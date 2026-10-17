import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'probe_environment.dart';
import 'probe_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('Scenario 3: DNS Failure & Connection Timeout (with completion wait)', () async {
    ProbeEnvironment.ensureInitialized();

    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';

    Future<void> runTimeoutProbe({
      required String filename,
      required String scenarioTitle,
      required String url,
      required MPVLogLevel logLevel,
      Duration maxWaitDuration = const Duration(seconds: 25),
    }) async {
      print('Running probe: $filename (logLevel: $logLevel, maxWait: ${maxWaitDuration.inSeconds}s)...');
      final player = Player(
        configuration: PlayerConfiguration(
          logLevel: logLevel,
        ),
      );

      await ProbeEnvironment.applyAppMpvProperties(player);

      final recorder = ProbeRecorder(player);
      recorder.logCustom('probe.config', 'logLevel=$logLevel, appProps=true');

      final failedToOpenCompleter = Completer<void>();
      final sub = player.stream.error.listen((err) {
        if (err.contains('Failed to open') && !failedToOpenCompleter.isCompleted) {
          failedToOpenCompleter.complete();
        }
      });

      await recorder.recordOpen(url, headers: const {}, play: true);

      // 等待 Failed to open 出现，或达到最大等待时间
      try {
        await failedToOpenCompleter.future.timeout(maxWaitDuration);
        print('Caught Failed to open within timeout for $filename!');
        // 稍等 500ms 让后续 unload 等日志完全写入
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } catch (_) {
        print('Reached maxWaitDuration for $filename without Failed to open.');
      }

      await sub.cancel();
      recorder.cancel();
      await player.dispose();

      final outContent = recorder.buildFixtureOutput(
        scenarioTitle: scenarioTitle,
        command: 'flutter test tool/player_probe/run_scenario_3.dart',
        urlPatternDescription: url,
        requestHeaders: const {},
        environmentInfo: envInfo,
        additionalNotes: '应用实际生产 mpv 配置（network-timeout=10, reconnect_delay_max=2），等待直至 Failed to open 派发',
      );

      final targetFile = File('test/fixtures/player_logs/$filename');
      await targetFile.writeAsString(outContent);
      print('Saved fixture: ${targetFile.path}');
    }

    // 3a. DNS 失败 (不存在的 .invalid 顶级保留域名)
    await runTimeoutProbe(
      filename: 'scenario_3_dns_fail_prod.txt',
      scenarioTitle: '场景 3a: DNS 解析失败 (不存在域名, 生产 error 级别)',
      url: 'http://probe-dns-nxdomain.invalid/video.mp4',
      logLevel: MPVLogLevel.error,
    );

    await runTimeoutProbe(
      filename: 'scenario_3_dns_fail_verbose.txt',
      scenarioTitle: '场景 3a: DNS 解析失败 (不存在域名, 详细 debug 级别)',
      url: 'http://probe-dns-nxdomain.invalid/video.mp4',
      logLevel: MPVLogLevel.debug,
    );

    // 3b. 连接超时 (不可路由私网地址 10.255.255.1:12345)
    await runTimeoutProbe(
      filename: 'scenario_3_connect_timeout_prod.txt',
      scenarioTitle: '场景 3b: 连接超时 (不可路由 IP, 生产 error 级别)',
      url: 'http://10.255.255.1:12345/video.mp4',
      logLevel: MPVLogLevel.error,
    );

    await runTimeoutProbe(
      filename: 'scenario_3_connect_timeout_verbose.txt',
      scenarioTitle: '场景 3b: 连接超时 (不可路由 IP, 详细 debug 级别)',
      url: 'http://10.255.255.1:12345/video.mp4',
      logLevel: MPVLogLevel.debug,
    );

    print('All Scenario 3 probes completed successfully!');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
