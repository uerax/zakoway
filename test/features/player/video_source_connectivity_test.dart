import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zakoway/features/player/source/native_source_runtime.dart';
import 'package:zakoway/features/player/widgets/video_source_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('验证 14 个视频源适配器的 isDirect 属性定义与分类', () {
    final runtime = NativeSourceRuntime();
    final sources = runtime.availableSources;

    final directSources = sources.where((s) => s.isDirect).map((s) => s.id).toSet();
    final proxySources = sources.where((s) => !s.isDirect).map((s) => s.id).toSet();

    // 可直连 (6个)
    expect(directSources, containsAll(['mifun', 'sorani', 'gugu', 'lzizy', 'animoe', 'tvtfun']));
    expect(directSources.length, 6);

    // 需代理 (8个)
    expect(proxySources, containsAll(['xifan-next', 'anime1', 'cycani', 'girigiri', 'moonci', 'mxdm', 'omofun', 'libvio']));
    expect(proxySources.length, 8);
  });

  testWidgets('验证 VideoSourceView 顶部胶囊切换与直连/代理过滤', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final defaultItems = getDefaultSourceItems();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoSourceView(
            sources: defaultItems,
            selectedSourceId: 'mifun',
            onSourceSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. 验证顶部胶囊显示 "全部 14"、"直连 6"、"代理 8"
    expect(find.textContaining('全部 14'), findsOneWidget);
    expect(find.textContaining('直连 6'), findsOneWidget);
    expect(find.textContaining('代理 8'), findsOneWidget);

    // 2. 初始为全部，既有直连源也有代理源
    expect(find.text('MiFun'), findsOneWidget);
    expect(find.text('稀饭Next'), findsOneWidget);
    // 验证无默认标签，卡片徽标为纯文本 "直连" / "代理"
    expect(find.text('默认'), findsNothing);
    expect(find.text('直连'), findsWidgets);
    expect(find.text('代理'), findsWidgets);

    // 3. 点击切换到 "直连 6"
    await tester.tap(find.textContaining('直连 6'));
    await tester.pumpAndSettle();

    expect(find.text('MiFun'), findsOneWidget);
    expect(find.text('稀饭Next'), findsNothing);
    expect(find.text('Anime1'), findsNothing);

    // 4. 点击切换到 "代理 8"
    await tester.tap(find.textContaining('代理 8'));
    await tester.pumpAndSettle();

    expect(find.text('MiFun'), findsNothing);
    expect(find.text('稀饭Next'), findsOneWidget);
    expect(find.text('Anime1'), findsOneWidget);
  });
}
