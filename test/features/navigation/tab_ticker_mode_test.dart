import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('TickerMode correctly isolates animations in IndexedStack tabs', (tester) async {
    int currentIndex = 0;
    late StateSetter setStateCallback;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setStateCallback = setState;
            return Scaffold(
              body: IndexedStack(
                index: currentIndex,
                children: [
                  TickerMode(
                    enabled: currentIndex == 0,
                    child: const _TestTickerWidget(name: 'Tab0'),
                  ),
                  TickerMode(
                    enabled: currentIndex == 1,
                    child: const _TestTickerWidget(name: 'Tab1'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    await tester.pump();

    // 初始状态：Tab 0 激活，Tab 1 挂起
    final tab0Finder = find.byKey(const ValueKey('Tab0'), skipOffstage: false);
    final tab1Finder = find.byKey(const ValueKey('Tab1'), skipOffstage: false);

    expect(TickerMode.valuesOf(tester.element(tab0Finder)).enabled, isTrue);
    expect(TickerMode.valuesOf(tester.element(tab1Finder)).enabled, isFalse);

    // 切换至 Tab 1：Tab 0 挂起，Tab 1 激活
    setStateCallback(() {
      currentIndex = 1;
    });
    await tester.pump();

    expect(TickerMode.valuesOf(tester.element(tab0Finder)).enabled, isFalse);
    expect(TickerMode.valuesOf(tester.element(tab1Finder)).enabled, isTrue);
  });
}

class _TestTickerWidget extends StatelessWidget {
  final String name;
  const _TestTickerWidget({required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey(name),
      child: Text(name),
    );
  }
}
