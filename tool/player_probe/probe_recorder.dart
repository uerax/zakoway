import 'dart:async';
import 'package:media_kit/media_kit.dart';

class ProbeEvent {
  ProbeEvent({
    required this.elapsedMs,
    required this.isoTimestamp,
    required this.tag,
    required this.message,
  });

  final int elapsedMs;
  final String isoTimestamp;
  final String tag;
  final String message;

  String format({required String Function(String) maskFn}) {
    final cleanMsg = maskFn(message);
    return '[+${elapsedMs.toString().padLeft(5, ' ')}ms] [$isoTimestamp] [$tag] $cleanMsg';
  }
}

class ProbeRecorder {
  ProbeRecorder(this.player) {
    _clock = Stopwatch()..start();
    _bindStreams();
  }

  final Player player;
  late final Stopwatch _clock;
  final List<ProbeEvent> events = [];
  final List<StreamSubscription<dynamic>> _subs = [];

  static String maskSensitive(String text) {
    // 替换 sign, t, fid, token 等敏感鉴权参数为 "..."
    var res = text.replaceAll(RegExp(r'sign=[^&\s"\''\)\>]+'), 'sign=...');
    res = res.replaceAllMapped(RegExp(r'([?&])t=\d+'), (m) => '${m[1]}t=...');
    res = res.replaceAllMapped(RegExp(r'([?&])token=[^&\s"\''\)\>]+'), (m) => '${m[1]}token=...');
    res = res.replaceAllMapped(RegExp(r'([?&])fid=[^&\s"\''\)\>]+'), (m) => '${m[1]}fid=...');
    return res;
  }

  void logCustom(String tag, String message) {
    events.add(ProbeEvent(
      elapsedMs: _clock.elapsedMilliseconds,
      isoTimestamp: DateTime.now().toIso8601String(),
      tag: tag,
      message: message,
    ));
  }

  void _bindStreams() {
    _subs.add(player.stream.error.listen((err) {
      logCustom('stream.error', err);
    }));

    _subs.add(player.stream.log.listen((log) {
      logCustom('stream.log', '[${log.prefix}] (${log.level}) ${log.text}');
    }));

    _subs.add(player.stream.width.listen((w) {
      logCustom('stream.width', '$w');
    }));

    _subs.add(player.stream.height.listen((h) {
      logCustom('stream.height', '$h');
    }));

    _subs.add(player.stream.videoParams.listen((vp) {
      logCustom(
        'stream.videoParams',
        'w=${vp.w}, h=${vp.h}, dw=${vp.dw}, dh=${vp.dh}, aspect=${vp.aspect}, pixelformat=${vp.pixelformat}, hwPixelformat=${vp.hwPixelformat}',
      );
    }));

    _subs.add(player.stream.tracks.listen((tracks) {
      logCustom(
        'stream.tracks',
        'videoCount=${tracks.video.length}, audioCount=${tracks.audio.length}, subtitleCount=${tracks.subtitle.length}',
      );
    }));

    _subs.add(player.stream.duration.listen((dur) {
      logCustom('stream.duration', '${dur.inMilliseconds}ms ($dur)');
    }));

    _subs.add(player.stream.position.listen((pos) {
      logCustom('stream.position', '${pos.inMilliseconds}ms ($pos)');
    }));

    _subs.add(player.stream.buffering.listen((b) {
      logCustom('stream.buffering', '$b');
    }));

    _subs.add(player.stream.buffer.listen((buf) {
      logCustom('stream.buffer', '${buf.inMilliseconds}ms ($buf)');
    }));

    _subs.add(player.stream.playing.listen((p) {
      logCustom('stream.playing', '$p');
    }));

    _subs.add(player.stream.completed.listen((c) {
      logCustom('stream.completed', '$c');
    }));
  }

  Future<void> recordOpen(
    String uri, {
    Map<String, String>? headers,
    bool play = true,
  }) async {
    final startMs = _clock.elapsedMilliseconds;
    logCustom(
      'action.open.call',
      'uri=$uri, play=$play, headers=${headers ?? {}}',
    );
    try {
      await player.open(
        Media(uri, httpHeaders: headers ?? const {}),
        play: play,
      );
      final finishMs = _clock.elapsedMilliseconds;
      logCustom(
        'action.open.future_completed',
        'cost=${finishMs - startMs}ms',
      );
    } catch (e, st) {
      final finishMs = _clock.elapsedMilliseconds;
      logCustom(
        'action.open.future_error',
        'cost=${finishMs - startMs}ms, error=$e\n$st',
      );
    }
  }

  void cancel() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  String buildFixtureOutput({
    required String scenarioTitle,
    required String command,
    required String urlPatternDescription,
    required Map<String, String> requestHeaders,
    required String environmentInfo,
    String? additionalNotes,
  }) {
    final buf = StringBuffer();
    buf.writeln('================================================================================');
    buf.writeln('ZAKOWAY PLAYER PROBE FIXTURE LOG');
    buf.writeln('================================================================================');
    buf.writeln('场景名称: $scenarioTitle');
    buf.writeln('测试日期: ${DateTime.now().toIso8601String()}');
    buf.writeln('执行环境: $environmentInfo');
    buf.writeln('执行命令: $command');
    buf.writeln('URL形态说明: $urlPatternDescription');
    buf.writeln('脱敏规则说明: 敏感参数 sign、t、token 等替换为 ...，其余保持完全原始输出');
    buf.writeln('请求头信息: $requestHeaders');
    if (additionalNotes != null) {
      buf.writeln('附加说明: $additionalNotes');
    }
    buf.writeln('================================================================================');
    buf.writeln('TIMELINE EVENTS (Monotonic relative ms from T0, absolute ISO, tag, raw message):');
    buf.writeln('================================================================================');

    for (final e in events) {
      buf.writeln(e.format(maskFn: maskSensitive));
    }

    buf.writeln('================================================================================');
    buf.writeln('END OF FIXTURE LOG');
    buf.writeln('================================================================================');
    return buf.toString();
  }
}
