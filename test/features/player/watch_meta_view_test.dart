import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zakoway/core/services/app_preferences.dart';
import 'package:zakoway/features/player/widgets/watch_meta_view.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppPreferences.init();
  });

  testWidgets('WatchMetaView 默认无选中追番状态，且支持选中与反选', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: WatchMetaView(
              title: '测试番剧',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final options = ['想看', '在看', '看过', '搁置', '抛弃'];

    // 验证初始状态：5 个选项全部存在且默认无一选中
    for (final opt in options) {
      expect(find.text(opt), findsOneWidget);
      final textWidget = tester.widget<Text>(find.text(opt));
      expect(textWidget.style?.fontWeight, FontWeight.w500);
    }

    // 点击「在看」选中
    await tester.tap(find.text('在看'));
    await tester.pumpAndSettle();

    final watchingText = tester.widget<Text>(find.text('在看'));
    expect(watchingText.style?.fontWeight, FontWeight.w700);

    // 再次点击「在看」取消选中（反选）
    await tester.tap(find.text('在看'));
    await tester.pumpAndSettle();

    final deselectedText = tester.widget<Text>(find.text('在看'));
    expect(deselectedText.style?.fontWeight, FontWeight.w500);

    // 点击「想看」选中
    await tester.tap(find.text('想看'));
    await tester.pumpAndSettle();

    final planToWatchText = tester.widget<Text>(find.text('想看'));
    expect(planToWatchText.style?.fontWeight, FontWeight.w700);
  });
}
