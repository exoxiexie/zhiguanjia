/// 对话输入栏测试（ChatInputBar）
///
/// 锁住两个易回归的交互：
/// 1. **发送即收键盘** —— 点发送按钮或按键盘「发送」键，输入框应立刻失焦
///    （键盘收起、输入栏落回屏幕底部），再回调 onSend。
/// 2. **输入框 1/2 行自适应** —— 未聚焦只占 1 行（平时不占地方），
///    聚焦后撑到 2 行，上限 5 行（再多在框内滚动）。
/// 该行为由公共组件统一提供，对话首页的输入栏使用该实现。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zhiguanjia/contracts/chat_service.dart';
import 'package:zhiguanjia/features/chat/chat_input_bar.dart';

/// 构造一个最小的输入栏宿主（关掉顶部工具行，只留输入框与发送按钮）
Future<void> _pumpBar(
  WidgetTester tester, {
  required TextEditingController controller,
  required VoidCallback onSend,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ChatInputBar(
        controller: controller,
        isLoading: false,
        selectedModel: kChatModels.first,
        onSend: onSend,
        showTopBar: false,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('ChatInputBar 发送交互', () {
    testWidgets('点发送按钮：先收起键盘（失焦）再回调 onSend', (tester) async {
      final controller = TextEditingController(text: '你好');
      addTearDown(controller.dispose);
      var sent = 0;

      await _pumpBar(tester, controller: controller, onSend: () => sent++);

      // 先聚焦输入框，模拟键盘已弹起
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus;
      expect(focused, isNotNull, reason: '输入框应能获得焦点');

      // 点圆形发送按钮
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pump();

      expect(sent, 1, reason: '应回调 onSend');
      expect(FocusManager.instance.primaryFocus, isNot(same(focused)),
          reason: '发送后输入框应失焦，键盘随之收起');
    });

    testWidgets('按键盘「发送」键同样收键盘并发送', (tester) async {
      final controller = TextEditingController(text: '你好');
      addTearDown(controller.dispose);
      var sent = 0;

      await _pumpBar(tester, controller: controller, onSend: () => sent++);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      final focused = FocusManager.instance.primaryFocus;
      expect(focused, isNotNull);

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();

      expect(sent, 1, reason: '应回调 onSend');
      expect(FocusManager.instance.primaryFocus, isNot(same(focused)),
          reason: '发送后输入框应失焦，键盘随之收起');
    });
  });

  group('ChatInputBar 行数自适应', () {
    testWidgets('未聚焦只占 1 行，聚焦后撑到 2 行，上限 5 行', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await _pumpBar(tester, controller: controller, onSend: () {});

      TextField field() => tester.widget<TextField>(find.byType(TextField));

      // 默认（未聚焦）：只占 1 行 —— 输入栏平时不该顶得太高
      expect(field().minLines, 1, reason: '未聚焦时应只占 1 行');
      expect(field().maxLines, 5, reason: '最多 5 行，再多在框内滚动');

      // 聚焦：撑到 2 行
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(field().minLines, 2, reason: '聚焦后应撑到 2 行');

      // 失焦（如发送后）：收回 1 行
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(field().minLines, 1, reason: '失焦后应收回 1 行');
    });

    testWidgets('聚焦后输入框渲染高度确实变高', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await _pumpBar(tester, controller: controller, onSend: () {});
      final idleHeight = tester.getSize(find.byType(TextField)).height;

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      final focusedHeight = tester.getSize(find.byType(TextField)).height;

      expect(focusedHeight, greaterThan(idleHeight));
    });
  });
}
