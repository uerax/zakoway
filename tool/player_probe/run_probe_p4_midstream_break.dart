// 运行命令: flutter test tool/player_probe/run_probe_p4_midstream_break.dart
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

  test('P4: True Midstream Disconnect (Refuse vs Recover)', () async {
    ProbeEnvironment.ensureInitialized();

    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';
    final sampleFile = File('tool/player_probe/sample_65s_faststart.mp4');
    if (!sampleFile.existsSync()) {
      throw Exception('sample_65s_faststart.mp4 not found. Please generate using ffmpeg.');
    }

    const successDefinition = '起播正常推进至 position >= 3 秒触发切断；切断后观察 60 秒，记录是否成功重连恢复或抛出错误';

    Future<void> runMidstreamProbe({
      required String filename,
      required String scenarioTitle,
      required MockServerMode serverMode,
      required MPVLogLevel logLevel,
      required String variantDescription,
    }) async {
      print('\n==================================================');
      print('Running P4: $filename ($scenarioTitle, logLevel: $logLevel)...');
      print('==================================================');

      final server = MockMediaServer(
        mediaFile: sampleFile,
        mode: serverMode,
      );
      await server.start();

      final player = Player(
        configuration: PlayerConfiguration(
          logLevel: logLevel,
        ),
      );
      await ProbeEnvironment.applyAppMpvProperties(player);

      final recorder = ProbeRecorder(player);
      recorder.logCustom('probe.config', 'logLevel=$logLevel, mode=$serverMode, sampleSize=${sampleFile.lengthSync()}B');

      final dropCompleter = Completer<void>();
      int transferredBytesAtDrop = 0;

      // 监听 position >= 3 秒时由探针进程通知切断
      final subPos = player.stream.position.listen((pos) {
        if (pos >= const Duration(seconds: 3) && !dropCompleter.isCompleted) {
          dropCompleter.complete();
          transferredBytesAtDrop = server.dropConnectionNow();
          recorder.logCustom(
            'action.disconnect_triggered',
            'position=${pos.inMilliseconds}ms, servedBytesAtDrop=$transferredBytesAtDrop, serverMode=$serverMode',
          );
          print('Disconnect triggered at position: ${pos.inMilliseconds}ms, bytes: $transferredBytesAtDrop');
        }
      });

      await recorder.recordOpen(server.url, headers: const {}, play: true);

      // 等待切断触发（最多等 15 秒）
      try {
        await dropCompleter.future.timeout(const Duration(seconds: 15));
      } catch (_) {
        print('Warning: position >= 3s was not reached within 15 seconds!');
      }

      // 切断后持续深度观察 60 秒
      print('Observing for 60 seconds after midstream disconnect...');
      await Future<void>.delayed(const Duration(seconds: 60));

      await subPos.cancel();
      recorder.cancel();
      await player.dispose();
      await server.stop();

      final outContent = recorder.buildFixtureOutput(
        scenarioTitle: scenarioTitle,
        command: 'flutter test tool/player_probe/run_probe_p4_midstream_break.dart',
        urlPatternDescription: '本地 Mock HTTP 媒体流 (127.0.0.1:${server.port})，65秒 faststart MP4 (moov在文件头)',
        requestHeaders: const {},
        environmentInfo: envInfo,
        additionalNotes: '起播平稳运行至 position >= 3000ms 时探针主动通知切断 Socket (已传输 $transferredBytesAtDrop 字节)；'
            '变体说明: $variantDescription；'
            '切断后持续深度观察 60 秒，记录 completed、stream.error、position、buffering、log 等全生命周期',
      );

      final targetFile = File('test/fixtures/player_logs/$filename');
      await targetFile.writeAsString(outContent);
      print('Saved fixture: ${targetFile.path}');
    }

    // 4a. 切断后持续拒绝连接 (生产 error 级别, 观察 60 秒)
    await runMidstreamProbe(
      filename: 'p4_midstream_break_refuse_prod.txt',
      scenarioTitle: 'P4a: 真实中途断流 (起播3秒切断后持续拒连, 生产 error 级别, 观察60s)',
      serverMode: MockServerMode.p4Refuse,
      logLevel: MPVLogLevel.error,
      variantDescription: '切断后后续所有 Range 重连请求直接拒绝 (destroy socket)',
    );

    // 4a. 切断后持续拒绝连接 (详细 debug 级别, 观察 60 秒)
    await runMidstreamProbe(
      filename: 'p4_midstream_break_refuse_verbose.txt',
      scenarioTitle: 'P4a: 真实中途断流 (起播3秒切断后持续拒连, 详细 debug 级别, 观察60s)',
      serverMode: MockServerMode.p4Refuse,
      logLevel: MPVLogLevel.debug,
      variantDescription: '切断后后续所有 Range 重连请求直接拒绝 (destroy socket)',
    );

    // 4b. 切断后恢复服务 (生产 error 级别, 观察 60 秒)
    await runMidstreamProbe(
      filename: 'p4_midstream_break_recover_prod.txt',
      scenarioTitle: 'P4b: 真实中途断流 (起播3秒切断后恢复服务, 生产 error 级别, 观察60s)',
      serverMode: MockServerMode.p4Recover,
      logLevel: MPVLogLevel.error,
      variantDescription: '切断后后续 Range 重连请求允许正常提供服务 (模拟网络自愈重连)',
    );

    // 4b. 切断后恢复服务 (详细 debug 级别, 观察 60 秒)
    await runMidstreamProbe(
      filename: 'p4_midstream_break_recover_verbose.txt',
      scenarioTitle: 'P4b: 真实中途断流 (起播3秒切断后恢复服务, 详细 debug 级别, 观察60s)',
      serverMode: MockServerMode.p4Recover,
      logLevel: MPVLogLevel.debug,
      variantDescription: '切断后后续 Range 重连请求允许正常提供服务 (模拟网络自愈重连)',
    );

    print('All P4 probes completed successfully!');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
