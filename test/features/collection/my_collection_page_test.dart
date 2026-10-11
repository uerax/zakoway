import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/collection/models/anime_collection_item.dart';
import 'package:zakoway/core/collection/services/anime_collection_service.dart';
import 'package:zakoway/core/models/bangumi/bangumi_collection.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/features/collection/pages/my_collection_page.dart';
import 'package:zakoway/features/common/widgets/anime_card.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.init();
    AnimeCollectionService.instance.allItems.clear();
  });

  testWidgets('MyCollectionPage renders 5 tabs and empty states',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MyCollectionPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('我的追番'), findsOneWidget);
    expect(find.text('同步数据'), findsOneWidget);

    // 默认 5 个分类 Tab
    expect(find.text('在看'), findsOneWidget);
    expect(find.text('想看'), findsOneWidget);
    expect(find.text('看过'), findsOneWidget);
    expect(find.text('搁置'), findsOneWidget);
    expect(find.text('抛弃'), findsOneWidget);

    // 默认激活「在看」分类的空态展示
    expect(find.text('暂无【在看】分类的番剧'), findsOneWidget);
  });

  testWidgets('MyCollectionPage displays populated items and updates counts',
      (tester) async {
    final service = AnimeCollectionService.instance;
    await service.setItem(
      AnimeCollectionItem(
        subjectId: 777,
        type: CollectType.watching,
        title: '葬送的芙莉莲',
        coverUrl: 'https://example.com/frieren.jpg',
        score: 8.9,
        updatedAt: DateTime.now(),
      ),
    );
    await service.setItem(
      AnimeCollectionItem(
        subjectId: 888,
        type: CollectType.planToWatch,
        title: '败犬女主太多了！',
        coverUrl: 'https://example.com/makeine.jpg',
        score: 8.4,
        updatedAt: DateTime.now(),
      ),
    );

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MyCollectionPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 验证 Tab 徽章数字准确响应 (在看与想看各存在 1 个 '1' 徽章)
    expect(find.text('在看'), findsOneWidget);
    expect(find.text('想看'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));

    // 当前在看分类中渲染了番剧卡片
    expect(find.byType(AnimeCard), findsOneWidget);
    expect(find.text('葬送的芙莉莲'), findsWidgets);

    // 切换到「想看」Tab
    await tester.tap(find.text('想看'));
    await tester.pumpAndSettle();

    expect(find.text('败犬女主太多了！'), findsWidgets);
  });
}
