// 运行命令: flutter test tool/player_probe/run_probe_p1_xfxf1_production.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zakoway/features/player/source/sources/xifan_next_source.dart';
import 'probe_environment.dart';
import 'probe_recorder.dart';

class ProbeIterationResult {
  ProbeIterationResult({
    required this.index,
    required this.success,
    required this.elapsedMs,
    required this.targetUrl,
    required this.targetIp,
    required this.failureKind,
    required this.errors,
    required this.logs,
  });

  final int index;
  final bool success;
  final int elapsedMs;
  final String targetUrl;
  final String targetIp;
  final String failureKind; // 'none', 'tls_handshake_closed', 'http_or_signature', 'timeout', 'unknown'
  final List<String> errors;
  final List<String> logs;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('P1: xfxf1 Production & IP Forms Probe', () async {
    ProbeEnvironment.ensureInitialized();
    final source = XifanNextSource();

    print('Step 1: Finding an episode with source_id=4 (xfxf1) using chapters()...');
    const animeUrl = 'https://next.xifanacg.com/anime/3403';
    final roads = await source.chapters(animeUrl);
    String? selectedEpUrl;
    String? selectedEpName;
    for (final r in roads) {
      for (final ep in r.episodes) {
        if (ep.url.contains('source_id=4')) {
          selectedEpUrl = ep.url;
          selectedEpName = '${r.name} - ${ep.name}';
          break;
        }
      }
      if (selectedEpUrl != null) break;
    }

    final finalEpUrl = selectedEpUrl!;
    final finalEpName = selectedEpName!;
    print('Selected Episode: $finalEpName -> $finalEpUrl');

    // 初始解析以获得基础域名和 IPv4 清单
    final initialResolve = await source.resolve(finalEpUrl);
    final initialUri = Uri.parse(initialResolve.url);
    final host = initialUri.host;
    print('Initial Host: $host');
    final ipAddresses = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
    final ipv4List = ipAddresses.map((a) => a.address).toSet().toList();
    print('Resolved IPv4 List: $ipv4List');

    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';
    const successDefinition = 'open 后 15 秒内 position >= 1000ms 为成功，出现 Failed to open 或 15 秒超时未达标为失败';

    String classifyFailure(List<String> errors, List<String> logs, bool timeout) {
      final combined = [...errors, ...logs].join(' ');
      if (combined.contains('tcp: ffurl_read') ||
          combined.contains('mbedtls_ssl_handshake') ||
          combined.contains('-0x4e') ||
          combined.contains('0xdfb9b0bb')) {
        return 'tls_handshake_closed';
      }
      if (combined.contains('HTTP error') || combined.contains('403') || combined.contains('404')) {
        return 'http_or_signature';
      }
      if (timeout) return 'timeout_no_progress';
      return 'unknown_error';
    }

    Future<void> runBatchTest({
      required String filename,
      required String scenarioTitle,
      required bool isIpForm,
      required String? targetSpecificIp,
      required int iterations,
      required MPVLogLevel logLevel,
      required String formDescription,
    }) async {
      print('\n==================================================');
      print('Running: $filename ($scenarioTitle, logLevel: $logLevel, count: $iterations)');
      print('==================================================');

      final results = <ProbeIterationResult>[];
      final fixtureBuf = StringBuffer();

      fixtureBuf.writeln('================================================================================');
      fixtureBuf.writeln('ZAKOWAY PLAYER PROBE FIXTURE LOG - P1');
      fixtureBuf.writeln('================================================================================');
      fixtureBuf.writeln('场景名称: $scenarioTitle');
      fixtureBuf.writeln('测试日期: ${DateTime.now().toIso8601String()}');
      fixtureBuf.writeln('执行环境: $envInfo');
      fixtureBuf.writeln('执行命令: flutter test tool/player_probe/run_probe_p1_xfxf1_production.dart');
      fixtureBuf.writeln('选用番剧与分集: $finalEpName ($finalEpUrl)');
      fixtureBuf.writeln('URL形态说明: $formDescription');
      fixtureBuf.writeln('成功定义: $successDefinition');
      fixtureBuf.writeln('脱敏规则说明: 敏感参数 sign、t、token 等替换为 ...，其余保持完全原始输出');
      fixtureBuf.writeln('附加说明: 生产 mpv 配置，每次迭代重新 resolve() 获取新签名，记录实际使用 IP 与失败类型归因');
      fixtureBuf.writeln('================================================================================\n');

      for (var i = 1; i <= iterations; i++) {
        print('Iteration $i/$iterations...');
        // 每次重新 resolve
        final freshResolve = await source.resolve(finalEpUrl);
        var playUrl = freshResolve.url;
        var headers = Map<String, String>.from(freshResolve.headers);
        String actualIp = 'domain_resolved';

        if (isIpForm) {
          final uri = Uri.parse(playUrl);
          actualIp = targetSpecificIp ?? ipv4List.first;
          final hostHeader = uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
          playUrl = uri.replace(host: actualIp).toString();
          headers['Host'] = hostHeader;
        }

        final player = Player(
          configuration: PlayerConfiguration(
            logLevel: logLevel,
          ),
        );
        await ProbeEnvironment.applyAppMpvProperties(player);

        final capturedErrors = <String>[];
        final capturedLogs = <String>[];
        final subError = player.stream.error.listen((e) => capturedErrors.add(e));
        final subLog = player.stream.log.listen((l) => capturedLogs.add('[${l.prefix}] (${l.level}) ${l.text}'));

        final completer = Completer<bool>();
        final sw = Stopwatch()..start();

        final subPos = player.stream.position.listen((pos) {
          if (pos >= const Duration(milliseconds: 1000) && !completer.isCompleted) {
            completer.complete(true);
          }
        });

        final subErr = player.stream.error.listen((err) {
          if (err.contains('Failed to open') && !completer.isCompleted) {
            completer.complete(false);
          }
        });

        try {
          await player.open(
            Media(playUrl, httpHeaders: headers),
            play: true,
          );
        } catch (_) {}

        bool isSuccess = false;
        bool isTimeout = false;
        try {
          isSuccess = await completer.future.timeout(const Duration(seconds: 15));
        } catch (_) {
          isSuccess = false;
          isTimeout = true;
        }
        sw.stop();

        await subPos.cancel();
        await subErr.cancel();
        await subError.cancel();
        await subLog.cancel();
        await player.dispose();

        final failKind = isSuccess ? 'none' : classifyFailure(capturedErrors, capturedLogs, isTimeout);
        final itRes = ProbeIterationResult(
          index: i,
          success: isSuccess,
          elapsedMs: sw.elapsedMilliseconds,
          targetUrl: playUrl,
          targetIp: actualIp,
          failureKind: failKind,
          errors: capturedErrors,
          logs: capturedLogs,
        );
        results.add(itRes);

        fixtureBuf.writeln('--- Iteration #$i ---');
        fixtureBuf.writeln('目标 URL: ${ProbeRecorder.maskSensitive(playUrl)}');
        fixtureBuf.writeln('实际使用 IP: $actualIp');
        fixtureBuf.writeln('请求头: $headers');
        fixtureBuf.writeln('结果: ${isSuccess ? "SUCCESS" : "FAILED"} (耗时: ${sw.elapsedMilliseconds}ms, 归因: $failKind)');
        if (capturedErrors.isNotEmpty) {
          fixtureBuf.writeln('stream.error:');
          for (final e in capturedErrors) {
            fixtureBuf.writeln('  ${ProbeRecorder.maskSensitive(e)}');
          }
        }
        if (capturedLogs.isNotEmpty) {
          fixtureBuf.writeln('stream.log:');
          for (final l in capturedLogs) {
            fixtureBuf.writeln('  ${ProbeRecorder.maskSensitive(l)}');
          }
        }
        fixtureBuf.writeln('');

        print('  Result: ${isSuccess ? "SUCCESS" : "FAILED"} ($failKind, ${sw.elapsedMilliseconds}ms)');

        if (i < iterations) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }

      // 汇总统计
      final successCount = results.where((r) => r.success).length;
      final failCount = results.length - successCount;
      final tlsFailCount = results.where((r) => r.failureKind == 'tls_handshake_closed').length;
      final httpFailCount = results.where((r) => r.failureKind == 'http_or_signature').length;
      final timeoutCount = results.where((r) => r.failureKind == 'timeout_no_progress').length;

      fixtureBuf.writeln('================================================================================');
      fixtureBuf.writeln('SUMMARY STATS:');
      fixtureBuf.writeln('总测试轮次: ${results.length}');
      fixtureBuf.writeln('成功次数: $successCount');
      fixtureBuf.writeln('失败次数: $failCount');
      fixtureBuf.writeln('  - TLS 握手中断失败: $tlsFailCount');
      fixtureBuf.writeln('  - HTTP/签名层失败: $httpFailCount');
      fixtureBuf.writeln('  - 15秒超时未达标: $timeoutCount');
      fixtureBuf.writeln('成功率: ${(successCount / results.length * 100).toStringAsFixed(1)}%');
      fixtureBuf.writeln('================================================================================');

      final targetFile = File('test/fixtures/player_logs/$filename');
      await targetFile.writeAsString(fixtureBuf.toString());
      print('Saved fixture: ${targetFile.path}');
    }

    // 1. 形态 A：原始域名形态（直接使用 resolve() 返回的 URL 与请求头），10 次
    await runBatchTest(
      filename: 'p1_xfxf1_prod_domain_prod.txt',
      scenarioTitle: 'P1 形态 A: xfxf1 原始域名形态 (生产 mpv 配置, error 级别, 10次)',
      isIpForm: false,
      targetSpecificIp: null,
      iterations: 10,
      logLevel: MPVLogLevel.error,
      formDescription: '直接采用 XifanNextSource().resolve() 返回的原生域名 URL 与 Headers，每次迭代获取新签名',
    );

    await runBatchTest(
      filename: 'p1_xfxf1_prod_domain_verbose.txt',
      scenarioTitle: 'P1 形态 A: xfxf1 原始域名形态 (生产 mpv 配置, debug 级别, 10次)',
      isIpForm: false,
      targetSpecificIp: null,
      iterations: 10,
      logLevel: MPVLogLevel.debug,
      formDescription: '直接采用 XifanNextSource().resolve() 返回的原生域名 URL 与 Headers，每次迭代获取新签名',
    );

    // 2. 形态 B：对 DNS 解析出的每个 IPv4 分别测 5 次（IP 形态）
    for (final ip in ipv4List) {
      final safeIpTag = ip.replaceAll('.', '_');
      await runBatchTest(
        filename: 'p1_xfxf1_prod_ip_${safeIpTag}_prod.txt',
        scenarioTitle: 'P1 形态 B: xfxf1 IP 改写形态 [$ip] (生产 mpv 配置, error 级别, 5次)',
        isIpForm: true,
        targetSpecificIp: ip,
        iterations: 5,
        logLevel: MPVLogLevel.error,
        formDescription: '域名替换为 IPv4 节点 $ip，附带 Host 请求头，每次迭代重新获取新签名',
      );

      await runBatchTest(
        filename: 'p1_xfxf1_prod_ip_${safeIpTag}_verbose.txt',
        scenarioTitle: 'P1 形态 B: xfxf1 IP 改写形态 [$ip] (生产 mpv 配置, debug 级别, 5次)',
        isIpForm: true,
        targetSpecificIp: ip,
        iterations: 5,
        logLevel: MPVLogLevel.debug,
        formDescription: '域名替换为 IPv4 节点 $ip，附带 Host 请求头，每次迭代重新获取新签名',
      );
    }

    print('All P1 probes finished successfully!');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
