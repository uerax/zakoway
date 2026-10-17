// 运行命令: flutter test tool/player_probe/run_probe_p5_open_demux_fail_60s.dart
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

  test('P5: Old Scenario 4a Extended to 60s Observation', () async {
    ProbeEnvironment.ensureInitialized();

    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';
    final sampleFile = File('tool/player_probe/sample_15s.mp4');
    if (!sampleFile.existsSync()) {
      throw Exception('sample_15s.mp4 not found.');
    }

    const successDefinition = '打开阶段能够识别格式并起播出画；若在 demux 阶段被截断持续拒连，观察 60 秒内底层是否最终抛出 Failed to open 或其他错误事件';

    Future<void> runExtendedDemuxProbe({
      required String filename,
      required String scenarioTitle,
      required MPVLogLevel logLevel,
    }) async {
      print('\n==================================================');
      print('Running P5: $filename ($scenarioTitle, logLevel: $logLevel)...');
      print('==================================================');

      final server = MockMediaServer(
        mediaFile: sampleFile,
        mode: MockServerMode.eofAndRefuse,
        eofByteThreshold: 70 * 1024, // 传输 70KB (moov在文件尾部无法读取) 后断开
      );
      await server.start();

      final player = Player(
        configuration: PlayerConfiguration(
          logLevel: logLevel,
        ),
      );
      await ProbeEnvironment.applyAppMpvProperties(player);

      final recorder = ProbeRecorder(player);
      recorder.logCustom(
        'probe.config',
        'logLevel=$logLevel, mode=eofAndRefuse, eofByteThreshold=70KB, sampleSize=${sampleFile.lengthSync()}B',
      );

      await recorder.recordOpen(server.url, headers: const {}, play: true);

      // 观察窗口延长至 60 秒
      print('Observing for 60 seconds (waiting for demuxer timeout/error)...');
      await Future<void>.delayed(const Duration(seconds: 60));

      recorder.cancel();
      await player.dispose();
      await server.stop();

      final outContent = recorder.buildFixtureOutput(
        scenarioTitle: scenarioTitle,
        command: 'flutter test tool/player_probe/run_probe_p5_open_demux_fail_60s.dart',
        urlPatternDescription: '本地 Mock HTTP 媒体流 (127.0.0.1:${server.port})，sample_15s.mp4 (moov在文件尾部，传输70KB后持续拒连)',
        requestHeaders: const {},
        environmentInfo: envInfo,
        additionalNotes: '重跑旧场景 4a 并把观察窗口从 8 秒延长到 60 秒；'
            '记录 mpv 底层在 demuxer 阶段未读到 moov 且后续重连全被拒时，是否最终输出 Failed to open 或停在 buffering=true',
      );

      final targetFile = File('test/fixtures/player_logs/$filename');
      await targetFile.writeAsString(outContent);
      print('Saved fixture: ${targetFile.path}');
    }

    // 生产 error 级别
    await runExtendedDemuxProbe(
      filename: 'p5_demux_fail_60s_prod.txt',
      scenarioTitle: 'P5: 打开阶段 demux 截断失败 (moov在尾部传输70KB拒连, 生产 error 级别, 观察60s)',
      logLevel: MPVLogLevel.error,
    );

    // 详细 debug 级别
    await runExtendedDemuxProbe(
      filename: 'p5_demux_fail_60s_verbose.txt',
      scenarioTitle: 'P5: 打开阶段 demux 截断失败 (moov在尾部传输70KB拒连, 详细 debug 级别, 观察60s)',
      logLevel: MPVLogLevel.debug,
    );

    print('All P5 probes completed successfully!');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
