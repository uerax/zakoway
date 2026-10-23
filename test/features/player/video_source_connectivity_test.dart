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

    // 可直连 (8个)
    expect(directSources, containsAll(['mifun', 'lzizy', 'animoe', 'tvtfun', 'anime1', 'cycani', 'girigiri', 'mxdm']));
    expect(directSources.length, 8);

    // 需代理 (6个)
    expect(proxySources, containsAll(['xifan-next', 'sorani', 'gugu', 'moonci', 'omofun', 'libvio']));
    expect(proxySources.length, 6);
  });

  testWidgets('验证 VideoSourceView 顶部胶囊切换与直连/海外过滤', (tester) async {
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

    // 1. 验证顶部胶囊显示 "全部 14"、"直连 8"、"海外 6"
    expect(find.textContaining('全部 14'), findsOneWidget);
    expect(find.textContaining('直连 8'), findsOneWidget);
    expect(find.textContaining('海外 6'), findsOneWidget);

    // 2. 初始为全部，既有直连源也有海外源
    expect(find.text('MiFun'), findsOneWidget);
    expect(find.text('稀饭Next'), findsOneWidget);
    // 验证无默认标签，分类胶囊已完整呈现
    expect(find.text('默认'), findsNothing);
    expect(find.textContaining('直连 8'), findsOneWidget);
    expect(find.textContaining('海外 6'), findsOneWidget);

    // 3. 点击切换到 "直连 8"
    await tester.tap(find.textContaining('直连 8'));
    await tester.pumpAndSettle();

    expect(find.text('MiFun'), findsOneWidget);
    expect(find.text('稀饭Next'), findsNothing);
    expect(find.text('Anime1'), findsOneWidget);

    // 4. 点击切换到 "海外 6"
    await tester.tap(find.textContaining('海外 6'));
    await tester.pumpAndSettle();

    expect(find.text('MiFun'), findsNothing);
    expect(find.text('稀饭Next'), findsOneWidget);
    expect(find.text('Anime1'), findsNothing);
  });
}
