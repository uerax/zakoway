import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/models/update/app_version_info.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/core/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppVersionInfo semver & logic tests', () {
    test('compareSemVer correctly compares version strings including beta suffixes', () {
      expect(AppVersionInfo.compareSemVer('1.0.1', '1.0.0'), 1);
      expect(AppVersionInfo.compareSemVer('1.0.0', '1.0.1'), -1);
      expect(AppVersionInfo.compareSemVer('1.0.0', '1.0.0'), 0);
      expect(AppVersionInfo.compareSemVer('v1.2.0', '1.1.9'), 1);
      expect(AppVersionInfo.compareSemVer('2.0.0', '1.99.99'), 1);

      // 正式版与测试版对比：相同主版本号下，正式版高于测试版
      expect(AppVersionInfo.compareSemVer('1.0.1', '1.0.1-beta.1'), 1);
      expect(AppVersionInfo.compareSemVer('1.0.1-beta.1', '1.0.1'), -1);

      // 更高主版本的测试版高于低主版本的正式版
      expect(AppVersionInfo.compareSemVer('1.1.0-beta.1', '1.0.1'), 1);
      expect(AppVersionInfo.compareSemVer('1.0.1', '1.1.0-beta.1'), -1);
    });

    test('AppDownloadAsset getEffectiveUrl applies acceleration prefix and parses sha256', () {
      const asset = AppDownloadAsset(
        fileName: 'Zakoway-v1.0.1-windows-x64.zip',
        url: 'https://github.com/uerax/zakoway/releases/download/v1.0.1/Zakoway.zip',
        size: 52428800,
        sha256: 'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855',
      );

      // 哈希自动规范化为小写
      expect(
        asset.sha256,
        'E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855',
      );

      // 留空直连
      expect(asset.getEffectiveUrl(''), asset.url);
      expect(asset.getEffectiveUrl(null), asset.url);

      // 加速前缀
      expect(
        asset.getEffectiveUrl('https://ghproxy.net/'),
        'https://ghproxy.net/${asset.url}',
      );
    });

    test('parseManifest handles dual-channel latest and beta selection', () {
      final manifestJson = {
        'latest': {
          'version': '1.0.0',
          'buildNumber': 1,
          'title': '正式版',
          'changelog': '稳定发布',
          'downloads': {},
        },
        'beta': {
          'version': '1.1.0-beta.1',
          'buildNumber': 2,
          'title': '测试版',
          'changelog': '尝鲜体验',
          'downloads': {},
        },
      };

      // 1. 关闭 beta 通道：返回 latest 稳定版
      final stableOnly = AppVersionInfo.parseManifest(
        manifestJson,
        includeBeta: false,
      );
      expect(stableOnly?.version, '1.0.0');
      expect(stableOnly?.channel, 'latest');
      expect(stableOnly?.isPrerelease, isFalse);

      // 2. 开启 beta 通道：由于 1.1.0-beta.1 > 1.0.0，返回测试版
      final withBeta = AppVersionInfo.parseManifest(
        manifestJson,
        includeBeta: true,
      );
      expect(withBeta?.version, '1.1.0-beta.1');
      expect(withBeta?.channel, 'beta');
      expect(withBeta?.isPrerelease, isTrue);
    });
  });

  group('UpdateService SHA-256 verification tests', () {
    test('verifyFileSha256 correctly verifies file integrity', () async {
      final tempDir = await Directory.systemTemp.createTemp('update_test_');
      final testFile = File('${tempDir.path}/test_asset.bin');
      const content = 'zakoway update package integrity test content';
      await testFile.writeAsString(content);

      final expectedHash = sha256.convert(utf8.encode(content)).toString();

      // 匹配成功
      final isValid = await UpdateService.instance.verifyFileSha256(
        testFile,
        expectedHash,
      );
      expect(isValid, isTrue);

      // 匹配失败
      final isInvalid = await UpdateService.instance.verifyFileSha256(
        testFile,
        'wronghash1234567890abcdef',
      );
      expect(isInvalid, isFalse);

      // 空哈希跳过比对
      final skipCheck = await UpdateService.instance.verifyFileSha256(
        testFile,
        '',
      );
      expect(skipCheck, isTrue);

      await tempDir.delete(recursive: true);
    });
  });

  group('AppPreferences update settings persistence', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppPreferences.init();
    });

    test('update download prefix saves and normalizes trailing slash', () async {
      expect(AppPreferences.getUpdateDownloadPrefix(), '');

      await AppPreferences.setUpdateDownloadPrefix('https://ghproxy.net');
      expect(AppPreferences.getUpdateDownloadPrefix(), 'https://ghproxy.net/');

      await AppPreferences.setUpdateDownloadPrefix('');
      expect(AppPreferences.getUpdateDownloadPrefix(), '');
    });

    test('beta channel preference persistence', () async {
      expect(AppPreferences.getIncludeBetaChannel(), isFalse);

      await AppPreferences.setIncludeBetaChannel(true);
      expect(AppPreferences.getIncludeBetaChannel(), isTrue);

      await AppPreferences.setIncludeBetaChannel(false);
      expect(AppPreferences.getIncludeBetaChannel(), isFalse);
    });
  });
}
