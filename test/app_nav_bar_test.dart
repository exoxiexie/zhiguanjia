/// 自绘底栏项测试（AppNavDestination，v1.0.32）
///
/// 锁住本次改造的三件事：
/// 1. **没有选中"药丸"** —— 官方 `NavigationDestination` 会在选中项背后画一个
///    `64×32` 的圆角底（`NavigationIndicator`），自绘后彻底不存在；
/// 2. **图标与文字间距 = [kNavIconLabelGap]（4dp）** —— 官方是 8dp，
///    由"图标盒内空隙 4 + 文字写死上边距 4"拼成，只能自绘才能改；
/// 3. **选中态图标换成实心深色** —— 从 outline 图标切到 filled 图标。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhiguanjia/features/common/app_nav_bar.dart';
import 'package:zhiguanjia/features/shell/shell_page.dart';

/// 渲染一整条底栏（与真机同款五项），返回后可直接取各格几何
Future<void> _pumpBar(WidgetTester tester, {int selectedIndex = 0}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          destinations: buildAppNavDestinations(
            items: kShellNavItems,
            selectedIndex: selectedIndex,
            onSelected: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('底栏项：无药丸', () {
    testWidgets('选中项背后不再有 NavigationIndicator（药丸）', (tester) async {
      await _pumpBar(tester);

      expect(find.byType(NavigationIndicator), findsNothing);
    });

    testWidgets('底栏里没有任何官方 NavigationDestination', (tester) async {
      await _pumpBar(tester);

      expect(find.byType(NavigationDestination), findsNothing);
      expect(find.byType(AppNavDestination), findsNWidgets(5));
    });
  });

  group('底栏项：图标与文字间距', () {
    testWidgets('间距为 kNavIconLabelGap（4dp），比官方的 8dp 更紧', (tester) async {
      await _pumpBar(tester);

      // 取「对话」这一格的图标与文字
      final iconRect = tester.getRect(find.byIcon(Icons.chat_bubble));
      final labelRect = tester.getRect(find.text('对话'));

      final gap = labelRect.top - iconRect.bottom;
      expect(gap, closeTo(kNavIconLabelGap, 0.01));
      expect(kNavIconLabelGap, lessThan(8.0), reason: '应比官方的 8dp 更紧');
    });

    testWidgets('未选中项同样按该间距排布', (tester) async {
      await _pumpBar(tester);

      final iconRect = tester.getRect(find.byIcon(Icons.dataset_outlined));
      final labelRect = tester.getRect(find.text('数据'));

      expect(labelRect.top - iconRect.bottom, closeTo(kNavIconLabelGap, 0.01));
    });
  });

  group('底栏项：选中态', () {
    testWidgets('选中项用实心图标，未选中项用线性图标', (tester) async {
      await _pumpBar(tester);

      // 选中「对话」→ 实心 chat_bubble，线性版本不应出现
      expect(find.byIcon(Icons.chat_bubble), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble_outline), findsNothing);

      // 未选中的「数据」→ 仍是线性
      expect(find.byIcon(Icons.dataset_outlined), findsOneWidget);
      expect(find.byIcon(Icons.dataset), findsNothing);
    });

    testWidgets('选中项图标为近黑实心色', (tester) async {
      await _pumpBar(tester);

      final icon = tester.widget<Icon>(find.byIcon(Icons.chat_bubble));
      expect(icon.color, kNavSelectedIconColor);
    });

    testWidgets('切到另一格后，实心与线性随之互换', (tester) async {
      await _pumpBar(tester, selectedIndex: 2); // 懂你

      expect(find.byIcon(Icons.lightbulb), findsOneWidget);
      expect(find.byIcon(Icons.lightbulb_outline), findsNothing);
      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(find.byIcon(Icons.chat_bubble), findsNothing);
    });
  });

  group('底栏项：点击', () {
    testWidgets('点击某一格回调其 index', (tester) async {
      final tapped = <int>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: NavigationBar(
              selectedIndex: 0,
              destinations: buildAppNavDestinations(
                items: kShellNavItems,
                selectedIndex: 0,
                onSelected: tapped.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.explore_outlined)); // 发现（index 3）
      await tester.pumpAndSettle();

      expect(tapped, [3]);
    });
  });

  group('底栏项：定义与几何自检', () {
    test('五项标签与顺序固定为 对话 / 数据 / 懂你 / 发现 / 我的', () {
      expect(kShellNavItems.map((e) => e.label).toList(),
          ['对话', '数据', '懂你', '发现', '我的']);
    });

    test('每项都配了实心版选中图标，且与线性版不同', () {
      for (final item in kShellNavItems) {
        expect(item.selectedIcon, isNot(item.icon),
            reason: '${item.label} 的选中图标应为另一枚（实心）');
      }
    });
  });
}
