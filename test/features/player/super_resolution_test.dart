import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/controller/playback_state.dart';
import 'package:zakoway/features/player/services/player_preferences_service.dart';
import 'package:zakoway/features/player/services/shader_asset_service.dart';
import 'package:zakoway/features/player/widgets/controls/super_resolution_dialog_helper.dart';
import 'package:zakoway/features/settings/widgets/super_resolution_settings_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlayerPreferencesService.instance.resetForTest();
  });

  group('Anime4K 超分辨率枚举与路径工具测试', () {
    test('SuperResolutionMode 存储值与反序列化映射测试', () {
      expect(SuperResolutionMode.off.storageValue, equals(1));
      expect(SuperResolutionMode.efficiency.storageValue, equals(2));
      expect(SuperResolutionMode.quality.storageValue, equals(3));

      expect(SuperResolutionMode.fromStorageValue(1), equals(SuperResolutionMode.off));
      expect(SuperResolutionMode.fromStorageValue(2), equals(SuperResolutionMode.efficiency));
      expect(SuperResolutionMode.fromStorageValue(3), equals(SuperResolutionMode.quality));
      expect(SuperResolutionMode.fromStorageValue(999), equals(SuperResolutionMode.off));
      expect(SuperResolutionMode.fromStorageValue(null), equals(SuperResolutionMode.off));
    });

    test('Anime4K 着色器列表定义完整性测试', () {
      expect(mpvAnime4KShaders, contains('Anime4K_Clamp_Highlights.glsl'));
      expect(mpvAnime4KShaders, contains('Anime4K_Restore_CNN_VL.glsl'));
      expect(mpvAnime4KShaders, contains('Anime4K_Upscale_CNN_x2_VL.glsl'));
      expect(mpvAnime4KShaders, contains('Anime4K_AutoDownscalePre_x2.glsl'));
      expect(mpvAnime4KShaders, contains('Anime4K_AutoDownscalePre_x4.glsl'));
      expect(mpvAnime4KShaders, contains('Anime4K_Upscale_CNN_x2_M.glsl'));

      expect(mpvAnime4KShadersLite, contains('Anime4K_Clamp_Highlights.glsl'));
      expect(mpvAnime4KShadersLite, contains('Anime4K_Restore_CNN_M.glsl'));
      expect(mpvAnime4KShadersLite, contains('Anime4K_Upscale_CNN_x2_M.glsl'));
      expect(mpvAnime4KShadersLite, contains('Anime4K_AutoDownscalePre_x2.glsl'));
      expect(mpvAnime4KShadersLite, contains('Anime4K_AutoDownscalePre_x4.glsl'));
      expect(mpvAnime4KShadersLite, contains('Anime4K_Upscale_CNN_x2_S.glsl'));
    });

    test('buildShadersAbsolutePath 路径合成规则测试（包含正斜杠标准化）', () {
      final sep = Platform.isWindows ? ';' : ':';
      final pathStr = buildShadersAbsolutePath(r'C:\test\shaders', [
        'Anime4K_Clamp_Highlights.glsl',
        'Anime4K_Restore_CNN_M.glsl',
      ]);

      expect(pathStr, contains('Anime4K_Clamp_Highlights.glsl'));
      expect(pathStr, contains('Anime4K_Restore_CNN_M.glsl'));
      expect(pathStr.contains(sep), isTrue);
      // 必须确保反斜杠全被规范化为正斜杠，严防 mpv 转义故障
      expect(pathStr.contains(r'\'), isFalse);
    });
  });

  group('PlayerPreferencesService 超分持久化测试', () {
    test('超分模式与提示开关持久化存储及读取测试', () async {
      final prefs = PlayerPreferencesService.instance;
      await prefs.initialize();

      expect(prefs.superResolutionMode, equals(SuperResolutionMode.off));
      expect(prefs.disableSuperResolutionWarning, isFalse);

      await prefs.saveSuperResolutionMode(SuperResolutionMode.quality);
      await prefs.saveDisableSuperResolutionWarning(true);

      expect(prefs.superResolutionMode, equals(SuperResolutionMode.quality));
      expect(prefs.disableSuperResolutionWarning, isTrue);

      // 重新初始化校验是否持久化到 SharedPreferences
      prefs.resetForTest();
      await prefs.initialize();
      expect(prefs.superResolutionMode, equals(SuperResolutionMode.quality));
      expect(prefs.disableSuperResolutionWarning, isTrue);
    });
  });

  group('ZakowayPlaybackController 超分状态控制测试', () {
    test('setSuperResolution 状态流转与持久化测试', () async {
      final controller = ZakowayPlaybackController();

      expect(controller.core.value.superResolution, equals(SuperResolutionMode.off));

      await controller.setSuperResolution(SuperResolutionMode.efficiency);
      expect(controller.core.value.superResolution, equals(SuperResolutionMode.efficiency));
      expect(
        PlayerPreferencesService.instance.superResolutionMode,
        equals(SuperResolutionMode.efficiency),
      );

      await controller.setSuperResolution(SuperResolutionMode.quality);
      expect(controller.core.value.superResolution, equals(SuperResolutionMode.quality));

      await controller.setSuperResolution(SuperResolutionMode.off);
      expect(controller.core.value.superResolution, equals(SuperResolutionMode.off));

      await controller.dispose();
    });
  });

  group('SuperResolutionDialogHelper 确认弹窗交互测试', () {
    testWidgets('非质量档切换无需弹窗确认', (tester) async {
      final controller = ZakowayPlaybackController();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                SuperResolutionDialogHelper.handleModeSelection(
                  context: context,
                  controller: controller,
                  mode: SuperResolutionMode.efficiency,
                );
              },
              child: const Text('切换效率档'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('切换效率档'));
      await tester.pumpAndSettle();

      expect(controller.core.value.superResolution, equals(SuperResolutionMode.efficiency));
      expect(find.text('性能提示'), findsNothing);

      await controller.dispose();
    });

    testWidgets('质量档在未禁用提示时弹出性能提示并可确认开启', (tester) async {
      final controller = ZakowayPlaybackController();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                SuperResolutionDialogHelper.handleModeSelection(
                  context: context,
                  controller: controller,
                  mode: SuperResolutionMode.quality,
                );
              },
              child: const Text('切换质量档'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('切换质量档'));
      await tester.pumpAndSettle();

      // 验证弹窗出现
      expect(find.text('性能提示'), findsOneWidget);
      expect(find.text('确认开启'), findsOneWidget);

      // 点击确认开启
      await tester.tap(find.text('确认开启'));
      await tester.pumpAndSettle();

      expect(controller.core.value.superResolution, equals(SuperResolutionMode.quality));

      await controller.dispose();
    });

    testWidgets('质量档提示中勾选下次不再询问后持久化关闭提示', (tester) async {
      final controller = ZakowayPlaybackController();
      expect(PlayerPreferencesService.instance.disableSuperResolutionWarning, isFalse);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                SuperResolutionDialogHelper.handleModeSelection(
                  context: context,
                  controller: controller,
                  mode: SuperResolutionMode.quality,
                );
              },
              child: const Text('切换质量档'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('切换质量档'));
      await tester.pumpAndSettle();

      // 勾选下次不再询问
      await tester.tap(find.text('下次不再询问'));
      await tester.pumpAndSettle();

      // 点击确认开启
      await tester.tap(find.text('确认开启'));
      await tester.pumpAndSettle();

      expect(PlayerPreferencesService.instance.disableSuperResolutionWarning, isTrue);

      await controller.dispose();
    });
  });

  group('SuperResolutionSettingsCard 设置卡片 Widget 测试', () {
    testWidgets('设置卡片正常渲染并支持切换提示开关与档位抽屉', (tester) async {
      await PlayerPreferencesService.instance.initialize();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SuperResolutionSettingsCard(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('画质与超分辨率 (Anime4K)'), findsOneWidget);
      expect(find.text('默认超分辨率模式'), findsOneWidget);
      expect(find.text('关闭性能提示'), findsOneWidget);

      // 点击打开模式选择抽屉
      await tester.tap(find.text('默认超分辨率模式'));
      await tester.pumpAndSettle();

      expect(find.text('选择默认超分辨率模式'), findsOneWidget);
      expect(find.text('效率档'), findsOneWidget);
      expect(find.text('质量档'), findsOneWidget);

      // 点击选择效率档
      await tester.tap(find.text('效率档'));
      await tester.pumpAndSettle();

      expect(
        PlayerPreferencesService.instance.superResolutionMode,
        equals(SuperResolutionMode.efficiency),
      );

      // 切换开关
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(
        PlayerPreferencesService.instance.disableSuperResolutionWarning,
        isTrue,
      );
    });
  });
}
