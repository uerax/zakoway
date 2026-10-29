import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'core/constants/app_constants.dart';
import 'core/network/bangumi_client.dart';
import 'core/providers/bangumi_providers.dart';
import 'core/services/app_preferences.dart';
import 'core/services/display_mode_service.dart';
import 'core/services/network_connectivity_service.dart';
import 'core/services/watch_history_service.dart';
import 'core/services/watched_episodes_service.dart';
import 'core/theme/m3_expressive_theme.dart';
import 'core/utils/appearance_manager.dart';
import 'core/utils/app_toast.dart';
import 'core/utils/font_manager.dart';
import 'core/utils/scroll_behavior.dart';
import 'features/common/widgets/app_desktop_title_bar.dart';
import 'features/main_navigation_shell.dart';
import 'features/player/services/shader_asset_service.dart';
import 'features/player/source/source_bundle_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化从原生平台读取应用动态版本号 (pubspec.yaml 打包注入)
  await AppConstants.initialize();

  // 0. 初始化跨平台视频播放底座 (基于 libmpv)
  MediaKit.ensureInitialized();

  // 1. 初始化并恢复本地持久化配置（网络线路、字体、壁纸等）
  await AppPreferences.init();
  if (!kIsWeb && Platform.isAndroid) {
    unawaited(DisplayModeService.initialize());
  }
  await WatchHistoryService.instance.getHistory();
  await WatchedEpisodesService.instance.initialize();

  // 1.05 初始化网络连通感知服务（用于播放器自适应 150MB Wi-Fi / 16MB 蜂窝缓冲调度）
  await NetworkConnectivityService.instance.initialize();

  // 1.1 异步初始化动态视频源解析器核心 Bundle
  SourceBundleManager.instance.initialize();

  // 1.15 异步预释放 Anime4K 超分辨率 GLSL 着色器到本地应用目录
  unawaited(ShaderAssetService.instance.copyShadersToExternalDirectory());

  // 2. 依据运行平台动态调优 Flutter 全局 ImageCache 显存水线与图片缓存数量：
  // 移动端：100MB / 200 张，保障滑动流畅并防止显存溢出；
  // 桌面端：200MB / 400 张，适配大屏高分辨显示器，回滑零二次解码。
  final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  PaintingBinding.instance.imageCache.maximumSize = isDesktop ? 400 : 200;
  PaintingBinding.instance.imageCache.maximumSizeBytes = isDesktop
      ? 200 * 1024 * 1024
      : 100 * 1024 * 1024;

  // 3. 桌面端初始化自定义无边框沉浸式窗口骨架
  if (isDesktop) {
    try {
      await windowManager.ensureInitialized();
      windowManager.waitUntilReadyToShow(
        const WindowOptions(
          titleBarStyle: TitleBarStyle.hidden,
        ),
        () async {
          await windowManager.show();
          await windowManager.focus();
        },
      );
    } catch (e) {
      debugPrint('桌面端 window_manager 初始化跳过: $e');
    }
  }

  runApp(const ZakowayApp());
}

class ZakowayApp extends StatelessWidget {
  final BangumiClient? client;

  const ZakowayApp({super.key, this.client});

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        if (client != null) bangumiClientProvider.overrideWithValue(client!),
      ],
      child: ListenableBuilder(
        listenable: Listenable.merge([
          FontManager.instance,
          AppearanceManager.instance,
        ]),
        builder: (context, _) {
        final currentFont = FontManager.instance.activeFontFamily;
        final fontFallback = FontManager.fallbackFontFamilies;
        // 动态响应用户选定的全局主题强调色
        final primaryColor = AppearanceManager.instance.primaryColor;

        return MaterialApp(
          title: 'Zakoway 动漫',
          debugShowCheckedModeBanner: false,
          scaffoldMessengerKey: AppToast.scaffoldMessengerKey,
          scrollBehavior: const AppScrollBehavior(),
          theme: M3ExpressiveTheme.build(
            primaryColor: primaryColor,
            brightness: Brightness.light,
            currentFont: currentFont,
            fontFallback: fontFallback,
          ),
          darkTheme: M3ExpressiveTheme.build(
            primaryColor: primaryColor,
            brightness: Brightness.dark,
            currentFont: currentFont,
            fontFallback: fontFallback,
          ),
          themeMode: ThemeMode.system,
          builder: (context, child) {
            final appFrame = AppDesktopWindowFrame(
              child: child ?? const SizedBox.shrink(),
            );
            // 特殊处理说明：
            // 桌面端 (Windows/macOS/Linux) 将全应用根节点排除在系统无障碍语义树之外。
            // 配合 windows runner 的 WM_GETOBJECT 拦截形成双保险，
            // 彻底防止 Flutter 引擎在桌面端产生任何 AXTree 拓扑反序列化更新与相关报错。
            if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
              return ExcludeSemantics(child: appFrame);
            }
            return appFrame;
          },
          home: MainNavigationShell(client: client),
        );
      },
    ),
  );
}
}
