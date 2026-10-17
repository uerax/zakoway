// 运行命令: flutter test tool/player_probe/run_probe_p6_delayed_log_isolation.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'probe_environment.dart';
import 'probe_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('P6: Delayed Log Isolation Test (Isolated Process vs Same Process)', () async {
    ProbeEnvironment.ensureInitialized();

    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';
    const successDefinition = '确认在独立隔离进程 vs 同一复用进程下，上一场景未完成的网络错误日志是否穿透注入至新 Player';

    // 辅助函数：运行单个超时探针并记录日志
    Future<ProbeRecorder> runSingleProbeInstance({
      required String url,
      required String tag,
      Duration maxWaitDuration = const Duration(seconds: 20),
    }) async {
      final player = Player(
        configuration: const PlayerConfiguration(
          logLevel: MPVLogLevel.error,
        ),
      );
      await ProbeEnvironment.applyAppMpvProperties(player);

      final recorder = ProbeRecorder(player);
      recorder.logCustom('probe.config', 'tag=$tag, url=$url');

      final completer = Completer<void>();
      final sub = player.stream.error.listen((err) {
        if (err.contains('Failed to open') && !completer.isCompleted) {
          completer.complete();
        }
      });

      await recorder.recordOpen(url, headers: const {}, play: true);

      try {
        await completer.future.timeout(maxWaitDuration);
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } catch (_) {}

      await sub.cancel();
      recorder.cancel();
      await player.dispose();
      return recorder;
    }

    // -------------------------------------------------------------------------
    // 组 1：同一进程内连续复用 (Same Process)
    // -------------------------------------------------------------------------
    print('\n==================================================');
    print('Running P6 Group 1: Same Process (DNS Fail -> Dispose -> Connect Timeout)...');
    print('==================================================');

    print('Step 1.1: Running DNS failure in current process...');
    // 不等第二次重试耗尽（约11秒派发第一次，若此时dispose），模拟旧场景提前退出的竞态
    final dnsRecorder = await runSingleProbeInstance(
      url: 'http://probe-dns-nxdomain.invalid/video.mp4',
      tag: 'p6.same_process.step1_dns',
      maxWaitDuration: const Duration(seconds: 14),
    );
    print('Step 1.1 finished (DNS events: ${dnsRecorder.events.length})');

    print('Step 1.2: Immediately creating new Player for connect timeout in SAME process...');
    final sameProcTimeoutRecorder = await runSingleProbeInstance(
      url: 'http://10.255.255.1:12345/video.mp4',
      tag: 'p6.same_process.step2_timeout',
      maxWaitDuration: const Duration(seconds: 20),
    );

    final sameProcHasDnsLeak = sameProcTimeoutRecorder.events.any(
      (e) => e.message.contains('probe-dns-nxdomain.invalid') || e.message.contains('Failed to resolve hostname'),
    );
    print('Group 1 Result: Same process DNS log leaked into Player 2? => $sameProcHasDnsLeak');

    final sameProcFixture = sameProcTimeoutRecorder.buildFixtureOutput(
      scenarioTitle: 'P6 组 1: 同一进程内连续复用 (DNS失败后立即新建Player跑连接超时)',
      command: 'flutter test tool/player_probe/run_probe_p6_delayed_log_isolation.dart',
      urlPatternDescription: 'http://10.255.255.1:12345/video.mp4 (在同一进程前置运行 probe-dns-nxdomain.invalid)',
      requestHeaders: const {},
      environmentInfo: envInfo,
      additionalNotes: '验证同进程内前一个 Player 的后台网络线程在 dispose 后是否向后一个 Player 派发迟到日志；'
          '实测结果: leaked=$sameProcHasDnsLeak',
    );
    await File('test/fixtures/player_logs/p6_same_process_connect_timeout_prod.txt').writeAsString(sameProcFixture);

    // -------------------------------------------------------------------------
    // 组 2：独立进程隔离 (Isolated Process via Process.run)
    // -------------------------------------------------------------------------
    print('\n==================================================');
    print('Running P6 Group 2: Isolated Process (Separate OS Process for Timeout)...');
    print('==================================================');

    // 我们通过运行一个只跑单个连接超时的独立测试命令
    // 先检查只运行场景 3b 的独立进程
    final isolatedCmd = 'flutter';
    final isolatedArgs = [
      'test',
      'tool/player_probe/run_scenario_3.dart',
      '--plain-name',
      'Scenario 3: DNS Failure & Connection Timeout (with completion wait)',
    ];

    // 为了完全精准对照，我们编写一个轻量的独立入口脚本只跑单次 connect timeout
    final standaloneScript = File('tool/player_probe/standalone_timeout.dart');
    await standaloneScript.writeAsString('''
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'probe_environment.dart';
import 'probe_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('standalone timeout', () async {
    ProbeEnvironment.ensureInitialized();
    final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.error));
    await ProbeEnvironment.applyAppMpvProperties(player);
    final recorder = ProbeRecorder(player);
    final completer = Completer<void>();
    player.stream.error.listen((err) {
      if (err.contains('Failed to open') && !completer.isCompleted) completer.complete();
    });
    await recorder.recordOpen('http://10.255.255.1:12345/video.mp4', play: true);
    try {
      await completer.future.timeout(const Duration(seconds: 22));
    } catch (_) {}
    recorder.cancel();
    await player.dispose();
    final out = recorder.buildFixtureOutput(
      scenarioTitle: 'P6 组 2: 独立全新进程单独运行连接超时',
      command: 'flutter test tool/player_probe/standalone_timeout.dart',
      urlPatternDescription: 'http://10.255.255.1:12345/video.mp4',
      requestHeaders: const {},
      environmentInfo: '$envInfo',
      additionalNotes: '在完全独立的干净 OS 进程中运行，进程启动前无任何 DNS 失败历史',
    );
    await File('test/fixtures/player_logs/p6_isolated_connect_timeout_prod.txt').writeAsString(out);
  }, timeout: const Timeout(Duration(seconds: 35)));
}
''');

    print('Launching standalone process for connect timeout...');
    final flutterExe = Platform.isWindows ? 'flutter' : 'flutter';
    final procRes = await Process.run(
      flutterExe,
      ['test', 'tool/player_probe/standalone_timeout.dart'],
      runInShell: true,
    );
    print('Standalone process finished with exitCode: ${procRes.exitCode}');
    if (procRes.stdout.toString().isNotEmpty) {
      print('Stdout: ${procRes.stdout}');
    }
    if (procRes.stderr.toString().isNotEmpty) {
      print('Stderr: ${procRes.stderr}');
    }

    if (standaloneScript.existsSync()) {
      await standaloneScript.delete();
    }

    final isolatedFixtureFile = File('test/fixtures/player_logs/p6_isolated_connect_timeout_prod.txt');
    bool isolatedHasDnsLeak = false;
    if (isolatedFixtureFile.existsSync()) {
      final content = await isolatedFixtureFile.readAsString();
      isolatedHasDnsLeak = content.contains('probe-dns-nxdomain.invalid') || content.contains('Failed to resolve hostname');
    }
    print('Group 2 Result: Isolated process DNS log leaked? => $isolatedHasDnsLeak');

    print('\n==================================================');
    print('P6 FINAL CONCLUSION:');
    print('Same Process Leaked: $sameProcHasDnsLeak');
    print('Isolated Process Leaked: $isolatedHasDnsLeak');
    print('==================================================');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
