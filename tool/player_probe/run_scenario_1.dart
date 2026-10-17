import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:zakoway/features/player/source/sources/xifan_next_source.dart';
import 'probe_environment.dart';
import 'probe_recorder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('Scenario 1: Handshake Closed & xfxf1 forms', () async {
    ProbeEnvironment.ensureInitialized();
    final source = XifanNextSource();

    // 1. 获取 3457 AL 线路直链
    print('Resolving anime 3457 episode 1 AL line...');
    final alResolve = await source.resolve(
      'https://next.xifanacg.com/anime/3457/play/206574?source_id=1&source=AL',
    );
    final alUrl = alResolve.url;
    final alHeaders = alResolve.headers;
    print('AL URL resolved: $alUrl');

    // 2. 获取 3403 xfxf1 线路直链
    print('Resolving anime 3403 episode 1 xfxf1 line...');
    final xfxf1Resolve = await source.resolve(
      'https://next.xifanacg.com/anime/3403/play/121397?source_id=4&source=xfxf1',
    );
    final xfxf1DomainUrl = xfxf1Resolve.url;
    final xfxf1DomainHeaders = xfxf1Resolve.headers;
    print('xfxf1 Domain URL resolved: $xfxf1DomainUrl');

    // 构造 xfxf1 "IP 改写 + Host 头" 形态
    final xfxf1Uri = Uri.parse(xfxf1DomainUrl);
    final ipv4s = await InternetAddress.lookup(
      xfxf1Uri.host,
      type: InternetAddressType.IPv4,
    );
    final ipTarget = ipv4s.isNotEmpty ? ipv4s.first.address : xfxf1Uri.host;
    final xfxf1IpUrl = xfxf1Uri.replace(host: ipTarget).toString();
    final hostHeader = xfxf1Uri.hasPort ? '${xfxf1Uri.host}:${xfxf1Uri.port}' : xfxf1Uri.host;
    final xfxf1IpHeaders = Map<String, String>.from(xfxf1DomainHeaders)..['Host'] = hostHeader;
    print('xfxf1 IP+Host URL: $xfxf1IpUrl (Host: $hostHeader)');

    const envInfo = 'Windows 11 Pro x64, media_kit 1.2.6, libmpv v0.36.0-403, FFmpeg n6.0, mbedTLS 3.5.0';

    Future<void> runSingleProbe({
      required String filename,
      required String scenarioTitle,
      required String url,
      required Map<String, String> headers,
      required MPVLogLevel logLevel,
      required bool applyAppProps,
      required String urlPatternDescription,
      Duration waitDuration = const Duration(seconds: 5),
    }) async {
      print('Running probe: $filename (logLevel: $logLevel, appProps: $applyAppProps)...');
      final player = Player(
        configuration: PlayerConfiguration(
          logLevel: logLevel,
        ),
      );

      if (applyAppProps) {
        await ProbeEnvironment.applyAppMpvProperties(player);
      }

      final recorder = ProbeRecorder(player);
      recorder.logCustom('probe.config', 'logLevel=$logLevel, applyAppProps=$applyAppProps');

      await recorder.recordOpen(url, headers: headers, play: true);
      await Future<void>.delayed(waitDuration);

      recorder.cancel();
      await player.dispose();

      final outContent = recorder.buildFixtureOutput(
        scenarioTitle: scenarioTitle,
        command: 'flutter test tool/player_probe/run_scenario_1.dart',
        urlPatternDescription: urlPatternDescription,
        requestHeaders: headers,
        environmentInfo: envInfo,
        additionalNotes: applyAppProps
            ? '应用实际生产 mpv 配置（stream-lavf-o reconnect=1,reconnect_on_network_error=1,reconnect_delay_max=2 等）'
            : '默认 mpv 配置对照组（无应用层 stream-lavf-o 与网络缓存优化）',
      );

      final targetFile = File('test/fixtures/player_logs/$filename');
      await targetFile.writeAsString(outContent);
      print('Saved fixture: ${targetFile.path}');
    }

    // 1a. AL 线路 (play.xfvod.pro:8088 域名形态, 生产配置)
    await runSingleProbe(
      filename: 'scenario_1_handshake_closed_al_prod.txt',
      scenarioTitle: '场景 1a: AL 线路 TLS 握手对端关闭 (域名形态, 生产 mpv 配置, error 级别)',
      url: alUrl,
      headers: alHeaders,
      logLevel: MPVLogLevel.error,
      applyAppProps: true,
      urlPatternDescription: 'AL 线路标准域名形态 (play.xfvod.pro:8088)，携带 Referer: https://next.xifanacg.com/',
    );

    await runSingleProbe(
      filename: 'scenario_1_handshake_closed_al_verbose.txt',
      scenarioTitle: '场景 1a: AL 线路 TLS 握手对端关闭 (域名形态, 生产 mpv 配置, debug 级别)',
      url: alUrl,
      headers: alHeaders,
      logLevel: MPVLogLevel.debug,
      applyAppProps: true,
      urlPatternDescription: 'AL 线路标准域名形态 (play.xfvod.pro:8088)，携带 Referer: https://next.xifanacg.com/',
    );

    // 1b. AL 线路 (play.xfvod.pro:8088 域名形态, 默认 mpv 配置对照组)
    await runSingleProbe(
      filename: 'scenario_1_handshake_closed_al_default_cfg_prod.txt',
      scenarioTitle: '场景 1b: AL 线路 TLS 握手对端关闭 (域名形态, 默认 mpv 配置对照组, error 级别)',
      url: alUrl,
      headers: alHeaders,
      logLevel: MPVLogLevel.error,
      applyAppProps: false,
      urlPatternDescription: 'AL 线路标准域名形态 (play.xfvod.pro:8088)，默认 mpv 配置',
    );

    await runSingleProbe(
      filename: 'scenario_1_handshake_closed_al_default_cfg_verbose.txt',
      scenarioTitle: '场景 1b: AL 线路 TLS 握手对端关闭 (域名形态, 默认 mpv 配置对照组, debug 级别)',
      url: alUrl,
      headers: alHeaders,
      logLevel: MPVLogLevel.debug,
      applyAppProps: false,
      urlPatternDescription: 'AL 线路标准域名形态 (play.xfvod.pro:8088)，默认 mpv 配置',
    );

    // 1c. xfxf1 线路 (原始域名形态, 生产配置)
    await runSingleProbe(
      filename: 'scenario_1_xfxf1_domain_prod.txt',
      scenarioTitle: '场景 1c: xfxf1 国内沃云线路 (原始域名形态, 生产 mpv 配置, error 级别)',
      url: xfxf1DomainUrl,
      headers: xfxf1DomainHeaders,
      logLevel: MPVLogLevel.error,
      applyAppProps: true,
      urlPatternDescription: 'xfxf1 原始域名形态 (${xfxf1Uri.host})，遵循源站 no-referrer 规范',
    );

    await runSingleProbe(
      filename: 'scenario_1_xfxf1_domain_verbose.txt',
      scenarioTitle: '场景 1c: xfxf1 国内沃云线路 (原始域名形态, 生产 mpv 配置, debug 级别)',
      url: xfxf1DomainUrl,
      headers: xfxf1DomainHeaders,
      logLevel: MPVLogLevel.debug,
      applyAppProps: true,
      urlPatternDescription: 'xfxf1 原始域名形态 (${xfxf1Uri.host})，遵循源站 no-referrer 规范',
    );

    // 1d. xfxf1 线路 (IP 改写 + Host 头形态, 生产配置)
    await runSingleProbe(
      filename: 'scenario_1_xfxf1_ip_host_prod.txt',
      scenarioTitle: '场景 1d: xfxf1 国内沃云线路 (IP 改写 + Host 头形态, 生产 mpv 配置, error 级别)',
      url: xfxf1IpUrl,
      headers: xfxf1IpHeaders,
      logLevel: MPVLogLevel.error,
      applyAppProps: true,
      urlPatternDescription: 'xfxf1 IP 改写形态 ($ipTarget)，携带 Host: $hostHeader',
    );

    await runSingleProbe(
      filename: 'scenario_1_xfxf1_ip_host_verbose.txt',
      scenarioTitle: '场景 1d: xfxf1 国内沃云线路 (IP 改写 + Host 头形态, 生产 mpv 配置, debug 级别)',
      url: xfxf1IpUrl,
      headers: xfxf1IpHeaders,
      logLevel: MPVLogLevel.debug,
      applyAppProps: true,
      urlPatternDescription: 'xfxf1 IP 改写形态 ($ipTarget)，携带 Host: $hostHeader',
    );

    print('All Scenario 1 probes completed successfully!');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
