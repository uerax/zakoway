// 运行命令: flutter test tool/player_probe/run_probe_p3_tls_matrix.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

class TargetHost {
  TargetHost({
    required this.domain,
    required this.port,
    required this.tag,
  });

  final String domain;
  final int port;
  final String tag;
  String? resolvedIpv4;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('P3: TLS Client Comparison Matrix', () async {
    final targets = [
      TargetHost(domain: 'play.xfvod.pro', port: 8088, tag: 'play_xfvod_pro_8088'),
      TargetHost(domain: 'apn.moedot.net', port: 443, tag: 'apn_moedot_net_443'),
      TargetHost(domain: 'bjdownload.pan.wo.cn', port: 30443, tag: 'bjdownload_pan_wo_cn_30443'),
    ];

    print('Step 1: Resolving IPv4 addresses for targets...');
    for (final t in targets) {
      try {
        final addrs = await InternetAddress.lookup(t.domain, type: InternetAddressType.IPv4);
        if (addrs.isNotEmpty) {
          t.resolvedIpv4 = addrs.first.address;
        } else {
          t.resolvedIpv4 = t.domain;
        }
      } catch (e) {
        print('Resolve failed for ${t.domain}: $e');
        t.resolvedIpv4 = t.domain;
      }
      print('Target [${t.domain}:${t.port}] -> IPv4: ${t.resolvedIpv4}');
    }

    final outDir = Directory('test/fixtures/player_logs');
    if (!outDir.existsSync()) {
      outDir.createSync(recursive: true);
    }

    // -------------------------------------------------------------
    // 1. Dart TLS 探针
    // -------------------------------------------------------------
    Future<void> runDartTlsProbe(TargetHost target) async {
      final buf = StringBuffer();
      buf.writeln('================================================================================');
      buf.writeln('TLS CLIENT MATRIX - DART SECURESOCKET');
      buf.writeln('================================================================================');
      buf.writeln('目标主机: ${target.domain}:${target.port}');
      buf.writeln('解析 IPv4: ${target.resolvedIpv4}');
      buf.writeln('测试日期: ${DateTime.now().toIso8601String()}');
      buf.writeln('执行命令: flutter test tool/player_probe/run_probe_p3_tls_matrix.dart');
      buf.writeln('================================================================================\n');

      final alpnConfigs = [
        ['http/1.1'],
        ['h2', 'http/1.1'],
      ];

      for (final isTwoStep in [false, true]) {
        for (final alpn in alpnConfigs) {
          final modeName = isTwoStep ? 'Two-Step (Socket.connect -> secure)' : 'Direct SecureSocket.connect';
          final alpnName = alpn.join(',');
          buf.writeln('--- Test Case: $modeName (ALPN: [$alpnName]) ---');
          print('Running Dart TLS: ${target.tag} - $modeName (ALPN: $alpnName)...');

          final sw = Stopwatch()..start();
          SecureSocket? secSocket;
          String? selectedProtocol;
          String? handshakeError;
          String? httpResponseLine;
          Map<String, String> responseHeaders = {};

          try {
            final securityCtx = SecurityContext(withTrustedRoots: true);
            if (!isTwoStep) {
              secSocket = await SecureSocket.connect(
                target.domain,
                target.port,
                context: securityCtx,
                onBadCertificate: (cert) => true,
                supportedProtocols: alpn,
                timeout: const Duration(seconds: 8),
              );
            } else {
              final rawSocket = await Socket.connect(
                target.resolvedIpv4!,
                target.port,
                timeout: const Duration(seconds: 8),
              );
              secSocket = await SecureSocket.secure(
                rawSocket,
                host: target.domain,
                context: securityCtx,
                onBadCertificate: (cert) => true,
                supportedProtocols: alpn,
              ).timeout(const Duration(seconds: 8));
            }
            selectedProtocol = secSocket.selectedProtocol;
            sw.stop();
            buf.writeln('TLS 握手: SUCCESS (耗时: ${sw.elapsedMilliseconds}ms, 协商 ALPN: $selectedProtocol)');

            // 发送 HTTP GET 请求
            final getReq = 'GET / HTTP/1.1\r\n'
                'Host: ${target.domain}:${target.port}\r\n'
                'Range: bytes=0-1023\r\n'
                'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/128.0.0.0 Safari/537.36\r\n'
                'Referer: https://next.xifanacg.com/\r\n'
                'Connection: close\r\n\r\n';
            secSocket.write(getReq);
            await secSocket.flush();

            final completer = Completer<String>();
            final incomingBuf = <int>[];
            final sub = secSocket.listen(
              (data) {
                incomingBuf.addAll(data);
                if (data.contains(10) && !completer.isCompleted) {
                  // 收到至少一行
                  completer.complete(utf8.decode(incomingBuf, allowMalformed: true));
                }
              },
              onError: (e) {
                if (!completer.isCompleted) completer.completeError(e);
              },
              onDone: () {
                if (!completer.isCompleted) {
                  completer.complete(utf8.decode(incomingBuf, allowMalformed: true));
                }
              },
              cancelOnError: true,
            );

            try {
              final respStr = await completer.future.timeout(const Duration(seconds: 5));
              final lines = respStr.split(RegExp(r'\r?\n'));
              if (lines.isNotEmpty) {
                httpResponseLine = lines.first;
                for (var idx = 1; idx < lines.length; idx++) {
                  final line = lines[idx];
                  if (line.isEmpty) break;
                  final splitIdx = line.indexOf(':');
                  if (splitIdx > 0) {
                    final k = line.substring(0, splitIdx).trim();
                    final v = line.substring(splitIdx + 1).trim();
                    responseHeaders[k] = v;
                  }
                }
              }
              buf.writeln('HTTP 响应首行: $httpResponseLine');
              buf.writeln('HTTP 响应头: $responseHeaders');
            } catch (httpErr) {
              buf.writeln('HTTP 读取异常: $httpErr');
            }
            await sub.cancel();
          } catch (e) {
            sw.stop();
            handshakeError = e.toString();
            buf.writeln('TLS 握手: FAILED (耗时: ${sw.elapsedMilliseconds}ms)');
            buf.writeln('错误信息: $handshakeError');
          } finally {
            try {
              secSocket?.destroy();
            } catch (_) {}
          }
          buf.writeln('');
        }
      }

      final f = File('test/fixtures/player_logs/tls_matrix_${target.tag}_dart.txt');
      await f.writeAsString(buf.toString());
      print('Saved: ${f.path}');
    }

    // -------------------------------------------------------------
    // 2. curl.exe 探针
    // -------------------------------------------------------------
    Future<void> runCurlProbe(TargetHost target) async {
      final buf = StringBuffer();
      buf.writeln('================================================================================');
      buf.writeln('TLS CLIENT MATRIX - CURL.EXE');
      buf.writeln('================================================================================');
      buf.writeln('目标主机: ${target.domain}:${target.port}');
      buf.writeln('测试日期: ${DateTime.now().toIso8601String()}');
      buf.writeln('执行环境: Windows 11 / MinGW curl.exe');
      buf.writeln('================================================================================\n');

      final variations = [
        ['--tlsv1.2', '--http1.1'],
        ['--tlsv1.3', '--http1.1'],
        ['--tlsv1.2', '--http2'],
        ['--tlsv1.3', '--http2'],
      ];

      for (final v in variations) {
        final optStr = v.join(' ');
        buf.writeln('--- Test Case: curl $optStr ---');
        print('Running curl: ${target.tag} $optStr...');
        final url = 'https://${target.domain}:${target.port}/';
        final args = [
          '-I',
          '-s',
          '-v',
          '--connect-timeout',
          '6',
          '-m',
          '8',
          ...v,
          '-A',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/128.0.0.0 Safari/537.36',
          '-e',
          'https://next.xifanacg.com/',
          url,
        ];

        try {
          final res = await Process.run('curl.exe', args);
          buf.writeln('Exit Code: ${res.exitCode}');
          buf.writeln('Stdout:');
          buf.writeln(res.stdout.toString().trim());
          buf.writeln('Stderr (Handshake trace):');
          buf.writeln(res.stderr.toString().trim());
        } catch (e) {
          buf.writeln('Execution Exception: $e');
        }
        buf.writeln('');
      }

      final f = File('test/fixtures/player_logs/tls_matrix_${target.tag}_curl.txt');
      await f.writeAsString(buf.toString());
      print('Saved: ${f.path}');
    }

    // -------------------------------------------------------------
    // 3. openssl s_client 探针
    // -------------------------------------------------------------
    Future<void> runOpensslProbe(TargetHost target) async {
      final buf = StringBuffer();
      buf.writeln('================================================================================');
      buf.writeln('TLS CLIENT MATRIX - OPENSSL S_CLIENT');
      buf.writeln('================================================================================');
      buf.writeln('目标主机: ${target.domain}:${target.port}');
      buf.writeln('目标 IPv4: ${target.resolvedIpv4}');
      buf.writeln('测试日期: ${DateTime.now().toIso8601String()}');
      buf.writeln('执行环境: OpenSSL 3.x (Git for Windows)');
      buf.writeln('================================================================================\n');

      final testCases = [
        {'name': 'tls1_2_servername_http11', 'args': ['-tls1_2', '-servername', target.domain, '-alpn', 'http/1.1']},
        {'name': 'tls1_3_servername_http11', 'args': ['-tls1_3', '-servername', target.domain, '-alpn', 'http/1.1']},
        {'name': 'tls1_2_servername_h2', 'args': ['-tls1_2', '-servername', target.domain, '-alpn', 'h2,http/1.1']},
        {'name': 'tls1_3_servername_h2', 'args': ['-tls1_3', '-servername', target.domain, '-alpn', 'h2,http/1.1']},
        {'name': 'tls1_2_noservername', 'args': ['-tls1_2', '-noservername']},
        {'name': 'tls1_3_noservername', 'args': ['-tls1_3', '-noservername']},
      ];

      for (final tc in testCases) {
        final name = tc['name'] as String;
        final extraArgs = tc['args'] as List<String>;
        buf.writeln('--- Test Case: openssl s_client $name (${extraArgs.join(' ')}) ---');
        print('Running openssl: ${target.tag} $name...');

        final connStr = '${target.resolvedIpv4}:${target.port}';
        final fullArgs = [
          's_client',
          '-connect',
          connStr,
          ...extraArgs,
        ];

        try {
          final process = await Process.start('openssl.exe', fullArgs);
          // 发送简单换行触发退出
          process.stdin.writeln('Q');
          await process.stdin.flush();

          final outFuture = process.stdout.transform(utf8.decoder).join();
          final errFuture = process.stderr.transform(utf8.decoder).join();

          final exitCode = await process.exitCode.timeout(
            const Duration(seconds: 8),
            onTimeout: () {
              process.kill();
              return -999;
            },
          );

          final out = await outFuture;
          final err = await errFuture;

          buf.writeln('Exit Code: $exitCode');
          buf.writeln('Stdout / SSL Session Output:');
          buf.writeln(out.trim());
          buf.writeln('Stderr:');
          buf.writeln(err.trim());
        } catch (e) {
          buf.writeln('Execution Exception: $e');
        }
        buf.writeln('');
      }

      final f = File('test/fixtures/player_logs/tls_matrix_${target.tag}_openssl.txt');
      await f.writeAsString(buf.toString());
      print('Saved: ${f.path}');
    }

    // -------------------------------------------------------------
    // 4. 浏览器参照探针（记录无头尝试与事实）
    // -------------------------------------------------------------
    Future<void> runBrowserReferenceProbe(TargetHost target) async {
      final buf = StringBuffer();
      buf.writeln('================================================================================');
      buf.writeln('TLS CLIENT MATRIX - BROWSER REFERENCE (EDGE / CHROME)');
      buf.writeln('================================================================================');
      buf.writeln('目标主机: ${target.domain}:${target.port}');
      buf.writeln('测试日期: ${DateTime.now().toIso8601String()}');
      buf.writeln('说明: 探索 Edge/Chrome 自动化访问该主机的行为表现');
      buf.writeln('================================================================================\n');

      const edgePath = r'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe';
      if (File(edgePath).existsSync()) {
        buf.writeln('检测到 Edge 安装路径: $edgePath');
        final targetUrl = 'https://${target.domain}:${target.port}/';
        buf.writeln('执行测试命令: msedge.exe --headless=new --dump-dom $targetUrl');
        try {
          final res = await Process.run(edgePath, [
            '--headless=new',
            '--dump-dom',
            '--enable-logging=stderr',
            '--v=1',
            targetUrl,
          ]).timeout(const Duration(seconds: 8));

          buf.writeln('Edge Exit Code: ${res.exitCode}');
          buf.writeln('Edge Stdout: ${res.stdout.toString().trim()}');
          buf.writeln('Edge Stderr: ${res.stderr.toString().trim()}');
          if (res.stderr.toString().contains('RunDeElevated') || res.stdout.toString().isEmpty) {
            buf.writeln('观测事实: 在管理员权限(Elevated)终端中执行 msedge.exe 时，Edge 触发底层安全隔离 RunDeElevated 降权派发，父进程无子进程网络事件标准输出返回。');
          }
        } catch (e) {
          buf.writeln('Edge 执行异常或超时: $e');
        }
      } else {
        buf.writeln('未在默认路径找到 msedge.exe');
      }

      final f = File('test/fixtures/player_logs/tls_matrix_${target.tag}_browser.txt');
      await f.writeAsString(buf.toString());
      print('Saved: ${f.path}');
    }

    // 执行全部对照组
    for (final target in targets) {
      await runDartTlsProbe(target);
      await runCurlProbe(target);
      await runOpensslProbe(target);
      await runBrowserReferenceProbe(target);
    }

    print('All P3 TLS Matrix probes finished successfully!');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
