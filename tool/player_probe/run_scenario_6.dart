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

  test('Scenario 6: Double open() Timing Variants & Stale Event Isolation', () async {
    ProbeEnvironment.ensureInitialized();

    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';
    final sampleFile = File('tool/player_probe/sample_15s.mp4');

    final server = MockMediaServer(
      mediaFile: sampleFile,
      mode: MockServerMode.normal,
    );
    await server.start();
    final urlA = 'http://127.0.0.1:${server.port}/stream_A.mp4';
    final urlB = 'http://127.0.0.1:${server.port}/stream_B.mp4';

    Future<void> runDoubleOpenProbe({
      required String filename,
      required String scenarioTitle,
      required MPVLogLevel logLevel,
      required Future<void> Function(Player player, ProbeRecorder recorder) triggerLogic,
      required String timingDescription,
    }) async {
      print('Running probe: $filename (logLevel: $logLevel)...');
      final player = Player(
        configuration: PlayerConfiguration(
          logLevel: logLevel,
        ),
      );

      await ProbeEnvironment.applyAppMpvProperties(player);

      final recorder = ProbeRecorder(player);
      recorder.logCustom('probe.config', 'logLevel=$logLevel, variant=$timingDescription');

      await triggerLogic(player, recorder);

      // 观察 B 流启动与后续事件 3 秒
      await Future<void>.delayed(const Duration(seconds: 3));

      recorder.cancel();
      await player.dispose();

      final outContent = recorder.buildFixtureOutput(
        scenarioTitle: scenarioTitle,
        command: 'flutter test tool/player_probe/run_scenario_6.dart',
        urlPatternDescription: 'Stream A ($urlA) -> Stream B ($urlB)',
        requestHeaders: const {},
        environmentInfo: envInfo,
        additionalNotes: '时序变体: $timingDescription。记录各流重置标记出现时刻及 A 的迟到事件',
      );

      final targetFile = File('test/fixtures/player_logs/$filename');
      await targetFile.writeAsString(outContent);
      print('Saved fixture: ${targetFile.path}');
    }

    // 6a. 间隔 20ms
    for (final level in [MPVLogLevel.error, MPVLogLevel.debug]) {
      final isProd = level == MPVLogLevel.error;
      await runDoubleOpenProbe(
        filename: isProd ? 'scenario_6_double_open_20ms_prod.txt' : 'scenario_6_double_open_20ms_verbose.txt',
        scenarioTitle: '场景 6a: 连续两次 open() (间隔 20ms, ${isProd ? "生产" : "详细"}级别)',
        logLevel: level,
        timingDescription: 'open A 后等待 20ms（尚未出画、Future 刚完成）立即 open B',
        triggerLogic: (player, recorder) async {
          unawaited(recorder.recordOpen(urlA, play: true));
          await Future<void>.delayed(const Duration(milliseconds: 20));
          await recorder.recordOpen(urlB, play: true);
        },
      );
    }

    // 6b. 间隔 300ms
    for (final level in [MPVLogLevel.error, MPVLogLevel.debug]) {
      final isProd = level == MPVLogLevel.error;
      await runDoubleOpenProbe(
        filename: isProd ? 'scenario_6_double_open_300ms_prod.txt' : 'scenario_6_double_open_300ms_verbose.txt',
        scenarioTitle: '场景 6b: 连续两次 open() (间隔 300ms, ${isProd ? "生产" : "详细"}级别)',
        logLevel: level,
        timingDescription: 'open A 后等待 300ms（解复用与初始缓冲阶段）立即 open B',
        triggerLogic: (player, recorder) async {
          unawaited(recorder.recordOpen(urlA, play: true));
          await Future<void>.delayed(const Duration(milliseconds: 300));
          await recorder.recordOpen(urlB, play: true);
        },
      );
    }

    // 6c. 首帧之后发起第二次 open
    for (final level in [MPVLogLevel.error, MPVLogLevel.debug]) {
      final isProd = level == MPVLogLevel.error;
      await runDoubleOpenProbe(
        filename: isProd ? 'scenario_6_double_open_after_first_frame_prod.txt' : 'scenario_6_double_open_after_first_frame_verbose.txt',
        scenarioTitle: '场景 6c: 连续两次 open() (首帧出画后立即 open B, ${isProd ? "生产" : "详细"}级别)',
        logLevel: level,
        timingDescription: 'open A 并等待首帧（duration 就绪且 buffering 为 false）后立即 open B',
        triggerLogic: (player, recorder) async {
          final firstFrameCompleter = Completer<void>();
          final sub = player.stream.duration.listen((dur) {
            if (dur > Duration.zero && !firstFrameCompleter.isCompleted) {
              firstFrameCompleter.complete();
            }
          });
          unawaited(recorder.recordOpen(urlA, play: true));
          await firstFrameCompleter.future;
          await sub.cancel();
          recorder.logCustom('probe.checkpoint', 'A 首帧出画，立即发起 open B');
          await recorder.recordOpen(urlB, play: true);
        },
      );
    }

    // 6d. A 正在播放（position 在推进中）时 open B
    for (final level in [MPVLogLevel.error, MPVLogLevel.debug]) {
      final isProd = level == MPVLogLevel.error;
      await runDoubleOpenProbe(
        filename: isProd ? 'scenario_6_open_while_playing_prod.txt' : 'scenario_6_open_while_playing_verbose.txt',
        scenarioTitle: '场景 6d: A 正在播放时 open B (${isProd ? "生产" : "详细"}级别)',
        logLevel: level,
        timingDescription: 'A 播放至 position >= 1.5 秒时（时钟持续前进中）突发 open B',
        triggerLogic: (player, recorder) async {
          final playingProgressCompleter = Completer<void>();
          final sub = player.stream.position.listen((pos) {
            if (pos >= const Duration(milliseconds: 1500) && !playingProgressCompleter.isCompleted) {
              playingProgressCompleter.complete();
            }
          });
          unawaited(recorder.recordOpen(urlA, play: true));
          await playingProgressCompleter.future;
          await sub.cancel();
          recorder.logCustom('probe.checkpoint', 'A 正在播放至 1.5s，时钟活跃推进中，立即发起 open B');
          await recorder.recordOpen(urlB, play: true);
        },
      );
    }

    await server.stop();
    print('All Scenario 6 probes completed successfully!');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
