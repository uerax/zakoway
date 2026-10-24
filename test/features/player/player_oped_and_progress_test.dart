import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/services/bangumi_oped_service.dart';
import 'package:zakoway/features/player/controller/playback_controller.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';
import 'package:zakoway/features/player/services/player_preferences_service.dart';
import 'package:zakoway/features/player/widgets/player_controls.dart';
import 'package:zakoway/features/player/widgets/player_progress_bar.dart';
import 'package:zakoway/features/player/widgets/player_skip_toast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BangumiOpedService 片头片尾数据解析测试', () {
    test('1. 正确解析标准文本格式与 -1 哨兵值', () {
      const rawText = '''
1;90;180;1350;1440
2;60;150;-1;-1
3;-1;-1;1200;1300
# 注释行或空行
malformed line
4;10;100;200;300
''';

      final service = BangumiOpedService.instance;
      final result = service.parseOpedData(rawText);

      expect(result.length, equals(4));

      // Ep 1: 有 OP 和 ED
      expect(result[1]?.hasOp, isTrue);
      expect(result[1]?.opStart, equals(90));
      expect(result[1]?.opEnd, equals(180));
      expect(result[1]?.hasEd, isTrue);
      expect(result[1]?.edStart, equals(1350));
      expect(result[1]?.edEnd, equals(1440));

      // Ep 2: 仅有 OP
      expect(result[2]?.hasOp, isTrue);
      expect(result[2]?.hasEd, isFalse);

      // Ep 3: 仅有 ED
      expect(result[3]?.hasOp, isFalse);
      expect(result[3]?.hasEd, isTrue);

      // Ep 4
      expect(result[4]?.hasOp, isTrue);
      expect(result[4]?.hasEd, isTrue);
    });

    test('2. 重复集数按第一条优先原则', () {
      const rawText = '''
1;90;180;1350;1440
1;100;190;1360;1450
''';

      final service = BangumiOpedService.instance;
      final result = service.parseOpedData(rawText);

      expect(result.length, equals(1));
      expect(result[1]?.opStart, equals(90));
    });

    test('3. getCachedOpedData 边界与无缓存保护', () {
      final service = BangumiOpedService.instance;
      expect(service.getCachedOpedData(-1), isNull);
      expect(service.getCachedOpedData(99999999), isNull);
    });
  });

  group('PlayerProgressBar 复合进度条渲染与交互测试', () {
    testWidgets('1. 进度条渲染包含弹幕波形、OP/ED 区间与缓冲条', (tester) async {
      Duration? started;
      Duration? ended;

      final danmakuItems = [
        DanmakuItem(text: '弹幕1', timeMs: 5000),
        DanmakuItem(text: '弹幕2', timeMs: 5200),
        DanmakuItem(text: '弹幕3', timeMs: 5400),
        DanmakuItem(text: '弹幕4', timeMs: 12000),
        DanmakuItem(text: '弹幕5', timeMs: 12500),
        DanmakuItem(text: '弹幕6', timeMs: 12800),
      ];

      const oped = EpisodeOpedSegment(
        episode: 1,
        opStart: 10,
        opEnd: 30,
        edStart: 100,
        edEnd: 120,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                child: PlayerProgressBar(
                  position: const Duration(seconds: 40),
                  duration: const Duration(seconds: 140),
                  buffer: const Duration(seconds: 80),
                  opedSegment: oped,
                  danmakuItems: danmakuItems,
                  onChangeStart: (d) => started = d,
                  onChanged: (_) {},
                  onChangeEnd: (d) => ended = d,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证存在进度条组件
      expect(find.byType(PlayerProgressBar), findsOneWidget);

      // 点击进度条中间位置 (约 50% 处，即 70 秒)
      await tester.tap(find.byType(PlayerProgressBar));
      await tester.pumpAndSettle();

      expect(started, isNotNull);
      expect(ended, isNotNull);
      expect(ended!.inSeconds, inInclusiveRange(65, 75));
    });

    testWidgets('2. 官方片长差距超过 10 秒时，进度条自动容灾熔断（不绘制 OP/ED 颜色条）', (tester) async {
      const oped = EpisodeOpedSegment(
        episode: 1,
        opStart: 10,
        opEnd: 30,
        edStart: 100,
        edEnd: 120,
      );

      // 当前时长 140s，官方片长 1440s，差距超过 10 秒
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                child: PlayerProgressBar(
                  position: const Duration(seconds: 40),
                  duration: const Duration(seconds: 140),
                  buffer: const Duration(seconds: 80),
                  opedSegment: oped,
                  officialDurationSeconds: 1440,
                  onChangeStart: (_) {},
                  onChanged: (_) {},
                  onChangeEnd: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证未绘制薄荷青色 OP 区间 (0xFF65D1C5)
      final opMarkerFinder = find.byWidgetPredicate(
        (w) => w is AnimatedContainer && w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color?.toARGB32() == const Color(0xFF65D1C5).withValues(alpha: 0.9).toARGB32(),
      );
      expect(opMarkerFinder, findsNothing);
    });

    testWidgets('3. 官方片长差距 <= 10 秒时，进度条正常自适应绘制 OP/ED 颜色条', (tester) async {
      const oped = EpisodeOpedSegment(
        episode: 1,
        opStart: 10,
        opEnd: 30,
        edStart: 100,
        edEnd: 120,
      );

      // 当前时长 140s，官方片长 142s，差距 2 秒 <= 10 秒
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 600,
                child: PlayerProgressBar(
                  position: const Duration(seconds: 40),
                  duration: const Duration(seconds: 140),
                  buffer: const Duration(seconds: 80),
                  opedSegment: oped,
                  officialDurationSeconds: 142,
                  onChangeStart: (_) {},
                  onChanged: (_) {},
                  onChangeEnd: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 验证正常绘制薄荷青色 OP 区间 (0xFF65D1C5)
      final opMarkerFinder = find.byWidgetPredicate(
        (w) => w is AnimatedContainer && w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color?.toARGB32() == const Color(0xFF65D1C5).withValues(alpha: 0.9).toARGB32(),
      );
      expect(opMarkerFinder, findsOneWidget);
    });
  });

  group('PlayerControls 自动跳过片头片尾与片长容灾测试', () {
    late ZakowayPlaybackController controller;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PlayerPreferencesService.instance.resetForTest();
      controller = ZakowayPlaybackController();
    });

    tearDown(() async {
      await controller.dispose();
      PlayerPreferencesService.instance.resetForTest();
    });

    test('1. 自动跳过片头片尾默认开启，且切换后自动持久化记住设置', () async {
      expect(PlayerPreferencesService.instance.autoSkipOped, isTrue);

      await PlayerPreferencesService.instance.saveAutoSkipOped(false);
      expect(PlayerPreferencesService.instance.autoSkipOped, isFalse);

      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool('zakoway_player_auto_skip_oped'), isFalse);

      await PlayerPreferencesService.instance.saveAutoSkipOped(true);
      expect(PlayerPreferencesService.instance.autoSkipOped, isTrue);
      expect(sp.getBool('zakoway_player_auto_skip_oped'), isTrue);
    });

    testWidgets('2. 开启自动跳过时，步入 OP 区间自动触发跳过并弹出撤销 Toast，点击撤销可回跳',
        (tester) async {
      const oped = EpisodeOpedSegment(
        episode: 1,
        opStart: 10,
        opEnd: 30,
        edStart: 100,
        edEnd: 120,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                title: '自动跳过测试',
                opedSegment: oped,
                autoSkipOped: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 步入 OP 区间（11 秒）
      controller.core.value = controller.core.value.copyWith(playing: true);
      controller.timeline.value = controller.timeline.value.copyWith(
        position: const Duration(seconds: 11),
        duration: const Duration(seconds: 140),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 验证已自动跳转至 30 秒（OP 结束处）
      expect(controller.timeline.value.position.inSeconds, equals(30));

      // 验证撤销浮标展示
      expect(find.byType(PlayerSkipToast), findsOneWidget);
      expect(find.text('撤销'), findsOneWidget);

      // 点击撤销回跳
      await tester.tap(find.text('撤销'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller.timeline.value.position.inSeconds, equals(10));
    });

    testWidgets('3. 关闭自动跳过时，步入 OP/ED 区间不自动跳过且不弹窗',
        (tester) async {
      const oped = EpisodeOpedSegment(
        episode: 1,
        opStart: 10,
        opEnd: 30,
        edStart: 100,
        edEnd: 120,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                title: '关闭跳过测试',
                opedSegment: oped,
                autoSkipOped: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 步入 OP 区间
      controller.core.value = controller.core.value.copyWith(playing: true);
      controller.timeline.value = controller.timeline.value.copyWith(
        position: const Duration(seconds: 15),
        duration: const Duration(seconds: 140),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 验证不跳转，不显示 Toast
      expect(controller.timeline.value.position.inSeconds, equals(15));
      expect(tester.widget<PlayerSkipToast>(find.byType(PlayerSkipToast)).visible, isFalse);
    });

    testWidgets('4. 容灾拦截：Bangumi 官方片长差距超过 10 秒时，熔断禁用（不触发跳过亦不弹窗）',
        (tester) async {
      const oped = EpisodeOpedSegment(
        episode: 1,
        opStart: 10,
        opEnd: 30,
        edStart: 100,
        edEnd: 120,
      );

      // 官方片长为 1440 秒（24分钟），当前视频为 PV 仅有 100 秒（差距 1340 秒 > 10 秒）
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                title: '容灾拦截测试',
                bangumiId: 1004,
                canonicalEpisode: 1,
                officialDurationSeconds: 1440,
                opedSegment: oped,
                autoSkipOped: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 步入 OP 区间（11 秒）
      controller.core.value = controller.core.value.copyWith(playing: true);
      controller.timeline.value = controller.timeline.value.copyWith(
        position: const Duration(seconds: 11),
        duration: const Duration(seconds: 100),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 验证被容灾拦截熔断：绝不跳转，绝不弹出任何浮标
      expect(controller.timeline.value.position.inSeconds, equals(11));
      expect(tester.widget<PlayerSkipToast>(find.byType(PlayerSkipToast)).visible, isFalse);
    });

    testWidgets('5. 容灾放行：Bangumi 官方片长差距在 10 秒以内时，正常放行启用',
        (tester) async {
      const oped = EpisodeOpedSegment(
        episode: 2,
        opStart: 10,
        opEnd: 30,
        edStart: 100,
        edEnd: 120,
      );

      // 官方片长为 1440 秒，当前视频为 1445 秒（差距 5 秒 <= 10 秒）
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: PlayerControls(
                controller: controller,
                title: '容灾放行测试',
                bangumiId: 1005,
                canonicalEpisode: 2,
                officialDurationSeconds: 1440,
                opedSegment: oped,
                autoSkipOped: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 步入 OP 区间（11 秒）
      controller.core.value = controller.core.value.copyWith(playing: true);
      controller.timeline.value = controller.timeline.value.copyWith(
        position: const Duration(seconds: 11),
        duration: const Duration(seconds: 1445),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 验证正常放行并跳转至 30 秒
      expect(controller.timeline.value.position.inSeconds, equals(30));
      expect(find.text('撤销'), findsOneWidget);
    });
  });
}
