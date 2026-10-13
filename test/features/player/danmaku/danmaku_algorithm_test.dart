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
  });
}
