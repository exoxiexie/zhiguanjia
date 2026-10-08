/// 底栏高度测试（v1.0.31：80dp → 56dp）
///
/// 为什么锁定这个：
/// Material 3 的 `NavigationBar` 默认内容高 **80dp**，明显高于业界主流
/// （M2 = 56dp、iOS UITabBar = 49pt、国内 App 普遍 49~56dp），观感偏"高"。
/// 本项目统一压到 [kNavigationBarHeight] = 56dp。
///
/// 这里用**同一份** [buildAppTheme] 做断言（不是测试里另写一套），
/// 因此：谁再把主题里的高度改回去 / 加回来，本用例立刻失败。
/// 同时防住"压矮后内部溢出"——内容高度 56dp 时若挤出 RenderFlex 溢出，
/// 测试会直接报错。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhiguanjia/features/common/app_nav_bar.dart';
import 'package:zhiguanjia/features/shell/shell_page.dart';
import 'package:zhiguanjia/main.dart';

/// 构造底栏（与 ShellPage 同款五项），可模拟底部系统安全区
Future<void> _pumpNavBar(
  WidgetTester tester, {
  double bottomInset = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: EdgeInsets.only(bottom: bottomInset),
            viewPadding: EdgeInsets.only(bottom: bottomInset),
          ),
          child: Scaffold(
            bottomNavigationBar: NavigationBar(
              selectedIndex: 0,
              // 用与真机一致的自绘项（v1.0.32 起）
              destinations: buildAppNavDestinations(
                items: kShellNavItems,
                selectedIndex: 0,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

double _navHeight(WidgetTester tester) =>
    tester.getSize(find.byType(NavigationBar)).height;

void main() {
  group('底栏高度', () {
    test('事实来源取 56dp（对齐业界主流，且不低于 48dp 最小触摸高度）', () {
      expect(kNavigationBarHeight, 56);
      expect(kNavigationBarHeight, greaterThanOrEqualTo(48));
    });

    testWidgets('内容高度为 56dp，不再是 M3 默认的 80dp', (tester) async {
      await _pumpNavBar(tester);

      expect(_navHeight(tester), kNavigationBarHeight);
      expect(_navHeight(tester), isNot(80.0));
    });

    testWidgets('真机总高 = 内容 56 + 底部安全区', (tester) async {
      await _pumpNavBar(tester, bottomInset: 34);
      expect(_navHeight(tester), kNavigationBarHeight + 34);

      await _pumpNavBar(tester, bottomInset: 48);
      expect(_navHeight(tester), kNavigationBarHeight + 48);
    });

    testWidgets('压矮后内部不溢出（五个 Tab 的图标与文字仍完整渲染）', (tester) async {
      await _pumpNavBar(tester);

      // 溢出会以 FlutterError 形式抛出，pumpAndSettle 时即失败；
      // 这里再正向确认五项标签都在。
      for (final label in ['对话', '数据', '懂你', '发现', '我的']) {
        expect(find.text(label), findsOneWidget, reason: '$label 应正常渲染');
      }
    });
  });
}
