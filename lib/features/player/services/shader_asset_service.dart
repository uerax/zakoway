import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Anime4K 超分辨率高质量档着色器滤镜链
const List<String> mpvAnime4KShaders = [
  'Anime4K_Clamp_Highlights.glsl',
  'Anime4K_Restore_CNN_VL.glsl',
  'Anime4K_Upscale_CNN_x2_VL.glsl',
  'Anime4K_AutoDownscalePre_x2.glsl',
  'Anime4K_AutoDownscalePre_x4.glsl',
  'Anime4K_Upscale_CNN_x2_M.glsl',
];

/// Anime4K 超分辨率轻量效率档着色器滤镜链
/// 精简官方推荐的快速重建管线，避免多重 Restore CNN 造成重复纹理写入与显卡掉帧
const List<String> mpvAnime4KShadersLite = [
  'Anime4K_Clamp_Highlights.glsl',
  'Anime4K_Restore_CNN_M.glsl',
  'Anime4K_Upscale_CNN_x2_M.glsl',
  'Anime4K_AutoDownscalePre_x2.glsl',
  'Anime4K_AutoDownscalePre_x4.glsl',
  'Anime4K_Upscale_CNN_x2_S.glsl',
];

/// 组装着色器文件绝对路径
/// 特殊处理说明：
/// 1. libmpv 在 Windows 平台下 glsl-shaders 参数必须使用分号 (;) 分隔多个着色器路径；
///    在 Linux / macOS / Android 等 POSIX 平台下则必须使用冒号 (:) 分隔。
/// 2. 无论在哪个操作系统上，路径中的反斜杠 (\) 必须统一替换为正斜杠 (/)！
///    mpv 的配置与指令解析器遵循 POSIX 转义语法，Windows 原生反斜杠（如 C:\Users\...\anime_shaders）
///    会被底层误解析为 \U unicode 转义或 \a 响铃控制字符，导致路径严重损坏、无法加载甚至渲染管线死锁。
String buildShadersAbsolutePath(String baseDirectory, List<String> shaders) {
  final absolutePaths = shaders.map((shader) {
    return path.join(baseDirectory, shader).replaceAll(r'\', '/');
  }).toList();
  if (Platform.isWindows) {
    return absolutePaths.join(';');
  }
  return absolutePaths.join(':');
}

/// Anime4K 着色器资源释放与路径管理服务
/// 负责在应用运行期将内置 Asset 中的 GLSL 着色器释放到本地文件系统供 libmpv 读取
class ShaderAssetService {
  ShaderAssetService._();
  static final ShaderAssetService instance = ShaderAssetService._();

  Directory? _shadersDirectory;
  Directory? get shadersDirectory => _shadersDirectory;

  bool _initialized = false;
  bool get isInitialized => _initialized;

  Completer<void>? _initCompleter;

  static const List<String> _kAllShaderFiles = [
    'Anime4K_AutoDownscalePre_x2.glsl',
    'Anime4K_AutoDownscalePre_x4.glsl',
    'Anime4K_Clamp_Highlights.glsl',
    'Anime4K_Restore_CNN_M.glsl',
    'Anime4K_Restore_CNN_S.glsl',
    'Anime4K_Restore_CNN_VL.glsl',
    'Anime4K_Upscale_CNN_x2_M.glsl',
    'Anime4K_Upscale_CNN_x2_S.glsl',
    'Anime4K_Upscale_CNN_x2_VL.glsl',
  ];

  /// 确保所有 Anime4K 着色器文件已解压释放到本地支持目录
  Future<void> copyShadersToExternalDirectory() async {
    if (_initialized && _shadersDirectory != null && await _shadersDirectory!.exists()) {
      return;
    }
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    try {
      final appSupportDir = await getApplicationSupportDirectory();
      final targetDir = Directory(path.join(appSupportDir.path, 'anime_shaders'));

      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }
      _shadersDirectory = targetDir;

      int copiedCount = 0;
      for (final fileName in _kAllShaderFiles) {
        final targetFile = File(path.join(targetDir.path, fileName));
        if (await targetFile.exists() && (await targetFile.length()) > 0) {
          continue;
        }

        try {
          final data = await rootBundle.load('assets/shaders/$fileName');
          final bytes = data.buffer.asUint8List();
          await targetFile.writeAsBytes(bytes, flush: true);
          copiedCount++;
        } catch (e) {
          debugPrint('[ShaderAssetService] 写入着色器失败 ($fileName): $e');
        }
      }

      if (copiedCount > 0) {
        debugPrint('[ShaderAssetService] 成功复制 $copiedCount 个着色器至: ${targetDir.path}');
      }
      _initialized = true;
      _initCompleter!.complete();
    } catch (e, st) {
      debugPrint('[ShaderAssetService] 初始化着色器目录异常: $e\n$st');
      _initCompleter!.completeError(e, st);
      _initCompleter = null;
      rethrow;
    }
  }

  /// 便捷方法：获取格式化后的绝对着色器配置字符串
  Future<String?> getShadersPathForMode({required bool isQuality}) async {
    await copyShadersToExternalDirectory();
    final dir = _shadersDirectory;
    if (dir == null) return null;
    final shaders = isQuality ? mpvAnime4KShaders : mpvAnime4KShadersLite;
    return buildShadersAbsolutePath(dir.path, shaders);
  }

  @visibleForTesting
  void setShadersDirectoryForTest(Directory dir) {
    _shadersDirectory = dir;
    _initialized = true;
  }
}
