// ignore_for_file: avoid_print

import 'dart:io';

/// 项目统一版本号与 Git Tag 联动自动化管理脚本
///
/// 使用方式:
/// 1. 直接指定版本:
///    dart run tool/bump_version.dart 0.0.2
///    dart run tool/bump_version.dart 0.0.2-beta
/// 2. 语义化递增:
///    dart run tool/bump_version.dart patch   # 0.0.1 -> 0.0.2
///    dart run tool/bump_version.dart minor   # 0.0.1 -> 0.1.0
///    dart run tool/bump_version.dart major   # 0.0.1 -> 1.0.0
///    dart run tool/bump_version.dart beta    # 0.0.1 -> 0.0.2-beta
/// 3. 可选参数:
///    --no-git    仅修改本地版本文件，不自动执行 git commit 与 git tag
///    --build=N   手动指定 buildNumber (默认自动 +1)
void main(List<String> args) {
  if (args.isEmpty || args.contains('-h') || args.contains('--help')) {
    _printUsage();
    exit(0);
  }

  final noGit = args.contains('--no-git');
  int? customBuildNumber;
  String? targetArg;

  for (final arg in args) {
    if (arg.startsWith('--build=')) {
      customBuildNumber = int.tryParse(arg.substring('--build='.length));
    } else if (!arg.startsWith('--')) {
      targetArg = arg.trim();
    }
  }

  if (targetArg == null || targetArg.isEmpty) {
    print('\x1B[31m[错误] 请提供目标版本号或递增模式 (patch / minor / major / beta / x.y.z / x.y.z-beta)\x1B[0m');
    _printUsage();
    exit(1);
  }

  // 1. 读取 pubspec.yaml
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('\x1B[31m[错误] 未在当前目录下找到 pubspec.yaml，请在项目根目录运行此脚本\x1B[0m');
    exit(1);
  }

  final pubspecContent = pubspecFile.readAsStringSync();
  final versionRegex = RegExp(r'^version:\s*([^\s+]+)(?:\+(\d+))?', multiLine: true);
  final match = versionRegex.firstMatch(pubspecContent);

  if (match == null) {
    print('\x1B[31m[错误] 无法在 pubspec.yaml 中匹配到 version 字段\x1B[0m');
    exit(1);
  }

  final currentVersion = match.group(1)!;
  final currentBuildNumber = int.tryParse(match.group(2) ?? '1') ?? 1;

  // 2. 计算新版本与新 buildNumber
  final nextVersion = calculateNextVersion(currentVersion, targetArg);
  final nextBuildNumber = customBuildNumber ?? (currentBuildNumber + 1);

  print('\x1B[36m========================================\x1B[0m');
  print('\x1B[36m  Zakoway 版本升级与 Git Tag 联动工具  \x1B[0m');
  print('\x1B[36m========================================\x1B[0m');
  print('当前版本: \x1B[33mv$currentVersion+$currentBuildNumber\x1B[0m');
  print('目标版本: \x1B[32mv$nextVersion+$nextBuildNumber\x1B[0m');
  print('对应 Tag: \x1B[32mv$nextVersion\x1B[0m');
  print('----------------------------------------');

  // 3. 更新 pubspec.yaml
  final newPubspecContent = pubspecContent.replaceFirst(
    versionRegex,
    'version: $nextVersion+$nextBuildNumber',
  );
  pubspecFile.writeAsStringSync(newPubspecContent);
  print('✔ [1/4] 更新 pubspec.yaml 完成');

  // 4. 更新 lib/core/constants/app_constants.dart 中的默认回退值
  final appConstantsFile = File('lib/core/constants/app_constants.dart');
  if (appConstantsFile.existsSync()) {
    var content = appConstantsFile.readAsStringSync();
    content = content.replaceFirst(
      RegExp(r"static String _appVersion = '[^']+';"),
      "static String _appVersion = '$nextVersion';",
    );
    content = content.replaceFirst(
      RegExp(r'static int _buildNumber = \d+;'),
      'static int _buildNumber = $nextBuildNumber;',
    );
    appConstantsFile.writeAsStringSync(content);
    print('✔ [2/4] 同步更新 app_constants.dart 回退版本');
  }

  // 5. 更新 version.json 模板信息
  final versionJsonFile = File('version.json');
  if (versionJsonFile.existsSync()) {
    var content = versionJsonFile.readAsStringSync();
    // 替换版本号与下载 URL 中的版本标签
    content = content.replaceAll(currentVersion, nextVersion);
    versionJsonFile.writeAsStringSync(content);
    print('✔ [3/4] 同步更新 version.json 基础节点');
  }

  // 6. 更新 windows/runner/Runner.rc 中的回退宏
  final runnerRcFile = File('windows/runner/Runner.rc');
  if (runnerRcFile.existsSync()) {
    var content = runnerRcFile.readAsStringSync();
    final cleanParts = nextVersion.split('-').first.split('.');
    final major = cleanParts.isNotEmpty ? cleanParts[0] : '0';
    final minor = cleanParts.length > 1 ? cleanParts[1] : '0';
    final patch = cleanParts.length > 2 ? cleanParts[2] : '0';

    content = content.replaceFirst(
      RegExp(r'#define VERSION_AS_NUMBER \d+,\d+,\d+,\d+'),
      '#define VERSION_AS_NUMBER $major,$minor,$patch,$nextBuildNumber',
    );
    content = content.replaceFirst(
      RegExp(r'#define VERSION_AS_STRING "[^"]+"'),
      '#define VERSION_AS_STRING "$nextVersion"',
    );
    runnerRcFile.writeAsStringSync(content);
    print('✔ [4/4] 同步更新 Runner.rc 资源回退配置');
  }

  if (noGit) {
    print('\x1B[33m[提示] 已指定 --no-git，跳过 Git 提交与打 Tag\x1B[0m');
    print('\x1B[32m✔ 版本升级操作完成！\x1B[0m');
    return;
  }

  // 7. 执行 Git 提交与创建 Tag
  print('----------------------------------------');
  print('正在执行 Git 变更提交与打 Tag...');

  final tagName = 'v$nextVersion';
  final commitMsg = 'chore(release): bump version to $tagName';

  _runGit(['add', 'pubspec.yaml', 'lib/core/constants/app_constants.dart', 'version.json', 'windows/runner/Runner.rc']);
  _runGit(['commit', '-m', commitMsg]);
  _runGit(['tag', '-a', tagName, '-m', 'Release $tagName']);

  print('\x1B[32m✔ Git 提交已生成: $commitMsg\x1B[0m');
  print('\x1B[32m✔ Git Tag 已打好: $tagName\x1B[0m');
  print('========================================');
  print('\x1B[32m🚀 全部流程完成！推送至远程即可自动触发 CI 发布 Release：\x1B[0m');
  print('\x1B[1m    git push origin master --tags\x1B[0m');
  print('========================================');
}

String calculateNextVersion(String current, String target) {
  final cleanTarget = target.startsWith('v') ? target.substring(1) : target;

  if (['patch', 'minor', 'major', 'beta'].contains(cleanTarget.toLowerCase())) {
    final base = current.split('+').first;
    final isBeta = base.contains('-');
    final mainVersion = base.split('-').first;
    final parts = mainVersion.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    while (parts.length < 3) {
      parts.add(0);
    }

    var major = parts[0];
    var minor = parts[1];
    var patch = parts[2];

    switch (cleanTarget.toLowerCase()) {
      case 'major':
        return '${major + 1}.0.0';
      case 'minor':
        return '$major.${minor + 1}.0';
      case 'patch':
        if (isBeta) {
          // 若当前是 0.0.2-beta，执行 patch 直接正式转正为 0.0.2
          return '$major.$minor.$patch';
        }
        return '$major.$minor.${patch + 1}';
      case 'beta':
        if (isBeta) {
          // 当前已经是 beta (例如 0.0.2-beta 或 0.0.2-beta.1)，递增测试序号
          final prePart = base.split('-')[1];
          final dotParts = prePart.split('.');
          if (dotParts.length > 1) {
            final num = int.tryParse(dotParts.last) ?? 1;
            return '$major.$minor.$patch-${dotParts.first}.${num + 1}';
          } else {
            return '$major.$minor.$patch-$prePart.2';
          }
        }
        // 当前是正式版，发下一个 patch 的 beta 版本
        return '$major.$minor.${patch + 1}-beta';
    }
  }

  // 直接指定的版本格式 (如 0.0.2 或 0.0.2-beta)
  return cleanTarget;
}

void _runGit(List<String> gitArgs) {
  final result = Process.runSync('git', gitArgs);
  if (result.exitCode != 0) {
    print('\x1B[31m[Git 错误] git ${gitArgs.join(' ')}\x1B[0m');
    print(result.stderr);
    exit(result.exitCode);
  }
}

void _printUsage() {
  print('''
Zakoway 版本升级与 Git Tag 联动工具

使用说明:
  dart run tool/bump_version.dart <版本号或模式> [选项]

参数示例:
  dart run tool/bump_version.dart patch         # 自动递增修订版本号 (如 0.0.1 -> 0.0.2)
  dart run tool/bump_version.dart minor         # 自动递增次版本号 (如 0.0.1 -> 0.1.0)
  dart run tool/bump_version.dart major         # 自动递增主版本号 (如 0.0.1 -> 1.0.0)
  dart run tool/bump_version.dart beta          # 发测试版 (如 0.0.1 -> 0.0.2-beta)
  dart run tool/bump_version.dart 0.0.2         # 直接指定正式版本号
  dart run tool/bump_version.dart 0.0.2-beta    # 直接指定测试版本号

选项:
  --no-git       仅修改本地版本文件，不自动提交 commit 与打 tag
  --build=N      手动指定构建版本号 (默认自动在原有基础上 +1)
''');
}
