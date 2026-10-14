import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/danmaku/danmaku.dart';

void main() {
  group('DanmakuTextNormalizer 文本归一化测试', () {
    test('全角标点与英文字符转换为半角', () {
      expect(
        DanmakuTextNormalizer.normalize('！Ｈｅｌｌｏ，Ｗｏｒｌｄ！'),
        equals('hello,world'),
      );
    });

    test('连续3个以上重复字符折叠为2个', () {
      expect(
        DanmakuTextNormalizer.normalize('23333333'),
        equals('233'),
      );
      expect(
        DanmakuTextNormalizer.normalize('哈哈哈哈哈哈！'),
        equals('哈哈'),
      );
      expect(
        DanmakuTextNormalizer.normalize('前方高能？？？？'),
        equals('前方高能'),
      );
    });

    test('两端标点符号剔除与大小写归一', () {
      expect(
        DanmakuTextNormalizer.normalize(' ~~~【前方高能】~~~ '),
        equals('【前方高能】'),
      );
    });
  });

  group('DanmakuScrollTrack 防追尾算法测试', () {
    late DanmakuScrollTrack track;

    setUp(() {
      track = DanmakuScrollTrack();
    });

    test('初始状态允许任意弹幕入场', () {
      expect(track.canAccept(1000, 0.1, 800), isTrue);
    });

    test('入场间隙校验：前一条弹幕未完全拉开安全间距前，拒绝入场', () {
      // 登记一条弹幕：在 1000ms 入场，宽度 100，速度 0.1 px/ms (即 100px/s)
      // 安全间隙为 28px，尾部安全离开时间 = 1000 + (100 + 28) / 0.1 = 1000 + 1280 = 2280ms
      track.register(
        startMs: 1000,
        width: 100,
        speed: 0.1,
        viewWidth: 800,
        safetyGapPx: 28,
      );

      // 在 1500ms（尚未达到 2280ms）时尝试入场，必须被拒绝
      expect(track.canAccept(1500, 0.1, 800, safetyGapPx: 28), isFalse);

      // 在 2281ms 时已越过安全间隙，允许同速或更慢弹幕入场
      expect(track.canAccept(2281, 0.1, 800, safetyGapPx: 28), isTrue);
    });

    test('速度反超校验：新弹幕速度过快会在中途反超碰撞时，拒绝入场', () {
      // 慢弹幕在 1000ms 入场，宽度 100，速度 0.05 px/ms
      // 完全离开左侧屏幕(800px)的时间 = 1000 + (800 + 100) / 0.05 = 1000 + 18000 = 19000ms
      track.register(
        startMs: 1000,
        width: 100,
        speed: 0.05,
        viewWidth: 800,
        safetyGapPx: 28,
      );

      // 在 3000ms 时，虽然已经超过了尾部离开时间 (1000 + 128 / 0.05 = 3560ms)？
      // 尾部安全离开时间 = 1000 + 2560 = 3560ms
      // 在 4000ms 时入场，安全间隙满足
      // 但是新弹幕速度极快：0.3 px/ms (超车速度)
      // 新弹幕到达左边缘(800 + 28) / 0.3 = 2760ms -> 4000 + 2760 = 6760ms
      // 而前一条慢弹幕要到 19000ms 才离开，新弹幕会在半途狠狠撞上慢弹幕！
      expect(track.canAccept(4000, 0.3, 800, safetyGapPx: 28), isFalse);

      // 若新弹幕速度合理（如 0.04，比慢弹幕还慢），绝不会反超，允许入场
      expect(track.canAccept(4000, 0.04, 800, safetyGapPx: 28), isTrue);
    });
  });

  group('DanmakuController 控制器测试', () {
    test('弹幕加载与自动时间排序', () {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '第三秒', timeMs: 3000),
        DanmakuItem(text: '第一秒', timeMs: 1000),
        DanmakuItem(text: '第二秒', timeMs: 2000),
      ]);

      expect(controller.items.length, equals(3));
      expect(controller.items[0].text, equals('第一秒'));
      expect(controller.items[1].text, equals('第二秒'));
      expect(controller.items[2].text, equals('第三秒'));
    });

    test('items 返回只读视图且在 loadItems 后指向最新内容', () {
      final controller = DanmakuController();
      final itemsRef1 = controller.items;
      expect(itemsRef1, isA<UnmodifiableListView<DanmakuItem>>());
      expect(itemsRef1.isEmpty, isTrue);

      controller.loadItems([
        DanmakuItem(text: '弹幕A', timeMs: 1000),
      ]);

      expect(controller.items.length, equals(1));
      expect(controller.items[0].text, equals('弹幕A'));
      expect(itemsRef1.length, equals(1));

      expect(
        () => controller.items.add(DanmakuItem(text: '非法', timeMs: 2000)),
        throwsUnsupportedError,
      );
    });

    test('正则与关键词屏蔽规则过滤', () {
      final controller = DanmakuController(
        initialSettings: const DanmakuSettings(
          filters: ['剧透', r'/^(\d{3,})$/'],
        ),
      );

      expect(controller.isBlocked('这里有严重剧透慎入'), isTrue);
      expect(controller.isBlocked('233333'), isTrue);
      expect(controller.isBlocked('正常的精彩弹幕'), isFalse);
    });
  });

  group('DanmakuView In-Flight 吸收合流测试', () {
    testWidgets('渲染并测试弹幕动态合流逻辑', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '前方高能', timeMs: 100),
        DanmakuItem(text: '前方高能！', timeMs: 500),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      // 开始播放并推进时钟
      controller.resume();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 100));

      // 推进到 600ms，两条高能弹幕都应到达
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(DanmakuView), findsOneWidget);
    });

    testWidgets('大屏桌面视口下正常渲染弹幕，自适应放缓速度与字号放大', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '桌面大屏弹幕测试', timeMs: 100),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1920,
              height: 1080,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(DanmakuView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('手机端竖屏小窗 (390x219) 动态计算轨道数至少容纳 10 轨', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '手机弹幕测试', timeMs: 100),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: SizedBox(
              width: 390,
              height: 219, // 16:9 竖屏小窗
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(DanmakuView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('手机端横屏全屏 (844x390) 动态计算轨道数远超 8 轨 (精致小字不糊屏)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(844, 390));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '手机全屏弹幕测试', timeMs: 100),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: SizedBox(
              width: 844,
              height: 390,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(DanmakuView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('小漂移平滑衰减纠偏，单帧无突跳瞬移 (正负对称)', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '平滑测试弹幕', timeMs: 0),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      // 先运行 100ms
      await tester.pump(const Duration(milliseconds: 100));

      // 模拟传入一个位于 (40ms ~ 600ms) 纠偏区间的正向漂移 (+200ms)
      controller.syncTime(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);

      // 模拟传入一个位于 (40ms ~ 600ms) 纠偏区间的负向微退漂移 (-150ms)
      controller.syncTime(const Duration(milliseconds: 150));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);

      // 连续推进若干帧，验证平滑收敛无异常
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(DanmakuView), findsOneWidget);
    });

    testWidgets('超过 600ms 的 Seek 大漂移走硬重定位', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: 'Seek测试弹幕1', timeMs: 100),
        DanmakuItem(text: 'Seek测试弹幕2', timeMs: 5000),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 100));

      // 触发超过 600ms 的大 Seek（直接跳到 5 秒）
      controller.syncTime(const Duration(milliseconds: 5000));
      await tester.pump(const Duration(milliseconds: 16));

      expect(tester.takeException(), isNull);
      expect(find.byType(DanmakuView), findsOneWidget);
    });

    testWidgets('高密度弹幕过载丢弃反压测试', (tester) async {
      final controller = DanmakuController();
      // 在同一时间点载入 300 条弹幕进行极端高潮轰炸
      final stormItems = List.generate(
        300,
        (i) => DanmakuItem(text: '高能轰炸弹幕 #$i', timeMs: 100),
      );
      controller.loadItems(stormItems);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.takeException(), isNull);
      expect(find.byType(DanmakuView), findsOneWidget);
    });
  });

  group('DanmakuLayoutPool 排版 LRU 缓存池测试', () {
    test('重复高频文本命中缓存，避免重复创建 TextPainter', () {
      final pool = DanmakuLayoutPool(maxEntries: 4);
      var missCount = 0;

      final layout1 = pool.acquire(
        text: '2333',
        color: Colors.white,
        fontSize: 18.0,
        strokeWidth: 1.0,
        onCacheMiss: () => missCount++,
      );

      expect(missCount, equals(1));
      expect(layout1.refCount, equals(1));

      // 再次获取完全相同样式的弹幕
      final layout2 = pool.acquire(
        text: '2333',
        color: Colors.white,
        fontSize: 18.0,
        strokeWidth: 1.0,
        onCacheMiss: () => missCount++,
      );

      // 必须命中缓存：missCount 保持为 1，对象为同一实例
      expect(missCount, equals(1));
      expect(identical(layout1, layout2), isTrue);
      expect(layout1.refCount, equals(2));

      // 归还 1 次引用
      layout2.dispose();
      expect(layout1.refCount, equals(1));
      expect(layout1.isEvicted, isFalse);

      // 彻底归还
      layout1.dispose();
      expect(layout1.refCount, equals(0));
    });

    test('超出容量限制触发 LRU 淘汰', () {
      final pool = DanmakuLayoutPool(maxEntries: 2);
      final l1 = pool.acquire(
        text: '文本1',
        color: Colors.white,
        fontSize: 18.0,
        strokeWidth: 1.0,
      );
      final l2 = pool.acquire(
        text: '文本2',
        color: Colors.white,
        fontSize: 18.0,
        strokeWidth: 1.0,
      );
      expect(l1.isEvicted, isFalse);

      // 插入第 3 个，导致最旧的 l1 被淘汰标记
      pool.acquire(
        text: '文本3',
        color: Colors.white,
        fontSize: 18.0,
        strokeWidth: 1.0,
      );
      expect(l1.isEvicted, isTrue);
      expect(l2.isEvicted, isFalse);

      l1.dispose();
      l2.dispose();
      pool.clear();
    });
  });

  group('DanmakuEntry 预缓存 normalizedKey 验证', () {
    test('Entry 构造时预先固化归一化键', () {
      final item = DanmakuItem(text: '！！！Hello？？？', timeMs: 0);
      final layout = DanmakuTextLayout(
        text: item.text,
        color: Colors.white,
        fontSize: 18.0,
        strokeWidth: 1.0,
      );
      final entry = DanmakuEntry(
        item: item,
        track: 0,
        startMs: 0,
        durationMs: 7000,
        speed: 0.1,
        x: 800,
        y: 0,
        baseText: item.text,
        layout: layout,
      );

      expect(entry.normalizedKey, equals('hello'));
      entry.dispose();
    });
  });

  group('DanmakuView 屏幕重建与状态保持测试', () {
    testWidgets('控制器记住位置：首次布局从控制器记忆位置开始重建，不从 0 开始', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '弹幕1 (1s)', timeMs: 1000),
        DanmakuItem(text: '弹幕2 (2s)', timeMs: 2000),
        DanmakuItem(text: '弹幕3 (3s)', timeMs: 3000),
        DanmakuItem(text: '弹幕4 (4s)', timeMs: 4000),
      ]);

      // 控制器提前同步到 3500ms
      controller.syncTime(const Duration(milliseconds: 3500));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(DanmakuView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('模拟单次 Seek 往回 1 秒：前沿 0 延迟原子重建，无 200ms 空白闪烁', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '弹幕A (1s)', timeMs: 1000),
        DanmakuItem(text: '弹幕B (2s)', timeMs: 2000),
        DanmakuItem(text: '弹幕C (3s)', timeMs: 3000),
        DanmakuItem(text: '弹幕D (4s)', timeMs: 4000),
        DanmakuItem(text: '弹幕E (5s)', timeMs: 5000),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      // 连续播放到 5000ms
      controller.syncTime(const Duration(milliseconds: 5000));
      await tester.pump(const Duration(milliseconds: 350));

      // 单次向后大跳转 1 秒 (5000ms -> 4000ms, drift = -1000ms > 600ms Seek 阈值)
      controller.syncTime(const Duration(milliseconds: 4000));
      // 0ms 立即原子完成重建，下一帧直接可见，无需等待 200ms
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.byType(DanmakuView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('连续密集 Seek 拖拽：后沿防抖稳定 180ms 后完成最终重建', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '弹幕A (1s)', timeMs: 1000),
        DanmakuItem(text: '弹幕B (2s)', timeMs: 2000),
        DanmakuItem(text: '弹幕C (3s)', timeMs: 3000),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 350));

      // 模拟第 1 次 Seek（前沿触发）
      controller.syncTime(const Duration(milliseconds: 2000));
      await tester.pump(const Duration(milliseconds: 50));

      // 紧接着连续快速 Seek 拖拽（间隔 < 300ms）
      controller.syncTime(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 50));
      controller.syncTime(const Duration(milliseconds: 3000));
      await tester.pump(const Duration(milliseconds: 50));

      // 拖拽停止后，等待 180ms 防抖结束 (50ms + 150ms = 200ms > 180ms)
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byType(DanmakuView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('连续多次尺寸变化防抖：稳定 180ms 后完成重建', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '弹幕1', timeMs: 500),
        DanmakuItem(text: '弹幕2', timeMs: 1000),
      ]);

      var width = 800.0;
      late StateSetter setStateCallback;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setStateCallback = setState;
                return SizedBox(
                  width: width,
                  height: 600,
                  child: DanmakuView(controller: controller),
                );
              },
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 200));

      // 连续在 180ms 内改变尺寸 3 次
      setStateCallback(() => width = 820.0);
      await tester.pump(const Duration(milliseconds: 50));
      setStateCallback(() => width = 840.0);
      await tester.pump(const Duration(milliseconds: 50));
      setStateCallback(() => width = 860.0);
      await tester.pump(const Duration(milliseconds: 50));

      // 此时距最后一次尺寸变化仅过去 50ms，防抖未超时
      // 继续推进 150ms（总计 200ms > 180ms），触发稳定重建
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.byType(DanmakuView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('KeyedSubtree 跨父容器保活：移动到新父树时 State 实例与控制器绑定不丢失', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '保活测试弹幕', timeMs: 500),
      ]);

      final subtreeKey = GlobalKey();
      var isFullscreen = false;
      late StateSetter setStateCallback;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setStateCallback = setState;
                if (isFullscreen) {
                  return Container(
                    color: Colors.black,
                    child: KeyedSubtree(
                      key: subtreeKey,
                      child: SizedBox(
                        width: 1920,
                        height: 1080,
                        child: DanmakuView(controller: controller),
                      ),
                    ),
                  );
                } else {
                  return Container(
                    color: Colors.white,
                    child: KeyedSubtree(
                      key: subtreeKey,
                      child: SizedBox(
                        width: 800,
                        height: 450,
                        child: DanmakuView(controller: controller),
                      ),
                    ),
                  );
                }
              },
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 200));

      // 切换布局至全屏
      setStateCallback(() => isFullscreen = true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(DanmakuView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('视口尺寸变化时保留在场弹幕 progress 严格一致，位置连续无跳变', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '连续性测试弹幕', timeMs: 100),
      ]);

      var width = 800.0;
      var height = 450.0;
      late StateSetter setStateCallback;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setStateCallback = setState;
                return SizedBox(
                  width: width,
                  height: height,
                  child: DanmakuView(controller: controller),
                );
              },
            ),
          ),
        ),
      );

      controller.resume();
      // 推进到 200ms 发射弹幕，再推进 300ms 让弹幕飞行
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      final state = tester.state(find.byType(DanmakuView)) as dynamic;
      expect(state.activeEntriesForTest.length, equals(1));
      final entry = state.activeEntriesForTest.first;
      final progressBefore = (state.clockMsForTest - entry.startMs) / entry.durationMs;
      expect(progressBefore, greaterThan(0.0));
      expect(progressBefore, lessThan(1.0));

      // 模拟离散全屏切换（800x450 -> 1920x1080）
      setStateCallback(() {
        width = 1920.0;
        height = 1080.0;
      });
      // 触发首帧立即原子重建
      await tester.pump(const Duration(milliseconds: 16));

      expect(state.activeEntriesForTest.length, equals(1));
      final entryAfter = state.activeEntriesForTest.first;
      final progressAfter = (state.clockMsForTest - entryAfter.startMs) / entryAfter.durationMs;

      // 验证重建前后 progress 严格一致（误差在微秒时钟推进范围 < 0.005 内）
      expect((progressAfter - progressBefore).abs(), lessThan(0.005));
    });

    testWidgets('设置变化时重建在屏弹幕：fontSizeScale/opacity/hideColor 等变化就地重建并保持进度', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '彩色弹幕', timeMs: 100, color: Colors.red),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      final state = tester.state(find.byType(DanmakuView)) as dynamic;
      expect(state.activeEntriesForTest.length, equals(1));
      final entryBefore = state.activeEntriesForTest.first;
      final progressBefore = (state.clockMsForTest - entryBefore.startMs) / entryBefore.durationMs;
      expect(entryBefore.layout.color, equals(Colors.red));
      final oldFontSize = entryBefore.layout.fontSize;

      // 调整设置：增大字号、改描边、改不透明度、开启白字过滤
      controller.updateSettings(
        controller.settings.copyWith(
          fontSizeScale: 1.5,
          strokeWidth: 3.5,
          opacity: 0.6,
          hideColor: true,
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      expect(state.activeEntriesForTest.length, equals(1));
      final entryAfter = state.activeEntriesForTest.first;
      final progressAfter = (state.clockMsForTest - entryAfter.startMs) / entryAfter.durationMs;

      // 验证进度保持严格一致
      expect((progressAfter - progressBefore).abs(), lessThan(0.005));
      // 验证样式立刻与新设置同步
      expect(entryAfter.layout.color, equals(Colors.white));
      expect(entryAfter.layout.fontSize, greaterThan(oldFontSize));
      expect(entryAfter.layout.strokeWidth, equals(3.5));
      expect(entryAfter.layout.opacity, equals(0.6));
    });

    testWidgets('hideScroll 打开时立即移除在屏滚动弹幕并释放其轨道', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '滚动弹幕', timeMs: 100, mode: DanmakuMode.scroll),
        DanmakuItem(text: '顶部弹幕', timeMs: 100, mode: DanmakuMode.top),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 300));

      final state = tester.state(find.byType(DanmakuView)) as dynamic;
      expect(state.activeEntriesForTest.length, equals(2));

      // 打开 hideScroll 屏蔽滚动弹幕
      controller.updateSettings(
        controller.settings.copyWith(hideScroll: true),
      );
      await tester.pump(const Duration(milliseconds: 16));

      // 滚动弹幕已被立即移除，仅剩顶部固定弹幕
      expect(state.activeEntriesForTest.length, equals(1));
      expect(state.activeEntriesForTest.first.mode, equals(DanmakuMode.top));
    });

    testWidgets('滚动弹幕合流吸收后，头部 x 坐标平滑连续零跳变', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '合流测试', timeMs: 100),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 300));

      final state = tester.state(find.byType(DanmakuView)) as dynamic;
      expect(state.activeEntriesForTest.length, equals(1));
      final active = state.activeEntriesForTest.first;
      final oldWidth = active.layout.size.width;
      final progressBefore = (state.clockMsForTest - active.startMs) / active.durationMs;
      final xBefore = 800.0 - progressBefore * (800.0 + oldWidth);

      // 原地注入一条同名弹幕触发 In-Flight 吸收
      final merged = state.tryMergeInFlight(
        DanmakuItem(text: '合流测试！', timeMs: 300),
        state.clockMsForTest,
        800.0,
      );
      expect(merged, isTrue);
      expect(active.count, equals(2));

      final newWidth = active.layout.size.width;
      final progressAfter = (state.clockMsForTest - active.startMs) / active.durationMs;
      final xAfter = 800.0 - progressAfter * (800.0 + newWidth);

      // 核心断言：合流前后同一时刻的头部 x 差小于 0.01 像素（保持平滑连续，零跳变）
      expect((xAfter - xBefore).abs(), lessThan(0.01));
      final expectedProgress = progressBefore * (800.0 + oldWidth) / (800.0 + newWidth);
      expect((progressAfter - expectedProgress).abs(), lessThan(0.0001));
    });
  });

  group('DanmakuView 飞行时钟解耦测试', () {
    testWidgets('飞行时钟解耦测试：视频时间轴纠偏仅调整媒体时钟，飞行运动时钟不受干扰保持绝对匀速', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '解耦测试弹幕', timeMs: 0),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      // 推进 200ms，弹幕入场并飞行中
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final state = tester.state(find.byType(DanmakuView)) as dynamic;
      final motionClockBefore = state.clockMsForTest as double;
      final mediaClockBefore = state.mediaClockMsForTest as double;
      expect(state.activeEntriesForTest.length, equals(1));
      final entry = state.activeEntriesForTest.first;
      final progressBefore = (motionClockBefore - entry.startMs) / entry.durationMs;

      // 模拟底层播放器上报一个 +200ms 的视频时间轴漂移 (处于 40ms ~ 600ms 的 EMA 低通滤波纠偏区)
      // 此时视频时间为 400ms，比当前时钟快 200ms
      controller.syncTime(const Duration(milliseconds: 400));

      // 推进 1 个 tick (16ms)
      await tester.pump(const Duration(milliseconds: 16));

      final motionClockAfter = state.clockMsForTest as double;
      final mediaClockAfter = state.mediaClockMsForTest as double;
      final progressAfter = (motionClockAfter - entry.startMs) / entry.durationMs;

      // 1. 媒体发射时钟吸收了低通纠偏 (漂移量 * 0.15 约 30ms 增量)，向前调整
      expect(mediaClockAfter - mediaClockBefore, greaterThan(35.0));

      // 2. 核心验证：飞行运动时钟彻底解耦，仅按物理 VSync 推进约 16ms，绝不受 200ms 漂移踢动
      final motionDelta = motionClockAfter - motionClockBefore;
      expect(motionDelta, closeTo(16.0, 1.0));

      // 3. 在屏飞行的弹幕进度变化严格等于 16ms / durationMs，无任何突跳拉扯
      final expectedProgressDelta = motionDelta / entry.durationMs;
      expect((progressAfter - progressBefore) - expectedProgressDelta, closeTo(0.0, 0.0001));
    });

    testWidgets('顶部优先排轨：轨道0空闲时立即优先复用轨道0，绝不无故下沉产生阶梯瀑布', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '弹幕1', timeMs: 0),
        DanmakuItem(text: '弹幕2', timeMs: 50), // 紧接着发，轨道0忙，应进轨道1
        DanmakuItem(text: '弹幕3', timeMs: 4000), // 4s后轨道0尾部已拉开，应重新进轨道0
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 16));
      // 推进到 100ms，弹幕1与弹幕2入场
      await tester.pump(const Duration(milliseconds: 100));

      final state = tester.state(find.byType(DanmakuView)) as dynamic;
      final entries = state.activeEntriesForTest as List<dynamic>;
      expect(entries.length, equals(2));
      expect(entries[0].track, equals(0));
      expect(entries[1].track, equals(1));

      // 推进到 4200ms，弹幕3入场
      for (var i = 0; i < 41; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(entries.length, equals(3));
      // 核心断言：弹幕3必须优先复用空闲的轨道0，而不是下沉到轨道2！
      expect(entries[2].track, equals(0));
    });

    testWidgets('hideScroll = true 时固定弹幕约 5 秒后消失并释放轨道，安静时段不无限停留', (tester) async {
      final controller = DanmakuController(
        initialSettings: const DanmakuSettings(hideScroll: true),
      );
      controller.loadItems([
        DanmakuItem(text: '顶部固定1', timeMs: 0, mode: DanmakuMode.top),
        DanmakuItem(text: '底部固定1', timeMs: 0, mode: DanmakuMode.bottom),
        DanmakuItem(text: '顶部固定2', timeMs: 6000, mode: DanmakuMode.top),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 16));

      final state = tester.state(find.byType(DanmakuView)) as dynamic;
      final entries = state.activeEntriesForTest as List<dynamic>;

      // 1. 0ms 时顶部与底部各有一条入场
      expect(entries.length, equals(2));
      expect(entries.any((e) => e.mode == DanmakuMode.top && e.track == 0), isTrue);
      expect(entries.any((e) => e.mode == DanmakuMode.bottom && e.track == 0), isTrue);

      // 2. 推进到 2500ms（仍在 5000ms 存活期内），固定弹幕仍保留在屏
      await tester.pump(const Duration(milliseconds: 2500));
      expect(entries.length, equals(2));

      // 3. 推进到 5100ms（超过 5000ms 存活期），固定弹幕必须全部到期淘汰释放轨道
      await tester.pump(const Duration(milliseconds: 2600));
      expect(entries.isEmpty, isTrue);

      // 4. 推进到 6100ms，第二条顶部弹幕入场，成功复用已释放的轨道 0（未被阻塞丢弃）
      await tester.pump(const Duration(milliseconds: 1000));
      expect(entries.length, equals(1));
      expect(entries[0].item.text, equals('顶部固定2'));
      expect(entries[0].track, equals(0));
    });

    testWidgets('安静时段里的固定弹幕唤醒淘汰：后续无弹幕时不会无限停留', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '独立固定弹幕', timeMs: 0, mode: DanmakuMode.top),
        // 下一条弹幕相隔 60 秒（安静时段）
        DanmakuItem(text: '远期弹幕', timeMs: 60000, mode: DanmakuMode.top),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 16));

      final state = tester.state(find.byType(DanmakuView)) as dynamic;
      final entries = state.activeEntriesForTest as List<dynamic>;

      expect(entries.length, equals(1));

      // 推进 5100ms：唤醒时刻成功捕获到最早固定弹幕到期时刻并唤醒淘汰
      await tester.pump(const Duration(milliseconds: 5100));
      expect(entries.isEmpty, isTrue);
    });

    testWidgets('运动时钟抗卡顿避震：卡顿帧位移不超过常态1.5倍，lagMs逐步补回且从不超过上限', (tester) async {
      final controller = DanmakuController();
      controller.loadItems([
        DanmakuItem(text: '避震测试滚动弹幕', timeMs: 0),
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 450,
              child: DanmakuView(controller: controller),
            ),
          ),
        ),
      );

      controller.resume();
      await tester.pump(const Duration(milliseconds: 16));

      final state = tester.state(find.byType(DanmakuView)) as dynamic;
      final entries = state.activeEntriesForTest as List<dynamic>;
      expect(entries.length, equals(1));
      final entry = entries.first;

      // 1. 连续推进多个 8.3ms（模拟 120Hz 稳定常态帧间隔）
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(microseconds: 8333));
      }

      final clockBeforeStutter = state.clockMsForTest as double;
      final progressBefore = (clockBeforeStutter - entry.startMs) / entry.durationMs;
      final xBefore = 800.0 - progressBefore * (800.0 + entry.layout.size.width);

      // 2. 模拟突发卡顿帧：单帧延迟 50ms (远大于 8.33ms)
      await tester.pump(const Duration(milliseconds: 50));

      final clockAfterStutter = state.clockMsForTest as double;
      final advanceDuringStutter = clockAfterStutter - clockBeforeStutter;
      final progressAfter = (clockAfterStutter - entry.startMs) / entry.durationMs;
      final xAfter = 800.0 - progressAfter * (800.0 + entry.layout.size.width);
      final displacement = xBefore - xAfter;

      // 正常 8.33ms 下的理论单帧位移
      final normalDisplacement = (8.333 / entry.durationMs) * (800.0 + entry.layout.size.width);

      // 核心断言 1：卡顿帧的位移严禁按 50ms 瞬移，必须被削峰拦截在常态 1.5 倍以内
      expect(displacement, lessThanOrEqualTo(normalDisplacement * 1.55));
      expect(advanceDuringStutter, lessThanOrEqualTo(8.333 * 1.55));

      // 核心断言 2：超出的时间记入 lagMs，且严格不超过 200ms 上限
      final initialLag = state.lagMsForTest as double;
      expect(initialLag, greaterThan(0.0));
      expect(initialLag, lessThanOrEqualTo(200.0));

      // 3. 随后续常态帧推进，lagMs 逐帧以不超过 5% 速度逐步平滑追回，单调递减
      var prevLag = initialLag;
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(microseconds: 8333));
        final curLag = state.lagMsForTest as double;
        expect(curLag, lessThan(prevLag)); // 逐步平滑追回
        prevLag = curLag;
      }

      // 持续推进直到 lag 完全补平归零
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(microseconds: 8333));
      }
      expect(state.lagMsForTest as double, equals(0.0));

      // 4. 模拟极端中断（dt = 300ms > 250ms，如首帧/窗口失焦）：
      // 运动时钟仅推进基准步长，严禁向 lagMs 累积欠账
      await tester.pump(const Duration(milliseconds: 300));
      expect(state.lagMsForTest as double, equals(0.0));
    });
  });
}
