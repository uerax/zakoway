// 运行命令: flutter run -d windows -t tool/player_probe/first_frame_app.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'probe_environment.dart';
import 'probe_recorder.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  MediaKit.ensureInitialized();

  runApp(const FirstFrameProbeApp());
}

class FirstFrameProbeApp extends StatefulWidget {
  const FirstFrameProbeApp({super.key});

  @override
  State<FirstFrameProbeApp> createState() => _FirstFrameProbeAppState();
}

class _FirstFrameProbeAppState extends State<FirstFrameProbeApp> {
  Player? _player;
  VideoController? _videoController;
  ProbeRecorder? _recorder;
  String _statusText = 'Preparing Direct3D surface...';
  bool _completed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startProbeAfterMount();
    });
  }

  Future<void> _startProbeAfterMount() async {
    // 延迟 1 秒，等待 Flutter Windows 主窗口、Direct3D 上下文完全构建呈现
    await Future<void>.delayed(const Duration(seconds: 1));

    final player = Player(
      configuration: const PlayerConfiguration(
        logLevel: MPVLogLevel.debug,
      ),
    );

    // 生产一致的 mpv 原生配置 (hwdec=auto, scale=spline36 等)
    await ProbeEnvironment.applyAppMpvProperties(player);

    // 生产一致的 VideoControllerConfiguration
    final controller = VideoController(
      player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );

    final recorder = ProbeRecorder(player);
    recorder.logCustom(
      'probe.config',
      'Production configuration: VideoControllerConfiguration(enableHardwareAcceleration: true), '
      'Video(controls: NoVideoControls, fit: BoxFit.contain), '
      'mpv: hwdec=auto, scale=spline36, cscale=spline36',
    );

    // 监听 VideoController 渲染首帧通知
    controller.waitUntilFirstFrameRendered.then((_) {
      print('>>> [P7 Event] Media A: waitUntilFirstFrameRendered completed!');
      recorder.logCustom(
        'video_controller.waitUntilFirstFrameRendered',
        'Media A: First frame rendered future completed!',
      );
    });

    setState(() {
      _player = player;
      _videoController = controller;
      _recorder = recorder;
      _statusText = 'Surface ready, initializing media sequence...';
    });

    // 稍等 500ms 让 Video 组件完成首个纹理挂载
    await Future<void>.delayed(const Duration(milliseconds: 500));

    Directory projectRoot = Directory.current;
    while (!File('${projectRoot.path}/pubspec.yaml').existsSync()) {
      final parent = projectRoot.parent;
      if (parent.path == projectRoot.path) break;
      projectRoot = parent;
    }
    print('Project Root resolved: ${projectRoot.path}');

    setState(() {
      _statusText = 'Playing Media A (sample_15s.mp4)...';
    });

    final fileA = File('${projectRoot.path}/tool/player_probe/sample_15s.mp4').absolute.path;
    final fileB = File('${projectRoot.path}/tool/player_probe/sample_65s_faststart.mp4').absolute.path;

    final uriA = Uri.file(fileA).toString();
    final uriB = Uri.file(fileB).toString();

    // 1. 播放媒体 A
    print('Playing Media A: $uriA');
    recorder.logCustom('action.open_media_a', 'uri=$uriA');
    await recorder.recordOpen(uriA, play: true);

    // 等待 2.5 秒，确保出画且媒体 A 稳定播放
    await Future<void>.delayed(const Duration(milliseconds: 2500));

    // 2. 媒体 A 播放中且 Video 挂载时，连续 open 媒体 B
    setState(() {
      _statusText = 'Playing Media B (open while Media A is playing)...';
    });
    print('Playing Media B (while Media A is playing): $uriB');
    recorder.logCustom('action.open_media_b_while_playing', 'uri=$uriB');

    // 再次调用 waitUntilFirstFrameRendered 观察第二次行为
    controller.waitUntilFirstFrameRendered.then((_) {
      print('>>> [P7 Event] Media B: waitUntilFirstFrameRendered completed (second invocation)!');
      recorder.logCustom(
        'video_controller.waitUntilFirstFrameRendered',
        'Media B: First frame rendered future completed (second invocation)!',
      );
    });

    await recorder.recordOpen(uriB, play: true);

    // 媒体 B 播放 2.5 秒，观察 width/height 是否先回到 null，以及新 videoParams 时序
    await Future<void>.delayed(const Duration(milliseconds: 2500));

    recorder.cancel();

    // 写入夹具文件
    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, media_kit_video, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';
    final outContent = recorder.buildFixtureOutput(
      scenarioTitle: 'P7: 真实渲染下的首帧信号与双媒体切播实测 (VideoController + Video 组件挂载)',
      command: 'flutter run -d windows -t tool/player_probe/first_frame_app.dart',
      urlPatternDescription: '本地媒体 sample_15s.mp4 -> 播放中切换 sample_65s_faststart.mp4',
      requestHeaders: const {},
      environmentInfo: envInfo,
      additionalNotes: '配置参数与生产严格一致: VideoControllerConfiguration(enableHardwareAcceleration: true), '
          'Video(controls: NoVideoControls, fit: BoxFit.contain)；\n'
          '硬件解码: hwdec=auto, hwdec-codecs=all；\n'
          '渲染器 vo: libmpv d3d11 GPU 纹理；\n'
          '观察重点: width/height、videoParams、position、duration、waitUntilFirstFrameRendered 的到达先后顺序；'
          '以及在 A 播放中且 Video 已挂载时 open B，记录 width/height 是否先回到 null 再出现新值。',
    );

    final targetFile = File('${projectRoot.path}/test/fixtures/player_logs/p7_first_frame_real_render.txt');
    await targetFile.writeAsString(outContent);
    print('P7 Fixture successfully saved to: ${targetFile.path}');

    setState(() {
      _statusText = 'Probe completed! Saved to ${targetFile.path}\nExiting in 1 second...';
      _completed = true;
    });

    await Future<void>.delayed(const Duration(seconds: 1));
    await player.dispose();
    exit(0);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _statusText,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 640,
                height: 360,
                child: _videoController != null
                    ? Video(
                        controller: _videoController!,
                        controls: NoVideoControls,
                        fit: BoxFit.contain,
                        pauseUponEnteringBackgroundMode: false,
                        resumeUponEnteringForegroundMode: true,
                      )
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white70),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
